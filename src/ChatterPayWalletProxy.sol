// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ChatterPayWalletProxy
 * @notice An upgradeable proxy contract using the ERC1967 standard.
 * @dev Delegates calls to an implementation address and supports upgrades.
 */
contract ChatterPayWalletProxy is ERC1967Proxy {
    /**
     * @notice Initializes the proxy with an implementation and initialization data.
     * @dev Calls the ERC1967Proxy constructor with the implementation address and data.
     * @param _logic The address of the implementation contract.
     * @param _data The initialization data to be passed to the implementation.
     */
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {}

    /**
     * @notice Retrieves the address of the current implementation.
     * @return The address of the implementation contract.
     */
    function getImplementation() public view returns (address) {
        return _implementation();
    }

    // Explicit receive function
    receive() external payable {}
}
