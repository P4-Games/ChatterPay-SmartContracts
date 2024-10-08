// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";
import {ChatterPayBeacon} from "../src/L2/ChatterPayBeacon.sol";
import {ChatterPayWalletFactory} from "../src/L2/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../src/L2/ChatterPayPaymaster.sol";
import {TokensPriceFeeds} from "../src/Ethereum/TokensPriceFeeds.sol";
import {ChatterPayNFT} from "../src/L2/ChatterPayNFT.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract DeployChatterPay is Script {
    
    uint256 ethSepoliaChainId = 11155111;
    uint256 scrollSepoliaChainId = 534351;
    uint256 scrollDevnetChainId = 2227728;
    uint256 arbitrumSepoliaChainId = 421614;

    HelperConfig helperConfig;
    ChatterPay chatterPay;
    ChatterPayBeacon beacon;
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
            ChatterPayBeacon,
            ChatterPayWalletFactory,
            TokensPriceFeeds,
            ChatterPayNFT
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

        // Deploy Beacon (with Logic address as parameter)
        // CREATE2 for production
        // beacon = new ChatterPayBeacon{
        //     salt: keccak256(abi.encodePacked(config.account))
        // }(address(chatterPay), config.account);
        beacon = new ChatterPayBeacon(address(chatterPay), config.account);
        console.log("Beacon deployed to address %s", address(beacon));

        // Deploy Paymaster
        // CREATE2 for production
        // paymaster = new ChatterPayPaymaster{
        //     salt: keccak256(abi.encodePacked(config.account))
        // }(config.account);
        paymaster = new ChatterPayPaymaster();
        console.log("Paymaster deployed to address %s", address(paymaster));

        // Deploy Factory (with Beacon, EntryPoint, Account & Paymaster addresses as parameters)
        // CREATE2 for production
        // factory = new ChatterPayWalletFactory{
        //     salt: keccak256(abi.encodePacked(config.account))
        // }(address(beacon), config.entryPoint, config.account, paymaster);
        factory = new ChatterPayWalletFactory(address(beacon), config.entryPoint, config.account, address(paymaster));
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
        string memory baseURI = "";
        chatterPayNFT = new ChatterPayNFT(config.account, baseURI);
        console.log(
            "ChatterPayNFT deployed to address %s",
            address(chatterPayNFT)
        );
        chatterPayNFT.setAuthorized(backendEOA, true);
        console.log("ChatterPayNFT: backend EOA authorized");

        vm.stopBroadcast();

        return (
            helperConfig,
            chatterPay,
            beacon,
            factory,
            tokensPriceFeeds,
            chatterPayNFT
        );
    }
}
