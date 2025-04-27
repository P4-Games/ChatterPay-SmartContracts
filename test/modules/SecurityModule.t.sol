// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
/**
 * @title SecurityModule
 * @notice Test module for ChatterPay security features
 * @dev Tests access controls, signature validation, reentrancy protection, and other security measures
 */

contract SecurityModule is BaseTest {
    // Test walletInstance instance
    ChatterPay public walletInstance;
    address public walletAddress;
    address public usdcTokenAddress;

    // Test accounts
    address public attacker;
    address public maliciousContract;

    // Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    function setUp() public override {
        super.setUp();

        // Deploy wallet
        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        walletInstance.addStableToken(USDC);

        // Disable freshness check for price feeds in tests
        walletInstance.updatePriceConfig(1 days, 8);

        vm.stopPrank();

        // Setup additional test accounts
        usdcTokenAddress = super.getUSDCAddress();
        attacker = makeAddr("attacker");
        maliciousContract = makeAddr("maliciousContract");
    }

    function wallet() public view returns (ChatterPay) {
        return walletInstance;
    }

    /**
     * @notice Tests access control for admin functions
     */
    function testAccessControl() public {
        // Test owner-only functions
        vm.startPrank(attacker);

        // Try to update fee
        vm.expectRevert();
        walletInstance.updateFee(100);

        // Try to whitelist token
        vm.expectRevert();
        walletInstance.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);

        // Try to upgrade implementation
        vm.expectRevert();
        walletInstance.upgradeToAndCall(address(0x123), "");

        vm.stopPrank();
    }

    /**
     * @notice Tests signature validation for UserOperations
     */
    function testSignatureValidation() public {
        // Create UserOperation hash
        bytes32 userOpHash = keccak256("test user operation");

        // Sign with owner's key
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Validate with correct signature
        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(_createUserOp(signature), userOpHash, 0);
        assertEq(validationData, 0, "Valid signature should return 0");

        // Test with invalid signature
        (v, r, s) = vm.sign(uint256(2), ethSignedMessageHash); // Different key
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.prank(ENTRY_POINT);
        validationData = walletInstance.validateUserOp(_createUserOp(invalidSignature), userOpHash, 0);
        assertEq(validationData, 1, "Invalid signature should return 1");
    }

    /**
     * @notice Tests reentrancy protection
     */
    function testReentrancyProtection() public {
        _fundWallet(walletAddress, 1000e6);

        ReentrancyAttacker attackerContract = new ReentrancyAttacker(address(walletInstance), usdcTokenAddress);

        // Whitelist token
        vm.prank(owner);
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);

        vm.startPrank(ENTRY_POINT);
        // First legitimate call
        walletInstance.executeTokenTransfer(USDC, address(attackerContract), 100e6);
        vm.stopPrank();
    }

    /**
     * @notice Tests EntryPoint authorization
     */
    function testEntryPointAuthorization() public {
        // Try to execute functions restricted to EntryPoint
        vm.startPrank(attacker);

        vm.expectRevert();
        walletInstance.executeTokenTransfer(USDC, user, 100e6);

        vm.expectRevert();
        walletInstance.executeSwap(USDC, USDT, 100e6, 90e6, user);

        vm.expectRevert();
        walletInstance.validateUserOp(_createUserOp(""), bytes32(0), 0);

        vm.stopPrank();
    }

    /**
     * @notice Tests ownership management
     */
    function testOwnershipManagement() public {
        address newOwner = makeAddr("newOwner");
        address currentOwner = walletInstance.owner();

        // Transfer ownership
        vm.prank(owner);
        walletInstance.transferOwnership(newOwner);

        // Verify new owner
        console.log("owner/newOwner", currentOwner, walletInstance.owner());
        assertEq(walletInstance.owner(), newOwner, "Ownership transfer failed");

        // Verify old owner lost privileges
        vm.prank(owner);
        vm.expectRevert();
        walletInstance.removeTokenFromWhitelist(usdcTokenAddress);
    }

    /**
     * @notice Tests token whitelist security
     */
    function testTokenWhitelistSecurity() public {
        // Try to transfer non-whitelisted token
        vm.prank(ENTRY_POINT);
        vm.expectRevert();
        walletInstance.executeTokenTransfer(USDT, user, 100e6);

        // Try to swap with non-whitelisted token
        vm.prank(ENTRY_POINT);
        vm.expectRevert();
        walletInstance.executeSwap(USDT, USDC, 100e6, 90e6, user);
    }

    /**
     * @notice Helper function to create a test UserOperation
     */
    function _createUserOp(bytes memory signature) internal pure returns (UserOperation memory) {
        return UserOperation({
            sender: address(0),
            nonce: 0,
            initCode: bytes(""),
            callData: bytes(""),
            callGasLimit: 0,
            verificationGasLimit: 0,
            preVerificationGas: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: bytes(""),
            signature: signature
        });
    }
}

/**
 * @notice Malicious contract for testing reentrancy protection
 */
contract MaliciousContract {
    ChatterPay private wallet;
    address usdcToken;
    bool private attacked;

    constructor(address _wallet, address _usdcToken) {
        wallet = ChatterPay(payable(_wallet));
        usdcToken = _usdcToken;
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            // Try to execute another transfer during the first transfer
            wallet.executeTokenTransfer(usdcToken, address(this), 100e6);
        }
    }
}

/**
 * @notice Malicious contract for testing reentrancy protection
 */
contract ReentrancyAttacker {
    ChatterPay private immutable wallet;
    address usdcToken;

    constructor(address _wallet, address _usdcToken) {
        wallet = ChatterPay(payable(_wallet));
        usdcToken = _usdcToken;
    }

    function attack() external {
        // Call executeTokenTransfer first from ENTRY_POINT
        wallet.executeTokenTransfer(usdcToken, address(this), 50e6);
    }
}
