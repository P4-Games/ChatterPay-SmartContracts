// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UserOperation} from "lib/entry-point-v6/interfaces/UserOperation.sol";
import {HelperConfig} from "script/utils/HelperConfig.s.sol";
import {IEntryPoint} from "lib/entry-point-v6/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChatterPayWalletFactory} from "src/ChatterPayWalletFactory.sol";
import {ChatterPay} from "src/ChatterPay.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

error SendPackedUserOp__NoProxyDeployed();

/**
 * @title SendPackedUserOp
 * @notice A script for sending packed user operations to the EntryPoint contract
 * @dev Uses Foundry's Script contract for deployment functionality
 */
contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    // Make sure you trust this user - don't run this on Mainnet!
    address RANDOM_APPROVER = makeAddr("RANDOM_APPROVER");

    /**
     * @notice Main execution function that sends a user operation
     * @dev Sets up configuration and sends a USDC approval operation through the EntryPoint
     */
    function run() public {
        // Setup
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        address ANVIL_DEFAULT_USER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        uint256 ANVIL_DEFAUL_USER_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        address chatterPayPaymasterAddress = DevOpsTools
            .get_most_recent_deployment("ChatterPayPaymaster", block.chainid);

        address dest = config.usdc;
        uint256 value = 0;
        address chatterPayWalletFactoryAddress = DevOpsTools
            .get_most_recent_deployment(
                "ChatterPayWalletFactory",
                block.chainid
            );
        address chatterPayProxyAddress;
        bytes memory initCode;
        if (
            ChatterPayWalletFactory(chatterPayWalletFactoryAddress)
                .getProxiesCount() > 0
        ) {
            // send userOp without initCode
            chatterPayProxyAddress = ChatterPayWalletFactory(
                chatterPayWalletFactoryAddress
            ).getProxies()[0];
            initCode = hex"";
        } else {
            // compute new address, send userOp with initCode to create account
            chatterPayProxyAddress = ChatterPayWalletFactory(
                chatterPayWalletFactoryAddress
            ).computeProxyAddress(ANVIL_DEFAULT_USER);
            bytes memory encodedData = abi.encodeWithSignature(
                "createProxy(address)",
                ANVIL_DEFAULT_USER
            );
            bytes memory encodedFactory = abi.encodePacked(
                chatterPayWalletFactoryAddress
            );
            initCode = abi.encodePacked(encodedFactory, encodedData);
        }

        // Example: approve 1e18 USDC to RANDOM_APPROVER
        // this is the function called by the wallet
        bytes memory functionData = abi.encodeWithSelector(
            IERC20.approve.selector,
            RANDOM_APPROVER,
            1e18
        );
        // this is the function on the wallet called by the entrypoint
        bytes memory executeCalldata = abi.encodeWithSelector(
            ChatterPay.execute.selector,
            dest,
            value,
            functionData
        );

        UserOperation memory userOp = generateSignedUserOperation(
            initCode,
            executeCalldata,
            helperConfig.getConfig(),
            chatterPayProxyAddress,
            ANVIL_DEFAUL_USER_KEY,
            chatterPayPaymasterAddress
        );
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        // Send transaction
        vm.startBroadcast();
        IEntryPoint(config.entryPoint).handleOps(ops, payable(config.account));
        vm.stopBroadcast();
    }

    /**
     * @notice Generates paymaster data including signature and expiration
     * @param _paymasterAddress Address of the paymaster contract
     * @param _proxyAddress Address of the proxy contract
     * @return bytes Encoded paymaster data including signature and expiration timestamp
     */
    function generatePaymasterAndData(
        address _paymasterAddress,
        address _proxyAddress
    ) public view returns (bytes memory) {
        // Backend signer
        uint256 backendPrivateKey = vm.envUint("BACKEND_PK");

        // Set expiration timestamp to current time + 1 hour (3600 seconds)
        uint64 expiration = uint64(block.timestamp + 3600);

        // Create the message to sign (proxyAddress and expiration)
        bytes32 messageHash = keccak256(
            abi.encodePacked(_proxyAddress, expiration)
        );

        // Sign the message using the backend signer's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendPrivateKey,
            messageHash
        );

        // Construct the signature in (r, s, v) format
        bytes memory signature = abi.encodePacked(r, s, v);

        // Convert the expiration timestamp to bytes (big endian)
        bytes8 expirationBytes = bytes8(expiration);

        // Construct paymasterAndData by concatenating paymaster address, signature, and expiration
        bytes memory paymasterAndData = abi.encodePacked(
            _paymasterAddress,
            signature,
            expirationBytes
        );

        return paymasterAndData;
    }

    /**
     * @notice Generates a signed user operation
     * @param initCode Initialization code for new account deployment
     * @param callData The calldata to be executed
     * @param config Network configuration
     * @param chatterPayProxy Address of the ChatterPay proxy
     * @param key Private key for signing
     * @param paymasterAddress Address of the paymaster
     * @return UserOperation The signed user operation
     */
    function generateSignedUserOperation(
        bytes memory initCode,
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address chatterPayProxy,
        uint256 key,
        address paymasterAddress
    ) public view returns (UserOperation memory) {
        bytes memory paymasterAndData = generatePaymasterAndData(
            paymasterAddress,
            chatterPayProxy
        );

        UserOperation memory userOp = _generateUnsignedUserOperation(
            initCode,
            callData,
            chatterPayProxy,
            paymasterAndData
        );

        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(
            userOp
        );

        bytes32 digest = userOpHash.toEthSignedMessageHash();

        uint8 v;
        bytes32 r;
        bytes32 s;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(key, digest);
        } else {
            (v, r, s) = vm.sign(config.account, digest);
        }
        userOp.signature = abi.encodePacked(r, s, v); // Note the order
        return userOp;
    }

    /**
     * @notice Generates an unsigned user operation with default gas parameters
     * @param initCode Initialization code for new account deployment
     * @param callData The calldata to be executed
     * @param sender Address of the sender
     * @param _paymasterAndData Encoded paymaster data
     * @return UserOperation The unsigned user operation
     */
    function _generateUnsignedUserOperation(
        bytes memory initCode,
        bytes memory callData,
        address sender,
        bytes memory _paymasterAndData
    ) internal pure returns (UserOperation memory) {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return
            UserOperation({
                sender: sender,
                nonce: 0,
                initCode: initCode,
                callData: callData,
                callGasLimit: callGasLimit,
                verificationGasLimit: verificationGasLimit,
                preVerificationGas: verificationGasLimit,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: maxPriorityFeePerGas,
                paymasterAndData: _paymasterAndData,
                signature: hex""
            });
    }
}
