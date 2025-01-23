// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20Extended} from "../../src/ChatterPay.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

/**
 * @title EntryPointModule Test Contract
 * @notice Test contract for validating ChatterPay's ERC-4337 integration
 * @dev Contains tests for UserOperation validation, signature verification, and paymaster interactions
 */
contract EntryPointModule is BaseTest {
    /// @notice Instance of the ChatterPay wallet being tested
    ChatterPay public walletInstance;
    
    /// @notice Address of the deployed wallet instance
    address public walletAddress;

    /// @notice Gas limit for user operations
    uint256 constant GAS_LIMIT = 1000000;
    
    /// @notice Maximum fee per gas for user operations
    uint256 constant MAX_FEE = 100 gwei;
    
    /// @notice Pre-verification gas amount for user operations
    uint256 constant PRE_VERIFICATION_GAS = 100000;
    
    /// @notice Gas limit for verification phase
    uint256 constant VERIFICATION_GAS_LIMIT = 150000;

    /// @notice Sets up the test environment
    /// @dev Deploys a new wallet instance and configures initial token settings
    function setUp() public override {
        super.setUp();
        
        // Deploy wallet
        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        vm.stopPrank();
    }

    /// @notice Getter function for the wallet instance
    /// @return ChatterPay The current wallet instance
    function wallet() public view returns (ChatterPay) {
        return walletInstance;
    }

    /**
     * @notice Tests basic validation of a UserOperation
     * @dev Verifies that a properly signed UserOperation passes validation
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
     * @notice Tests execution of a UserOperation containing a token transfer
     * @dev Validates a UserOperation that transfers USDC tokens
     */
    function testUserOpWithTokenTransfer() public {
        uint256 TRANSFER_AMOUNT = 100e6; // 100 USDC
        _fundWallet(walletAddress, TRANSFER_AMOUNT);
        vm.deal(address(walletInstance), 1 ether);

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
     * @notice Tests UserOperation with paymaster integration
     * @dev Verifies that a UserOperation with paymaster data is properly validated
     */
    function testUserOpWithPaymaster() public {
        vm.deal(address(paymaster), 10 ether);
        vm.deal(address(walletInstance), 1 ether);

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

        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(
            userOp,
            userOpHash,
            1 ether
        );

        assertEq(validationData, 0, "UserOp validation with paymaster failed");
    }

    /**
     * @notice Tests batch processing of multiple UserOperations
     * @dev Creates and validates multiple token transfer operations
     */
    function testBatchUserOps() public {
        _fundWallet(walletAddress, 1000e6);

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
     * @notice Tests rejection of UserOperations with invalid signatures
     * @dev Attempts to validate a UserOperation signed with incorrect key
     */
    function testInvalidSignature() public {
        UserOperation memory userOp = _createBasicUserOp();
        bytes32 userOpHash = _getUserOpHash(userOp);
        
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
     * @notice Tests prefund handling in UserOperations
     * @dev Verifies correct ETH balance changes during prefund phase
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

    /// @notice Creates a basic UserOperation with empty calldata
    /// @return UserOperation A basic UserOperation instance
    function _createBasicUserOp() internal view returns (UserOperation memory) {
        return _createUserOp("");
    }

    /// @notice Creates a UserOperation with specified calldata
    /// @param callData The calldata to include in the UserOperation
    /// @return UserOperation The created UserOperation instance
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

    /// @notice Calculates the hash of a UserOperation
    /// @param userOp The UserOperation to hash
    /// @return bytes32 The calculated hash
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

    /// @notice Signs a UserOperation hash with a private key
    /// @param userOpHash The hash to sign
    /// @param privateKey The private key to sign with
    /// @return bytes The signature
    function _signUserOp(
        bytes32 userOpHash,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Calculates the expected fee in token decimals
    /// @param token The token address
    /// @param feeInCents The fee amount in cents
    /// @return uint256 The calculated fee amount in token decimals
    function _calculateExpectedFee(
        address token,
        uint256 feeInCents
    ) internal view returns (uint256) {
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        
        return (feeInCents * (10 ** tokenDecimals)) / 100;
    }
}