// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPayNFT} from "../src/ChatterPayNFT.sol";

/**
 * @title DeployChatterPay
 * @notice A script to upgrade the ChatterPay NFT contract implementation
 * @dev Uses OpenZeppelin's Upgrades library to handle proxy upgrades
 */
contract DeployChatterPay is Script {
    HelperConfig helperConfig;

    /**
     * @notice Main function to execute the NFT contract upgrade
     * @dev Upgrades the proxy to a new implementation while maintaining the same state
     */
    function run() external {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        string memory baseURI = "https://back.chatterpay.net/nft/metadata/opensea/";

        // Set previously deployed NFT proxy contract address
        address proxy = address(0);
        bytes memory data = abi.encodeWithSignature("initialize(address,string)", config.account, baseURI);

        vm.startBroadcast();

        Upgrades.upgradeProxy(proxy, "ChatterPayNFT.v2.sol", data, config.account);

        console.log("NFT updated to:", address(proxy));

        vm.stopBroadcast();
    }
}
