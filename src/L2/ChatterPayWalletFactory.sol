// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ChatterPayWalletProxy} from "./ChatterPayWalletProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

error ChatterPayWalletFactory__InvalidOwner();

interface IChatterPayWalletFactory {
    function createProxy(address _owner) external returns (address);

    function getProxyOwner(address proxy) external returns (bytes memory);

    function computeProxyAddress(
        address _owner
    ) external view returns (address);

    function getProxies() external view returns (address[] memory);

    function getProxiesCount() external view returns (uint256);
}

contract ChatterPayWalletFactory is Ownable, IChatterPayWalletFactory {
    address[] public proxies;
    address immutable entryPoint;
    address public walletImplementation;
    address public paymaster;

    event ProxyCreated(address indexed owner, address indexed proxyAddress);
    event NewImplementation(address indexed _walletImplementation);

    constructor(
        address _walletImplementation,
        address _entryPoint,
        address _owner,
        address _paymaster
    ) Ownable(_owner) {
        walletImplementation = _walletImplementation;
        entryPoint = _entryPoint;
        paymaster = _paymaster;
    }

    /**
     * @notice Creates a new wallet proxy for a specified owner.
     * @dev Deploys a new proxy contract and initializes it with the provided parameters.
     * @param _owner The address of the owner for the new proxy.
     * @return The address of the newly created proxy.
     * @custom:events Emits a `ProxyCreated` event on success.
     * @custom:reverts ChatterPayWalletFactory__InvalidOwner if the `_owner` address is zero.
     */
    function createProxy(address _owner) public returns (address) {
        if (_owner == address(0))
            revert ChatterPayWalletFactory__InvalidOwner();
        ERC1967Proxy walletProxy = new ERC1967Proxy{
            salt: keccak256(abi.encodePacked(_owner))
        }(
            walletImplementation,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                entryPoint,
                _owner,
                paymaster
            )
        );
        proxies.push(address(walletProxy));
        emit ProxyCreated(_owner, address(walletProxy));
        return address(walletProxy);
    }

    /**
     * @notice Retrieves the owner of a specified proxy wallet.
     * @dev Calls the `owner()` function on the proxy contract to fetch its owner.
     * @param proxy The address of the proxy contract.
     * @return The owner address as a bytes array.
     */
    function getProxyOwner(address proxy) public returns (bytes memory) {
        (, bytes memory data) = proxy.call(abi.encodeWithSignature("owner()"));
        return data;
    }

    /**
     * @notice Updates the wallet implementation address used for deploying new proxies.
     * @dev Only callable by the contract owner.
     * @param _walletImplementation The new wallet implementation address.
     * @custom:events Emits a `NewImplementation` event on success.
     */
    function setImplementationAddress(
        address _walletImplementation
    ) public onlyOwner {
        walletImplementation = _walletImplementation;
        emit NewImplementation(_walletImplementation);
    }

    /**
     * @notice Computes the deterministic address for a proxy based on the owner address.
     * @dev Uses `CREATE2` hashing to compute the address without deploying the contract.
     * @param _owner The address of the owner.
     * @return The computed proxy address.
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
     * @notice Retrieves the bytecode for a proxy contract initialized with a specific owner.
     * @dev Combines the creation code of the proxy and the initialization code.
     * @param _owner The address of the owner for which to generate the bytecode.
     * @return The bytecode of the proxy contract.
     */
    function getProxyBytecode(
        address _owner
    ) internal view returns (bytes memory) {
        bytes memory initializationCode = abi.encodeWithSignature(
            "initialize(address,address,address)",
            entryPoint,
            _owner,
            paymaster
        );
        return
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(walletImplementation, initializationCode)
            );
    }

    /**
     * @notice Fetches all deployed proxy addresses.
     * @dev Returns the array of proxy addresses stored in the `proxies` variable.
     * @return An array of addresses representing all deployed proxies.
     */
    function getProxies() public view returns (address[] memory) {
        return proxies;
    }

    /**
     * @notice Retrieves the total number of proxies deployed by the factory.
     * @dev Counts the length of the `proxies` array.
     * @return The total number of deployed proxies.
     */
    function getProxiesCount() public view returns (uint256) {
        return proxies.length;
    }
}
