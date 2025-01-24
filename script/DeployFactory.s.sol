// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPayWalletFactory} from "../src/ChatterPayWalletFactory.sol";
import {ChatterPay} from "../src/ChatterPay.sol";

/**
 * @title DeployFactory
 * @notice Deployment script for ChatterPayWalletFactory and its dependencies
 * @dev Uses Foundry's Script contract for deployments
 */
contract DeployFactory is Script {
    ChatterPayWalletFactory public factory;
    HelperConfig helperConfig;
    ChatterPay implementation;
    address entryPoint;
    address backendEOA;
    address paymaster;
    address router;

    /**
     * @notice Main deployment function
     * @dev Deploys ChatterPay implementation first, then the factory contract
     * @return ChatterPayWalletFactory The deployed factory contract
     */
    function run() public returns (ChatterPayWalletFactory) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entryPoint = config.entryPoint;
        backendEOA = config.account;
        paymaster = vm.envAddress("PAYMASTER_ADDRESS");
        router = vm.envAddress("ROUTER_ADDRESS");

        vm.startBroadcast(config.account);

        implementation = new ChatterPay();
        console.log("ChatterPay implementation deployed at:", address(implementation));

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