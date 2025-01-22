// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/L2/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AdminModule
 * @notice Test module for ChatterPay administrative functionality
 * @dev Tests fee management, token whitelisting, upgrades, and other admin functions
 */
contract AdminModule is BaseTest {
    // Test walletInstance instance
    ChatterPay walletInstance;
    address walletAddress;

    // Events
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event TokenWhitelisted(address indexed token, bool status);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event FeeAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);
    event CustomSlippageSet(address indexed token, uint256 slippageBps);

    function wallet() public view returns (ChatterPay) {
        return walletInstance;
    }
    
    function setUp() public override {
        super.setUp();
        
        // Deploy wallet
        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        vm.stopPrank();
    }

    /**
     * @notice Tests fee management functionality
     */
    function testFeeManagement() public {
        vm.startPrank(owner);

        // Test initial fee
        uint256 initialFee = walletInstance.s_feeInCents();
        
        // Update fee
        uint256 newFee = 100; // $1.00
        vm.expectEmit(true, true, true, true);
        emit FeeUpdated(initialFee, newFee);
        walletInstance.updateFee(newFee);
        
        // Verify fee update
        assertEq(walletInstance.s_feeInCents(), newFee, "Fee not updated correctly");

        // Test fee limits
        vm.expectRevert(); // Should revert with fee too high
        walletInstance.updateFee(10000); // $100.00

        vm.stopPrank();
    }

    /**
     * @notice Tests token whitelist management
     */
    function testTokenWhitelisting() public {
        vm.startPrank(owner);

        // Test whitelisting token
        vm.expectEmit(true, true, true, true);
        emit TokenWhitelisted(USDC, true);
        emit PriceFeedUpdated(USDC, USDC_USD_FEED);
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);

        // Verify whitelist status
        assertTrue(walletInstance.s_whitelistedTokens(USDC), "Token not whitelisted");
        assertEq(walletInstance.s_priceFeeds(USDC), USDC_USD_FEED, "Price feed not set");

        // Test removing from whitelist
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, false, address(0));
        assertFalse(walletInstance.s_whitelistedTokens(USDC), "Token still whitelisted");
        assertEq(walletInstance.s_priceFeeds(USDC), address(0), "Price feed not cleared");

        vm.stopPrank();
    }

    /**
     * @notice Tests fee admin management
     */
    function testFeeAdminManagement() public {
        vm.startPrank(owner);

        // Set new fee admin
        address newFeeAdmin = makeAddr("newFeeAdmin");
        vm.expectEmit(true, true, true, true);
        emit FeeAdminUpdated(address(0), newFeeAdmin);
        walletInstance.updateFeeAdmin(newFeeAdmin);

        // Verify fee admin permissions
        vm.stopPrank();
        
        vm.prank(newFeeAdmin);
        walletInstance.updateFee(75); // Should succeed
        
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(); // Should fail
        walletInstance.updateFee(100);
    }

    /**
     * @notice Tests custom pool fee management
     */
    function testCustomPoolFees() public {
        vm.startPrank(owner);

        // Set custom pool fee
        uint24 customFee = 500; // 0.05%
        vm.expectEmit(true, true, true, true);
        emit CustomPoolFeeSet(USDC, USDT, customFee);
        walletInstance.setCustomPoolFee(USDC, USDT, customFee);

        // Verify custom fee
        bytes32 pairHash = _getPairHash(USDC, USDT);
        assertEq(walletInstance.s_customPoolFees(pairHash), customFee, "Custom pool fee not set");

        // Test invalid fee
        vm.expectRevert(); // Should revert with invalid fee
        walletInstance.setCustomPoolFee(USDC, USDT, 1_000_000); // 100%

        vm.stopPrank();
    }

    /**
     * @notice Tests custom slippage management
     */
    function testCustomSlippage() public {
        vm.startPrank(owner);

        // Set custom slippage
        uint256 slippageBps = 100; // 1%
        vm.expectEmit(true, true, true, true);
        emit CustomSlippageSet(USDC, slippageBps);
        walletInstance.setCustomSlippage(USDC, slippageBps);

        // Verify custom slippage
        assertEq(walletInstance.s_customSlippage(USDC), slippageBps, "Custom slippage not set");

        // Test invalid slippage
        vm.expectRevert(); // Should revert with invalid slippage
        walletInstance.setCustomSlippage(USDC, 5001); // > 50%

        vm.stopPrank();
    }

    /**
     * @notice Tests contract upgrade functionality
     */
    function testUpgrade() public {
        vm.startPrank(owner);

        // Deploy new implementation
        ChatterPay newImplementation = new ChatterPay();

        // Perform upgrade
        walletInstance.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade
        assertTrue(walletInstance.s_whitelistedTokens(USDC), "State lost after upgrade");

        // Test unauthorized upgrade
        vm.stopPrank();
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        walletInstance.upgradeToAndCall(address(newImplementation), "");
    }

    /**
     * @notice Tests access control for admin functions
     */
    function testAccessControl() public {
        address unauthorized = makeAddr("unauthorized");
        vm.startPrank(unauthorized);

        // Try all admin functions with unauthorized account
        vm.expectRevert();
        walletInstance.updateFee(100);

        vm.expectRevert();
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);

        vm.expectRevert();
        walletInstance.updateFeeAdmin(unauthorized);

        vm.expectRevert();
        walletInstance.setCustomPoolFee(USDC, USDT, 500);

        vm.expectRevert();
        walletInstance.setCustomSlippage(USDC, 100);

        vm.expectRevert();
        walletInstance.upgradeToAndCall(address(0x123), "");
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Calculates hash for token pair
     */
    function _getPairHash(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            tokenA < tokenB ? tokenA : tokenB,
            tokenA < tokenB ? tokenB : tokenA
        ));
    }
}