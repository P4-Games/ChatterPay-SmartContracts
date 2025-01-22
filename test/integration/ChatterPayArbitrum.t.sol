// SPDX-License-Identifier: MIT
// @title ChatterPayArbitrumTest
// @notice Test suite for ChatterPay smart contract on Arbitrum Sepolia
// @dev Comprehensive testing of wallet creation, token swapping, and Uniswap V3 integration
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ChatterPay} from "../../src/L2/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../../src/L2/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../../src/L2/ChatterPayPaymaster.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interfaces for interacting with Uniswap V3 pool creation and liquidity management
interface IUniswapV3Factory {
    // Creates a new liquidity pool for two tokens
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);

    // Gets the pool address for a token pair and fee
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

interface IUniswapV3Pool {
    // Initializes the pool with an initial price
    function initialize(uint160 sqrtPriceX96) external;

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

interface INonfungiblePositionManager {
    // Parameters for creating a new liquidity position
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

    // Mints a new liquidity position
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

contract ChatterPayArbitrumTest is Test {
    // Core contract instances
    ChatterPay implementation;
    ChatterPayWalletFactory factory;
    ChatterPayPaymaster paymaster;

    // Constants
    address constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    address constant UNISWAP_ROUTER =
        0x101F443B4d1b059569D643917553c771E1b9663E;
    address constant UNISWAP_FACTORY =
        0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
    address constant POSITION_MANAGER =
        0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65;
    address constant USDC = 0xCB269E6f05146bFb378d999EAec06b3fF708c279; // 6 Decimals
    address constant USDT = 0xF08d6E2b3e15776286FDCc6a77e85EF70Bf61e84; // 18 decimals
    address constant USDC_USD_FEED = 0x0153002d20B96532C639313c2d54c3dA09109309;
    address constant USDT_USD_FEED = 0x80EDee6f667eCc9f63a0a6f55578F870651f06A4;

    // Test accounts
    address owner;
    address user;
    uint256 ownerKey;

    // Sets up test environment with contracts and initial liquidity
    function setUp() public {
        ownerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        owner = vm.addr(ownerKey);
        user = makeAddr("user");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);

        // Deploy core contracts
        vm.startPrank(owner);

        // Deploy implementation
        implementation = new ChatterPay();
        console.log(
            "ChatterPay implementation deployed at:",
            address(implementation)
        );

        // Deploy & fund paymaster
        paymaster = new ChatterPayPaymaster(ENTRY_POINT, owner);
        console.log("Paymaster deployed at:", address(paymaster));
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        require(success, "Failed to fund paymaster");

        // Deploy factory
        factory = new ChatterPayWalletFactory(
            address(implementation),
            ENTRY_POINT,
            owner,
            address(paymaster),
            UNISWAP_ROUTER
        );
        console.log("Factory deployed at:", address(factory));

        /*// Setup pool with liquidity
        uint256 usdcAmount = 1000000e6;    // 1M USDC
        uint256 usdtAmount = 1000000e6;   // 1M USDT

        deal(USDC, owner, usdcAmount);
        deal(USDT, owner, usdtAmount);

        // 1. First we need to create the pool
        address pool = IUniswapV3Factory(UNISWAP_FACTORY).createPool(
            USDC,
            USDT,
            100
        );
        console.log("Pool created at:", pool);

        // 2. Initialize the pool with initial price
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        // 3. Approve tokens before adding liquidity
        IERC20(USDC).approve(POSITION_MANAGER, type(uint256).max);
        IERC20(USDT).approve(POSITION_MANAGER, type(uint256).max);

        // 4. Add liquidity
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: USDC < USDT ? USDC : USDT,
                token1: USDC < USDT ? USDT : USDC,
                fee: 100,
                tickLower: -60,
                tickUpper: 60,
                amount0Desired: USDC < USDT ? usdcAmount : usdtAmount,
                amount1Desired: USDC < USDT ? usdtAmount : usdcAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: owner,
                deadline: block.timestamp + 1000
            });

        // Mint position and log results
        (
            uint tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = INonfungiblePositionManager(POSITION_MANAGER).mint(params);

        console.log("Position created - tokenId:", tokenId);
        console.log("Liquidity added:", liquidity);
        console.log("Amount0 used:", amount0);
        console.log("Amount1 used:", amount1);*/

        vm.stopPrank();
    }

    function testCreateWallet() public {
        vm.startPrank(owner);

        address walletAddress = factory.createProxy(owner);
        console.log("Wallet deployed at:", walletAddress);

        ChatterPay wallet = ChatterPay(payable(walletAddress));
        assertEq(wallet.owner(), owner);
        assertEq(address(wallet.swapRouter()), UNISWAP_ROUTER);

        vm.stopPrank();
    }

    function testTokenSetupAndSwap() public {
        vm.warp(1737341661);

        // Check pool and liquidity
        address pool = IUniswapV3Factory(UNISWAP_FACTORY).getPool(USDC, USDT, 100);
        console.log("Pool address:", pool);
        require(pool != address(0), "Pool does not exist");

        // Check pool state
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        console.log("Pool current price:", sqrtPriceX96);
        console.log("Pool current tick:", tick);

        // Check balances
        uint256 usdcBalance = IERC20(USDC).balanceOf(pool);
        uint256 usdtBalance = IERC20(USDT).balanceOf(pool);
        console.log("Pool USDC balance:", usdcBalance);
        console.log("Pool USDT balance:", usdtBalance);

        vm.startPrank(owner);
        address walletAddress = factory.createProxy(owner);
        ChatterPay wallet = ChatterPay(payable(walletAddress));

        // Configure tokens
        wallet.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        wallet.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);

        uint256 amountIn = 1000000;
        uint256 fee = amountIn / 2;
        uint256 swapAmount = amountIn - fee;
        
        // Min out is 1% of swap amount just for testing
        uint256 minOut = swapAmount / 100;
        
        console.log("=== Swap Parameters ===");
        console.log("Amount in:", amountIn);
        console.log("Fee amount:", fee);
        console.log("Swap amount:", swapAmount);
        console.log("Min out:", minOut);
        
        // Fund wallet
        deal(USDC, owner, amountIn);
        IERC20(USDC).transfer(walletAddress, amountIn);
        
        vm.stopPrank();

        // Verify allowance
        console.log("=== Allowances ===");
        console.log("USDC allowance before:", IERC20(USDC).allowance(walletAddress, UNISWAP_ROUTER));

        vm.prank(ENTRY_POINT);
        wallet.approveToken(USDC, amountIn);

        console.log("USDC allowance after:", IERC20(USDC).allowance(walletAddress, UNISWAP_ROUTER));

        // Execute swap
        vm.prank(ENTRY_POINT);
        wallet.executeSwap(USDC, USDT, amountIn, minOut, owner);

        // Log / Verify results
        console.log("=== Final State ===");
        console.log("Final USDC Balance of wallet:", IERC20(USDC).balanceOf(walletAddress));
        console.log("Final USDT Balance of owner:", IERC20(USDT).balanceOf(owner));
    }

    receive() external payable {}
}
