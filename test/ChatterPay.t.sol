// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/L2/ChatterPayWalletFactory.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {MockSwapRouter} from "./mocks/MockSwapRouter.sol";
import {console2} from "forge-std/console2.sol";

contract ChatterPayTest is Test {
    // Events to test
    event TokenApproved(address indexed token, address indexed spender, uint256 amount);
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );
    event FeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);
    event TokenWhitelisted(address indexed token, bool indexed status);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event FeeAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    // Test contracts
    ChatterPay public implementation;
    ChatterPay public chatterPay;
    ChatterPayWalletFactory public factory;
    MockSwapRouter public swapRouter;
    
    // Mock tokens and price feeds
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockPriceFeed public priceFeedA;
    MockPriceFeed public priceFeedB;

    // Test addresses
    address public entryPoint;
    address public owner;
    address public paymaster;
    address public feeAdmin;
    address public user;

    function setUp() public {
        console2.log("Starting setUp");
        
        // Setup addresses
        owner = makeAddr("owner");
        paymaster = makeAddr("paymaster");
        feeAdmin = makeAddr("feeAdmin");
        user = makeAddr("user");
        entryPoint = makeAddr("entryPoint");
        console2.log("Addresses set up");

        // Deploy mock tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);
        console2.log("Mock tokens deployed");

        // Deploy mock price feeds
        priceFeedA = new MockPriceFeed();
        priceFeedB = new MockPriceFeed();
        console2.log("Mock price feeds deployed");
        
        // Set initial prices
        priceFeedA.setPrice(1e8);
        priceFeedB.setPrice(2e8);
        console2.log("Prices set");

        // Deploy mock swap router
        swapRouter = new MockSwapRouter();
        console2.log("Mock swap router deployed");

        // Deploy implementation
        implementation = new ChatterPay();
        console2.log("Implementation deployed at:", address(implementation));

        // Deploy factory
        factory = new ChatterPayWalletFactory(
            address(implementation),
            entryPoint,
            owner,
            paymaster,
            address(swapRouter)
        );
        console2.log("Factory deployed at:", address(factory));

        // Deploy wallet through factory (which handles initialization)
        vm.startPrank(owner);
        address walletAddress = factory.createProxy(owner);
        chatterPay = ChatterPay(walletAddress);
        console2.log("Proxy created at:", walletAddress);

        // Whitelist tokens and set price feeds
        chatterPay.setTokenWhitelistAndPriceFeed(address(tokenA), true, address(priceFeedA));
        chatterPay.setTokenWhitelistAndPriceFeed(address(tokenB), true, address(priceFeedB));
        
        vm.stopPrank();

        // Fund user with tokens
        tokenA.mint(user, 1000e18);
        tokenB.mint(user, 1000e18);
        console2.log("User funded with tokens");
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialization() public view {
        assertEq(address(chatterPay.swapRouter()), address(swapRouter));
        assertEq(address(chatterPay.factory()), address(factory));
        assertEq(chatterPay.s_feeInCents(), 50);
        assertEq(chatterPay.s_feeAdmin(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                           TOKEN APPROVAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ApproveToken() public {
        uint256 amount = 100e18;
        
        // Simulate call from EntryPoint
        vm.startPrank(entryPoint);
        
        vm.expectEmit(true, true, false, true);
        emit TokenApproved(address(tokenA), address(swapRouter), amount);
        
        chatterPay.approveToken(address(tokenA), amount);
        
        assertEq(tokenA.allowance(address(chatterPay), address(swapRouter)), amount);
        vm.stopPrank();
    }

    function testFail_ApproveTokenNotWhitelisted() public {
        address randomToken = makeAddr("randomToken");
        vm.prank(user);
        chatterPay.approveToken(randomToken, 100e18);
    }

    function testFail_ApproveTokenZeroAmount() public {
        vm.prank(user);
        chatterPay.approveToken(address(tokenA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              SWAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteSwap() public {
        uint256 amountIn = 100e18;
        uint256 fee = (50 * 10 ** (18 - 2)) / 1e8;
        uint256 swapAmount = amountIn - fee;
        
        // According to the mock router, output is half of input
        uint256 amountOut = swapAmount / 2;
        
        uint256 initialBalance = tokenB.balanceOf(user);
        
        // Setup: Transfer tokens to the proxy first
        vm.startPrank(user);
        tokenA.transfer(address(chatterPay), amountIn);
        vm.stopPrank();
        
        // Execute swap from EntryPoint context
        vm.startPrank(entryPoint);
        vm.expectEmit(true, true, false, true);
        emit SwapExecuted(
            address(tokenA), 
            address(tokenB), 
            swapAmount,
            amountOut,
            user
        );
        
        chatterPay.executeSwap(
            address(tokenA),
            address(tokenB),
            amountIn,
            amountOut,
            user
        );
        vm.stopPrank();

        // Verify balance change
        uint256 finalBalance = tokenB.balanceOf(user);
        assertEq(finalBalance - initialBalance, amountOut, "Invalid output amount");
    }

    function testFail_SwapInvalidSlippage() public {
        uint256 amountIn = 100e18;
        uint256 amountOutMin = 1e18;
        
        vm.startPrank(user);
        tokenA.approve(address(chatterPay), amountIn);
        
        chatterPay.executeSwap(
            address(tokenA),
            address(tokenB),
            amountIn,
            amountOutMin,
            user
        );
        vm.stopPrank();
    }

    function testFail_SwapNotWhitelisted() public {
        address randomToken = makeAddr("randomToken");
        vm.prank(user);
        chatterPay.executeSwap(
            randomToken,
            address(tokenB),
            100e18,
            45e18,
            user
        );
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateFee() public {
        uint256 newFee = 100; // $1.00
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit FeeUpdated(50, newFee);
        
        chatterPay.updateFee(newFee);
        assertEq(chatterPay.s_feeInCents(), newFee);
    }

    function testFail_UpdateFeeTooHigh() public {
        vm.prank(owner);
        chatterPay.updateFee(2000); // $20.00 > MAX_FEE
    }

    function test_UpdateFeeAdmin() public {
        address newAdmin = makeAddr("newAdmin");
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit FeeAdminUpdated(owner, newAdmin);
        
        chatterPay.updateFeeAdmin(newAdmin);
        assertEq(chatterPay.s_feeAdmin(), newAdmin);
    }

    function test_RemoveTokenFromWhitelist() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit TokenWhitelisted(address(tokenA), false);
        
        chatterPay.removeTokenFromWhitelist(address(tokenA));
        assertFalse(chatterPay.s_whitelistedTokens(address(tokenA)));
    }

    /*//////////////////////////////////////////////////////////////
                           PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PriceFeedValidation() public {
        MockPriceFeed newFeed = new MockPriceFeed();
        newFeed.setPrice(1e8);
        
        vm.prank(owner);
        chatterPay.setTokenWhitelistAndPriceFeed(
            makeAddr("newToken"),
            true,
            address(newFeed)
        );
    }

    function testFail_StalePriceFeed() public {
        MockPriceFeed staleFeed = new MockPriceFeed();
        staleFeed.setPrice(1e8);
        staleFeed.setUpdatedAt(block.timestamp - 2 hours); // Stale price
        
        vm.prank(owner);
        chatterPay.setTokenWhitelistAndPriceFeed(
            makeAddr("newToken"),
            true,
            address(staleFeed)
        );
    }
}