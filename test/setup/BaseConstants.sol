// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BaseConstants
 * @notice Library containing constant addresses and configuration values for tokens, price feeds,
 * Uniswap and other essential contracts used in tests.
 * @dev All addresses are for testing purposes and may vary depending on the network.
 */
library BaseConstants {
    struct Config {
        /// @notice USDC token address (6 decimals)
        address USDC;
        /// @notice USDT token address (18 decimals)
        address USDT;
        /// @notice WETH token address (18 decimals)
        address WETH;
        /// @notice USDC/USD price feed (returns 8 decimals)
        address USDC_USD_FEED;
        /// @notice USDT/USD price feed (returns 8 decimals)
        address USDT_USD_FEED;
        /// @notice WETH/USD price feed (returns 8 decimals)
        address WETH_USD_FEED;
        /// @notice EntryPoint contract address for account abstraction tests.
        address ENTRY_POINT;
        /// @notice Uniswap V3 Router address.
        address UNISWAP_ROUTER;
        /// @notice Uniswap V3 Factory address.
        address UNISWAP_FACTORY;
        /// @notice Uniswap V3 Position Manager address.
        address POSITION_MANAGER;
        /// @notice Initial liquidity used in tests.
        uint256 INITIAL_LIQUIDITY;
        /// @notice Fee tier for the Uniswap pool (0.3%).
        uint24 POOL_FEE;
    }

    function getConfig(uint256 chainId) internal pure returns (Config memory) {
        if (chainId == 421614) {
            // Arbitrum Sepolia
            return Config({
                USDC: 0x8431eBc62F7B08af1bBf80eE7c85364ffc24ae24, // Manteca USDC
                USDT: 0xe6B817E31421929403040c3e42A6a5C5D2958b4A,
                WETH: 0xE9C723D01393a437bac13CE8f925A5bc8E1c335c,
                USDC_USD_FEED: 0x0153002d20B96532C639313c2d54c3dA09109309,
                USDT_USD_FEED: 0x80EDee6f667eCc9f63a0a6f55578F870651f06A4,
                WETH_USD_FEED: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165,
                ENTRY_POINT: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                UNISWAP_ROUTER: 0x101F443B4d1b059569D643917553c771E1b9663E,
                UNISWAP_FACTORY: 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e,
                POSITION_MANAGER: 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65,
                INITIAL_LIQUIDITY: 1_000_000e6,
                POOL_FEE: 3000
            });
        } else if (chainId == 534351) {
            // Arbitrum Sepolia (ejemplo)
            return Config({
                USDC: 0x7878290DB8C4f02bd06E0E249617871c19508bE6,
                USDT: 0x776133ea03666b73a8e3FC23f39f90e66360716E,
                WETH: 0xd5654b986d5aDba8662c06e847E32579078561dC,
                USDC_USD_FEED: 0xFadA8b0737D4A3AE7118918B7E69E689034c0127,
                USDT_USD_FEED: 0xb84a700192A78103B2dA2530D99718A2a954cE86,
                WETH_USD_FEED: 0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41,
                ENTRY_POINT: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                UNISWAP_ROUTER: 0x17AFD0263D6909Ba1F9a8EAC697f76532365Fb95,
                UNISWAP_FACTORY: 0x0287f57A1a17a725428689dfD9E65ECA01d82510,
                POSITION_MANAGER: 0xA9c7C2BCEd22D1d47111610Af21a53B6D1e69eeD,
                INITIAL_LIQUIDITY: 1_000_000e6,
                POOL_FEE: 3000
            });
        } else {
            revert("BaseConstants: unknown chainId");
        }
    }
}
