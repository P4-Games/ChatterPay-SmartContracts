// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockSwapRouter {
    function exactInputSingle(
        ISwapRouter.ExactInputSingleParams calldata params
    ) external returns (uint256 amountOut) {
        // Transfer tokenIn from msg.sender to this contract
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        
        // Transfer tokenOut to recipient
        // For testing, we'll use the amountOutMinimum as the actual amount out
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOutMinimum);
        
        return params.amountOutMinimum;
    }

    function exactInput(
        ISwapRouter.ExactInputParams calldata /* params */
    ) external pure returns (uint256 /* amountOut */) {
        return 0;
    }
}