// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ChatterPayWalletFactory} from "../src/L2/ChatterPayWalletFactory.sol";

// address _walletImplementation,
//         address _entryPoint,
//         address _owner,
//         address _paymaster
contract DeployChatterPayWalletFactory is Script {
    HelperConfig helperConfig;

    function run() external {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // This will get the address of the most recent deployment of the ChatterPay Implementation contract
        // If you want to set the implementation to a different address, you can do so here
        address implementation = DevOpsTools.get_most_recent_deployment(
            "ChatterPay",
            block.chainid
        );

        // This will get the address of the most recent deployment of the ChatterPayPaymaster contract
        // If you want to set the paymaster to a different address, you can do so here
        address paymaster = DevOpsTools.get_most_recent_deployment(
            "ChatterPayPaymaster",
            block.chainid
        );

        vm.startBroadcast();

        ChatterPayWalletFactory chatterPayWalletFactory = new ChatterPayWalletFactory(
                implementation,
                config.entryPoint,
                config.account,
                paymaster
            );

        console.log("Factory deployed to:", address(chatterPayWalletFactory));

        vm.stopBroadcast();
    }
}
