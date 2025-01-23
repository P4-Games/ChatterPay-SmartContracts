// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/L2/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20Extended} from "../../src/L2/ChatterPay.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
/**
 * @title EntryPointModule
 * @notice Test module for ChatterPay EntryPoint integration and ERC-4337 functionality
 * @dev Tests UserOperation validation, signature verification, and paymaster interaction
 */
contract EntryPointModule is BaseTest {
    // Test wallet instance
    ChatterPay public walletInstance;
    address public walletAddress;

    // Test constants
    uint256 constant GAS_LIMIT = 1000000;
    uint256 constant MAX_FEE = 100 gwei;
    uint256 constant PRE_VERIFICATION_GAS = 100000;
    uint256 constant VERIFICATION_GAS_LIMIT = 150000;

    function setUp() public override {
        super.setUp();
        
        // Deploy wallet
        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        vm.stopPrank();
    }

    function wallet() public view returns (ChatterPay) {
        return walletInstance;
    }

    /**
     * @notice Tests basic UserOperation validation
     */
    function testBasicUserOpValidation() public {
        UserOperation memory userOp = _createBasicUserOp();
        bytes32 userOpHash = _getUserOpHash(userOp);
        
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, messageHash);
        userOp.signature = abi.encodePacked(r, s, v);

        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 0);
    }

    /**
     * @notice Tests UserOperation execution with token transfer
     */
    function testUserOpWithTokenTransfer() public {
        uint256 TRANSFER_AMOUNT = 100e6; // 100 USDC
        // Fondear
        _fundWallet(walletAddress, TRANSFER_AMOUNT);
        vm.deal(address(walletInstance), 1 ether);

        // Preparar UserOp
        bytes memory callData = abi.encodeWithSelector(
            ChatterPay.executeTokenTransfer.selector,
            USDC, user, TRANSFER_AMOUNT
        );
        
        UserOperation memory userOp = UserOperation({
            sender: address(walletInstance),
            nonce: 0,
            initCode: "",
            callData: callData,
            callGasLimit: 200000,
            verificationGasLimit: 150000,
            preVerificationGas: 21000,
            maxFeePerGas: 100 gwei,
            maxPriorityFeePerGas: 2 gwei,
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash); 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, messageHash);
        userOp.signature = abi.encodePacked(r, s, v);

        vm.prank(ENTRY_POINT);
        walletInstance.validateUserOp(userOp, userOpHash, 0);
    }

    /**
     * @notice Tests UserOperation with paymaster
     */
    function testUserOpWithPaymaster() public {
        // Fund paymaster
        vm.deal(address(paymaster), 10 ether);
        
        // Fund wallet with ETH for potential prefund
        vm.deal(address(walletInstance), 1 ether);

        // Create UserOperation with paymaster
        bytes memory callData = abi.encodeWithSelector(
            ChatterPay.executeTokenTransfer.selector,
            USDC,
            user,
            100e6
        );

        UserOperation memory userOp = _createUserOp(callData);
        userOp.paymasterAndData = abi.encodePacked(address(paymaster));
        
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerKey);

        // Validate with paymaster
        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(
            userOp,
            userOpHash,
            1 ether
        );

        assertEq(validationData, 0, "UserOp validation with paymaster failed");
    }

    /**
     * @notice Tests batch UserOperations
     */
    function testBatchUserOps() public {
        // Fund wallet
        _fundWallet(walletAddress, 1000e6);

        // Create multiple UserOperations
        UserOperation[] memory userOps = new UserOperation[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            bytes memory callData = abi.encodeWithSelector(
                ChatterPay.executeTokenTransfer.selector,
                USDC,
                makeAddr(string.concat("recipient", vm.toString(i))),
                100e6
            );
            
            userOps[i] = _createUserOp(callData);
            bytes32 userOpHash = _getUserOpHash(userOps[i]);
            userOps[i].signature = _signUserOp(userOpHash, ownerKey);
        }

        // Validate all operations
        for (uint256 i = 0; i < userOps.length; i++) {
            vm.prank(ENTRY_POINT);
            uint256 validationData = walletInstance.validateUserOp(
                userOps[i],
                _getUserOpHash(userOps[i]),
                0
            );
            assertEq(validationData, 0, string.concat("UserOp ", vm.toString(i), " validation failed"));
        }
    }

    /**
     * @notice Tests invalid signature rejection
     */
    function testInvalidSignature() public {
        UserOperation memory userOp = _createBasicUserOp();
        bytes32 userOpHash = _getUserOpHash(userOp);
        
        // Sign with wrong key
        uint256 wrongKey = 0x1234;
        userOp.signature = _signUserOp(userOpHash, wrongKey);

        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(
            userOp,
            userOpHash,
            0
        );

        assertEq(validationData, 1, "Invalid signature not rejected");
    }

    /**
     * @notice Tests prefund handling
     */
    function testPrefundHandling() public {
        vm.deal(address(walletInstance), 2 ether);
        uint256 initialBalance = address(walletInstance).balance;

        UserOperation memory userOp = _createBasicUserOp();
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerKey);

        vm.prank(ENTRY_POINT);
        walletInstance.validateUserOp(userOp, userOpHash, 1 ether);
        
        assertEq(address(walletInstance).balance, initialBalance - 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Creates a basic UserOperation
     */
    function _createBasicUserOp() internal view returns (UserOperation memory) {
        return _createUserOp("");
    }

    /**
     * @dev Creates a UserOperation with specific calldata
     */
    function _createUserOp(
        bytes memory callData
    ) internal view returns (UserOperation memory) {
        return UserOperation({
            sender: address(walletInstance),
            nonce: 0,
            initCode: bytes(""),
            callData: callData,
            callGasLimit: GAS_LIMIT,
            verificationGasLimit: VERIFICATION_GAS_LIMIT,
            preVerificationGas: PRE_VERIFICATION_GAS,
            maxFeePerGas: MAX_FEE,
            maxPriorityFeePerGas: MAX_FEE,
            paymasterAndData: bytes(""),
            signature: bytes("")
        });
    }

    /**
     * @dev Calculates UserOperation hash
     */
    function _getUserOpHash(UserOperation memory userOp) internal view returns (bytes32) {
        bytes32 userOpHash = keccak256(abi.encode(
            userOp.sender,
            userOp.nonce,
            keccak256(userOp.initCode),
            keccak256(userOp.callData),
            userOp.callGasLimit,
            userOp.verificationGasLimit, 
            userOp.preVerificationGas,
            userOp.maxFeePerGas,
            userOp.maxPriorityFeePerGas,
            keccak256(userOp.paymasterAndData)
        ));

        return keccak256(abi.encode(
            userOpHash,
            address(ENTRY_POINT),
            block.chainid
        ));
    }

    /**
     * @dev Signs a UserOperation hash
     */
    function _signUserOp(
        bytes32 userOpHash,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @dev Helper function to calculate expected fee
     * @param token Token address
     * @param feeInCents Fee amount in cents
     * @return Fee amount in token decimals
     */
    function _calculateExpectedFee(
        address token,
        uint256 feeInCents
    ) internal view returns (uint256) {
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        
        return (feeInCents * (10 ** tokenDecimals)) / 100;
    }
}