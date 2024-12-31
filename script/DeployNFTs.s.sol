// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ChatterPayNFT} from "../src/L2/ChatterPayNFT.sol";

contract DeployChatterPay is Script {
    
    HelperConfig helperConfig;
    string baseURI = "https://back.chatterpay.net/nft/metadata/opensea/";

    function run() external {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast();

        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPayNFT.sol",
            abi.encodeCall(ChatterPayNFT.initialize, (config.account, baseURI))
        );

        console.log("NFT deployed to:", address(proxy));

        vm.stopBroadcast();
    }
}
