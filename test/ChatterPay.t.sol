// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./setup/BaseTest.sol";
import {Test, console} from "forge-std/Test.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";
import {SwapModule} from "./modules/SwapModule.t.sol";
import {AdminModule} from "./modules/AdminModule.t.sol";
import {TransferModule} from "./modules/TransferModule.t.sol";
import {SecurityModule} from "./modules/SecurityModule.t.sol";
import {EntryPointModule} from "./modules/EntryPointModule.t.sol";

/**
 * @title ChatterPayTest
 * @notice Main test coordinator for ChatterPay smart contracts
 * @dev Orchestrates all test modules and provides common setup
 */
contract ChatterPayTest is BaseTest {
    // Test modules
    SwapModule public swapTests;
    TransferModule public transferTests;
    AdminModule public adminTests;
    SecurityModule public securityTests;
    EntryPointModule public entryPointTests;

    /**
     * @notice Sets up the test environment and initializes all test modules
     */
    function setUp() public override {
        super.setUp();
        
        // Initialize test modules with proper inheritance
        swapTests = new SwapModule();
        swapTests.setUp();

        transferTests = new TransferModule();
        transferTests.setUp();

        adminTests = new AdminModule();
        adminTests.setUp();

        securityTests = new SecurityModule();
        securityTests.setUp();

        entryPointTests = new EntryPointModule();
        entryPointTests.setUp();

        // Whitelist USDC token for all modules
        vm.startPrank(owner);
        swapTests.wallet().setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        transferTests.wallet().setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        adminTests.wallet().setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        securityTests.wallet().setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        entryPointTests.wallet().setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        vm.stopPrank();
    }

    /**
     * @notice Tests basic wallet creation and setup
     */
    function testCreateWallet() public {
        vm.startPrank(owner);
        address walletAddress = factory.createProxy(owner);
        console.log("Wallet deployed at:", walletAddress);

        ChatterPay wallet = ChatterPay(payable(walletAddress));
        assertEq(wallet.owner(), owner);
        assertEq(address(wallet.swapRouter()), UNISWAP_ROUTER);
        vm.stopPrank();
    }

    /**
     * @notice Runs all swap-related tests
     */
    function testSwapFeatures() public {
        // Test basic swap functionality
        swapTests.testBasicSwap();
        
        // Test custom configurations
        swapTests.testSwapWithCustomPoolFee();
        swapTests.testSwapWithCustomSlippage();
        
        // Test fee calculations
        swapTests.testSwapWithFee();
        
        // Test failure cases
        swapTests.testFailInvalidSwap();
        
        // Test complete workflow
        swapTests.testTokenSetupAndSwap();
    }

    /**
     * @notice Runs all transfer-related tests
     */
    function testTransferFeatures() public {
        // Test single transfer
        transferTests.testBasicTransfer();
        
        // Test batch transfers
        transferTests.testBatchTransfer();
        
        // Test fee calculations
        transferTests.testTransferFees();
        
        // Test failure cases
        transferTests.testInsufficientBalance();
        transferTests.testNonWhitelistedToken();
        transferTests.testZeroAmount();
    }

    /**
     * @notice Runs all admin-related tests
     */
    function testAdminFeatures() public {
        // Test fee management
        adminTests.testFeeManagement();
        
        // Test token whitelisting
        adminTests.testTokenWhitelisting();
        
        // Test admin roles
        adminTests.testFeeAdminManagement();
        
        // Test custom settings
        adminTests.testCustomPoolFees();
        adminTests.testCustomSlippage();
        
        // Test upgrades
        adminTests.testUpgrade();
    }

    /**
     * @notice Runs all EntryPoint-related tests
     */
    function testEntryPointFeatures() public {
        // Test UserOp validation
        entryPointTests.testBasicUserOpValidation();
        
        // Test operations
        entryPointTests.testUserOpWithTokenTransfer();
        entryPointTests.testUserOpWithPaymaster();
        
        // Test batch operations
        entryPointTests.testBatchUserOps();
        
        // Test failure cases
        entryPointTests.testInvalidSignature();
        
        // Test gas handling
        entryPointTests.testPrefundHandling();
    }
}