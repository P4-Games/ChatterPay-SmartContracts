// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPayPaymaster} from "../src/L2/ChatterPayPaymaster.sol";

contract DeployChatterPayPaymaster is Script {
    HelperConfig helperConfig;

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
