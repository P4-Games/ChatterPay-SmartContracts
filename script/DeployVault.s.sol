// DeployChatterPayVault.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ChatterPayVault} from "../src/ChatterPayVault.sol";

contract DeployChatterPayVault is Script {
    function run() external {
        vm.startBroadcast();

        ChatterPayVault chatterPayVault = new ChatterPayVault();

        console.log("Vault deployed to:", address(chatterPayVault));

        vm.stopBroadcast();
    }
}