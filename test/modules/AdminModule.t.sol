// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory, IUniswapV3Pool, INonfungiblePositionManager} from "../setup/BaseTest.sol";

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
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);
    event CustomSlippageSet(address indexed token, uint256 slippageBps);

    function wallet() public view returns (ChatterPay) {
        return walletInstance;
    }

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        walletAddress = factory.createProxy(owner);
        walletInstance = ChatterPay(payable(walletAddress));

        // Disable freshness check for price feeds in tests
        walletInstance.updatePriceConfig(1 days, 8);

        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        walletInstance.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);
        walletInstance.addStableToken(USDC);
        walletInstance.addStableToken(USDT);
        walletInstance.updateFee(50);
        vm.stopPrank();
    }

    /**
     * @notice Tests fee admin management
     */
    function testFeeManagement() public {
        vm.startPrank(owner);
        assertEq(walletInstance.getFeeInCents(), 50);
        walletInstance.updateFee(100);
        assertEq(walletInstance.getFeeInCents(), 100);
        vm.stopPrank();
    }

    /**
     * @notice Tests token whitelist management
     */
    function testTokenWhitelisting() public {
        vm.startPrank(owner);
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        assertTrue(walletInstance.isTokenWhitelisted(USDC));
        assertEq(walletInstance.getPriceFeed(USDC), USDC_USD_FEED);
        vm.stopPrank();
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
        assertEq(walletInstance.getCustomPoolFee(pairHash), customFee, "Custom pool fee not set");

        // Test invalid fee
        vm.expectRevert();
        walletInstance.setCustomPoolFee(USDC, USDT, 1_000_000);

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
        assertEq(walletInstance.getCustomSlippage(USDC), slippageBps, "Custom slippage not set");

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
        assertTrue(walletInstance.isTokenWhitelisted(USDC), "State lost after upgrade");

        // Test unauthorized upgrade
        vm.stopPrank();
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        walletInstance.upgradeToAndCall(address(newImplementation), "");
    }

    /**
     * @notice Ensures storage is preserved after an upgrade from proxy
     */
    function testStoragePreservedAcrossUpgrade() public {
        vm.startPrank(owner);

        // Initial state setup
        walletInstance.updateFee(111);
        walletInstance.setCustomSlippage(USDC, 250);

        // Deploy new implementation
        ChatterPay newImpl = new ChatterPay();

        // Upgrade via proxy
        walletInstance.upgradeToAndCall(address(newImpl), "");

        // Re-attach
        ChatterPay upgraded = ChatterPay(payable(walletAddress));

        // Only verify state
        assertEq(upgraded.getFeeInCents(), 111);
        assertEq(upgraded.getCustomSlippage(USDC), 250);

        vm.stopPrank();
    }

    /**
     * @notice Tests access control for admin functions
     */
    function testAccessControl() public {
        address unauthorized = makeAddr("unauthorized");

        vm.startPrank(unauthorized);

        // Functions that still use onlyOwner
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized));
        walletInstance.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized));
        walletInstance.setCustomPoolFee(USDC, USDT, 500);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized));
        walletInstance.setCustomSlippage(USDC, 100);

        vm.stopPrank();

        // Functions that use onlyChatterPayAdmin
        address notAdmin = makeAddr("notAdmin");
        vm.startPrank(notAdmin);

        vm.expectRevert(abi.encodeWithSignature("ChatterPay__NotFromChatterPayAdmin()"));
        walletInstance.updateFee(75);

        vm.expectRevert(abi.encodeWithSignature("ChatterPay__NotFromChatterPayAdmin()"));
        walletInstance.upgradeToAndCall(address(0x123), "");

        vm.stopPrank();
    }

    /**
     * @notice Tests that the factory admin (ChatterPay admin) can access restricted admin functions
     * @dev Validates that only the factory.owner() is authorized to call functions guarded by onlyChatterPayAdmin
     */
    function testChatterPayAdminCanAccessAdminFunctions() public {
        // Use the actual ChatterPay admin, which is the factory's owner
        address admin = factory.owner();

        // Deploy a dummy new implementation for the upgrade
        ChatterPay newImplementation = new ChatterPay();

        // Act as the admin
        vm.startPrank(admin);

        // Should succeed without revert
        walletInstance.updateFee(80);
        walletInstance.upgradeToAndCall(address(newImplementation), ""); // Safe dummy upgrade

        vm.stopPrank();

        // Check that fee was updated correctly
        assertEq(walletInstance.getFeeInCents(), 80);
    }

    /**
     * @notice Tests adding a token to the stable token list and checks duplicate prevention
     */
    function testAddStableToken() public {
        vm.startPrank(owner);

        address fakeStable = makeAddr("fakeStable");

        // Should add token successfully
        walletInstance.addStableToken(fakeStable);
        assertTrue(walletInstance.isStableToken(fakeStable));

        // Should revert if token is already stable
        vm.expectRevert(abi.encodeWithSignature("ChatterPay__AlreadyStableToken()"));
        walletInstance.addStableToken(fakeStable);

        vm.stopPrank();
    }

    /**
     * @notice Tests removing a token from the stable token list and checks removal edge case
     */
    function testRemoveStableToken() public {
        vm.startPrank(owner);

        address fakeStable = makeAddr("fakeStable");

        // Add first
        walletInstance.addStableToken(fakeStable);
        assertTrue(walletInstance.isStableToken(fakeStable));

        // Remove
        walletInstance.removeStableToken(fakeStable);
        assertFalse(walletInstance.isStableToken(fakeStable));

        // Should revert if token is already removed
        vm.expectRevert(abi.encodeWithSignature("ChatterPay__NotStableToken()"));
        walletInstance.removeStableToken(fakeStable);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Calculates hash for token pair
     */
    function _getPairHash(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }
}
