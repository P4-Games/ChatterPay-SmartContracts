// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Mock
 * @dev A mock ERC20 token contract for testing purposes that extends OpenZeppelin's ERC20 implementation
 */
contract ERC20Mock is ERC20 {
    /**
     * @dev Constructor that sets the name and symbol of the token
     * @param name The name of the token
     * @param symbol The symbol of the token
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /**
     * @dev Mints new tokens to a specified account
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /**
     * @dev Burns tokens from a specified account
     * @param account The address from which tokens will be burned
     * @param amount The amount of tokens to burn
     */
    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
