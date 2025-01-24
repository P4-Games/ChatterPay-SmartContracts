// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPay} from "../src/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/ChatterPayWalletFactory.sol";
import {ChatterPayPaymaster} from "../src/ChatterPayPaymaster.sol";
import {ChatterPayNFT} from "../src/ChatterPayNFT.sol";
import {ChatterPayVault} from "../src/ChatterPayVault.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

/**
 * @title DeployAllContracts
 * @notice A deployment script for all ChatterPay contracts
 * @dev Uses Foundry's Script contract for deployments and OpenZeppelin's Upgrades library for proxy deployments
 */
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
    string NFTBaseUri = vm.envString("NFT_BASE_URI");

    /**
     * @notice Main deployment function that deploys all contracts
     * @dev Deploys contracts in order: Paymaster, ChatterPay, Factory, NFT, and Vault
     * @return HelperConfig The configuration helper contract
     * @return ChatterPay The main ChatterPay contract
     * @return ChatterPayWalletFactory The wallet factory contract
     * @return ChatterPayNFT The NFT contract
     * @return ChatterPayPaymaster The paymaster contract
     */
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

    /**
     * @notice Deploys the ChatterPayPaymaster contract
     * @dev Sets up paymaster with EntryPoint and backend signer
     */
    function deployPaymaster() internal {
        paymaster = new ChatterPayPaymaster(entryPoint, backendEOA);
        console.log("Paymaster deployed to address %s", address(paymaster));
        console.log("Entrypint used address %s", address(entryPoint));
    }

    /**
     * @notice Deploys the ChatterPay implementation contract
     * @dev Casts the contract to payable after deployment
     */
    function deployChatterPay() internal {
        chatterPay = new ChatterPay();
        console.log("ChatterPay deployed to address %s:", address(chatterPay));
        chatterPay = ChatterPay(payable(chatterPay));
    }

    /**
     * @notice Deploys the ChatterPayWalletFactory contract
     * @dev Sets up factory with ChatterPay implementation, EntryPoint, backend signer, paymaster and Uniswap router
     */
    function deployFactory() internal {
        address router = vm.envAddress("UNISWAP_ROUTER");
        
        factory = new ChatterPayWalletFactory(
            address(chatterPay),
            entryPoint,
            backendEOA,
            address(paymaster),
            router
        );

        console.log("Wallet Factory deployed to address %s:", address(factory));
    }

    /**
     * @notice Deploys the ChatterPayNFT contract with proxy
     * @dev Uses OpenZeppelin's UnsafeUpgrades to deploy a transparent proxy pattern
     */
    function deployNFT() internal {
        // Deploy implementation contract first
        nftImplementation = new ChatterPayNFT();
        
        // Deploy proxy with initialize call
        bytes memory initData = abi.encodeCall(ChatterPayNFT.initialize, (backendEOA, NFTBaseUri));
        address proxy = UnsafeUpgrades.deployTransparentProxy(
            address(nftImplementation),
            backendEOA,
            initData
        );
        
        console.log("NFT implementation deployed to address %s:", address(nftImplementation));
        console.log("NFT proxy deployed to address %s:", proxy);
        chatterPayNFT = ChatterPayNFT(proxy);
    }

    /**
     * @notice Deploys the ChatterPayVault contract
     * @dev Simple deployment with no initialization needed
     */
    function deployVault() internal {
        vault = new ChatterPayVault();
        console.log("Vault deployed to address %s:", address(vault));
    }
}
