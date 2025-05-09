// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../../src/ChatterPayWalletFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FactoryTokenModule
 * @notice Test module for the globally whitelisted tokens in the factory
 * @dev Tests managing token whitelist at the factory level and wallets using these tokens
 */
contract FactoryTokenModule is BaseTest {
    // Test wallet instance
    ChatterPay walletInstance;
    address walletAddress;

    // Events
    event GlobalTokenWhitelisted(address indexed token, bool status);
    event GlobalPriceFeedUpdated(address indexed token, address indexed priceFeed);

    function setUp() public override {
        super.setUp();

        // Create a wallet without setting any local tokens
        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));
        
        // Disable freshness check for price feeds in tests
        walletInstance.updatePriceConfig(1 days, 8);
        vm.stopPrank();
    }

    /**
     * @notice Tests adding a token to the global whitelist
     */
    function testGlobalTokenWhitelisting() public {
        vm.startPrank(owner);
        
        // Set up expectations for events
        vm.expectEmit(true, true, true, true);
        emit GlobalTokenWhitelisted(USDC, true);
        vm.expectEmit(true, true, true, true);
        emit GlobalPriceFeedUpdated(USDC, USDC_USD_FEED);
        
        // Whitelist token at factory level
        factory.setGlobalTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        
        // Verify global whitelist state
        assertTrue(factory.globalWhitelistedTokens(USDC), "Token not whitelisted at factory level");
        assertEq(factory.globalPriceFeeds(USDC), USDC_USD_FEED, "Price feed not set at factory level");
        vm.stopPrank();
    }

    /**
     * @notice Tests that a wallet can use a token whitelisted at the factory level
     */
    function testWalletUsingGloballyWhitelistedToken() public {
        // First whitelist the token at the factory level
        vm.prank(owner);
        factory.setGlobalTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        
        // Verify the wallet can see the token as whitelisted
        assertTrue(walletInstance.isTokenWhitelisted(USDC), "Wallet doesn't see factory whitelisted token");
        assertEq(walletInstance.getPriceFeed(USDC), USDC_USD_FEED, "Wallet doesn't use factory price feed");
        
        // Fund the wallet with some tokens
        deal(USDC, walletAddress, 1000 * 10**6);

        // Test a transfer using the globally whitelisted token
        vm.startPrank(ENTRY_POINT);
        walletInstance.executeTokenTransfer(USDC, makeAddr("recipient"), 500 * 10**6);
        vm.stopPrank();
        
        // Verify transfer was successful
        uint256 recipientBalance = IERC20(USDC).balanceOf(makeAddr("recipient"));
        assertTrue(recipientBalance > 0, "Transfer with globally whitelisted token failed");
    }

    /**
     * @notice Tests that local wallet whitelist takes precedence over global whitelist
     */
    function testLocalWhitelistPrecedence() public {
        // Use USDT_USD_FEED as the custom price feed, which is a different
        // but valid price feed already set up in BaseTest
        address customPriceFeed = USDT_USD_FEED;
        
        // Whitelist at factory level
        vm.prank(owner);
        factory.setGlobalTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        
        // Whitelist with a different price feed at wallet level
        vm.prank(owner);
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, customPriceFeed);
        
        // Local price feed should take precedence
        assertEq(walletInstance.getPriceFeed(USDC), customPriceFeed, "Local price feed not taking precedence");
    }

    /**
     * @notice Tests removing a token from the global whitelist
     */
    function testRemovingTokenFromGlobalWhitelist() public {
        // First add the token
        vm.prank(owner);
        factory.setGlobalTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        
        // Verify it's whitelisted
        assertTrue(walletInstance.isTokenWhitelisted(USDC), "Token not whitelisted initially");
        
        // Now remove it
        vm.prank(owner);
        factory.setGlobalTokenWhitelistAndPriceFeed(USDC, false, USDC_USD_FEED);
        
        // Verify it's no longer whitelisted
        assertFalse(walletInstance.isTokenWhitelisted(USDC), "Token still whitelisted after removal");
    }

    /**
     * @notice Tests authorization control for the global whitelist
     */
    function testGlobalWhitelistAuthorizationControls() public {
        address unauthorized = makeAddr("unauthorized");
        
        // Attempt to whitelist with non-owner account
        vm.prank(unauthorized);
        vm.expectRevert(); // Should revert with Ownable error
        factory.setGlobalTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
    }
} 