// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
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
    address[] public tokens;
    address[] public priceFeeds;
    bool[] public tokensStableFlags;

    /**
     * @notice Main deployment function
     * @dev Deploys ChatterPay implementation first, then the factory contract
     * @return ChatterPayWalletFactory The deployed factory contract
     */
    function run() public returns (ChatterPayWalletFactory) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.backendSigner);

        implementation = new ChatterPay();
        console2.log("ChatterPay implementation deployed at:", address(implementation));

        factory = new ChatterPayWalletFactory(
            config.backendSigner, // _walletImplementation (temporary, will be updated later)
            config.entryPoint, // _entryPoint
            config.backendSigner, // _owner
            vm.envAddress("PAYMASTER_ADDRESS"), // _paymaster
            config.uniswapConfig.router, // _router
            config.backendSigner, // _feeAdmin (using account as fee admin)
            tokens, // _whitelistedTokens
            priceFeeds, // _priceFeeds
            tokensStableFlags
        );

        console2.log("Wallet Factory deployed at address %s", address(factory));

        // Validate deployment
        require(factory.owner() == config.backendSigner, "Factory owner not set correctly");
        require(factory.paymaster() == vm.envAddress("PAYMASTER_ADDRESS"), "Paymaster not set correctly");

        vm.stopBroadcast();
        return factory;
    }
}
