// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/L2/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../src/L2/ChatterPayPaymaster.sol";
import {TokensPriceFeeds} from "../src/Ethereum/TokensPriceFeeds.sol";
import {ChatterPayNFT} from "../src/L2/ChatterPayNFT.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract DeployChatterPay is Script {
    uint256 ethSepoliaChainId = 11155111;
    uint256 scrollSepoliaChainId = 534351;
    uint256 scrollDevnetChainId = 2227728;
    uint256 arbitrumSepoliaChainId = 421614;

    HelperConfig helperConfig;
    ChatterPay chatterPay;
    ChatterPayWalletFactory factory;
    ChatterPayPaymaster paymaster;
    TokensPriceFeeds tokensPriceFeeds;
    ChatterPayNFT chatterPayNFT;

    address backendEOA = vm.envAddress("BACKEND_EOA");

    function run() public {
        deployChatterPayOnL2();
    }

    function deployChatterPayOnL2()
        public
        returns (
            HelperConfig,
            ChatterPay,
            ChatterPayWalletFactory,
            TokensPriceFeeds,
            ChatterPayNFT,
            ChatterPayPaymaster
        )
    {
        // Deploy HelperConfig
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        console.log(
            "Deploying ChatterPay contracts in chainId %s with account: %s",
            block.chainid,
            config.account
        );

        // Deploy Logic
        // CREATE2 for production
        // chatterPay = new ChatterPay{
        //     salt: keccak256(abi.encodePacked(config.account))
        // }();
        chatterPay = new ChatterPay();
        console.log("ChatterPay deployed to address %s", address(chatterPay));

        // Deploy Paymaster
        // CREATE2 for production
        // paymaster = new ChatterPayPaymaster{
        //     salt: keccak256(abi.encodePacked(config.account))
        // }(config.account);
        address backendSigner = vm.envAddress("BACKEND_EOA");
        paymaster = new ChatterPayPaymaster(config.entryPoint, backendSigner);
        console.log("Paymaster deployed to address %s", address(paymaster));

        // Deploy Factory (with Wallet Implementation, EntryPoint, Account & Paymaster addresses as parameters)
        // CREATE2 for production
        // factory = new ChatterPayWalletFactory{
        //     salt: keccak256(abi.encodePacked(config.account))
        // }(address(chatterPay), config.entryPoint, config.account, paymaster);
        factory = new ChatterPayWalletFactory(address(chatterPay), config.entryPoint, config.account, address(paymaster));
        console.log(
            "WalletFactory deployed to address %s",
            address(factory)
        );

        chatterPay.initialize(
            config.entryPoint,
            config.account,
            address(paymaster)
        );
        console.log("ChatterPay initialized");

        // Deploy ChatterPayNFT
        // main: "https://chatterpay-back-671609149217.us-central1.run.app/"
        // dev: "https://chatterpay-back-staging-671609149217.us-central1.run.app/"
        string
            memory baseURI = "https://chatterpay-back-staging-671609149217.us-central1.run.app/";
        address proxyNFT = Upgrades.deployUUPSProxy(
            "ChatterPayNFT.sol",
            abi.encodeCall(ChatterPayNFT.initialize, (config.account, baseURI))
        );

        console.log("proxyNFT deployed to address %s", address(proxyNFT));
        chatterPayNFT = ChatterPayNFT(proxyNFT);

        vm.stopBroadcast();

        return (
            helperConfig,
            chatterPay,
            factory,
            tokensPriceFeeds,
            chatterPayNFT,
            paymaster
        );
    }
}
