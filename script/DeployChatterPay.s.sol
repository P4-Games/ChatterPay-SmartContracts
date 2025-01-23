// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ChatterPay} from "../src/ChatterPay.sol";

contract DeployChatterPay is Script {
    function run() external {
        vm.startBroadcast();

        ChatterPay chatterPay = new ChatterPay();

        console.log("ChatterPay implementation deployed to:", address(chatterPay));

        vm.stopBroadcast();
    }
}
