// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPay} from "../src/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../src/ChatterPayPaymaster.sol";
import {ChatterPayNFT} from "../src/ChatterPayNFT.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Extended} from "../src/ChatterPay.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Factory, IUniswapV3Pool, INonfungiblePositionManager} from "../test/setup/BaseTest.sol";
import "forge-std/console2.sol";

pragma solidity ^0.8.24;

/**
 * @title DeployAllContracts
 * @notice Script to deploy the full ChatterPay contract suite for testing or production setup.
 *
 * This script:
 *  - Deploys the Paymaster, NFT, WalletFactory, and ChatterPay implementation contracts.
 *  - Initializes the ChatterPay contract with correct configuration.
 *  - Registers the implementation in the factory.
 *  - Logs gas usage and key contract addresses.
 *
 * 🔧 Configuration:
 * Requires environment variables to be set as specified in `.env.example`.
 *
 * ⚠️ Important:
 * If the following variables are already set:
 *  - `DEPLOYED_PAYMASTER_ADDRESS`
 *  - `DEPLOYED_NFT_ADDRESS`
 * then **those contracts will NOT be deployed again** — the existing deployed addresses will be used
 * for configuration and initialization instead.
 */
contract DeployAllContracts is Script {
    // Network Configuration
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;

    // Contract Instances
    ChatterPay chatterPay;
    ChatterPayWalletFactory factory;
    ChatterPayPaymaster paymaster;
    ChatterPayNFT chatterPayNFT;

    // Uniswap V3 Addresses
    address uniswapFactory;
    address uniswapPositionManager;
    address uniswapRouter;

    // Fee tier of 0.3%
    uint24 poolFee = 3000;

    // Tokens, Price Feeds and tokens-stable flags arrays
    address[] tokens;
    address[] priceFeeds;
    bool[] tokensStableFlags;

    // Environment Variables
    string deployNetworkEnv = vm.envString("DEPLOY_NETWORK_ENV");

    /**
     * @notice Main deployment function
     */
    function run()
        public
        returns (HelperConfig, ChatterPay, ChatterPayWalletFactory, ChatterPayNFT, ChatterPayPaymaster)
    {
        // Initialize network configuration
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();

        uniswapFactory = config.uniswapConfig.factory;
        uniswapPositionManager = config.uniswapConfig.positionManager;
        uniswapRouter = config.uniswapConfig.router;

        // Extract tokens, priceFeeds and flags from config.tokensConfig
        uint256 numTokens = config.tokensConfig.length;
        tokens = new address[](numTokens);
        priceFeeds = new address[](numTokens);
        tokensStableFlags = new bool[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            tokens[i] = config.tokensConfig[i].token;
            priceFeeds[i] = config.tokensConfig[i].priceFeed;
            tokensStableFlags[i] = config.tokensConfig[i].isStable;
        }

        // Start broadcasting transactions with the configured account
        vm.startBroadcast(config.backendSigner);

        console2.log(
            "Deploying ChatterPay contracts on chainId %d with account: %s", block.chainid, config.backendSigner
        );

        // Step-by-step deployment and configuration
        deployPaymaster(); // 1. Deploy Paymaster
        deployFactory(); // 2. Deploy Wallet Factory
        deployChatterPay(); // 3. Deploy ChatterPay using UUPS Proxy
        deployNFT(); // 4. Deploy NFT with Transparent Proxy

        if (block.chainid != 31337) {
            // anvil
            configureUniswapPool(); // 5. Configure Uniswap V3 Pool (skip in Anvil)
        }

        // Stop broadcasting transactions
        vm.stopBroadcast();

        console2.log("To Put in bdd:");
        console2.log("{");
        console2.log('"entryPoint": "%s",', address(config.entryPoint));
        console2.log('"factoryAddress": "%s",', address(factory));
        console2.log('"chatterPayAddress": "%s",', address(chatterPay));
        console2.log('"chatterNFTAddress": "%s",', address(chatterPayNFT));
        console2.log('"paymasterAddress": "%s",', address(paymaster));
        console2.log('"routerAddress": "%s"', uniswapRouter);
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
     * @notice Deploy paymaster with entryPoint and backend signer (config.backendSigner)
     */
    function deployPaymaster() internal {
        address paymasterAddress;
        try vm.envAddress("DEPLOYED_PAYMASTER_ADDRESS") returns (address addr) {
            paymasterAddress = addr;
        } catch {
            paymasterAddress = address(0);
        }

        if (paymasterAddress == address(0)) {
            console2.log("Creating NEW Paymaster!");
            paymaster = new ChatterPayPaymaster(config.entryPoint, config.backendSigner);
        } else {
            console2.log("Using existing Paymaster!");
            paymaster = ChatterPayPaymaster(payable(paymasterAddress));
        }
        console2.log("Paymaster deployed at address %s", address(paymaster));
        console2.log("EntryPoint used at address %s", config.entryPoint);
        console2.log("Backend signer set to %s", config.backendSigner);
    }

    /**
     * @notice Deploys the ChatterPayWalletFactory contract.
     * @dev Factory owner is set as the contract creator (config.backendSigner).
     */
    function deployFactory() internal {
        factory = new ChatterPayWalletFactory(
            config.backendSigner, // _walletImplementation (temporary, will be updated later)
            config.entryPoint, // _entryPoint
            config.backendSigner, // _owner
            address(paymaster), // _paymaster
            uniswapRouter, // _router
            tokens, // _whitelistedTokens
            priceFeeds, // _priceFeeds
            tokensStableFlags
        );
        console2.log("Wallet Factory deployed at address %s", address(factory));

        // Validate deployment
        require(factory.owner() == config.backendSigner, "Factory owner not set correctly");
        require(factory.paymaster() == address(paymaster), "Paymaster not set correctly");
    }

    /**
     * @notice Deploys the ChatterPay contract using UUPS Proxy with new initializer parameters.
     */
    function deployChatterPay() internal {
        // Deploy the ChatterPay contract using UUPS Proxy via Upgrades library.
        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPay.sol:ChatterPay", // Contract name as string.
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address[],address[],bool[])",
                config.entryPoint, // _entryPoint.
                config.backendSigner, // _owner (owner must be the creator).
                address(paymaster), // _paymaster.
                uniswapRouter, // _router.
                address(factory), // _factory.
                tokens, // _whitelistedTokens (token addresses).
                priceFeeds, // _priceFeeds (corresponding price feed addresses).
                tokensStableFlags // __tokensStableFlags.
            )
        );

        // Retrieve and log the implementation address.
        address implementation = Upgrades.getImplementationAddress(proxy);
        console2.log("ChatterPay Implementation deployed at %s", implementation);

        // Update the factory with the correct implementation.
        factory.setImplementationAddress(implementation);
        console2.log("Wallet Factory implementation updated to %s", implementation);

        // Set chatterPay to the proxy address.
        chatterPay = ChatterPay(payable(proxy));
        console2.log("ChatterPay Proxy deployed at %s", address(chatterPay));
    }

    /**
     * @notice Deploys the ChatterPayNFT contract using Transparent Proxy.
     */
    function deployNFT() internal {
        address nftAddress;
        try vm.envAddress("DEPLOYED_NFT_ADDRESS") returns (address addr) {
            nftAddress = addr;
        } catch {
            nftAddress = address(0);
        }

        if (nftAddress == address(0)) {
            console2.log("Creating NEW NFT Contract!");
            chatterPayNFT = ChatterPayNFT(
                Upgrades.deployTransparentProxy(
                    "ChatterPayNFT.sol:ChatterPayNFT",
                    config.backendSigner, // Initial owner.
                    abi.encodeWithSignature("initialize(address,string)", config.backendSigner, config.nftBaseUri)
                )
            );
        } else {
            chatterPayNFT = ChatterPayNFT(nftAddress);
            console2.log("ChatterPayNFT Proxy alreadydeployed at address %s", address(chatterPayNFT));
        }
    }

    /**
     * @notice Mints test tokens for the Uniswap pool (Only in test networks).
     */
    function mintTestTokens() internal {
        // Amount to mint (100M)
        uint256 mintAmountUSDT = 100_000_000 * 1e6; // USDT uses 6 decimals.
        uint256 mintAmountWETH = 100_000_000 * 1e18; // WETH uses 18 decimals.

        // Mint test tokens by calling the mint function.
        bytes memory mintData = abi.encodeWithSignature("mint(address,uint256)", config.backendSigner, mintAmountUSDT);
        (bool successA,) = tokens[0].call(mintData);
        require(successA, "Failed to mint tokenA");
        console2.log("Minted %d tokens A to %s", mintAmountUSDT, config.backendSigner);

        mintData = abi.encodeWithSignature("mint(address,uint256)", config.backendSigner, mintAmountWETH);
        (bool successB,) = tokens[1].call(mintData);
        require(successB, "Failed to mint tokenB");
        console2.log("Minted %d tokens B to %s", mintAmountWETH, config.backendSigner);
    }

    /**
     * @notice Configures the Uniswap V3 Pool between two tokens.
     * @dev Creates and initializes the pool if it doesn't exist, and adds liquidity if below threshold.
     */
    function configureUniswapPool() internal {
        // Only in test networks
        if (keccak256(bytes(deployNetworkEnv)) == keccak256(bytes("PROD"))) {
            console2.log("Skipping Uniswap pool configuration in PROD environment.");
            return;
        }

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
        try IERC20Extended(tokenA).balanceOf(config.backendSigner) returns (uint256 balanceA) {
            try IERC20Extended(tokenB).balanceOf(config.backendSigner) returns (uint256 balanceB) {
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
                        recipient: config.backendSigner,
                        deadline: block.timestamp + 1000
                    });

                    try INonfungiblePositionManager(uniswapPositionManager).mint(params) returns (
                        uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1
                    ) {
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
     * @notice Helper function to parse addresses from a comma-separated string.
     * @param _addressesStr Comma-separated string of addresses.
     * @return address[] Array of parsed addresses.
     */
    function _parseAddresses(string memory _addressesStr) internal pure returns (address[] memory) {
        string[] memory parts = vm.split(_addressesStr, ",");
        address[] memory addresses = new address[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            addresses[i] = vm.parseAddress(parts[i]);
        }
        return addresses;
    }

    /**
     * @notice Helper function to parse booleans from a comma-separated string.
     * @param _boolsStr Comma-separated string of booleans (e.g., "true,false,true").
     * @return bool[] Array of parsed booleans.
     */
    function _parseBools(string memory _boolsStr) internal pure returns (bool[] memory) {
        string[] memory parts = vm.split(_boolsStr, ",");
        bool[] memory bools = new bool[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            // Convert to lower case if needed, then compare
            if (keccak256(bytes(parts[i])) == keccak256("true")) {
                bools[i] = true;
            } else if (keccak256(bytes(parts[i])) == keccak256("false")) {
                bools[i] = false;
            } else {
                revert("Invalid boolean string value");
            }
        }
        return bools;
    }
}
