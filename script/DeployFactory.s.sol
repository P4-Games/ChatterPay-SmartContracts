// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPayWalletFactory} from "../src/ChatterPayWalletFactory.sol";
import {ChatterPay} from "../src/ChatterPay.sol";

contract DeployFactory is Script {
    ChatterPayWalletFactory public factory;  // Cambiado el nombre para evitar shadowing
    HelperConfig helperConfig;
    ChatterPay implementation;
    address entryPoint;
    address backendEOA;
    address paymaster;
    address router;

    function run() public returns (ChatterPayWalletFactory) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entryPoint = config.entryPoint;
        backendEOA = config.account;
        paymaster = vm.envAddress("PAYMASTER_ADDRESS");  // Obtener del env en lugar de config
        router = vm.envAddress("ROUTER_ADDRESS");

        vm.startBroadcast(config.account);

        // Deploy implementation first
        implementation = new ChatterPay();
        console.log("ChatterPay implementation deployed at:", address(implementation));

        // Deploy factory with all required parameters
        factory = new ChatterPayWalletFactory(
            address(implementation),
            entryPoint,
            backendEOA,
            paymaster,
            router
        );

        console.log("Factory deployed at:", address(factory));

        vm.stopBroadcast();
        return factory;
    }
}