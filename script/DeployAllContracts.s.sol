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
            "Deploying ChatterPay contracts on chainId %d with account: %d",
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
        // Deploy paymaster with entryPoint and backend signer (which is the config.account in this case)
        paymaster = new ChatterPayPaymaster(config.entryPoint, config.account);
        
        console2.log("Paymaster deployed at address %d", address(paymaster));
        console2.log("EntryPoint used at address %d", config.entryPoint);
        console2.log("Backend signer set to %d", config.account);
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
        console2.log("Wallet Factory deployed at address %d:", address(factory));
    }

    /**
     * @notice Deploys the ChatterPay contract using UUPS Proxy
     */
    function deployChatterPay() internal {
        // Deploy the ChatterPay contract using UUPS Proxy via Upgrades library
        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPay.sol:ChatterPay", // Contract name as string
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address)",
                config.entryPoint,  // _entryPoint
                config.account,     // _newOwner
                address(paymaster), // _paymaster
                config.router,      // _router
                address(factory)    // _factory
            )
        );

        // Get the implementation address
        address implementation = Upgrades.getImplementationAddress(proxy);
        console2.log("ChatterPay Implementation deployed at %d", implementation);

        // Update the factory with the correct implementation
        factory.setImplementationAddress(implementation);
        console2.log("Factory implementation updated to %d", implementation);

        // Cast the proxy address to payable
        address payable payableProxy = payable(proxy);
        chatterPay = ChatterPay(payableProxy);
        console2.log("ChatterPay Proxy deployed at %d", address(chatterPay));
    }

    /**
     * @notice Deploys the ChatterPayNFT contract using Transparent Proxy
     */
    function deployNFT() internal {
        // Deploy the ChatterPayNFT contract using Transparent Proxy via Upgrades library
        chatterPayNFT = ChatterPayNFT(
            Upgrades.deployTransparentProxy(
                "ChatterPayNFT.sol:ChatterPayNFT", // Contract name as string
                config.account,  // Initial owner
                abi.encodeWithSignature(
                    "initialize(address,string)",
                    config.account,
                    NFTBaseUri
                )
            )
        );

        console2.log("ChatterPayNFT Proxy deployed at %d:", address(chatterPayNFT));
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
            console2.log("Token %d whitelisted with Price Feed %d", address(token), address(priceFeed));
        }
    }

    /**
     * This function allows the contract to mint test tokens for the Uniswap pool (Only in test networks)
     */
    function mintTestTokens() internal {
        // Cantidad a mintear (100M)
        uint256 mintAmountUSDT = 100_000_000 * 1e6;  // USDT usa 6 decimales
        uint256 mintAmountWETH = 100_000_000 * 1e18; // WETH usa 18 decimales

        // Interfaz para mintear tokens de prueba
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
     * @notice Configures the Uniswap V3 Pool between two tokens
     * @dev Checks if the pool exists; if not, creates and initializes it
     */
    function configureUniswapPool() internal {
        // Ensure there are at least two tokens to create a pool
        require(tokens.length >= 2, "At least two tokens are needed for the pool");
        address tokenA = tokens[0];
        address tokenB = tokens[1];

        // Log the addresses we're working with
        console2.log("Configuring Uniswap pool with:");
        console2.log("- TokenA:", tokenA);
        console2.log("- TokenB:", tokenB);
        console2.log("- Factory:", uniswapFactory);
        console2.log("- Position Manager:", uniswapPositionManager);
        console2.log("- Fee:", poolFee);

        // Verify the factory contract exists
        address factory = uniswapFactory;
        uint256 factorySize;
        assembly {
            factorySize := extcodesize(factory)
        }
        require(factorySize > 0, "Uniswap factory not deployed at specified address");

        mintTestTokens();
        
        try IUniswapV3Factory(uniswapFactory).getPool(tokenA, tokenB, poolFee) returns (address pool) {
            if (pool == address(0)) {
                console2.log("Pool does not exist. Creating new pool...");
                try IUniswapV3Factory(uniswapFactory).createPool(tokenA, tokenB, poolFee) returns (address newPool) {
                    console2.log("Pool created at address:", newPool);
                    
                    // Initialize the pool with a sqrt price of 1
                    uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1 * 2^96
                    try IUniswapV3Pool(newPool).initialize(sqrtPriceX96) {
                        console2.log("Pool initialized successfully");
                        pool = newPool;
                    } catch Error(string memory reason) {
                        console2.log("Failed to initialize pool:", reason);
                        return;
                    }
                } catch Error(string memory reason) {
                    console2.log("Failed to create pool:", reason);
                    return;
                }
            } else {
                console2.log("Existing pool found at:", pool);
            }

            // Try to read the liquidity
            try IUniswapV3Pool(pool).liquidity() returns (uint128 existingLiquidity) {
                console2.log("Current pool liquidity:", existingLiquidity);
                
                uint128 minLiquidityThreshold = 500_000 * 1e6;
                if (existingLiquidity < minLiquidityThreshold) {
                    console2.log("Liquidity below threshold. Will attempt to add liquidity...");
                    addLiquidityToPool(tokenA, tokenB, pool);
                }
            } catch Error(string memory reason) {
                console2.log("Failed to read liquidity:", reason);
            }
        } catch Error(string memory reason) {
            console2.log("Failed to get pool:", reason);
            return;
        }
    }

    function addLiquidityToPool(address tokenA, address tokenB, address pool) internal {
        try IERC20Extended(tokenA).balanceOf(config.account) returns (uint256 balanceA) {
            try IERC20Extended(tokenB).balanceOf(config.account) returns (uint256 balanceB) {
                console2.log("Token balances:");
                console2.log("- TokenA:", balanceA);
                console2.log("- TokenB:", balanceB);

                if (balanceA > 0 && balanceB > 0) {
                    // Approve tokens
                    try IERC20(tokenA).approve(uniswapPositionManager, balanceA) returns (bool success) {
                        require(success, "Failed to approve tokenA");
                        try IERC20(tokenB).approve(uniswapPositionManager, balanceB) returns (bool success2) {
                            require(success2, "Failed to approve tokenB");
                            
                            console2.log("Tokens approved for Position Manager");

                            // Create position
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
                                console2.log("- Token ID:", tokenId);
                                console2.log("- Liquidity:", liquidity);
                                console2.log("- Amount0:", amount0);
                                console2.log("- Amount1:", amount1);
                            } catch Error(string memory reason) {
                                console2.log("Failed to mint position:", reason);
                            }
                        } catch Error(string memory reason) {
                            console2.log("Failed to approve tokenB:", reason);
                        }
                    } catch Error(string memory reason) {
                        console2.log("Failed to approve tokenA:", reason);
                    }
                } else {
                    console2.log("Insufficient balance to add liquidity");
                }
            } catch Error(string memory reason) {
                console2.log("Failed to get tokenB balance:", reason);
            }
        } catch Error(string memory reason) {
            console2.log("Failed to get tokenA balance:", reason);
        }
    }

    /**
     * @notice Deploys the ChatterPayVault contract
     */
    function deployVault() internal {
        vault = new ChatterPayVault();
        console2.log("Vault deployed at address %d:", address(vault));
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