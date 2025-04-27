// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPayNFT} from "../src/ChatterPayNFT.sol";

/**
 * @title DeployChatterPay
 * @notice A deployment script for the ChatterPay NFT contract
 * @dev Uses OpenZeppelin UUPS proxy pattern for upgradeability
 */
contract DeployChatterPay is Script {
    /**
     * @dev Helper contract for network-specific configurations
     */
    HelperConfig helperConfig;

    /**
     * @dev Base URI for NFT metadata
     */
    string baseURI = "https://back.chatterpay.net/nft/metadata/opensea/";

    /**
     * @notice Deploys the ChatterPay NFT contract
     * @dev Deploys a UUPS proxy with the ChatterPayNFT implementation
     * The proxy is initialized with an admin account and base URI from config
     */
    function run() external {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast();

        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPayNFT.sol", abi.encodeCall(ChatterPayNFT.initialize, (config.backendSigner, baseURI))
        );

        console.log("NFT deployed to:", address(proxy));

        vm.stopBroadcast();
    }
}
