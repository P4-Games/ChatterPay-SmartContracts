// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {MockERC20} from "./MockERC20.sol";
import {console2} from "forge-std/console2.sol";

contract MockSwapRouter {
    function exactInputSingle(
        ISwapRouter.ExactInputSingleParams calldata params
    ) external returns (uint256 amountOut) {
        // Transfer input tokens from sender
        MockERC20(params.tokenIn).transferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        // Calculate output amount (use 1:0.5 rate)
        amountOut = params.amountIn / 2;
        require(amountOut >= params.amountOutMinimum, "Too little received");

        // Mint output tokens to recipient
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);

        return amountOut;
    }

    function exactInput(
        ISwapRouter.ExactInputParams calldata params
    ) external returns (uint256 amountOut) {
        revert("Not implemented");
    }
}