// DeployChatterPayVault.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ChatterPayVault} from "../src/ChatterPayVault.sol";

/**
 * @title Deploy ChatterPay Vault Script
 * @notice This script deploys the ChatterPayVault contract
 * @dev Uses Foundry's Script contract for deployment
 */
contract DeployChatterPayVault is Script {
    /**
     * @notice Deploys a new instance of the ChatterPayVault contract
     * @dev Broadcasts the deployment transaction and logs the deployed address
     */
    function run() external {
        vm.startBroadcast();

        ChatterPayVault chatterPayVault = new ChatterPayVault();

        console.log("Vault deployed to:", address(chatterPayVault));

        vm.stopBroadcast();
    }
}