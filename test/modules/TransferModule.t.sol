// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/L2/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol"; 
import {IERC20Extended} from "../../src/L2/ChatterPay.sol";

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
    uint256 constant EXPECTED_FEE = 50e6;      // 50 cents in USDC
    
    ChatterPay walletInstance;
    address walletAddress;

    function setUp() public override {
        super.setUp();
        
        // Deploy wallet
        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        vm.stopPrank();
    }

    /**
     * @notice Tests basic token transfer with fee
     */
    function testBasicTransfer() public {
        // En lugar de crear un nuevo wallet, usa el que ya existe
        _fundWallet(walletAddress, TRANSFER_AMOUNT);
        
        uint256 initialBalance = IERC20(USDC).balanceOf(walletAddress);
        uint256 initialRecipientBalance = IERC20(USDC).balanceOf(user);
        uint256 initialFeeAdminBalance = IERC20(USDC).balanceOf(walletInstance.s_feeAdmin());

        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, user, TRANSFER_AMOUNT);

        // Post-transfer checks
        uint256 finalBalance = IERC20(USDC).balanceOf(walletAddress);
        uint256 finalRecipientBalance = IERC20(USDC).balanceOf(user);
        uint256 finalFeeAdminBalance = IERC20(USDC).balanceOf(walletInstance.s_feeAdmin());

        assertEq(finalBalance, initialBalance - TRANSFER_AMOUNT, "Incorrect walletInstance balance after transfer");
        assertEq(finalRecipientBalance, initialRecipientBalance + (TRANSFER_AMOUNT - EXPECTED_FEE), "Incorrect recipient balance");
        assertEq(finalFeeAdminBalance, initialFeeAdminBalance + EXPECTED_FEE, "Incorrect fee transfer");
    }

    /**
     * @notice Tests batch token transfer functionality
     */
    function testBatchTransfer() public {
        // Setup recipients and amounts
        address[] memory recipients = new address[](3);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = makeAddr("recipient2");
        recipients[2] = makeAddr("recipient3");

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e6;
        amounts[1] = 200e6;
        amounts[2] = 300e6;

        uint256 totalAmount = 600e6; // Sum of all transfers
        _fundWallet(walletAddress, totalAmount + (EXPECTED_FEE * 3)); // Include fees for all transfers

        vm.prank(ENTRY_POINT);
        
        address[] memory tokens = new address[](3);
        for(uint i = 0; i < 3; i++) {
            tokens[i] = USDC;
        }

        walletInstance.executeBatchTokenTransfer(tokens, recipients, amounts);

        // Verify each recipient's balance
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(
                IERC20(USDC).balanceOf(recipients[i]),
                amounts[i] - EXPECTED_FEE,
                string.concat("Incorrect recipient balance for recipient ", vm.toString(i))
            );
        }

        // Verify fees collected
        assertEq(
            IERC20(USDC).balanceOf(walletInstance.s_feeAdmin()),
            EXPECTED_FEE * 3,
            "Incorrect total fees collected"
        );
    }

    /**
     * @notice Tests transfer with insufficient balance
     */
    function testFailInsufficientBalance() public {
        // Fund walletInstance with insufficient amount
        _fundWallet(walletAddress, EXPECTED_FEE); // Only fund fee amount

        // Should revert
        vm.prank(ENTRY_POINT);
        vm.expectRevert(); // Should revert with insufficient balance
        walletInstance.executeTokenTransfer(USDC, user, TRANSFER_AMOUNT);
    }

    /**
     * @notice Tests transfer with non-whitelisted token
     */
    function testFailNonWhitelistedToken() public {
        vm.startPrank(owner);
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, false, address(0));
        vm.stopPrank();

        vm.prank(ENTRY_POINT);
        vm.expectRevert(); // Should revert with token not whitelisted
        walletInstance.executeTokenTransfer(USDC, user, TRANSFER_AMOUNT);
    }

    /**
     * @notice Tests transfer with zero amount
     */
    function testFailZeroAmount() public {
        // Try to transfer zero amount
        vm.prank(ENTRY_POINT);
        vm.expectRevert(); // Should revert with zero amount
        walletInstance.executeTokenTransfer(USDC, user, 0);
    }

    /**
     * @notice Tests transfer to zero address
     */
    function testFailZeroAddress() public {
        // Fund wallet
        _fundWallet(walletAddress, TRANSFER_AMOUNT);

        // Try to transfer to zero address
        vm.prank(ENTRY_POINT);
        vm.expectRevert(); // Should revert with zero address
        walletInstance.executeTokenTransfer(USDC, address(0), TRANSFER_AMOUNT);
    }

    /**
     * @notice Tests fee calculation accuracy
     */
    function testFeeCalculation() public {
        // Test different fee amounts
        uint256[] memory testAmounts = new uint256[](3);
        testAmounts[0] = 100e6;   // 100 USDC
        testAmounts[1] = 1000e6;  // 1000 USDC
        testAmounts[2] = 10000e6; // 10000 USDC

        for (uint256 i = 0; i < testAmounts.length; i++) {
            // Fund wallet
            _fundWallet(walletAddress, testAmounts[i]);
            
            uint256 initialFeeAdminBalance = IERC20(USDC).balanceOf(walletInstance.s_feeAdmin());
            
            // Execute transfer
            vm.prank(ENTRY_POINT);
            walletInstance.executeTokenTransfer(USDC, user, testAmounts[i]);
            
            uint256 feeCollected = IERC20(USDC).balanceOf(walletInstance.s_feeAdmin()) - initialFeeAdminBalance;
            assertEq(feeCollected, EXPECTED_FEE, "Incorrect fee amount collected");
        }
    }

    /**
     * @notice Tests fee calculations and deductions for transfers
     */
    function testTransferFees() public {
        // Fund wallet
        _fundWallet(walletAddress, 1000e6);  // 1000 USDC
        
        // Get initial balances
        uint256 initialFeeAdminBalance = IERC20(USDC).balanceOf(walletInstance.s_feeAdmin());
        uint256 initialRecipientBalance = IERC20(USDC).balanceOf(user);
        
        // Execute transfer
        vm.prank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, user, 100e6);  // Transfer 100 USDC
        
        // Calculate expected fee
        uint256 fee = _calculateExpectedFee(USDC, walletInstance.s_feeInCents());
        
        // Verify fee was taken
        assertEq(
            IERC20(USDC).balanceOf(walletInstance.s_feeAdmin()) - initialFeeAdminBalance,
            fee,
            "Fee not transferred correctly"
        );
        
        // Verify recipient received correct amount
        assertEq(
            IERC20(USDC).balanceOf(user) - initialRecipientBalance,
            100e6 - fee,
            "Recipient received wrong amount"
        );
    }

    /**
     * @dev Helper function to calculate expected fee
     */
    function _calculateExpectedFee(
        address token,
        uint256 feeInCents
    ) internal view returns (uint256) {
        (uint256 price, , , , ) = AggregatorV3Interface(walletInstance.s_priceFeeds(token)).latestRoundData();
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        return (feeInCents * (10 ** tokenDecimals)) / (price / 1e8) / 100;
    }
}