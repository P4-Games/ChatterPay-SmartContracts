// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {IERC20Extended} from "../../src/ChatterPay.sol";

/**
 * @title TransferModule
 * @notice Test module for ChatterPay token transfer functionality
 * @dev Tests single transfers, batch transfers, fee calculations and validations
 */
contract TransferModule is BaseTest {
    // Events for test tracking
    event TransferExecuted(address indexed token, address indexed recipient, uint256 amount);
    event FeeCollected(address indexed token, uint256 feeAmount);

    // Test constants
    uint256 constant TRANSFER_AMOUNT = 1000e6; // 1000 USDC
    uint256 EXPECTED_FEE = 5e5; // 0.5 cents in USDC
    uint256 constant FEE_TOLERANCE = 1e4; // 0.01 USDC tolerance for price fluctuations

    ChatterPay walletInstance;
    address walletAddress;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        walletInstance.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);
        vm.stopPrank();
    }

    function wallet() public view returns (ChatterPay) {
        return walletInstance;
    }

    function testBasicTransfer() public {
        _fundWallet(walletAddress, TRANSFER_AMOUNT);

        uint256 expectedFee = 500000; // 0.5 USDC
        uint256 initialRecipientBalance = IERC20(USDC).balanceOf(user);

        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, user, TRANSFER_AMOUNT);

        uint256 actualReceivedAmount = IERC20(USDC).balanceOf(user) - initialRecipientBalance;
        uint256 expectedReceivedAmount = TRANSFER_AMOUNT - expectedFee;
        assertApproxEqAbs(actualReceivedAmount, expectedReceivedAmount, FEE_TOLERANCE);
    }

    /**
     * @notice Tests batch token transfer functionality
     */
    function testBatchTransfer() public {
        uint256 totalAmount = 600e6 + (EXPECTED_FEE * 3);
        _fundWallet(walletAddress, totalAmount);

        address feeAdmin = walletInstance.getFeeAdmin();
        uint256 initialFeeBalance = IERC20(USDC).balanceOf(feeAdmin);

        address[] memory recipients = new address[](3);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = makeAddr("recipient2");
        recipients[2] = makeAddr("recipient3");

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e6;
        amounts[1] = 200e6;
        amounts[2] = 300e6;

        address[] memory tokens = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokens[i] = USDC;
        }

        vm.prank(ENTRY_POINT);
        walletInstance.executeBatchTokenTransfer(tokens, recipients, amounts);

        uint256 finalFeeBalance = IERC20(USDC).balanceOf(feeAdmin);
        uint256 feesCollected = finalFeeBalance - initialFeeBalance;
        assertApproxEqAbs(feesCollected, EXPECTED_FEE * 3, FEE_TOLERANCE * 3, "Incorrect fees collected");
    }

    /**
     * @notice Tests transfer with insufficient balance
     */
    function testInsufficientBalance() public {
        _fundWallet(walletAddress, EXPECTED_FEE);

        vm.expectRevert();
        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, user, TRANSFER_AMOUNT);
    }

    /**
     * @notice Tests transfer with non-whitelisted token
     */
    /**
     * @notice Tests transfer with non-whitelisted token
     */
    function testNonWhitelistedToken() public {
        vm.startPrank(owner);
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, false, USDC_USD_FEED);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, user, TRANSFER_AMOUNT);
    }

    /**
     * @notice Tests transfer with zero amount
     */
    function testZeroAmount() public {
        vm.expectRevert();
        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, user, 0);
    }

    /**
     * @notice Tests transfer to zero address
     */
    function testZeroAddress() public {
        _fundWallet(walletAddress, TRANSFER_AMOUNT);

        vm.expectRevert();
        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, address(0), TRANSFER_AMOUNT);
    }

    /**
     * @notice Tests fee calculation accuracy
     */
    function testFeeCalculation() public {
        // Test different fee amounts
        uint256[] memory testAmounts = new uint256[](3);
        testAmounts[0] = 100e6; // 100 USDC
        testAmounts[1] = 1000e6; // 1000 USDC
        testAmounts[2] = 10000e6; // 10000 USDC

        for (uint256 i = 0; i < testAmounts.length; i++) {
            // Fund wallet
            _fundWallet(walletAddress, testAmounts[i]);

            uint256 initialFeeAdminBalance = IERC20(USDC).balanceOf(walletInstance.getFeeAdmin());

            // Execute transfer
            vm.prank(ENTRY_POINT);
            walletInstance.executeTokenTransfer(USDC, user, testAmounts[i]);

            uint256 feeCollected = IERC20(USDC).balanceOf(walletInstance.getFeeAdmin()) - initialFeeAdminBalance;
            assertApproxEqAbs(feeCollected, EXPECTED_FEE, FEE_TOLERANCE, "Incorrect fee amount collected");
        }
    }

    /**
     * @notice Tests fee calculations and deductions for transfers
     */
    function testTransferFees() public {
        // Fund wallet
        _fundWallet(walletAddress, 1000e6); // 1000 USDC

        // Get initial balances
        uint256 initialFeeAdminBalance = IERC20(USDC).balanceOf(walletInstance.getFeeAdmin());
        uint256 initialRecipientBalance = IERC20(USDC).balanceOf(user);

        // Execute transfer
        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, user, 100e6); // Transfer 100 USDC

        // Calculate expected fee
        uint256 fee = _calculateExpectedFee(USDC, 50);

        // Verify fee was taken
        assertApproxEqAbs(
            IERC20(USDC).balanceOf(walletInstance.getFeeAdmin()) - initialFeeAdminBalance,
            fee,
            FEE_TOLERANCE,
            "Fee not transferred correctly"
        );

        // Verify recipient received correct amount
        assertApproxEqAbs(
            IERC20(USDC).balanceOf(user) - initialRecipientBalance,
            100e6 - fee,
            FEE_TOLERANCE,
            "Recipient received wrong amount"
        );
    }

    /**
     * @dev Helper function to calculate expected fee
     */
    function _calculateExpectedFee(address token, uint256 feeInCents) internal view returns (uint256) {
        uint256 tokenDecimals = IERC20Extended(token).decimals();

        return (feeInCents * (10 ** tokenDecimals)) / 100;
    }
}
