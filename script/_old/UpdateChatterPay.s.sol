// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ChatterPayWalletFactory} from "../src/ChatterPayWalletFactory.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {ChatterPay} from "../src/ChatterPay.sol";

/**
 * @title UpdateChatterPay
 * @notice Script to update the ChatterPay implementation contract address in the factory
 * @dev Uses Foundry's Script contract and DevOpsTools for deployment functionality
 */
contract UpdateChatterPay is Script {
    /**
     * @notice Updates the ChatterPay implementation address in the factory
     * @dev Deploys a new ChatterPay implementation and updates the factory to point to it
     * Uses DevOpsTools to find the most recent factory deployment
     */
    function run() external {
        vm.startBroadcast();

        ChatterPay chatterPay = new ChatterPay();

        address factoryAddress = DevOpsTools.get_most_recent_deployment("ChatterPayWalletFactory", block.chainid);
        console.log("Most recent deployment ChatterPay Wallet Factory %s", address(factoryAddress));

        ChatterPayWalletFactory factory = ChatterPayWalletFactory(factoryAddress);

        // factory.setImplementationAddress(address(chatterPay));

        // console.log("ChatterPay implementation updated to %s and updated in the factory", address(chatterPay));

        vm.stopBroadcast();
    }
}
