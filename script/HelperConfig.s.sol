// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EntryPoint} from "lib/entry-point-v6/core/EntryPoint.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address entryPoint;
        address usdc;
        address usdt;
        address weth;
        address matic;
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
    address constant ANVIL_DEFAULT_ACCOUNT =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETHEREUM_SEPOLIA_CHAIN_ID] = getEthereumSepoliaConfig();
        networkConfigs[SCROLL_SEPOLIA_CHAIN_ID] = getScrollSepoliaConfig();
        networkConfigs[SCROLL_DEVNET_CHAIN_ID] = getScrollDevnetConfig();
        networkConfigs[ARBITRUM_SEPOLIA_CHAIN_ID] = getArbitrumSepoliaConfig();
        networkConfigs[OPTIMISM_SEPOLIA_CHAIN_ID] = getOptimismSepoliaConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else if (networkConfigs[chainId].account != address(0)) {
            return networkConfigs[chainId];
        } else {
            console.log("Invalid chainId: %s", chainId);
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/

    function getEthereumSepoliaConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.7
                usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
                usdt: 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06,
                weth: 0x0000000000000000000000000000000000000000, // address TBD
                matic: 0x0000000000000000000000000000000000000000, // address TBD
                account: BURNER_WALLET
            });
    }

    function getArbitrumSepoliaConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.7
                usdc: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d,
                usdt: 0x961bf3bf61d3446907E0Db83C9c5D958c17A94f6, // address TBD
                weth: 0x0000000000000000000000000000000000000000, // address TBD
                matic: 0x0000000000000000000000000000000000000000, // address TBD
                account: BURNER_WALLET
            });
    }

    function getScrollDevnetConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.7
                usdc: 0x0000000000000000000000000000000000000000, // address to be deployed
                usdt: 0x0000000000000000000000000000000000000000, // address TBD
                weth: 0x0000000000000000000000000000000000000000, // address TBD
                matic: 0x0000000000000000000000000000000000000000, // address TBD
                account: BURNER_WALLET
            });
    }

    function getScrollSepoliaConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.7
                usdc: 0x0000000000000000000000000000000000000000, // address to be deployed
                usdt: 0x0000000000000000000000000000000000000000, // address TBD
                weth: 0x0000000000000000000000000000000000000000, // address TBD
                matic: 0x0000000000000000000000000000000000000000, // address TBD
                account: BURNER_WALLET
            });
    }

    function getOptimismSepoliaConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, // v0.7
                usdc: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7,
                usdt: 0x0000000000000000000000000000000000000000, // address TBD
                weth: 0x0000000000000000000000000000000000000000, // address TBD
                matic: 0x0000000000000000000000000000000000000000, // address TBD
                account: BURNER_WALLET
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.account != address(0)) {
            return localNetworkConfig;
        }

        // deploy mocks
        console.log("Deploying mocks...");
        vm.startBroadcast(ANVIL_DEFAULT_ACCOUNT);
        EntryPoint entryPoint = new EntryPoint();
        console.log("EntryPoint deployed! %s", address(entryPoint));
        ERC20Mock usdcMock = new ERC20Mock();
        console.log("USDC deployed! %s", address(usdcMock));
        ERC20Mock usdtMock = new ERC20Mock();
        console.log("USDT deployed! %s", address(usdtMock));
        ERC20Mock wethMock = new ERC20Mock();
        console.log("WETH deployed! %s", address(wethMock));
        ERC20Mock maticMock = new ERC20Mock();
        console.log("MATIC deployed! %s", address(maticMock));
        vm.stopBroadcast();
        console.log("Mocks deployed!");

        localNetworkConfig = NetworkConfig({
            entryPoint: address(entryPoint),
            usdc: address(usdcMock),
            usdt: address(usdtMock),
            weth: address(wethMock),
            matic: address(maticMock),
            account: ANVIL_DEFAULT_ACCOUNT
        });
        return localNetworkConfig;
    }
}
