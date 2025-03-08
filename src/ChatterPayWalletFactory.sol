// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ChatterPayWalletProxy} from "./ChatterPayWalletProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

error ChatterPayWalletFactory__InvalidOwner();
error ChatterPayWalletFactory__InvalidProxyCall();
error ChatterPayWalletFactory__InvalidFeeAdmin();
error ChatterPayWalletFactory__InvalidArrayLengths();
error ChatterPayWalletFactory__ZeroAddress();

/**
 * @title IChatterPayWalletFactory
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
}

/**
 * @title ChatterPayWalletFactory
 * @notice Factory contract for deploying and managing ChatterPay wallet proxies
 * @dev Inherits from Ownable and implements IChatterPayWalletFactory
 */
contract ChatterPayWalletFactory is Ownable, IChatterPayWalletFactory {
    address[] public proxies;
    address immutable entryPoint;
    address public walletImplementation;
    address public paymaster;
    address public immutable router;
    address public feeAdmin;

    // Default token configuration
    address[] public defaultWhitelistedTokens;
    address[] public defaultPriceFeeds;

    event ProxyCreated(address indexed owner, address indexed proxyAddress);
    event NewImplementation(address indexed _walletImplementation);
    event FeeAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event DefaultTokensUpdated(address[] tokens, address[] priceFeeds);

    /**
     * @notice Initializes the factory with required addresses
     * @param _walletImplementation Address of the wallet implementation contract
     * @param _entryPoint Address of the EntryPoint contract
     * @param _owner Address of the factory owner
     * @param _paymaster Address of the paymaster contract
     * @param _router Address of the router contract
     * @param _feeAdmin Address of the fee administrator
     * @param _whitelistedTokens Array of initially whitelisted token addresses
     * @param _priceFeeds Array of corresponding price feed addresses
     */
    constructor(
        address _walletImplementation,
        address _entryPoint,
        address _owner,
        address _paymaster,
        address _router,
        address _feeAdmin,
        address[] memory _whitelistedTokens,
        address[] memory _priceFeeds
    ) Ownable(_owner) {
        if (_walletImplementation == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_entryPoint == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_owner == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_paymaster == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_router == address(0)) revert ChatterPayWalletFactory__ZeroAddress();
        if (_feeAdmin == address(0)) revert ChatterPayWalletFactory__InvalidFeeAdmin();
        if (_whitelistedTokens.length != _priceFeeds.length) 
            revert ChatterPayWalletFactory__InvalidArrayLengths();

        walletImplementation = _walletImplementation;
        entryPoint = _entryPoint;
        paymaster = _paymaster;
        router = _router;
        feeAdmin = _feeAdmin;
        defaultWhitelistedTokens = _whitelistedTokens;
        defaultPriceFeeds = _priceFeeds;
    }

    /**
     * @notice Returns the owner address of the factory
     * @return address The owner's address
     */
    function owner() public view virtual override(Ownable, IChatterPayWalletFactory) returns (address) {
        return super.owner();
    }

    /**
     * @notice Creates a new wallet proxy for a given owner
     * @param _owner Address that will own the new wallet
     * @return address The address of the newly created proxy
     * @dev Uses CREATE2 for deterministic address generation
     */
    function createProxy(address _owner) public returns (address) {
        if (_owner == address(0)) revert ChatterPayWalletFactory__InvalidOwner();
        
        ERC1967Proxy walletProxy = new ERC1967Proxy{
            salt: keccak256(abi.encodePacked(_owner))
        }(
            walletImplementation,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],address[])",
                entryPoint,
                _owner,
                paymaster,
                router,
                address(this),
                feeAdmin,
                defaultWhitelistedTokens,
                defaultPriceFeeds
            )
        );
        
        proxies.push(address(walletProxy));
        emit ProxyCreated(_owner, address(walletProxy));
        return address(walletProxy);
    }

    /**
     * @notice Gets the raw owner data from a proxy contract
     * @param proxy Address of the proxy contract
     * @return bytes memory Raw bytes data of the owner
     */
    function getProxyOwner(address proxy) public returns (bytes memory) {
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
     * @notice Sets the fee admin address
     * @param _newFeeAdmin New fee admin address
     */
    function setFeeAdmin(address _newFeeAdmin) external onlyOwner {
        if (_newFeeAdmin == address(0)) revert ChatterPayWalletFactory__InvalidFeeAdmin();
        address oldAdmin = feeAdmin;
        feeAdmin = _newFeeAdmin;
        emit FeeAdminUpdated(oldAdmin, _newFeeAdmin);
    }

    /**
     * @notice Updates the default token and price feed lists
     * @param _tokens New list of whitelisted tokens
     * @param _priceFeeds New list of price feeds
     */
    function setDefaultTokensAndFeeds(
        address[] calldata _tokens,
        address[] calldata _priceFeeds
    ) external onlyOwner {
        if (_tokens.length != _priceFeeds.length) 
            revert ChatterPayWalletFactory__InvalidArrayLengths();
            
        defaultWhitelistedTokens = _tokens;
        defaultPriceFeeds = _priceFeeds;
        emit DefaultTokensUpdated(_tokens, _priceFeeds);
    }

    /**
     * @notice Computes the deterministic address for a proxy before deployment
     * @param _owner Address of the future proxy owner
     * @return address The computed proxy address
     */
    function computeProxyAddress(address _owner) public view returns (address) {
        bytes memory bytecode = getProxyBytecode(_owner);
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                keccak256(abi.encodePacked(_owner)),
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Generates the bytecode for proxy deployment
     * @param _owner Address of the proxy owner
     * @return bytes memory The proxy bytecode with initialization data
     */
    function getProxyBytecode(address _owner) internal view returns (bytes memory) {
        bytes memory initializationCode = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address[],address[])",
            entryPoint,
            _owner,
            paymaster,
            router,
            address(this),
            feeAdmin,
            defaultWhitelistedTokens,
            defaultPriceFeeds
        );
        return abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(walletImplementation, initializationCode)
        );
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
}