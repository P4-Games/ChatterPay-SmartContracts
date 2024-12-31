// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";

contract DeployChatterPay is Script {

    HelperConfig helperConfig;
    function run() external {

        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // This will get the address of the most recent deployment of the ChatterPayPaymaster contract
        // If you want to set the paymaster to a different address, you can do so here
        address paymaster = DevOpsTools.get_most_recent_deployment(
            "ChatterPayPaymaster",
            block.chainid
        );

        vm.startBroadcast();

        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPay.sol",
            abi.encodeCall(ChatterPay.initialize, (config.entryPoint, config.account, paymaster))
        );

        console.log("ChatterPay Proxy deployed to:", address(proxy));

        vm.stopBroadcast();
    }
}
