// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/L2/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../src/L2/ChatterPayPaymaster.sol";
import {ChatterPayNFT} from "../src/L2/ChatterPayNFT.sol";
import {ChatterPayVault} from "../src/L2/ChatterPayVault.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployAllContracts is Script {
    uint256 ethSepoliaChainId = 11155111;
    uint256 scrollSepoliaChainId = 534351;
    uint256 scrollDevnetChainId = 2227728;
    uint256 arbitrumSepoliaChainId = 421614;

    HelperConfig helperConfig;
    ChatterPay chatterPay;
    ChatterPayWalletFactory factory;
    ChatterPayPaymaster paymaster;
    ChatterPayNFT chatterPayNFT;
    ChatterPayVault vault;
    address entryPoint;
    address backendEOA;
    string NFTBaseUri = vm.envString("NFT_BASE_URI");

    function run()
        public
        returns (
            HelperConfig,
            ChatterPay,
            ChatterPayWalletFactory,
            ChatterPayNFT,
            ChatterPayPaymaster
        )
    {

        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entryPoint = config.entryPoint;
        backendEOA = config.account;
        vm.startBroadcast(config.account);

        console.log(
            "Deploying ChatterPay contracts in chainId %s with account: %s",
            block.chainid,
            config.account
        );

        deployPaymaster();
        deployChatterPay();
        deployFactory();
        deployNFT();
        deployVault();

        vm.stopBroadcast();

        return (helperConfig, chatterPay, factory, chatterPayNFT, paymaster);
    }

    function deployPaymaster() internal {
        paymaster = new ChatterPayPaymaster(entryPoint, backendEOA);
        console.log("Paymaster deployed to address %s", address(paymaster));
        console.log("Entrypint used address %s", address(entryPoint));
    }

    function deployChatterPay() internal {
        chatterPay = new ChatterPay();
        console.log("ChatterPay Proxy deployed to address %s:", address(chatterPay));
        chatterPay = ChatterPay(payable(chatterPay));
    }

    function deployFactory() internal {
        factory = new ChatterPayWalletFactory(
            address(chatterPay),
            entryPoint,
            backendEOA,
            address(paymaster)
        );
        console.log("Factory deployed to address %s:", address(factory));
    }

    function deployNFT() internal {
        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPayNFT.sol",
            abi.encodeCall(ChatterPayNFT.initialize, (backendEOA, NFTBaseUri))
        );
        console.log("NFT deployed to address %s:", address(proxy));
        chatterPayNFT = ChatterPayNFT(proxy);
    }

    function deployVault() internal {
        vault = new ChatterPayVault();
        console.log("Vault deployed to address %s:", address(vault));
    }
}
