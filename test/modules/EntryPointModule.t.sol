// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20Extended} from "../../src/ChatterPay.sol";

/**
 * @title EntryPointModule
 * @notice Test suite for ChatterPay's ERC-4337 EIP-712 signature validation
 */
contract EntryPointModule is BaseTest {
    ChatterPay public walletInstance;
    address public walletAddress;

    uint256 constant GAS_LIMIT = 1000000;
    uint256 constant MAX_FEE = 100 gwei;
    uint256 constant PRE_VERIFICATION_GAS = 100000;
    uint256 constant VERIFICATION_GAS_LIMIT = 150000;

    bytes32 internal constant USER_OP_TYPEHASH = keccak256(
        "UserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,uint256 callGasLimit,uint256 verificationGasLimit,uint256 preVerificationGas,uint256 maxFeePerGas,uint256 maxPriorityFeePerGas,bytes paymasterAndData,uint256 chainId)"
    );

    function setUp() public override {
        super.setUp();
        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        walletInstance.addStableToken(USDT);
        vm.stopPrank();
    }

    function testBasicUserOpValidation() public {
        UserOperation memory userOp = _createBasicUserOp();
        userOp.signature = _signUserOp(userOp, ownerKey, address(walletInstance));
        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(userOp, bytes32(0), 0);
        assertEq(validationData, 0);
    }

    function testUserOpWithTokenTransfer() public {
        uint256 TRANSFER_AMOUNT = 100e6;
        _fundWallet(walletAddress, TRANSFER_AMOUNT);
        vm.deal(address(walletInstance), 1 ether);

        bytes memory callData =
            abi.encodeWithSelector(ChatterPay.executeTokenTransfer.selector, USDC, user, TRANSFER_AMOUNT);

        UserOperation memory userOp = _createUserOp(callData);
        userOp.signature = _signUserOp(userOp, ownerKey, address(walletInstance));

        vm.prank(ENTRY_POINT);
        walletInstance.validateUserOp(userOp, bytes32(0), 0);
    }

    function testUserOpWithPaymaster() public {
        vm.deal(address(paymaster), 10 ether);
        vm.deal(address(walletInstance), 1 ether);

        bytes memory callData = abi.encodeWithSelector(ChatterPay.executeTokenTransfer.selector, USDC, user, 100e6);

        UserOperation memory userOp = _createUserOp(callData);
        userOp.paymasterAndData = abi.encodePacked(address(paymaster));
        userOp.signature = _signUserOp(userOp, ownerKey, address(walletInstance));

        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(userOp, bytes32(0), 1 ether);
        assertEq(validationData, 0, "UserOp with paymaster should pass");
    }

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
            userOps[i].signature = _signUserOp(userOps[i], ownerKey, address(walletInstance));
        }

        for (uint256 i = 0; i < userOps.length; i++) {
            vm.prank(ENTRY_POINT);
            uint256 validationData = walletInstance.validateUserOp(userOps[i], bytes32(0), 0);
            assertEq(validationData, 0, string.concat("UserOp ", vm.toString(i), " validation failed"));
        }
    }

    function testInvalidSignature() public {
        UserOperation memory userOp = _createBasicUserOp();
        userOp.signature = _signUserOp(userOp, 0x1234, address(walletInstance));

        vm.prank(ENTRY_POINT);
        uint256 validationData = walletInstance.validateUserOp(userOp, bytes32(0), 0);
        assertEq(validationData, 1, "Invalid signature should fail");
    }

    function testPrefundHandling() public {
        vm.deal(address(walletInstance), 2 ether);
        uint256 initialBalance = address(walletInstance).balance;

        UserOperation memory userOp = _createBasicUserOp();
        userOp.signature = _signUserOp(userOp, ownerKey, address(walletInstance));

        vm.prank(ENTRY_POINT);
        walletInstance.validateUserOp(userOp, bytes32(0), 1 ether);

        assertEq(address(walletInstance).balance, initialBalance - 1 ether);
    }

    function _createBasicUserOp() internal view returns (UserOperation memory) {
        return _createUserOp("");
    }

    function _createUserOp(bytes memory callData) internal view returns (UserOperation memory) {
        return UserOperation({
            sender: address(walletInstance),
            nonce: 0,
            initCode: "",
            callData: callData,
            callGasLimit: GAS_LIMIT,
            verificationGasLimit: VERIFICATION_GAS_LIMIT,
            preVerificationGas: PRE_VERIFICATION_GAS,
            maxFeePerGas: MAX_FEE,
            maxPriorityFeePerGas: MAX_FEE,
            paymasterAndData: "",
            signature: ""
        });
    }

    function _getUserOpDigest(UserOperation memory userOp, address verifyingContract) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                USER_OP_TYPEHASH,
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                keccak256(userOp.paymasterAndData),
                block.chainid
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ChatterPay")),
                keccak256(bytes("1.0.0")),
                block.chainid,
                verifyingContract
            )
        );

        return keccak256(abi.encodePacked("\\x19\\x01", domainSeparator, structHash));
    }

    function _signUserOp(UserOperation memory userOp, uint256 privateKey, address verifyingContract)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = _getUserOpDigest(userOp, verifyingContract);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _calculateExpectedFee(address token, uint256 feeInCents) internal view returns (uint256) {
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        return (feeInCents * (10 ** tokenDecimals)) / 100;
    }
}
