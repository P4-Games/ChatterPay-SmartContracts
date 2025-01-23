// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Extended} from "../../src/ChatterPay.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Factory, IUniswapV3Pool, INonfungiblePositionManager} from "../setup/BaseTest.sol";

/**
 * @title SwapModule Test Contract
 * @notice Test contract for validating ChatterPay's swap functionality
 * @dev Contains tests for token swaps, custom fees, slippage protection and error cases
 */
contract SwapModule is BaseTest {
    /// @notice Instance of the ChatterPay wallet being tested
    ChatterPay public moduleWallet;
    
    /// @notice Address of the deployed wallet instance
    address public moduleWalletAddress;

    /// @notice Events emitted during swap operations
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address pool, uint256 tokenId, uint128 liquidity);

    /// @notice Sets up the test environment
    /// @dev Deploys a new wallet instance and configures initial token settings
    function setUp() public override {
        // Call parent setup first
        super.setUp();
        
        // Deploy wallet using parent factory
        vm.startPrank(owner);
        moduleWalletAddress = factory.createProxy(owner);
        moduleWallet = ChatterPay(payable(moduleWalletAddress));

        // Verify router configuration
        require(address(moduleWallet.swapRouter()) != address(0), "Router not set");

        // Setup tokens using parent contract constants
        moduleWallet.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        moduleWallet.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);
        
        vm.stopPrank();
    }

    /// @notice Getter function for the wallet instance
    /// @return ChatterPay The current wallet instance
    function wallet() public view returns (ChatterPay) {
        return moduleWallet;
    }

    /**
     * @notice Tests basic swap functionality between USDC and USDT
     * @dev Executes a swap with logging of key steps and balance verification
     */
    function testBasicSwap() public {
        uint256 SWAP_AMOUNT = 1000e6;
        
        // Log initial setup
        console.log("=== Test Setup ===");
        console.log("Swap amount:", SWAP_AMOUNT);
        console.log("USDC address:", USDC);
        console.log("USDT address:", USDT);
        
        // Get pool
        address pool = IUniswapV3Factory(UNISWAP_FACTORY).getPool(USDC, USDT, POOL_FEE);
        require(pool != address(0), "Pool doesn't exist");
        console.log("Pool address:", pool);
        
        // Fund wallet
        _fundWallet(moduleWalletAddress, SWAP_AMOUNT);
        console.log("Wallet funded with:", SWAP_AMOUNT);
        
        // Verify initial balance
        uint256 initialBalance = IERC20(USDC).balanceOf(moduleWalletAddress);
        console.log("Initial wallet balance:", initialBalance);
        require(initialBalance == SWAP_AMOUNT, "Funding failed");
        
        uint256 initialUSDTBalance = IERC20(USDT).balanceOf(owner);
        console.log("Initial owner USDT balance:", initialUSDTBalance);
        
        // Calculate expected fee
        uint256 expectedFee = _calculateExpectedFee(USDC, 50);
        console.log("Expected fee:", expectedFee);
        
        // Calculate minimum amount out
        uint256 minAmountOut = ((SWAP_AMOUNT - expectedFee) * 10**12) * 30 / 100;
        console.log("Minimum amount out:", minAmountOut);
        
        vm.startPrank(ENTRY_POINT);
        moduleWallet.approveToken(USDC, SWAP_AMOUNT);
        console.log("Token approved for swap");
        
        moduleWallet.executeSwap(USDC, USDT, SWAP_AMOUNT, minAmountOut, owner);
        vm.stopPrank();
        
        uint256 finalUSDTBalance = IERC20(USDT).balanceOf(owner);
        console.log("Final owner USDT balance:", finalUSDTBalance);
        console.log("USDT received:", finalUSDTBalance - initialUSDTBalance);
        
        assertTrue(finalUSDTBalance > initialUSDTBalance);
    }

    /**
     * @notice Tests swap execution with a custom pool fee
     * @dev Sets a custom 0.3% pool fee and verifies swap succeeds
     */
    function testSwapWithCustomPoolFee() public {
        vm.startPrank(owner);
        uint24 customFee = 3000; // 0.3%
        moduleWallet.setCustomPoolFee(USDC, USDT, customFee);
        vm.stopPrank();

        uint256 amountIn = 1000e6;
        uint256 minOut = 990e6;
        
        _fundWallet(moduleWalletAddress, amountIn);
        
        vm.startPrank(ENTRY_POINT);
        moduleWallet.approveToken(USDC, amountIn);
        moduleWallet.executeSwap(USDC, USDT, amountIn, minOut, owner);
        vm.stopPrank();
        
        assertGt(IERC20(USDT).balanceOf(owner), 0, "Swap with custom fee failed");
    }

    /**
     * @notice Tests swap execution with custom slippage settings
     * @dev Sets a custom 1% slippage tolerance and executes swap
     */
    function testSwapWithCustomSlippage() public {
        vm.startPrank(owner);
        uint256 customSlippage = 100; // 1%
        moduleWallet.setCustomSlippage(USDC, customSlippage);
        vm.stopPrank();

        uint256 amountIn = 1000e6;
        uint256 minOut = 990e6;
        
        _fundWallet(moduleWalletAddress, amountIn);
        
        vm.startPrank(ENTRY_POINT);
        moduleWallet.approveToken(USDC, amountIn);
        moduleWallet.executeSwap(USDC, USDT, amountIn, minOut, owner);
        vm.stopPrank();
    }

    /**
     * @notice Tests swap execution with fee calculation verification
     * @dev Executes swap and verifies collected fees match expected amounts
     */
    function testSwapWithFee() public {
        uint256 amountIn = 1000e6;
        
        _fundWallet(moduleWalletAddress, amountIn);
        address feeAdmin = wallet().s_feeAdmin();
        uint256 minAmountOut = 0; // Set minimum amount for testing purposes
        
        // Get initial balances
        uint256 initialFeeAdminBalance = IERC20(USDC).balanceOf(feeAdmin);
        console.log("Fee admin:", feeAdmin);
        console.log("Initial balance:", initialFeeAdminBalance);

        // Execute swap
        vm.prank(ENTRY_POINT);
        moduleWallet.executeSwap(USDC, USDT, amountIn, minAmountOut, owner);

        // Get final balance
        uint256 finalFeeAdminBalance = IERC20(USDC).balanceOf(feeAdmin);
        console.log("Final balance:", finalFeeAdminBalance);
        uint256 feeCollected = finalFeeAdminBalance - initialFeeAdminBalance;
        console.log("Fee collected:", feeCollected);

        // Calculate expected fee and check within margin
        uint256 expectedFee = _calculateExpectedFee(USDC, 50);
        console.log("Expected fee:", expectedFee);
        
        assertTrue(
            feeCollected >= expectedFee - 3 && feeCollected <= expectedFee + 3,
            "Fee not within acceptable range"
        );
    }

    /**
     * @notice Tests swap failure scenarios
     * @dev Attempts swap with non-whitelisted token to verify proper error handling
     */
    function testFailInvalidSwap() public {
        uint256 amountIn = 1000e6;
        _fundWallet(moduleWalletAddress, amountIn);
        
        vm.startPrank(owner);
        moduleWallet.setTokenWhitelistAndPriceFeed(USDC, false, address(0));
        vm.stopPrank();
        
        vm.prank(ENTRY_POINT);
        vm.expectRevert("ChatterPay__TokenNotWhitelisted");
        moduleWallet.executeSwap(USDC, USDT, amountIn, 0, owner);
    }

    /**
     * @notice Tests complete swap workflow from setup to execution
     * @dev Validates entire swap process including setup, funding, approval and execution
     */
    function testTokenSetupAndSwap() public {
        // Set block timestamp
        vm.warp(1737341661);

        // Setup swap parameters
        uint256 amountIn = 1000e6; 
        uint256 fee = 5e5; // 0.5 cents in USDC
        uint256 swapAmount = amountIn - fee;
        uint256 minOut = (swapAmount * 1e12) * 7 / 10;

        // Log initial state
        _logSwapState("Initial State", moduleWalletAddress);
        
        // Fund wallet
        _fundWallet(moduleWalletAddress, amountIn);
        
        // Verify funding
        _logSwapState("After Funding", moduleWalletAddress);
        require(IERC20(USDC).balanceOf(moduleWalletAddress) == amountIn, "Funding failed");

        // Log router info
        _logRouterInfo(moduleWalletAddress);

        // Approve and execute swap
        vm.startPrank(ENTRY_POINT);
        moduleWallet.approveToken(USDC, amountIn);

        _logSwapState("After Approval", moduleWalletAddress);

        // Log pool state
        _logPoolState();

        // Execute swap
        moduleWallet.executeSwap(USDC, USDT, amountIn, minOut, owner);
        vm.stopPrank();

        // Log final state
        _logSwapState("Final State", moduleWalletAddress);
    }

    /**
     * @notice Calculates expected fee amount for a given token
     * @dev Converts fee from cents to token decimals
     * @param token The token address to calculate fee for
     * @param feeInCents The fee amount in cents
     * @return The calculated fee amount in token decimals
     */
    function _calculateExpectedFee(
        address token,
        uint256 feeInCents
    ) internal view returns (uint256) {
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        
        console.log("=== Fee Calculation Debug ===");
        console.log("Token:", token);
        console.log("Fee in cents:", feeInCents);
        console.log("Token decimals:", tokenDecimals);
        
        // Calculate step by step
        uint256 scaledAmount = feeInCents * (10 ** tokenDecimals);
        console.log("Scaled amount:", scaledAmount);
        
        uint256 finalFee = scaledAmount / 100;
        console.log("Final fee:", finalFee);
        
        return finalFee;
    }
}