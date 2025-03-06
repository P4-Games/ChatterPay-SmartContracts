// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPay} from "../src/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../src/ChatterPayPaymaster.sol";
import {ChatterPayNFT} from "../src/ChatterPayNFT.sol";
import {ChatterPayVault} from "../src/ChatterPayVault.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Extended} from "../src/ChatterPay.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Factory, IUniswapV3Pool, INonfungiblePositionManager} from "../test/setup/BaseTest.sol";
import "forge-std/console2.sol";

contract DeployAllContracts is Script {
    // Network Configuration
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;

    // Contract Instances
    ChatterPay chatterPay;
    ChatterPayWalletFactory factory;
    ChatterPayPaymaster paymaster;
    ChatterPayNFT chatterPayNFT;
    ChatterPayVault vault;

    // Uniswap V3 Addresses (immutable)
    address immutable uniswapFactory;
    address immutable uniswapPositionManager;
    uint24 poolFee = 3000; // Fee tier of 0.3%

    // Tokens and Price Feeds arrays
    address[] tokens;
    address[] priceFeeds;

    // Environment Variables
    string NFTBaseUri = vm.envString("NFT_BASE_URI");

    // Comma-separated list of tokens
    string tokensEnv = vm.envString("TOKENS"); 

    // Comma-separated list of price feeds
    string priceFeedsEnv = vm.envString("PRICE_FEEDS"); 

    constructor() {
        uniswapFactory = vm.envAddress("UNISWAP_FACTORY");
        uniswapPositionManager = vm.envAddress("POSITION_MANAGER");
    }

    /**
     * @notice Main deployment function
     */
    function run()
        public
        returns (
            HelperConfig,
            ChatterPay,
            ChatterPayWalletFactory,
            ChatterPayNFT,
            ChatterPayPaymaster
        )
    {
        // Initialize network configuration
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();

        // Parse tokens and price feeds from environment variables
        tokens = _parseAddresses(tokensEnv);
        priceFeeds = _parseAddresses(priceFeedsEnv);

        // Ensure the number of tokens matches the number of price feeds
        require(tokens.length == priceFeeds.length, "Tokens and Price Feeds must have the same length");

        // Start broadcasting transactions with the configured account
        vm.startBroadcast(config.account);

        console2.log(
            "Deploying ChatterPay contracts on chainId %d with account: %s",
            block.chainid,
            config.account
        );

        // Step-by-step deployment and configuration
        deployPaymaster();                           // 1. Deploy Paymaster
        deployFactory();                             // 2. Deploy Wallet Factory
        deployChatterPay();                          // 3. Deploy ChatterPay using UUPS Proxy
        deployNFT();                                 // 4. Deploy NFT with Transparent Proxy
        configureUniswapPool();                      // 5. Configure Uniswap V3 Pool
        deployVault();                               // 6. Deploy Vault

        // Stop broadcasting transactions
        vm.stopBroadcast();

        console2.log('To Put in bdd:');
        console2.log("{");
        console2.log('"entryPoint": "%s",', "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789");
        console2.log('"factoryAddress": "%s",', address(factory));
        console2.log('"chatterPayAddress": "%s",', address(chatterPay));
        console2.log('"chatterNFTAddress": "%s",', address(chatterPayNFT));
        console2.log('"paymasterAddress": "%s"', address(paymaster));
        console2.log("}");

        console2.log("------------------------------------------------------------------------------");
        console2.log("------------------------------ IMPORTANT! ------------------------------------");
        console2.log("------------------------------------------------------------------------------");
        console2.log("Stake ETH in EntryPoint for Paymaster to function properly!");
        console2.log("See .doc/deployment/deployment-guidelines.md for details.");
        console2.log("------------------------------------------------------------------------------");

        // Return deployed contract instances and configuration
        return (helperConfig, chatterPay, factory, chatterPayNFT, paymaster);
    }

    /**
     * @notice Deploy paymaster with entryPoint and backend signer (config.account)
     */
    function deployPaymaster() internal {
         address paymasterAddress = vm.envAddress("DEPLOYED_PAYMASTER_ADDRESS");

        if (paymasterAddress == address(0)) {
            console2.log("Creating NEW Paymaster!");
            paymaster = new ChatterPayPaymaster(config.entryPoint, config.account);
        } else {
            console2.log("Using existing Paymaster!");
            paymaster = ChatterPayPaymaster(payable(paymasterAddress));
        }
        console2.log("Paymaster deployed at address %s", address(paymaster));
        console2.log("EntryPoint used at address %s", config.entryPoint);
        console2.log("Backend signer set to %s", config.account);
    }

    /**
     * @notice Deploys the ChatterPayWalletFactory contract.
     * @dev Factory owner is set as the contract creator (config.account).
     */
    function deployFactory() internal {
        factory = new ChatterPayWalletFactory(
            config.account,      // _walletImplementation (temporary, will be updated later)
            config.entryPoint,   // _entryPoint
            config.account,      // _owner
            address(paymaster),  // _paymaster
            config.router,       // _router
            config.account,      // _feeAdmin (using account as fee admin)
            tokens,              // _whitelistedTokens
            priceFeeds           // _priceFeeds
        );
        console2.log("Wallet Factory deployed at address %s", address(factory));
        
        // Validate deployment
        require(factory.owner() == config.account, "Factory owner not set correctly");
        require(factory.paymaster() == address(paymaster), "Paymaster not set correctly");
    }

    /**
     * @notice Deploys the ChatterPay contract using UUPS Proxy with new initializer parameters.
     */
    function deployChatterPay() internal {
        // Use config.account as fee admin (must equal factory.owner())
        address feeAdmin = config.account;

        // Deploy the ChatterPay contract using UUPS Proxy via Upgrades library.
        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPay.sol:ChatterPay", // Contract name as string.
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],address[])",
                config.entryPoint,   // _entryPoint.
                config.account,      // _owner (owner must be the creator).
                address(paymaster),  // _paymaster.
                config.router,       // _router.
                address(factory),    // _factory.
                feeAdmin,            // _feeAdmin.
                tokens,              // _whitelistedTokens (token addresses).
                priceFeeds           // _priceFeeds (corresponding price feed addresses).
            )
        );

        // Retrieve and log the implementation address.
        address implementation = Upgrades.getImplementationAddress(proxy);
        console2.log("ChatterPay Implementation deployed at %s", implementation);

        // Update the factory with the correct implementation.
        factory.setImplementationAddress(implementation);
        console2.log("Factory implementation updated to %s", implementation);

        // Set chatterPay to the proxy address.
        chatterPay = ChatterPay(payable(proxy));
        console2.log("ChatterPay Proxy deployed at %s", address(chatterPay));
    }

    /**
     * @notice Deploys the ChatterPayNFT contract using Transparent Proxy.
     */
    function deployNFT() internal {
        chatterPayNFT = ChatterPayNFT(
            Upgrades.deployTransparentProxy(
                "ChatterPayNFT.sol:ChatterPayNFT", // Contract name as string.
                config.account,  // Initial owner.
                abi.encodeWithSignature(
                    "initialize(address,string)",
                    config.account,
                    NFTBaseUri
                )
            )
        );
        console2.log("ChatterPayNFT Proxy deployed at address %s", address(chatterPayNFT));
    }

    /**
     * @notice Mints test tokens for the Uniswap pool (Only in test networks).
     */
    function mintTestTokens() internal {
        // Amount to mint (100M)
        uint256 mintAmountUSDT = 100_000_000 * 1e6;  // USDT uses 6 decimals.
        uint256 mintAmountWETH = 100_000_000 * 1e18; // WETH uses 18 decimals.

        // Mint test tokens by calling the mint function.
        bytes memory mintData = abi.encodeWithSignature("mint(address,uint256)", config.account, mintAmountUSDT);
        (bool successA,) = tokens[0].call(mintData);
        require(successA, "Failed to mint tokenA");
        console2.log("Minted %d tokens A to %s", mintAmountUSDT, config.account);

        mintData = abi.encodeWithSignature("mint(address,uint256)", config.account, mintAmountWETH);
        (bool successB,) = tokens[1].call(mintData);
        require(successB, "Failed to mint tokenB");
        console2.log("Minted %d tokens B to %s", mintAmountWETH, config.account);
    }

    /**
     * @notice Configures the Uniswap V3 Pool between two tokens.
     * @dev Creates and initializes the pool if it doesn't exist, and adds liquidity if below threshold.
     */
    function configureUniswapPool() internal {
        // Ensure there are at least two tokens for the pool.
        require(tokens.length >= 2, "At least two tokens are needed for the pool");
        address tokenA = tokens[0];
        address tokenB = tokens[1];

        console2.log("Configuring Uniswap pool with:");
        console2.log("- TokenA: %s", tokenA);
        console2.log("- TokenB: %s", tokenB);
        console2.log("- Factory: %s", uniswapFactory);
        console2.log("- Position Manager: %s", uniswapPositionManager);
        console2.log("- Fee: %d", poolFee);

        // Use a local variable for the immutable uniswapFactory.
        address localFactory = uniswapFactory;
        uint256 factorySize;
        assembly {
            factorySize := extcodesize(localFactory)
        }
        require(factorySize > 0, "Uniswap factory not deployed at specified address");

        mintTestTokens();

        try IUniswapV3Factory(uniswapFactory).getPool(tokenA, tokenB, poolFee) returns (address pool) {
            if (pool == address(0)) {
                console2.log("Pool does not exist. Creating new pool...");
                try IUniswapV3Factory(uniswapFactory).createPool(tokenA, tokenB, poolFee) returns (address newPool) {
                    console2.log("Pool created at address: %s", newPool);
                    // Initialize the pool with a sqrt price of 1 * 2^96.
                    uint160 sqrtPriceX96 = 79228162514264337593543950336;
                    try IUniswapV3Pool(newPool).initialize(sqrtPriceX96) {
                        console2.log("Pool initialized successfully");
                        pool = newPool;
                    } catch Error(string memory reason) {
                        console2.log("Failed to initialize pool: %s", reason);
                        return;
                    }
                } catch Error(string memory reason) {
                    console2.log("Failed to create pool: %s", reason);
                    return;
                }
            } else {
                console2.log("Existing pool found at: %s", pool);
            }

            // Read pool liquidity and add liquidity if needed.
            try IUniswapV3Pool(pool).liquidity() returns (uint128 existingLiquidity) {
                console2.log("Current pool liquidity: %d", existingLiquidity);
                uint128 minLiquidityThreshold = 500_000 * 1e6;
                if (existingLiquidity < minLiquidityThreshold) {
                    console2.log("Liquidity below threshold. Attempting to add liquidity to pool: %s", pool);
                    addLiquidityToPool(tokenA, tokenB, pool);
                }
            } catch Error(string memory reason) {
                console2.log("Failed to read liquidity: %s", reason);
            }
        } catch Error(string memory reason) {
            console2.log("Failed to get pool: %s", reason);
            return;
        }
    }

    /**
     * @notice Adds liquidity to the specified Uniswap pool.
     */
    function addLiquidityToPool(address tokenA, address tokenB, address pool) internal {
        // Log the pool address to use the parameter.
        console2.log("Adding liquidity to pool: %s", pool);
        try IERC20Extended(tokenA).balanceOf(config.account) returns (uint256 balanceA) {
            try IERC20Extended(tokenB).balanceOf(config.account) returns (uint256 balanceB) {
                console2.log("Token balances:");
                console2.log("- TokenA: %d", balanceA);
                console2.log("- TokenB: %d", balanceB);
                if (balanceA > 0 && balanceB > 0) {
                    // Approve tokens for the Position Manager.
                    require(IERC20(tokenA).approve(uniswapPositionManager, balanceA), "Failed to approve tokenA");
                    require(IERC20(tokenB).approve(uniswapPositionManager, balanceB), "Failed to approve tokenB");
                    console2.log("Tokens approved for Position Manager");

                    // Set tick ranges (example values).
                    int24 tickSpacing = 60;
                    int24 tickLower = (-887220 / tickSpacing) * tickSpacing;
                    int24 tickUpper = (887220 / tickSpacing) * tickSpacing;

                    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                        token0: tokenA,
                        token1: tokenB,
                        fee: poolFee,
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        amount0Desired: balanceA,
                        amount1Desired: balanceB,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: config.account,
                        deadline: block.timestamp + 1000
                    });

                    try INonfungiblePositionManager(uniswapPositionManager).mint(params) returns
                        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
                        console2.log("Successfully added liquidity:");
                        console2.log("- Token ID: %d", tokenId);
                        console2.log("- Liquidity: %d", liquidity);
                        console2.log("- Amount0: %d", amount0);
                        console2.log("- Amount1: %d", amount1);
                    } catch Error(string memory reason) {
                        console2.log("Failed to mint position: %s", reason);
                    }
                } else {
                    console2.log("Insufficient balance to add liquidity");
                }
            } catch Error(string memory reason) {
                console2.log("Failed to get tokenB balance: %s", reason);
            }
        } catch Error(string memory reason) {
            console2.log("Failed to get tokenA balance: %s", reason);
        }
    }

    /**
     * @notice Deploys the ChatterPayVault contract.
     */
    function deployVault() internal {
        vault = new ChatterPayVault();
        console2.log("Vault deployed at address %s", address(vault));
    }

    /**
     * @notice Helper function to parse addresses from a comma-separated string.
     * @param _addressesStr Comma-separated string of addresses.
     * @return address[] Array of parsed addresses.
     */
    function _parseAddresses(string memory _addressesStr) internal pure returns (address[] memory) {
        string[] memory parts = vm.split(_addressesStr, ",");
        address[] memory addresses = new address[](parts.length);
        for (uint i = 0; i < parts.length; i++) {
            addresses[i] = vm.parseAddress(parts[i]);
        }
        return addresses;
    }
}