// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Import necessary libraries and contracts
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

// Uniswap V3 Interfaces (as defined earlier)

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

    // Uniswap V3 Addresses
    address uniswapFactory;
    address uniswapPositionManager;
    uint24 poolFee = 3000; // Fee tier of 0.3%

    // Tokens and Price Feeds
    address[] tokens;
    address[] priceFeeds;

    // Environment Variables
    string NFTBaseUri = vm.envString("NFT_BASE_URI");
    string tokensEnv = vm.envString("TOKENS"); // Comma-separated list of tokens
    string priceFeedsEnv = vm.envString("PRICE_FEEDS"); // Comma-separated list of price feeds

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

        // Retrieve Uniswap addresses from environment variables
        uniswapFactory = vm.envAddress("UNISWAP_FACTORY");
        uniswapPositionManager = vm.envAddress("POSITION_MANAGER");

        // Parse tokens and price feeds from environment variables
        tokens = _parseAddresses(tokensEnv);
        priceFeeds = _parseAddresses(priceFeedsEnv);

        // Ensure the number of tokens matches the number of price feeds
        require(tokens.length == priceFeeds.length, "Tokens and Price Feeds must have the same length");

        // Start broadcasting transactions with the configured account
        vm.startBroadcast(config.account);

        console2.log(
            "Deploying ChatterPay contracts on chainId %s with account: %s",
            block.chainid,
            config.account
        );

        // Step-by-step deployment and configuration
        deployPaymaster();                           // 1. Deploy Paymaster
        deployFactory();                             // 2. Deploy Wallet Factory
        deployChatterPay();                          // 3. Deploy ChatterPay using UUPS Proxy
        // Removed: setFactoryInChatterPay();        // 4. Set Factory address in ChatterPay
        deployNFT();                                 // 4. Deploy NFT with Transparent Proxy
        configurePriceFeedsAndWhitelistTokens();     // 5. Configure Price Feeds and Whitelisted Tokens
        configureUniswapPool();                      // 6. Configure Uniswap V3 Pool
        deployVault();                               // 7. Deploy Vault

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Return deployed contract instances and configuration
        return (helperConfig, chatterPay, factory, chatterPayNFT, paymaster);
    }

    /**
     * @notice Deploys the ChatterPayPaymaster contract
     */
    function deployPaymaster() internal {
        paymaster = new ChatterPayPaymaster(config.entryPoint, config.account);
        console2.log("Paymaster deployed at address %s", address(paymaster));
        console2.log("EntryPoint used at address %s", config.entryPoint);
    }

    /**
     * @notice Deploys the ChatterPayWalletFactory contract
     */
    function deployFactory() internal {
        factory = new ChatterPayWalletFactory(
            address(0), // Placeholder, will set factory's owner later if needed
            config.entryPoint,
            config.account,
            address(paymaster),
            config.router
        );
        console2.log("Wallet Factory deployed at address %s:", address(factory));
    }

    /**
     * @notice Deploys the ChatterPay contract using UUPS Proxy
     */
    function deployChatterPay() internal {
        // Deploy the ChatterPay contract using UUPS Proxy via Upgrades library
        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPay", // Contract name as string
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                config.entryPoint,  // _entryPoint
                config.account,     // _newOwner
                address(paymaster), // _paymaster
                config.router,      // _router
                address(factory)    // _factory
            )
        );

        // Cast the proxy address to payable
        address payable payableProxy = payable(proxy);

        // Assign the proxy to the ChatterPay contract instance
        chatterPay = ChatterPay(payableProxy);

        console2.log("ChatterPay Proxy deployed at %s", address(chatterPay));
    }

    /**
     * @notice Deploys the ChatterPayNFT contract using Transparent Proxy
     */
    function deployNFT() internal {
        // Deploy the ChatterPayNFT contract using Transparent Proxy via Upgrades library
        chatterPayNFT = ChatterPayNFT(
            Upgrades.deployTransparentProxy(
                "ChatterPayNFT", // Contract name as string
                config.account,  // Initial owner
                abi.encodeWithSignature(
                    "initialize(address,string)",
                    config.account,
                    NFTBaseUri
                )
            )
        );

        console2.log("ChatterPayNFT Proxy deployed at %s:", address(chatterPayNFT));
    }

    /**
     * @notice Configures Price Feeds and Whitelisted Tokens in the ChatterPay contract
     */
    function configurePriceFeedsAndWhitelistTokens() internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            address priceFeed = priceFeeds[i];

            // Whitelist the token and set its corresponding price feed
            chatterPay.setTokenWhitelistAndPriceFeed(token, true, priceFeed);
            console2.log("Token %s whitelisted with Price Feed %s", address(token), address(priceFeed));
        }
    }

    /**
     * @notice Configures the Uniswap V3 Pool between two tokens
     * @dev Checks if the pool exists; if not, creates and initializes it
     */
    function configureUniswapPool() internal {
        // Ensure there are at least two tokens to create a pool
        require(tokens.length >= 2, "At least two tokens are needed for the pool");
        address tokenA = tokens[0];
        address tokenB = tokens[1];

        // Check if the pool already exists
        address pool = IUniswapV3Factory(uniswapFactory).getPool(tokenA, tokenB, poolFee);
        if (pool == address(0)) {
            console2.log("Pool not found. Creating pool...");
            pool = IUniswapV3Factory(uniswapFactory).createPool(tokenA, tokenB, poolFee);
            console2.log("Pool created at address %s", pool);

            // Initialize the pool with an initial price (e.g., 1:1)
            uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1 * 2^96
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            console2.log("Pool initialized with sqrtPriceX96: %s", sqrtPriceX96);
        } else {
            console2.log("Existing pool found at address %s", pool);
        }

        // Retrieve existing liquidity in the pool
        uint128 existingLiquidity = IUniswapV3Pool(pool).liquidity();
        console2.log("Existing liquidity in the pool: %s", existingLiquidity);

        // Define a minimum liquidity threshold (e.g., 500,000 units)
        uint128 minLiquidityThreshold = 500_000 * 1e6;

        if (existingLiquidity < minLiquidityThreshold) {
            console2.log("Liquidity below threshold. Adding liquidity...");

            // Retrieve token balances of the deployer account
            uint256 balanceA = IERC20Extended(tokenA).balanceOf(config.account);
            uint256 balanceB = IERC20Extended(tokenB).balanceOf(config.account);

            if (balanceA > 0 && balanceB > 0) {
                console2.log("Adding liquidity to the pool...");

                // Approve the Position Manager to spend tokens
                IERC20(tokenA).approve(uniswapPositionManager, balanceA);
                IERC20(tokenB).approve(uniswapPositionManager, balanceB);
                console2.log("Tokens approved for Position Manager");

                // Define ticks with a wide range
                int24 tickSpacing = 60; // Depends on the pool's fee tier
                int24 tickLower = (-887220 / tickSpacing) * tickSpacing;
                int24 tickUpper = (887220 / tickSpacing) * tickSpacing;

                // Create parameters for minting liquidity position
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

                // Mint the liquidity position
                (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(uniswapPositionManager).mint(params);
                console2.log("Liquidity added: tokenId=%s, liquidity=%s, amount0=%s, amount1=%s", tokenId, liquidity, amount0, amount1);
            } else {
                console2.log("Insufficient balance to add liquidity.");
            }
        } else {
            console2.log("Sufficient liquidity already exists. No need to add more.");
        }
    }

    /**
     * @notice Deploys the ChatterPayVault contract
     */
    function deployVault() internal {
        vault = new ChatterPayVault();
        console2.log("Vault deployed at address %s:", address(vault));
    }

    /**
     * @notice Helper function to parse addresses from a comma-separated string
     * @param _addressesStr Comma-separated string of addresses
     * @return address[] Array of parsed addresses
     */
    function _parseAddresses(string memory _addressesStr) internal returns (address[] memory) {
        string[] memory parts = vm.split(_addressesStr, ",");
        address[] memory addresses = new address[](parts.length);
        for (uint i = 0; i < parts.length; i++) {
            // Foundry cheatcode that parses a string like "0x1234..." into a raw address
            addresses[i] = vm.parseAddress(parts[i]); 
        }
        return addresses;
    }

    /**
     * @notice Converts a byte array to an address
     * @param bys Byte array representing an address
     * @return addr The converted address
     * @dev Corrected the memory offset in the assembly code
     */
    function _bytesToAddress(bytes memory bys) internal pure returns (address addr) {
        require(bys.length == 20, "Invalid address length");
        assembly {
            // Load the address from the byte array starting at the 32-byte offset
            addr := mload(add(bys, 32))
        }
    }
}