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
     * @param token The ERC20 token address
     * @param priceFeed The Chainlink price feed address for the token (e.g. USDT/USD)
     * @param isStable Boolean indicating if the token is considered stable (e.g. true for USDC/USDT)
     */
    struct TokenConfig {
        address token;
        address priceFeed;
        bool isStable;
    }

    /**
     * @notice Configuration struct containing network-specific addresses
     * @param entryPoint The EntryPoint contract address
     * @param usdc USDC token address
     * @param usdt USDT token address
     * @param weth WETH token address
     * @param matic MATIC token address
     * @param uniswapRouter uniswap Router
     * @param account Backend signer account address
     */
    struct NetworkConfig {
        address entryPoint;
        address usdc;
        address usdt;
        address weth;
        address matic;
        address uniswapRouter;
        address account;
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
        console.log("backend_signer account", BACKEND_SIGNER);
        networkConfigs[ETHEREUM_SEPOLIA_CHAIN_ID] = getEthereumSepoliaConfig();
        networkConfigs[SCROLL_SEPOLIA_CHAIN_ID] = getScrollSepoliaConfig();
        networkConfigs[SCROLL_DEVNET_CHAIN_ID] = getScrollDevnetConfig();
        networkConfigs[ARBITRUM_SEPOLIA_CHAIN_ID] = getArbitrumSepoliaConfig();
        networkConfigs[OPTIMISM_SEPOLIA_CHAIN_ID] = getOptimismSepoliaConfig();
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
        } else if (networkConfigs[chainId].account != address(0)) {
            return networkConfigs[chainId];
        } else {
            console.log("Invalid account %s for chainId: %s", networkConfigs[chainId].account, chainId);
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/

    /**
     * /// @notice Returns the configuration for the Arbitrum mainnet
     * /// @return NetworkConfig Configuration with addresses on Arbitrum One
     */
    function getArbitrumOneConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.6
            usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // native (circle) USDC
            usdt: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // USDT
            weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
            matic: 0x0000000000000000000000000000000000000000, // Not implemented yet
            uniswapRouter: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // SwapRouter02
            account: BACKEND_SIGNER
        });
    }

    /**
     * @notice Gets configuration for Ethereum Sepolia testnet
     * @return NetworkConfig Configuration with Ethereum Sepolia addresses
     */
    function getEthereumSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.6
            usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            usdt: 0xe6B817E31421929403040c3e42A6a5C5D2958b4A,
            weth: 0xE9C723D01393a437bac13CE8f925A5bc8E1c335c,
            matic: 0x0000000000000000000000000000000000000000, // Not implemented yet
            uniswapRouter: 0x101F443B4d1b059569D643917553c771E1b9663E, // SwapRouter02
            account: BACKEND_SIGNER
        });
    }

    /**
     * @notice Gets configuration for Arbitrum Sepolia testnet
     * @return NetworkConfig Configuration with Arbitrum Sepolia addresses
     */
    function getArbitrumSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.6
            usdc: 0x8431eBc62F7B08af1bBf80eE7c85364ffc24ae24, // USDC (Manteca)
            usdt: 0xe6B817E31421929403040c3e42A6a5C5D2958b4A,
            weth: 0xE9C723D01393a437bac13CE8f925A5bc8E1c335c,
            matic: 0x0000000000000000000000000000000000000000, // Not implemented yet
            uniswapRouter: 0x101F443B4d1b059569D643917553c771E1b9663E, // SwapRouter02
            account: BACKEND_SIGNER
        });
    }

    /**
     * @notice Gets configuration for Scroll devnet
     * @return NetworkConfig Configuration with Scroll devnet addresses
     */
    function getScrollDevnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.6
            usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            usdt: 0xe6B817E31421929403040c3e42A6a5C5D2958b4A,
            weth: 0xE9C723D01393a437bac13CE8f925A5bc8E1c335c,
            matic: 0x0000000000000000000000000000000000000000, // Not implemented yet
            uniswapRouter: 0x101F443B4d1b059569D643917553c771E1b9663E,
            account: BACKEND_SIGNER
        });
    }

    /**
     * @notice Gets configuration for Scroll Sepolia testnet
     * @return NetworkConfig Configuration with Scroll Sepolia addresses
     */
    function getScrollSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.6
            usdc: 0xFadA8b0737D4A3AE7118918B7E69E689034c0127,
            usdt: 0xb84a700192A78103B2dA2530D99718A2a954cE86,
            weth: 0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41,
            matic: 0x0000000000000000000000000000000000000000, // Not implemented yet
            uniswapRouter: 0x17AFD0263D6909Ba1F9a8EAC697f76532365Fb95,
            account: BACKEND_SIGNER
        });
    }

    /**
     * @notice Gets configuration for Optimism Sepolia testnet
     * @return NetworkConfig Configuration with Optimism Sepolia addresses
     */
    function getOptimismSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.6
            usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            usdt: 0xe6B817E31421929403040c3e42A6a5C5D2958b4A,
            weth: 0xE9C723D01393a437bac13CE8f925A5bc8E1c335c,
            matic: 0x0000000000000000000000000000000000000000, // address TBD
            uniswapRouter: 0x101F443B4d1b059569D643917553c771E1b9663E,
            account: BACKEND_SIGNER
        });
    }

    /**
     * @notice Gets or creates configuration for local Anvil network
     * @dev Deploys mock contracts if they don't exist
     * @return NetworkConfig Configuration with local network addresses
     */
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.account != address(0)) {
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
        ERC20Mock maticMock = new ERC20Mock("MATIC", "MATIC");
        console.log("MATIC deployed! %s", address(maticMock));
        vm.stopBroadcast();
        console.log("Mocks deployed!");

        localNetworkConfig = NetworkConfig({
            entryPoint: address(entryPoint),
            usdc: address(usdcMock),
            usdt: address(usdtMock),
            weth: address(wethMock),
            matic: address(maticMock),
            uniswapRouter: 0x101F443B4d1b059569D643917553c771E1b9663E,
            account: BACKEND_SIGNER
        });
        return localNetworkConfig;
    }
}
