// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ChatterPayWalletFactory} from "../src/L2/ChatterPayWalletFactory.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";

contract UpdateChatterPay is Script {
    function run() external {
        vm.startBroadcast();

        // Change this contract for the new version ChatterPay implementation contract you want to deploy
        ChatterPay chatterPay = new ChatterPay();

        // This will get the address of the most recent deployment of the ChatterPay Factory contract
        // If you want to set the implementation to a different address, you can replace it here
        address factoryAddress = DevOpsTools.get_most_recent_deployment(
            "ChatterPayWalletFactory",
            block.chainid
        );

        ChatterPayWalletFactory factory = ChatterPayWalletFactory(
            factoryAddress
        );
        
        factory.setImplementationAddress(address(chatterPay));

        console.log(
            "ChatterPay implementation updated to %s and updated in the factory",
            address(chatterPay)
        );

        vm.stopBroadcast();
    }
}
