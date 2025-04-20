// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/**
 * @title Uniswap V3 Swap Router Interface
 * @author ChatterPay Team
 * @notice Interface for executing token swaps through Uniswap V3
 * @dev Handles single-hop and multi-hop swaps with exact input amounts
 */
interface ISwapRouter {
    /**
     * @notice Parameters for single-hop exact input swaps
     * @param tokenIn The contract address of the input token
     * @param tokenOut The contract address of the output token
     * @param fee The pool fee tier (in hundredths of a bip)
     * @param recipient The address that will receive the output tokens
     * @param amountIn The exact amount of input tokens to swap
     * @param amountOutMinimum The minimum amount of output tokens that must be received
     * @param sqrtPriceLimitX96 The price limit for the swap specified as a sqrt(price) Q64.96 value
     */
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible
     * @param params The parameters for the swap, specified through ExactInputSingleParams
     * @return amountOut The amount of output tokens received from the swap
     */
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    /**
     * @notice Parameters for multi-hop exact input swaps
     * @param path The encoded path of the swap, containing all tokens and fee tiers
     * @param recipient The address that will receive the output tokens
     * @param deadline The Unix timestamp after which the transaction will revert
     * @param amountIn The exact amount of input tokens to swap
     * @param amountOutMinimum The minimum amount of output tokens that must be received
     */
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible through multiple pools
     * @param params The parameters for the swap, specified through ExactInputParams
     * @return amountOut The amount of output tokens received from the swap
     */
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
