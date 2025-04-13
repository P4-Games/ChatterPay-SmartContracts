// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EntryPoint} from "lib/entry-point-v6/core/EntryPoint.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

/**
 * @title HelperConfig
 * @notice Helper contract for managing network configurations across different chains
 * @dev Provides configuration data for different networks including entry points and token addresses
 */
contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Configuration struct containing token-specific parameters
     * @param symbol The ERC20 token symbol (e.g., "USDC")
     * @param token The ERC20 token address
     * @param priceFeed Chainlink price feed address (e.g., USDC/USD)
     * @param isStable Whether the token is considered stable (e.g., true for USDC/USDT)
     *
     * @dev Chainlink price feeds reference: https://docs.chain.link/data-feeds/price-feeds
     */
    struct TokenConfig {
        string symbol;
        address token;
        address priceFeed;
        bool isStable;
    }

    /**
     * @notice Configuration struct for Uniswap V3
     * @param router Router contract address
     * @param factory Address of the Uniswap V3 factory
     * @param positionManager Address of the Uniswap V3 non-fungible position manager
     */
    struct UniswapConfig {
        address router;
        address factory;
        address positionManager;
    }

    /**
     * @notice Configuration struct containing network-specific addresses
     * @param entryPoint The EntryPoint contract address
     * @param backendSigner Backend signer account address
     * @param nftBaseUri NFT Contract Base Uri
     * @param tokensConfig Array of token configurations, including address, price feed, and stability flag
     * @param uniswapConfig Uniswap-specific configuration (factory + positionManager)
     */
    struct NetworkConfig {
        address entryPoint;
        address backendSigner;
        string nftBaseUri;
        TokenConfig[] tokensConfig;
        UniswapConfig uniswapConfig;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 constant ETHEREUM_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant SCROLL_DEVNET_CHAIN_ID = 2227728;
    uint256 constant SCROLL_SEPOLIA_CHAIN_ID = 534351;
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 constant OPTIMISM_SEPOLIA_CHAIN_ID = 11155420;
    uint256 constant LOCAL_CHAIN_ID = 31337;

    address constant BURNER_WALLET = 0x08f88ef7ecD64a2eA1f3887d725F78DDF1bacDF1;
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address immutable BACKEND_SIGNER;

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the contract and sets up network configurations
     * @dev Reads backend signer from environment and initializes configs for all supported networks
     */
    constructor() {
        BACKEND_SIGNER = vm.envAddress("BACKEND_EOA");
        networkConfigs[SCROLL_SEPOLIA_CHAIN_ID] = getScrollSepoliaConfig();
        networkConfigs[ARBITRUM_SEPOLIA_CHAIN_ID] = getArbitrumSepoliaConfig();
    }

    /**
     * @notice Gets the network configuration for the current chain
     * @return NetworkConfig Configuration for the current blockchain network
     */
    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    /**
     * @notice Gets network configuration for a specific chain ID
     * @param chainId The blockchain network ID
     * @return NetworkConfig Configuration for the specified chain ID
     */
    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else if (networkConfigs[chainId].backendSigner != address(0)) {
            return networkConfigs[chainId];
        } else {
            console.log("Invalid account %s for chainId: %s", networkConfigs[chainId].backendSigner, chainId);
            revert HelperConfig__InvalidChainId();
        }
    }

    /**
     * @notice Retrieves a token address by its symbol for the current network
     * @dev Performs a linear search through the tokensConfig array of the current network config
     * @param symbol The symbol of the token to search for (e.g., "USDC", "USDT", "WETH")
     * @return token The ERC20 token address matching the given symbol
     */
    function getTokenBySymbol(string memory symbol) external view returns (address token) {
        NetworkConfig memory config = networkConfigs[block.chainid];
        for (uint256 i = 0; i < config.tokensConfig.length; i++) {
            if (keccak256(bytes(config.tokensConfig[i].symbol)) == keccak256(bytes(symbol))) {
                return config.tokensConfig[i].token;
            }
        }
        revert(string(abi.encodePacked("Token symbol not found: ", symbol)));
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets configuration for Arbitrum Sepolia testnet
     * @return NetworkConfig Configuration with Arbitrum Sepolia addresses
     */
    function getArbitrumSepoliaConfig() public view returns (NetworkConfig memory) {
        // 0: USDT, 1: WETH, 2: USDC
        TokenConfig[] memory tokenConfigs = new TokenConfig[](3);

        tokenConfigs[0] = TokenConfig({
            symbol: "UDST",
            token: 0xe6B817E31421929403040c3e42A6a5C5D2958b4A,
            priceFeed: 0x80EDee6f667eCc9f63a0a6f55578F870651f06A4,
            isStable: true
        });

        tokenConfigs[1] = TokenConfig({
            symbol: "WETH",
            token: 0xE9C723D01393a437bac13CE8f925A5bc8E1c335c,
            priceFeed: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165,
            isStable: false
        });

        tokenConfigs[2] = TokenConfig({
            symbol: "UDDC",
            token: 0x8431eBc62F7B08af1bBf80eE7c85364ffc24ae24,
            priceFeed: 0x0153002d20B96532C639313c2d54c3dA09109309,
            isStable: true
        });

        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
            backendSigner: BACKEND_SIGNER,
            nftBaseUri: "https://dev.back.chatterpay.net/nft/metadata/opensea/",
            tokensConfig: tokenConfigs,
            uniswapConfig: UniswapConfig({
                router: 0x101F443B4d1b059569D643917553c771E1b9663E,
                factory: 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e,
                positionManager: 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65
            })
        });
    }

    /**
     * @notice Gets configuration for Scroll Sepolia testnet
     * @return NetworkConfig Configuration with Scroll Sepolia addresses
     */
    function getScrollSepoliaConfig() public view returns (NetworkConfig memory) {
        // 0: USDT, 1: WETH, 2: USDC
        TokenConfig[] memory tokenConfigs = new TokenConfig[](3);

        tokenConfigs[0] = TokenConfig({
            symbol: "UDST",
            token: 0x776133ea03666b73a8e3FC23f39f90e66360716E,
            priceFeed: 0xb84a700192A78103B2dA2530D99718A2a954cE86,
            isStable: true
        });

        tokenConfigs[1] = TokenConfig({
            symbol: "WETH",
            token: 0xd5654b986d5aDba8662c06e847E32579078561dC,
            priceFeed: 0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41,
            isStable: false
        });

        tokenConfigs[2] = TokenConfig({
            symbol: "USDC",
            token: 0x7878290DB8C4f02bd06E0E249617871c19508bE6,
            priceFeed: 0xFadA8b0737D4A3AE7118918B7E69E689034c0127,
            isStable: true
        });

        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
            backendSigner: BACKEND_SIGNER,
            nftBaseUri: "https://dev.back.chatterpay.net/nft/metadata/opensea/",
            tokensConfig: tokenConfigs,
            uniswapConfig: UniswapConfig({
                router: 0x17AFD0263D6909Ba1F9a8EAC697f76532365Fb95,
                factory: 0x0287f57A1a17a725428689dfD9E65ECA01d82510,
                positionManager: 0xA9c7C2BCEd22D1d47111610Af21a53B6D1e69eeD
            })
        });
    }

    /**
     * @notice Gets or creates configuration for local Anvil network
     * @dev Deploys mock contracts if they don't exist
     * @return NetworkConfig Configuration with local network addresses
     */
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.backendSigner != address(0)) {
            return localNetworkConfig;
        }

        // deploy mocks
        console.log("Deploying mocks...");
        vm.startBroadcast(ANVIL_DEFAULT_ACCOUNT);
        EntryPoint entryPoint = new EntryPoint();
        console.log("EntryPoint deployed! %s", address(entryPoint));
        ERC20Mock usdcMock = new ERC20Mock("Circle USD", "USDC");
        console.log("USDC deployed! %s", address(usdcMock));
        ERC20Mock usdtMock = new ERC20Mock("Tether USD", "USDT");
        console.log("USDT deployed! %s", address(usdtMock));
        ERC20Mock wethMock = new ERC20Mock("Wrapped ETH", "WETH");
        console.log("WETH deployed! %s", address(wethMock));
        vm.stopBroadcast();
        console.log("Mocks deployed!");

        // 0: USDT, 1: WETH, 2: USDC
        TokenConfig[] memory tokenConfigs = new TokenConfig[](3);
        tokenConfigs[0] = TokenConfig({symbol: "USDT", token: address(usdtMock), priceFeed: address(0), isStable: true});
        tokenConfigs[1] =
            TokenConfig({symbol: "WETH", token: address(wethMock), priceFeed: address(0), isStable: false});
        tokenConfigs[2] = TokenConfig({symbol: "USDC", token: address(usdcMock), priceFeed: address(0), isStable: true});

        localNetworkConfig = NetworkConfig({
            entryPoint: address(entryPoint),
            backendSigner: BACKEND_SIGNER,
            nftBaseUri: "https://dev.back.chatterpay.net/nft/metadata/opensea/",
            tokensConfig: tokenConfigs,
            uniswapConfig: UniswapConfig({router: address(0), factory: address(0), positionManager: address(0)})
        });
        return localNetworkConfig;
    }
}
