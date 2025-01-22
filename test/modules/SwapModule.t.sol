// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseTest} from "../setup/BaseTest.sol";
import {ChatterPay} from "../../src/L2/ChatterPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface for Uniswap V3 factory functionality
 */
interface IUniswapV3Factory {
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

/**
 * @dev Interface for Uniswap V3 pool functionality
 */
interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;

    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

/**
 * @dev Interface for Uniswap V3 position management
 */
interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

contract SwapModule is BaseTest {
    ChatterPay public moduleWallet;
    address public moduleWalletAddress;

    // Events for test tracking
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address pool, uint256 tokenId, uint128 liquidity);

    function setUp() public override {
        super.setUp();
        
        // Deploy wallet
        vm.startPrank(owner);
        moduleWalletAddress = factory.createProxy(owner);
        moduleWallet = ChatterPay(payable(moduleWalletAddress));
        
        // Setup tokens
        moduleWallet.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        moduleWallet.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);
        vm.stopPrank();
    }

    function wallet() public view returns (ChatterPay) {
        return moduleWallet;
    }

    /**
     * @notice Tests basic swap functionality
     */
    function testBasicSwap() public {
        uint256 amountIn = 1000e6; // 1000 USDC
        uint256 minOut = 990e6;    // Expecting 99% or better
        
        _fundWallet(moduleWalletAddress, amountIn);
        
        vm.startPrank(ENTRY_POINT);
        moduleWallet.approveToken(USDC, amountIn);
        moduleWallet.executeSwap(USDC, USDT, amountIn, minOut, owner);
        vm.stopPrank();
        
        assertGt(IERC20(USDT).balanceOf(owner), 0, "Swap failed to deliver tokens");
    }

    /**
     * @notice Tests swap with custom pool fee
     */
    function testSwapWithCustomPoolFee() public {
        vm.startPrank(owner);
        uint24 customFee = 500; // 0.05%
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
     * @notice Tests swap with custom slippage
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
     * @notice Tests swap with fee calculation
     */
    function testSwapWithFee() public {
        uint256 amountIn = 1000e6;
        uint256 fee = 50e6; // 50 cents in USDC
        uint256 expectedSwapAmount = amountIn - fee;
        
        _fundWallet(moduleWalletAddress, amountIn);
        
        uint256 initialPaymasterBalance = IERC20(USDC).balanceOf(address(paymaster));
        
        vm.startPrank(ENTRY_POINT);
        moduleWallet.approveToken(USDC, amountIn);
        moduleWallet.executeSwap(USDC, USDT, amountIn, 0, owner);
        vm.stopPrank();
        
        assertEq(
            IERC20(USDC).balanceOf(address(paymaster)) - initialPaymasterBalance,
            fee,
            "Fee not collected correctly"
        );
    }

    /**
     * @notice Tests swap failure cases
     */
    function testFailInvalidSwap() public {
        uint256 amountIn = 1000e6;
        _fundWallet(moduleWalletAddress, amountIn);

        // Test non-whitelisted token
        vm.startPrank(ENTRY_POINT);
        vm.expectRevert();
        moduleWallet.executeSwap(address(0x123), USDT, amountIn, 0, owner);
        vm.stopPrank();

        // Test insufficient balance
        vm.startPrank(ENTRY_POINT);
        vm.expectRevert();
        moduleWallet.executeSwap(USDC, USDT, amountIn * 2, 0, owner);
        vm.stopPrank();

        // Test excessive slippage
        vm.startPrank(ENTRY_POINT);
        vm.expectRevert();
        moduleWallet.executeSwap(USDC, USDT, amountIn, amountIn * 2, owner);
        vm.stopPrank();
    }

    /**
     * @notice Tests complete swap workflow including setup and execution
     */
    function testTokenSetupAndSwap() public {
        // Set block timestamp
        vm.warp(1737341661);

        // Setup swap parameters
        uint256 amountIn = 1000e6; 
        uint256 fee = 50e6; // 50 cents in USDC
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
}