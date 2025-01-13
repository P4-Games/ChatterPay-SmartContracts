// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPay} from "../src/L2/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/L2/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../src/L2/ChatterPayPaymaster.sol";
import {ChatterPayNFT} from "../src/L2/ChatterPayNFT.sol";
import {ChatterPayVault} from "../src/L2/ChatterPayVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAllContracts is Script {
    uint256 ethSepoliaChainId = 11155111;
    uint256 scrollSepoliaChainId = 534351;
    uint256 scrollDevnetChainId = 2227728;
    uint256 arbitrumSepoliaChainId = 421614;

    HelperConfig helperConfig;
    ChatterPay implementation;
    ChatterPay chatterPay;
    ChatterPayWalletFactory factory;
    ChatterPayPaymaster paymaster;
    ChatterPayNFT nftImplementation;
    ChatterPayNFT chatterPayNFT;
    ChatterPayVault vault;
    address entryPoint;
    address backendEOA;
    address router;
    string NFTBaseUri = "https://back.chatterpay.net/nft/metadata/opensea/";

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
        router = vm.envAddress("ROUTER_ADDRESS");

        vm.startBroadcast(config.account);

        console.log(
            "Deploying ChatterPay contracts in chainId %s with account: %s",
            block.chainid,
            config.account
        );

        // 1. Deploy Paymaster first
        paymaster = new ChatterPayPaymaster(entryPoint, backendEOA);
        console.log("Paymaster deployed to address %s", address(paymaster));

        // 2. Deploy ChatterPay implementation
        implementation = new ChatterPay();
        console.log("ChatterPay implementation deployed to address %s", address(implementation));

        // 3. Deploy Factory
        factory = new ChatterPayWalletFactory(
            address(implementation),
            entryPoint,
            backendEOA,
            address(paymaster),
            router
        );
        console.log("Factory deployed to address %s", address(factory));

        // 4. Deploy ChatterPay Proxy and initialize
        bytes memory chatterPayInitData = abi.encodeCall(
            ChatterPay.initialize,
            (
                entryPoint,
                backendEOA,
                address(paymaster),
                router,
                address(factory)
            )
        );
        
        ERC1967Proxy chatterPayProxy = new ERC1967Proxy(
            address(implementation),
            chatterPayInitData
        );
        chatterPay = ChatterPay(payable(address(chatterPayProxy)));
        console.log("ChatterPay proxy deployed to address %s", address(chatterPayProxy));

        // 5. Deploy NFT implementation and proxy
        nftImplementation = new ChatterPayNFT();
        console.log("NFT implementation deployed to address %s", address(nftImplementation));

        bytes memory nftInitData = abi.encodeCall(
            ChatterPayNFT.initialize,
            (backendEOA, NFTBaseUri)
        );

        ERC1967Proxy nftProxy = new ERC1967Proxy(
            address(nftImplementation),
            nftInitData
        );
        chatterPayNFT = ChatterPayNFT(address(nftProxy));
        console.log("NFT proxy deployed to address %s", address(nftProxy));

        // 6. Deploy Vault
        vault = new ChatterPayVault();
        console.log("Vault deployed to address %s", address(vault));

        vm.stopBroadcast();

        return (helperConfig, chatterPay, factory, chatterPayNFT, paymaster);
    }
}