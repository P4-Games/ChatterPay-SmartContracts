// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BaseConstants
 * @notice Library containing constant addresses and configuration values for tokens, price feeds,
 * Uniswap and other essential contracts used in tests.
 * @dev All addresses are for testing purposes and may vary depending on the network.
 */
library BaseConstants {
    // Token addresses
    /// @notice USDC token address (6 decimals)
    address public constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    /// @notice USDT token address (18 decimals)
    address public constant USDT = 0xe6B817E31421929403040c3e42A6a5C5D2958b4A;

    // Price feed addresses (Chainlink)
    /// @notice USDC/USD price feed (returns 8 decimals)
    address public constant USDC_USD_FEED = 0x0153002d20B96532C639313c2d54c3dA09109309;
    /// @notice USDT/USD price feed (returns 8 decimals)
    address public constant USDT_USD_FEED = 0x80EDee6f667eCc9f63a0a6f55578F870651f06A4;

    // Uniswap related addresses
    /// @notice EntryPoint contract address for account abstraction tests.
    address public constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    /// @notice Uniswap V3 Router address.
    address public constant UNISWAP_ROUTER = 0x101F443B4d1b059569D643917553c771E1b9663E;
    /// @notice Uniswap V3 Factory address.
    address public constant UNISWAP_FACTORY = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e;
    /// @notice Uniswap V3 Position Manager address.
    address public constant POSITION_MANAGER = 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65;

    // Test configuration
    /// @notice Initial liquidity used in tests.
    uint256 public constant INITIAL_LIQUIDITY = 1_000_000e6;
    /// @notice Fee tier for the Uniswap pool (0.3%).
    uint24 public constant POOL_FEE = 3000;
}
