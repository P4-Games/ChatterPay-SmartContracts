// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPayPaymaster} from "../src/ChatterPayPaymaster.sol";

/**
 * @title DeployChatterPayPaymaster
 * @notice A deployment script for the ChatterPayPaymaster contract
 * @dev Uses Foundry's Script contract for deployment functionality
 */
contract DeployChatterPayPaymaster is Script {
    HelperConfig helperConfig;

    /**
     * @notice Deploys the ChatterPayPaymaster contract
     * @dev Gets network configuration from HelperConfig and deploys the paymaster with appropriate parameters
     */
    function run() external {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast();

        console.log("Deploying ChatterPayPaymaster...");
        console.log("EntryPoint:", config.entryPoint);
        console.log("Backend Signer:", config.account);
        
        ChatterPayPaymaster chatterPayPaymaster = new ChatterPayPaymaster(
            config.entryPoint,
            config.account
        );

        console.log(
            "Paymaster deployed to:",
            address(chatterPayPaymaster)
        );

        console.log("------------------------------------------------------------------------------");
        console.log("------------------------------ IMPORTANT! ------------------------------------");
        console.log("------------------------------------------------------------------------------");
        console.log("Stake ETH in EntryPoint for Paymaster to function properly!");
        console.log("See .doc/deployment/deployment-guidelines.md for details.");
        console.log("------------------------------------------------------------------------------");

        vm.stopBroadcast();
    }
}
