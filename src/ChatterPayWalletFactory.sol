// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
// IMPORTS
//////////////////////////////////////////////////////////////*/

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ChatterPayWalletProxy} from "./ChatterPayWalletProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/*//////////////////////////////////////////////////////////////
// ERRORS
//////////////////////////////////////////////////////////////*/

error ChatterPayWalletFactory__InvalidOwner();
error ChatterPayWalletFactory__InvalidProxyCall();
error ChatterPayWalletFactory__InvalidArrayLengths();
error ChatterPayWalletFactory__ZeroAddress();

/*//////////////////////////////////////////////////////////////
// INTERFACES
//////////////////////////////////////////////////////////////*/

/**
 * @title IChatterPayWalletFactory
 * @author ChatterPay Team
 * @notice Interface for the ChatterPayWalletFactory contract defining core functionality
 */
interface IChatterPayWalletFactory {
    function createProxy(address _owner) external returns (address);
    function getProxyOwner(address proxy) external returns (bytes memory);
    function getProxyOwnerAddress(address proxy) external returns (address);
    function computeProxyAddress(address _owner) external view returns (address);
    function getProxies() external view returns (address[] memory);
    function getProxiesCount() external view returns (uint256);
    function owner() external view returns (address);
    function walletImplementation() external view returns (address);
    function paymaster() external view returns (address);
    function globalWhitelistedTokens(address token) external view returns (bool);
    function globalPriceFeeds(address token) external view returns (address);
}

/**
 * @title ChatterPayWalletFactory
 * @notice Factory contract for deploying and managing ChatterPay wallet proxies
 * @dev Inherits from Ownable and implements IChatterPayWalletFactory
 */
contract ChatterPayWalletFactory is Ownable, IChatterPayWalletFactory {
    /*//////////////////////////////////////////////////////////////
    // CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    address[] public proxies;
    address immutable entryPoint;
    address public walletImplementation;
    address public paymaster;
    address public immutable router;
    address[] public defaultWhitelistedTokens;
    address[] public defaultPriceFeeds;
    bool[] public defaultTokensStableFlags;
    
    // Global whitelist and price feed management
    mapping(address => bool) public globalWhitelistedTokens;
    mapping(address => address) public globalPriceFeeds;

    /*//////////////////////////////////////////////////////////////
    // EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProxyCreated(address indexed owner, address indexed proxyAddress);
    event NewImplementation(address indexed _walletImplementation);
    event DefaultTokensUpdated(address[] tokens, address[] priceFeeds);
    event GlobalTokenWhitelisted(address indexed token, bool status);
    event GlobalPriceFeedUpdated(address indexed token, address indexed priceFeed);

    /*//////////////////////////////////////////////////////////////
    // INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the factory with required addresses
     * @param _walletImplementation Address of the wallet implementation contract
     * @param _entryPoint Address of the EntryPoint contract
     * @param _owner Address of the factory owner
     * @param _paymaster Address of the paymaster contract
     * @param _router Address of the router contract
     * @param _whitelistedTokens Array of initially whitelisted token addresses
     * @param _priceFeeds Array of corresponding price feed addresses
     */
    constructor(
        address _walletImplementation,
        address _entryPoint,
        address _owner,
        address _paymaster,
        address _router,
        address[] memory _whitelistedTokens,
        address[] memory _priceFeeds,
        bool[] memory _tokensStableFlags
    ) Ownable(_owner) {
        if (_walletImplementation == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_entryPoint == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_owner == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_paymaster == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_router == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_whitelistedTokens.length != _priceFeeds.length) {
            revert ChatterPayWalletFactory__InvalidArrayLengths();
        }
        if (_whitelistedTokens.length != _tokensStableFlags.length) {
            revert ChatterPayWalletFactory__InvalidArrayLengths();
        }

        walletImplementation = _walletImplementation;
        entryPoint = _entryPoint;
        paymaster = _paymaster;
        router = _router;
        defaultWhitelistedTokens = _whitelistedTokens;
        defaultPriceFeeds = _priceFeeds;
        defaultTokensStableFlags = _tokensStableFlags;
    }

    /*//////////////////////////////////////////////////////////////
    // GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the owner address of the factory
     * @return address The owner's address
     */
    function owner() public view virtual override(Ownable, IChatterPayWalletFactory) returns (address) {
        return super.owner();
    }

    /**
     * @notice Gets the raw owner data from a proxy contract
     * @param proxy Address of the proxy contract
     * @return bytes memory Raw bytes data of the owner
     */
    function getProxyOwner(address proxy) public returns (bytes memory) {
        if (proxy == address(0)) revert ChatterPayWalletFactory__InvalidOwner();
        (bool success, bytes memory data) = proxy.call(abi.encodeWithSignature("owner()"));
        if (!success) revert ChatterPayWalletFactory__InvalidProxyCall();
        return data;
    }

    /**
     * @notice Gets the owner address from a proxy contract
     * @param proxy Address of the proxy contract
     * @return address The owner's address
     */
    function getProxyOwnerAddress(address proxy) public returns (address) {
        bytes memory ownerBytes = getProxyOwner(proxy);
        if (ownerBytes.length != 32) revert ChatterPayWalletFactory__InvalidProxyCall();
        address ownerAddress;
        assembly {
            ownerAddress := mload(add(ownerBytes, 32))
        }
        return ownerAddress;
    }

    /**
     * @notice Returns all deployed proxy addresses
     * @return address[] memory Array of proxy addresses
     */
    function getProxies() public view returns (address[] memory) {
        return proxies;
    }

    /**
     * @notice Returns the total number of deployed proxies
     * @return uint256 The count of deployed proxies
     */
    function getProxiesCount() public view returns (uint256) {
        return proxies.length;
    }

    /**
     * @notice Computes the deterministic address for a proxy before deployment
     * @param _owner Address of the future proxy owner
     * @return address The computed proxy address
     */
    function computeProxyAddress(address _owner) public view returns (address) {
        bytes memory bytecode = getProxyBytecode(_owner);
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), keccak256(abi.encodePacked(_owner)), keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }

    /*//////////////////////////////////////////////////////////////
    // MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new wallet proxy for a given owner
     * @param _owner Address that will own the new wallet
     * @return address The address of the newly created proxy
     * @dev Uses CREATE2 for deterministic address generation
     */
    function createProxy(address _owner) public returns (address) {
        if (_owner == address(0)) revert ChatterPayWalletFactory__InvalidOwner();

        ERC1967Proxy walletProxy = new ERC1967Proxy{salt: keccak256(abi.encodePacked(_owner))}(
            walletImplementation,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address[],address[],bool[])",
                entryPoint,
                _owner,
                paymaster,
                router,
                address(this),
                defaultWhitelistedTokens,
                defaultPriceFeeds,
                defaultTokensStableFlags
            )
        );

        proxies.push(address(walletProxy));
        emit ProxyCreated(_owner, address(walletProxy));
        return address(walletProxy);
    }

    /*//////////////////////////////////////////////////////////////
    // ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the wallet implementation address
     * @param _walletImplementation New implementation address
     * @dev Can only be called by the owner
     */
    function setImplementationAddress(address _walletImplementation) public onlyOwner {
        if (_walletImplementation == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        walletImplementation = _walletImplementation;
        emit NewImplementation(_walletImplementation);
    }

    /**
     * @notice Updates the default token and price feed lists
     * @param _tokens New list of whitelisted tokens
     * @param _priceFeeds New list of price feeds
     */
    function setDefaultTokensAndFeeds(address[] calldata _tokens, address[] calldata _priceFeeds) external onlyOwner {
        if (_tokens.length != _priceFeeds.length) {
            revert ChatterPayWalletFactory__InvalidArrayLengths();
        }

        defaultWhitelistedTokens = _tokens;
        defaultPriceFeeds = _priceFeeds;
        emit DefaultTokensUpdated(_tokens, _priceFeeds);
    }

    /**
     * @notice Sets global token whitelist and price feed
     * @param token Token address
     * @param status Whitelist status
     * @param priceFeed Oracle price feed address
     */
    function setGlobalTokenWhitelistAndPriceFeed(
        address token,
        bool status,
        address priceFeed
    ) external onlyOwner {
        if (token == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (priceFeed == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        
        globalWhitelistedTokens[token] = status;
        if (status) {
            globalPriceFeeds[token] = priceFeed;
            emit GlobalPriceFeedUpdated(token, priceFeed);
        } else {
            // Clear price feed if token is removed from whitelist
            if (globalPriceFeeds[token] != address(0)) {
                delete globalPriceFeeds[token];
                emit GlobalPriceFeedUpdated(token, address(0));
            }
        }
        emit GlobalTokenWhitelisted(token, status);
    }

    /*//////////////////////////////////////////////////////////////
    // INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Generates the bytecode for proxy deployment
     * @param _owner Address of the proxy owner
     * @return bytes memory The proxy bytecode with initialization data
     */
    function getProxyBytecode(address _owner) internal view returns (bytes memory) {
        bytes memory initializationCode = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address[],address[],bool[])",
            entryPoint,
            _owner,
            paymaster,
            router,
            address(this),
            defaultWhitelistedTokens,
            defaultPriceFeeds,
            defaultTokensStableFlags
        );
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(walletImplementation, initializationCode));
    }
}
