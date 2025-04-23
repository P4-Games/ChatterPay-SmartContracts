// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ChatterPay} from "../../src/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../../src/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../../src/ChatterPayPaymaster.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseConstants} from "./BaseConstants.sol";

/*//////////////////////////////////////////////////////////////
//                        INTERFACES
//////////////////////////////////////////////////////////////*/

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
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

    function liquidity() external view returns (uint128);
}

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

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

abstract contract BaseTest is Test {
    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Core contract instances
    ChatterPay public implementation;
    ChatterPayWalletFactory public factory;
    ChatterPayPaymaster public paymaster;
    ChatterPay public baseWallet;

    // Test accounts
    address public owner;
    address public user;
    uint256 public ownerKey;

    address constant ENTRY_POINT = BaseConstants.ENTRY_POINT;
    address constant UNISWAP_ROUTER = BaseConstants.UNISWAP_ROUTER;
    address constant UNISWAP_FACTORY = BaseConstants.UNISWAP_FACTORY;
    address constant POSITION_MANAGER = BaseConstants.POSITION_MANAGER;
    address constant USDC = BaseConstants.USDC;
    address constant USDT = BaseConstants.USDT;
    address constant USDC_USD_FEED = BaseConstants.USDC_USD_FEED;
    address constant USDT_USD_FEED = BaseConstants.USDT_USD_FEED;
    uint256 constant INITIAL_LIQUIDITY = BaseConstants.INITIAL_LIQUIDITY;
    uint24 constant POOL_FEE = BaseConstants.POOL_FEE;

    /*//////////////////////////////////////////////////////////////
                           SETUP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets up the test environment.
     * @dev Deploys contracts and configures initial state.
     */
    function setUp() public virtual {
        // Initialize test accounts

        // Burned Key for local blk with adr: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        ownerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        owner = vm.addr(ownerKey);
        user = makeAddr("user");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);

        // Deploy contracts (including initialization)
        _deployContracts();

        // Setup Uniswap liquidity
        _setupUniswapLiquidity();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deploys and initializes all required contracts.
     */
    function _deployContracts() internal {
        vm.startPrank(owner);

        // Deploy ChatterPay implementation
        implementation = new ChatterPay();
        console.log("ChatterPay implementation deployed at:", address(implementation));

        // Deploy & fund paymaster
        paymaster = new ChatterPayPaymaster(ENTRY_POINT, owner);
        console.log("Paymaster deployed at:", address(paymaster));
        (bool success,) = address(paymaster).call{value: 1 ether}("");
        require(success, "Failed to fund paymaster");

        // Deploy factory (passing the implementation address)
        factory = new ChatterPayWalletFactory(
            address(implementation), // _walletImplementation
            ENTRY_POINT, // _entryPoint
            owner, // _owner
            address(paymaster), // _paymaster
            UNISWAP_ROUTER, // _router
            new address[](0), // _whitelistedTokens
            new address[](0), // _priceFeeds
            new bool[](0) // _tokensStableFlags
        );
        console.log("Factory deployed at:", address(factory));

        // Initialize the ChatterPay implementation with required parameters
        address[] memory whitelistedTokens = new address[](2);
        whitelistedTokens[0] = USDC;
        whitelistedTokens[1] = USDT;
        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = USDC_USD_FEED;
        priceFeeds[1] = USDT_USD_FEED;

        vm.stopPrank();
    }

    /**
     * @dev Sets up Uniswap V3 liquidity pool with initial liquidity
     */
    function _setupUniswapLiquidity() internal {
        vm.startPrank(owner);

        // Setup initial token amounts
        uint256 usdcAmount = INITIAL_LIQUIDITY;
        uint256 usdtAmount = INITIAL_LIQUIDITY * 1e12;

        // Mint tokens to owner
        _ensureBalance(USDC, owner, usdcAmount);
        _ensureBalance(USDT, owner, usdtAmount);

        // Create and initialize pool if it doesn't exist
        address pool = IUniswapV3Factory(UNISWAP_FACTORY).getPool(USDC, USDT, POOL_FEE);

        if (pool == address(0)) {
            console.log("Pool not found, creating and initializing...");
            pool = _createAndInitializePool();
            console.log("Pool created at:", pool);

            console.log("Adding Pool liquidity...");
            _addInitialLiquidity(usdcAmount, usdtAmount);
            console.log("Initial liquidity added");
        } else {
            console.log("Pool already exists, skipping creation");
        }

        console.log("_setupUniswapLiquidity end");
        vm.stopPrank();
    }

    /**
     * @notice Ensures that the given address holds at least the desired token amount.
     * @dev Uses `deal` to top up the token balance if it is below the specified threshold.
     *      Useful for preparing test accounts with mock ERC20 balances.
     * @param token The ERC20 token address.
     * @param to The recipient address to check and possibly fund.
     * @param desiredAmount The target token balance to ensure.
     *
     * @dev Note that the contract addresses for USDC and USDT in BaseConstants
     *      belong to Arbitrum Sepolia. Make sure that when running the tests,
     *      the RPC_URL variable is pointing to a node provider for Arbitrum Sepolia.
     */
    function _ensureBalance(address token, address to, uint256 desiredAmount) internal {
        console.log("Ensuring balance for:", token, to);

        uint256 currentBalance = IERC20(token).balanceOf(to);
        console.log("Current balance:", currentBalance);

        if (currentBalance < desiredAmount) {
            console.log("Topping up with deal to:", desiredAmount);
            deal(token, to, desiredAmount);
            console.log("Top up complete");
        } else {
            console.log("Sufficient balance, skipping deal");
        }
    }

    /**
     * @dev Creates and initializes a new Uniswap V3 pool
     */
    function _createAndInitializePool() internal returns (address pool) {
        // Create pool
        pool = IUniswapV3Factory(UNISWAP_FACTORY).createPool(USDC, USDT, POOL_FEE);
        console.log("Pool created at:", pool);

        // Initialize pool with price
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 2^96
        sqrtPriceX96 = uint160(uint256(sqrtPriceX96) * 1000000); // Multiply by sqrt(10^12)
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        return pool;
    }

    /**
     * @dev Adds initial liquidity to the Uniswap pool
     */
    function _addInitialLiquidity(uint256 usdcAmount, uint256 usdtAmount) internal {
        // Approve tokens
        IERC20(USDC).approve(POSITION_MANAGER, type(uint256).max);
        IERC20(USDT).approve(POSITION_MANAGER, type(uint256).max);

        // Calculate ticks
        int24 tickSpacing = 60;
        int24 tickLower = (-887220 / tickSpacing) * tickSpacing;
        int24 tickUpper = (887220 / tickSpacing) * tickSpacing;

        // Add liquidity
        INonfungiblePositionManager(POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: USDT,
                fee: POOL_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: usdcAmount,
                amount1Desired: usdtAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: owner,
                deadline: block.timestamp + 1000
            })
        );
    }

    /**
     * @dev Funds a wallet with specified token amount
     */
    function _fundWallet(address _wallet, uint256 _amount) internal {
        require(_wallet != address(0), "Cannot fund zero address");
        deal(USDC, _wallet, _amount);
    }

    /**
     * @dev Logs the state of tokens for a wallet
     */
    function _logSwapState(string memory state, address walletAddress) internal view {
        console.log("=== ", state, " ===");
        console.log("Wallet address:", walletAddress);
        console.log("USDC address:", USDC);
        console.log("USDC balance:", IERC20(USDC).balanceOf(walletAddress));
        if (keccak256(abi.encodePacked(state)) == keccak256(abi.encodePacked("Final State"))) {
            console.log("Final USDT Balance of owner:", IERC20(USDT).balanceOf(owner));
        }
    }

    /**
     * @dev Logs router information
     */
    function _logRouterInfo(address walletAddress) internal view {
        console.log("=== Router Info ===");
        console.log("Router address:", UNISWAP_ROUTER);
        console.log("USDC allowance:", IERC20(USDC).allowance(walletAddress, UNISWAP_ROUTER));
    }

    /**
     * @dev Logs pool state information
     */
    function _logPoolState() internal view {
        address pool = IUniswapV3Factory(UNISWAP_FACTORY).getPool(USDC, USDT, POOL_FEE);
        (uint160 sqrtPriceX96, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();
        console.log("=== Pool State ===");
        console.log("Pool initialized price:", sqrtPriceX96);
        console.log("Pool current tick:", tick);
    }

    /**
     * @dev Required for receiving ETH
     */
    receive() external payable {}
}
