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

        ChatterPayPaymaster chatterPayPaymaster = new ChatterPayPaymaster(
            config.entryPoint,
            config.account
        );

        console.log(
            "Paymaster deployed to:",
            address(chatterPayPaymaster)
        );

        vm.stopBroadcast();
    }
}
