// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ChatterPay} from "../../src/L2/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../../src/L2/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../../src/L2/ChatterPayPaymaster.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ChatterPayArbitrumTest is Test {
    // Core contracts
    ChatterPay implementation;
    ChatterPayWalletFactory factory;
    ChatterPayPaymaster paymaster;

    // Real Arbitrum Sepolia addresses
    address constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    address constant UNISWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant USDT = 0x961bf3bf61d3446907E0Db83C9c5D958c17A94f6;

    // Price Feed addresses for Arbitrum Sepolia
    address constant USDC_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant USDT_USD_FEED = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;

    // Test accounts
    address owner;
    address user;
    uint256 ownerKey;

    function setUp() public {
        // Setup accounts with meaningful names for debugging
        ownerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Default anvil private key
        owner = vm.addr(ownerKey);
        user = makeAddr("user");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);

        // Start acting as owner
        vm.startPrank(owner);

        // 1. Deploy ChatterPay implementation
        implementation = new ChatterPay();
        console.log(
            "ChatterPay implementation deployed at:",
            address(implementation)
        );

        // 2. Deploy Paymaster
        paymaster = new ChatterPayPaymaster(ENTRY_POINT, owner);
        console.log("Paymaster deployed at:", address(paymaster));

        // Fund paymaster with ETH for gas
        (bool success, ) = address(paymaster).call{value: 1 ether}("");
        require(success, "Failed to fund paymaster");

        // 3. Deploy Factory
        factory = new ChatterPayWalletFactory(
            address(implementation),
            ENTRY_POINT,
            owner,
            address(paymaster),
            UNISWAP_ROUTER
        );
        console.log("Factory deployed at:", address(factory));

        vm.stopPrank();

        // Label addresses for better trace output
        vm.label(ENTRY_POINT, "EntryPoint");
        vm.label(UNISWAP_ROUTER, "UniswapRouter");
        vm.label(USDC, "USDC");
        vm.label(USDT, "USDT");
        vm.label(address(implementation), "Implementation");
        vm.label(address(paymaster), "Paymaster");
        vm.label(address(factory), "Factory");
    }

    function testCreateWallet() public {
        vm.startPrank(owner);

        // Create new wallet through factory
        address walletAddress = factory.createProxy(owner);
        console.log("Wallet deployed at:", walletAddress);

        // Get wallet instance
        ChatterPay wallet = ChatterPay(payable(walletAddress));

        // Verify basic initialization
        assertEq(wallet.owner(), owner);
        assertEq(address(wallet.swapRouter()), UNISWAP_ROUTER);

        vm.stopPrank();
    }

    function testTokenSetupAndSwap() public {
        vm.startPrank(owner);

        // 1. Create wallet
        address walletAddress = factory.createProxy(owner);
        ChatterPay wallet = ChatterPay(payable(walletAddress));

        // 2. Setup token configuration
        wallet.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        wallet.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);

        // 3. Fund wallet with USDC
        deal(USDC, walletAddress, 1000e6); // 1000 USDC

        // 4. Approve USDC spend - needs to come from EntryPoint
        vm.stopPrank();
        vm.prank(ENTRY_POINT);
        wallet.approveToken(USDC, 1000e6);

        // 5. Execute swap - needs to come from EntryPoint
        uint256 amountIn = 100e6; // 100 USDC
        uint256 minOut = 95e6; // Expect at least 95 USDT

        vm.prank(ENTRY_POINT);
        wallet.executeSwap(USDC, USDT, amountIn, minOut, owner);

        // 6. Verify balances changed
        uint256 usdcBalance = IERC20(USDC).balanceOf(walletAddress);
        uint256 usdtBalance = IERC20(USDT).balanceOf(owner);

        console.log("Final USDC balance:", usdcBalance);
        console.log("Final USDT balance:", usdtBalance);

        assertTrue(usdcBalance < 1000e6, "USDC not spent");
        assertTrue(usdtBalance > 0, "No USDT received");
    }

    function testMultipleSwaps() public {
        vm.startPrank(owner);

        // Create and setup wallet
        address walletAddress = factory.createProxy(owner);
        ChatterPay wallet = ChatterPay(payable(walletAddress));

        wallet.setTokenWhitelistAndPriceFeed(USDC, true, USDC_USD_FEED);
        wallet.setTokenWhitelistAndPriceFeed(USDT, true, USDT_USD_FEED);

        // Fund with more USDC
        deal(USDC, walletAddress, 5000e6); // 5000 USDC

        vm.stopPrank();

        // Do multiple swaps
        uint256[] memory swapAmounts = new uint256[](3);
        swapAmounts[0] = 100e6; // 100 USDC
        swapAmounts[1] = 200e6; // 200 USDC
        swapAmounts[2] = 300e6; // 300 USDC

        for (uint i = 0; i < swapAmounts.length; i++) {
            // Approve spend
            vm.prank(ENTRY_POINT);
            wallet.approveToken(USDC, swapAmounts[i]);

            // Execute swap
            vm.prank(ENTRY_POINT);
            wallet.executeSwap(
                USDC,
                USDT,
                swapAmounts[i],
                (swapAmounts[i] * 95) / 100, // 95% min output
                owner
            );

            // Log balances after each swap
            console.log("Swap", i + 1, "complete");
            console.log("USDC balance:", IERC20(USDC).balanceOf(walletAddress));
            console.log("USDT balance:", IERC20(USDT).balanceOf(owner));
        }
    }

    receive() external payable {}
}
