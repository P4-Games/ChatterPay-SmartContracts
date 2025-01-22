// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/L2/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title EntryPointModule
 * @notice Test module for ChatterPay EntryPoint integration and ERC-4337 functionality
 * @dev Tests UserOperation validation, signature verification, and paymaster interaction
 */
contract EntryPointModule is BaseTest {
    // Test wallet instance
    ChatterPay walletInstance;
    address walletAddress;

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
        wallet = ChatterPay(payable(walletAddress));
        wallet.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        vm.stopPrank();
    }

    function wallet() public view returns (ChatterPay) {
        return walletInstance;
    }

    /**
     * @notice Tests basic UserOperation validation
     */
    function testBasicUserOpValidation() public {
        // Create and sign UserOperation
        UserOperation memory userOp = _createBasicUserOp();
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerKey);

        // Validate UserOperation
        vm.prank(ENTRY_POINT);
        uint256 validationData = wallet.validateUserOp(
            userOp,
            userOpHash,
            0
        );

        assertEq(validationData, 0, "UserOp validation failed");
    }

    /**
     * @notice Tests UserOperation execution with token transfer
     */
    function testUserOpWithTokenTransfer() public {
        // Fund wallet
        _fundWallet(walletAddress, 1000e6);

        // Create UserOperation for token transfer
        bytes memory callData = abi.encodeWithSelector(
            ChatterPay.executeTokenTransfer.selector,
            USDC,
            user,
            100e6
        );

        UserOperation memory userOp = _createUserOp(callData);
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerKey);

        // Execute UserOperation
        vm.prank(ENTRY_POINT);
        wallet.validateUserOp(userOp, userOpHash, 0);

        // Verify transfer
        assertEq(IERC20(USDC).balanceOf(user), 100e6 - 50e6, "Transfer amount incorrect"); // Minus fee
    }

    /**
     * @notice Tests UserOperation with paymaster
     */
    function testUserOpWithPaymaster() public {
        // Fund paymaster
        vm.deal(address(paymaster), 10 ether);

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
        uint256 validationData = wallet.validateUserOp(
            userOp,
            userOpHash,
            0.1 ether
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
            uint256 validationData = wallet.validateUserOp(
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
        uint256 validationData = wallet.validateUserOp(
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
        uint256 prefundAmount = 0.1 ether;
        
        // Record initial balances
        uint256 initialEntryPointBalance = address(ENTRY_POINT).balance;
        uint256 initialWalletBalance = address(wallet).balance;

        // Fund wallet
        vm.deal(address(wallet), 1 ether);

        // Create and validate UserOp with prefund
        UserOperation memory userOp = _createBasicUserOp();
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerKey);

        vm.prank(ENTRY_POINT);
        wallet.validateUserOp(userOp, userOpHash, prefundAmount);

        // Verify prefund transfer
        assertEq(
            address(ENTRY_POINT).balance,
            initialEntryPointBalance + prefundAmount,
            "Prefund not transferred correctly"
        );
        assertEq(
            address(wallet).balance,
            initialWalletBalance + 1 ether - prefundAmount,
            "Wallet balance incorrect after prefund"
        );
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
            sender: address(wallet),
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
    function _getUserOpHash(
        UserOperation memory userOp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(userOp));
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
}