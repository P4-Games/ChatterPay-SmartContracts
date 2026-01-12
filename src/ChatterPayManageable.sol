// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ChatterPay} from "./ChatterPay.sol";

/**
 * @title ChatterPayManageable
 * @notice A temporary version of ChatterPay that allows the Admin to update tokens.
 * @dev This is used ONLY during migration to add tokens to existing wallets.
 */
contract ChatterPayManageable is ChatterPay {
    /**
     * @notice Temporary migration function to add the new tokens.
     * @dev Only callable by the ChatterPay Admin (Factory Owner).
     */
    function migrateTokens(
        address[] calldata tokens,
        address[] calldata feeds,
        bool[] calldata stables
    ) external onlyChatterPayAdmin {
        ChatterPayState storage state = _getChatterPayState();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            address feed = feeds[i];
            
            // Set whitelist and price feed directly in storage
            state.whitelistedTokens[token] = true;
            state.priceFeeds[token] = feed;
            
            if (stables[i]) {
                state.stableTokens[token] = true;
            }
        }
    }
}
