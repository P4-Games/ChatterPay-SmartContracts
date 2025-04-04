// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ChatterPay} from "../src/ChatterPay.sol";

/// @title ChatterPay Deployment Script
/// @notice Script to deploy the ChatterPay contract
/// @dev Uses Foundry's Script contract for deployment functionality
contract DeployChatterPay is Script {
    /// @notice Deploys the ChatterPay contract
    /// @dev Broadcasts the deployment transaction and logs the deployed address
    function run() external {
        vm.startBroadcast();

        ChatterPay chatterPay = new ChatterPay();

        console.log("ChatterPay implementation deployed to:", address(chatterPay));

        vm.stopBroadcast();
    }
}
