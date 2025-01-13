// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ChatterPayWalletProxy} from "./ChatterPayWalletProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

error ChatterPayWalletFactory__InvalidOwner();
error ChatterPayWalletFactory__InvalidProxyCall();

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

contract ChatterPayWalletFactory is Ownable, IChatterPayWalletFactory {
    address[] public proxies;
    address immutable entryPoint;
    address public walletImplementation;
    address public paymaster;
    address public immutable router;

    event ProxyCreated(address indexed owner, address indexed proxyAddress);
    event NewImplementation(address indexed _walletImplementation);

    constructor(
        address _walletImplementation,
        address _entryPoint,
        address _owner,
        address _paymaster,
        address _router
    ) Ownable(_owner) {
        walletImplementation = _walletImplementation;
        entryPoint = _entryPoint;
        paymaster = _paymaster;
        router = _router;
    }

    function owner() public view virtual override(Ownable, IChatterPayWalletFactory) returns (address) {
        return super.owner();
    }

    function createProxy(address _owner) public returns (address) {
        if (_owner == address(0)) revert ChatterPayWalletFactory__InvalidOwner();
        
        ERC1967Proxy walletProxy = new ERC1967Proxy{
            salt: keccak256(abi.encodePacked(_owner))
        }(
            walletImplementation,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                entryPoint,
                _owner,
                paymaster,
                router,
                address(this)
            )
        );
        
        proxies.push(address(walletProxy));
        emit ProxyCreated(_owner, address(walletProxy));
        return address(walletProxy);
    }

    function getProxyOwner(address proxy) public returns (bytes memory) {
        (bool success, bytes memory data) = proxy.call(abi.encodeWithSignature("owner()"));
        if (!success) revert ChatterPayWalletFactory__InvalidProxyCall();
        return data;
    }

    function getProxyOwnerAddress(address proxy) public returns (address) {
        bytes memory ownerBytes = getProxyOwner(proxy);
        if (ownerBytes.length != 32) revert ChatterPayWalletFactory__InvalidProxyCall();
        address ownerAddress;  // Cambiado el nombre de la variable
        assembly {
            ownerAddress := mload(add(ownerBytes, 32))
        }
        return ownerAddress;
    }

    function setImplementationAddress(address _walletImplementation) public onlyOwner {
        walletImplementation = _walletImplementation;
        emit NewImplementation(_walletImplementation);
    }

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

    function getProxyBytecode(address _owner) internal view returns (bytes memory) {
        bytes memory initializationCode = abi.encodeWithSignature(
            "initialize(address,address,address)",
            entryPoint,
            _owner,
            paymaster
        );
        return abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(walletImplementation, initializationCode)
        );
    }

    function getProxies() public view returns (address[] memory) {
        return proxies;
    }

    function getProxiesCount() public view returns (uint256) {
        return proxies.length;
    }
}