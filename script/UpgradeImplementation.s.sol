// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./utils/HelperConfig.s.sol";
import {ChatterPay} from "../src/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/ChatterPayWalletFactory.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import "forge-std/console2.sol";

/**
 * @title Upgrade Chatterpay Implementation and Factory
 * @notice This script deploys the ChatterPay implementation contract, initializes it
 *         with configuration parameters, and updates the factory with the new implementation address.
 *         It also prints the deployed address, factory used, and total gas consumed.
 *
 * Steps performed:
 * 1. Deploy ChatterPay implementation.
 * 2. Call initialize() with proper parameters (entryPoint, backendSigner, paymaster, router, etc).
 * 3. Set the deployed address on ChatterPayWalletFactory.
 * 4. Log relevant addresses and gas usage.
 *
 * 🔧 Configuration:
 * Requires the following environment variables to be set **before execution**:
 *  - `DEPLOYED_FACTORY`
 *  - `DEPLOYED_PAYMASTER_ADDRESS`
 *
 * ⚠️ These are **required** to proceed. If any is missing, the script will revert with an error.
 * These values will be used instead of deploying new instances.
 */
contract UpgradeImplementation is Script {
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;

    address[] tokens;
    address[] priceFeeds;
    bool[] tokensStableFlags;

    function run() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getConfig();

        // Validate required environment variables
        address maybeFactory = vm.envOr("DEPLOYED_FACTORY", address(0));
        address maybePaymaster = vm.envOr("DEPLOYED_PAYMASTER_ADDRESS", address(0));

        if (maybeFactory == address(0)) {
            revert("DEPLOYED_FACTORY env var is required but not set.");
        }
        if (maybePaymaster == address(0)) {
            revert("DEPLOYED_PAYMASTER_ADDRESS env var is required but not set.");
        }

        address factoryAddress = maybeFactory;
        address paymaster = maybePaymaster;

        console2.log("Using existing factory: %s", factoryAddress);
        console2.log("Using existing paymaster: %s", paymaster);

        // Setup tokens
        uint256 numTokens = config.tokensConfig.length;
        tokens = new address[](numTokens);
        priceFeeds = new address[](numTokens);
        tokensStableFlags = new bool[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            tokens[i] = config.tokensConfig[i].token;
            priceFeeds[i] = config.tokensConfig[i].priceFeed;
            tokensStableFlags[i] = config.tokensConfig[i].isStable;
        }

        vm.startBroadcast(config.backendSigner);
        uint256 gasStart = gasleft();

        // Deploy the ChatterPay contract using UUPS Proxy via Upgrades library.
        address proxy = Upgrades.deployUUPSProxy(
            "ChatterPay.sol:ChatterPay", // Contract name as string.
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address[],address[],bool[])",
                config.entryPoint,
                config.backendSigner,
                paymaster,
                config.uniswapConfig.router,
                factoryAddress,
                tokens,
                priceFeeds,
                tokensStableFlags
            )
        );

        // Retrieve and log the implementation address.
        address implementation = Upgrades.getImplementationAddress(proxy);
        console2.log("ChatterPay Implementation deployed at %s", implementation);

        // Call setImplementationAddress
        ChatterPayWalletFactory factory = ChatterPayWalletFactory(factoryAddress);
        factory.setImplementationAddress(address(implementation));
        console2.log("Factory implementation address uprade to %s", address(implementation));

        // Set chatterPay to the proxy address.
        ChatterPay chatterPay = ChatterPay(payable(proxy));
        console2.log("ChatterPay Proxy deployed at %s", address(chatterPay));

        uint256 gasUsed = gasStart - gasleft();
        console2.log("Total gas used:", gasUsed);

        vm.stopBroadcast();
    }
}
