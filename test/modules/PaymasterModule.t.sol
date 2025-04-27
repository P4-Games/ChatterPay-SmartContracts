// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {
    ChatterPayPaymaster,
    ChatterPayPaymaster__InvalidSignature,
    ChatterPayPaymaster__OnlyOwner,
    ChatterPayPaymaster__InvalidDataLength
} from "../../src/ChatterPayPaymaster.sol";
import {UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title PaymasterTest
 * @notice Test contract for validating ChatterPayPaymaster functionality
 * @dev Tests paymaster validation, signature verification, and error cases
 */
contract PaymasterTest is BaseTest {
    /// @notice Instance of the paymaster contract being tested
    ChatterPayPaymaster public paymasterInstance;

    /// @notice Backend signer's private key for testing
    uint256 private backendSignerKey;

    /// @notice Backend signer's address
    address private backendSigner;

    /// @notice Test wallet address
    address public testWallet;

    /// @notice Sets up the test environment
    function setUp() public override {
        super.setUp();

        // Setup backend signer
        backendSignerKey = 0x12345; // Test private key
        backendSigner = vm.addr(backendSignerKey);
        testWallet = makeAddr("testWallet");

        // Deploy paymaster with test configuration
        vm.startPrank(owner);
        paymasterInstance = new ChatterPayPaymaster(ENTRY_POINT, backendSigner);
        vm.deal(address(paymasterInstance), 10 ether); // Fund paymaster
        vm.stopPrank();
    }

    /**
     * @notice Tests successful validation of a properly signed UserOperation
     * @dev Verifies that a valid signature and unexpired timestamp pass validation
     */
    function testValidPaymasterUserOp() public {
        // Create test UserOperation
        UserOperation memory userOp = _createBasicUserOp();

        // Generate paymaster data with valid signature
        uint64 expiration = uint64(block.timestamp + 3600); // 1 hour from now
        bytes memory paymasterData = _generatePaymasterData(
            address(paymasterInstance), userOp.sender, expiration, userOp.callData, backendSignerKey
        );
        userOp.paymasterAndData = paymasterData;

        // Validate through EntryPoint
        vm.prank(ENTRY_POINT);
        (bytes memory context, uint256 validationData) =
            paymasterInstance.validatePaymasterUserOp(userOp, bytes32(0), 0);

        // Extract validUntil from validationData (bits 160-191)
        uint48 validUntil = uint48(validationData >> 160);

        // Assert validation succeeded and expiration time is properly set
        assertEq(validationData & 1, 0, "Signature verification should succeed");
        assertEq(validUntil, expiration, "validUntil should match expiration time");
        assertEq(context.length, 0, "Context should be empty");
    }

    /**
     * @notice Tests rejection of expired signatures
     * @dev Verifies that an expired timestamp causes validation to return correct validationData
     */
    function testExpiredSignature() public {
        UserOperation memory userOp = _createBasicUserOp();

        // Generate paymaster data with soon-to-expire timestamp
        uint64 expiration = uint64(block.timestamp + 10); // Expire soon
        bytes memory paymasterData = _generatePaymasterData(
            address(paymasterInstance), userOp.sender, expiration, userOp.callData, backendSignerKey
        );
        userOp.paymasterAndData = paymasterData;

        // Validate through EntryPoint
        vm.prank(ENTRY_POINT);
        (bytes memory context, uint256 validationData) =
            paymasterInstance.validatePaymasterUserOp(userOp, bytes32(0), 0);

        // Extract validUntil from validationData (bits 160-191)
        uint48 validUntil = uint48(validationData >> 160);

        // Assert validUntil is set correctly
        assertEq(validUntil, expiration, "validUntil should match expiration time");
        assertEq(context.length, 0, "Context should be empty");

        // Time travel past expiration
        vm.warp(block.timestamp + 20);

        // EntryPoint would reject this operation due to expiration
        // This test simulates the EntryPoint's behavior
        bool wouldBeRejected = block.timestamp > validUntil;
        assertTrue(wouldBeRejected, "Operation should be rejected after expiration");
    }

    /**
     * @notice Tests rejection of invalid signatures
     * @dev Verifies that an incorrectly signed operation is rejected
     */
    function testInvalidSignature() public {
        UserOperation memory userOp = _createBasicUserOp();

        // Generate paymaster data with wrong signer
        uint64 expiration = uint64(block.timestamp + 3600);
        uint256 wrongKey = 0x9999; // Different private key
        bytes memory paymasterData =
            _generatePaymasterData(address(paymasterInstance), userOp.sender, expiration, userOp.callData, wrongKey);
        userOp.paymasterAndData = paymasterData;

        // Expect revert on validation
        vm.prank(ENTRY_POINT);
        vm.expectRevert(ChatterPayPaymaster__InvalidSignature.selector);
        paymasterInstance.validatePaymasterUserOp(userOp, bytes32(0), 0);
    }

    /**
     * @notice Tests paymaster's ETH withdrawal functionality
     * @dev Verifies owner can withdraw ETH and non-owners cannot
     */
    function testWithdraw() public {
        uint256 initialBalance = 1 ether;
        vm.deal(address(paymasterInstance), initialBalance);

        // Test non-owner withdrawal (should fail)
        vm.prank(user);
        vm.expectRevert(ChatterPayPaymaster__OnlyOwner.selector);
        paymasterInstance.withdraw();

        // Test owner withdrawal (should succeed)
        uint256 ownerInitialBalance = owner.balance;
        vm.prank(owner);
        paymasterInstance.withdraw();

        assertEq(address(paymasterInstance).balance, 0, "Paymaster should have 0 balance");
        assertEq(owner.balance, ownerInitialBalance + initialBalance, "Owner should receive full balance");
    }

    /**
     * @notice Tests access control for execute function
     * @dev Verifies only owner can execute arbitrary calls
     */
    function testExecute() public {
        address destination = makeAddr("destination");
        bytes memory data = "";
        uint256 value = 0.1 ether;

        // Fund paymaster
        vm.deal(address(paymasterInstance), 1 ether);

        // Test non-owner execute (should fail)
        vm.prank(user);
        vm.expectRevert(ChatterPayPaymaster__OnlyOwner.selector);
        paymasterInstance.execute(destination, value, data);

        // Test owner execute (should succeed)
        vm.prank(owner);
        paymasterInstance.execute(destination, value, data);

        assertEq(destination.balance, value, "Destination should receive value");
    }

    /**
     * @notice Tests invalid data length in paymaster data
     */
    function testInvalidDataLength() public {
        UserOperation memory userOp = _createBasicUserOp();
        userOp.paymasterAndData = abi.encodePacked(address(paymasterInstance)); // Invalid length

        vm.prank(ENTRY_POINT);
        vm.expectRevert(ChatterPayPaymaster__InvalidDataLength.selector);
        paymasterInstance.validatePaymasterUserOp(userOp, bytes32(0), 0);
    }

    /**
     * @notice Tests validation with correct length but invalid format
     */
    function testValidDataLengthButInvalidFormat() public {
        UserOperation memory userOp = _createBasicUserOp();

        // Create data with correct length (93 bytes) but invalid content
        bytes memory invalidData = new bytes(93);
        for (uint256 i = 0; i < 93; i++) {
            invalidData[i] = bytes1(uint8(i)); // Fill with sequential values
        }

        userOp.paymasterAndData = invalidData;

        vm.prank(ENTRY_POINT);
        // This should fail during signature verification
        vm.expectRevert(); // Will likely revert with one of several possible errors
        paymasterInstance.validatePaymasterUserOp(userOp, bytes32(0), 0);
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a basic UserOperation for testing
    function _createBasicUserOp() internal view returns (UserOperation memory) {
        return UserOperation({
            sender: testWallet,
            nonce: 0,
            initCode: bytes(""),
            callData: abi.encodeWithSignature("test()"),
            callGasLimit: 1000000,
            verificationGasLimit: 1000000,
            preVerificationGas: 21000,
            maxFeePerGas: 100 gwei,
            maxPriorityFeePerGas: 100 gwei,
            paymasterAndData: bytes(""),
            signature: bytes("")
        });
    }

    /// @notice Generates paymaster data including signature
    function _generatePaymasterData(
        address paymaster,
        address sender,
        uint64 expiration,
        bytes memory callData,
        uint256 signerKey
    ) internal view returns (bytes memory) {
        // Create message hash
        bytes32 messageHash = keccak256(abi.encode(sender, expiration, uint256(block.chainid), ENTRY_POINT, callData));

        // Sign message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, messageHash);

        // Solidity and JavaScript handle signature formats differently
        // vm.sign may return v as 0 or 1, we need it to be 27 or 28
        if (v < 27) {
            v += 27;
        }

        // Crear paymasterAndData con disposición de bytes exacta y controlada
        bytes memory paymasterAndData = new bytes(93);

        // Copiar dirección del paymaster (primeros 20 bytes)
        for (uint256 i = 0; i < 20; i++) {
            paymasterAndData[i] = bytes20(paymaster)[i];
        }

        // Copiar r (32 bytes)
        for (uint256 i = 0; i < 32; i++) {
            paymasterAndData[20 + i] = bytes32(r)[i];
        }

        // Copiar s (32 bytes)
        for (uint256 i = 0; i < 32; i++) {
            paymasterAndData[52 + i] = bytes32(s)[i];
        }

        // Establecer v (1 byte)
        paymasterAndData[84] = bytes1(v);

        // Copiar expiración (8 bytes)
        for (uint256 i = 0; i < 8; i++) {
            paymasterAndData[85 + i] = bytes8(expiration)[i];
        }

        return paymasterAndData;
    }
}
