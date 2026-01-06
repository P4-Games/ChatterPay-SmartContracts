// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ChatterPay} from "../src/ChatterPay.sol";
import {
    ChatterPayWalletFactory,
    IChatterPayWalletFactory
} from "../src/ChatterPayWalletFactory.sol";
import {ChatterPayManageable} from "../src/ChatterPayManageable.sol";

/**
 * @title UpdateExistingWallets
 * @notice Script to update token whitelists on all existing ChatterPay wallets
 * @dev This script:
 *  - Iterates through all wallets from specified factory addresses
 *  - Adds new tokens (wstETH, USX, StakedUSX, USDQ) to each wallet
 *  - Updates price feeds for each token
 *  - Marks stable tokens appropriately
 *
 * Requirements:
 *  - Must be run by the owner of each wallet (or use ChatterPay admin execute function)
 *  - Requires BACKEND_EOA to be the admin/owner
 */
contract UpdateExistingWallets is Script {
    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    // Old factory addresses to get existing wallets from
    address[] public oldFactories;

    // Mainnet defaults
    address[] public mainnetFactories = [
        0xE17Ca047427557C3bdeD9d151a823D8e2B514e74,
        0x18F1978f64cbE69DF8B46934DD2f4Abb30268fD1,
        0xf3C022440b32e594F846f0E365Ef18Dc0059F5Af
    ];
    /* address[] public mainnetFactories = [
        0x489aa621F1C441568b82e428Ae9791EbE099E5B7
    ];*/

    // New tokens to add
    struct TokenData {
        address token;
        address priceFeed;
        bool isStable;
        string symbol;
    }

    TokenData[] public newTokens;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public totalWallets;
    uint256 public successfulUpdates;
    uint256 public failedUpdates;
    address public admin;
    address public manageableLogic;

    // Batching configuration
    uint256 public offset;
    uint256 public batchSize;

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTION
    //////////////////////////////////////////////////////////////*/

    function run() external {
        // Initialize new tokens array
        initializeNewTokens();

        // Load config from environment
        admin = vm.envAddress("BACKEND_EOA");

        // Load factories: Default to mainnet if FACTORIES env is not set
        try vm.envString("FACTORIES") returns (string memory fList) {
            oldFactories = parseAddressList(fList);
        } catch {
            oldFactories = mainnetFactories;
        }
        // Batching: Default to 0 and 50 if not specified
        try vm.envUint("OFFSET") returns (uint256 o) {
            offset = o;
        } catch {
            offset = 0;
        }
        try vm.envUint("BATCH_SIZE") returns (uint256 b) {
            batchSize = b;
        } catch {
            batchSize = 50;
        }
        // Detect if bridge logic is already deployed (reuse it for batches)
        try vm.envAddress("BRIDGE_LOGIC") returns (address b) {
            manageableLogic = b;
            console.log("Using existing bridge bridge at: %s", manageableLogic);
        } catch {
            // Deploy the manageable bridge logic
            vm.startBroadcast(admin);
            manageableLogic = address(new ChatterPayManageable());
            vm.stopBroadcast();
            console.log("Deployed NEW bridge logic at: %s", manageableLogic);
            console.log(
                "--> IMPORTANT: Run next batches with BRIDGE_LOGIC=%s to save gas!",
                manageableLogic
            );
        }
        console.log("=========================================");
        console.log("ChatterPay Wallet Token Whitelist Update");
        console.log("=========================================");
        console.log("Admin address: %s", admin);
        console.log("Number of old factories: %d", oldFactories.length);
        console.log("New tokens to add: %d", newTokens.length);
        console.log("Batching: Offset %d, Batch Size %d", offset, batchSize);
        console.log("");

        // Enumerate all wallets from old factories
        address[] memory allWallets = enumerateWallets();
        totalWallets = allWallets.length;
        console.log(
            "Total wallets found across all factories: %d",
            totalWallets
        );

        // Calculate slice
        uint256 end = offset + batchSize;
        if (end > allWallets.length) end = allWallets.length;

        if (offset >= allWallets.length) {
            console.log(
                "Offset %d is beyond total wallets %d. Nothing to do.",
                offset,
                allWallets.length
            );
            return;
        }

        console.log("Processing batch: wallets %d to %d", offset + 1, end);
        console.log("");

        // Start broadcasting transactions
        vm.startBroadcast(admin);

        // Update each wallet in the batch
        for (uint256 i = offset; i < end; i++) {
            updateWallet(allWallets[i], i + 1, allWallets.length);
        }

        vm.stopBroadcast();

        // Print summary
        printSummary();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the array of new tokens to add
     */
    function initializeNewTokens() internal {
        // wstETH
        newTokens.push(
            TokenData({
                token: 0xf610A9dfB7C89644979b4A0f27063E9e7d7Cda32,
                priceFeed: 0x439a2b573C8Ecd215990Fc25b4F547E89CF67b79,
                isStable: false,
                symbol: "wstETH"
            })
        );

        // USX
        newTokens.push(
            TokenData({
                token: 0x3b005fefC63Ca7c8d25eE21FbA3787229ba4CF03,
                priceFeed: 0x43d12Fb3AfCAd5347fA764EeAB105478337b7200,
                isStable: true,
                symbol: "USX"
            })
        );

        // StakedUSX
        newTokens.push(
            TokenData({
                token: 0xcB14BcdF6cD483665D10dfD6f87d908996C7F922,
                priceFeed: 0x43d12Fb3AfCAd5347fA764EeAB105478337b7200,
                isStable: true,
                symbol: "StakedUSX"
            })
        );

        // USDQ
        newTokens.push(
            TokenData({
                token: 0xdb9E8F82D6d45fFf803161F2a5f75543972B229a,
                priceFeed: 0x43d12Fb3AfCAd5347fA764EeAB105478337b7200,
                isStable: true,
                symbol: "USDQ"
            })
        );
    }

    /**
     * @notice Enumerates all wallets from the old factories
     * @return allWallets Array of all wallet addresses
     */
    function enumerateWallets() internal returns (address[] memory) {
        console.log("=== WALLET ENUMERATION (WITH DEDUPLICATION) ===");

        // Use a temporary array to collect all addresses first
        // We'll use a larger size to accommodate potential over-reporting
        address[] memory tempWallets = new address[](5000);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < oldFactories.length; i++) {
            console.log("");
            console.log("Factory %d: %s", i + 1, oldFactories[i]);

            // Get count first
            uint256 reportedCount = 0;
            try
                IChatterPayWalletFactory(oldFactories[i]).getProxiesCount()
            returns (uint256 count) {
                reportedCount = count;
                console.log("  getProxiesCount() returned: %d", count);
            } catch {
                console.log("  ERROR: Failed to call getProxiesCount()");
                continue;
            }
            // Get actual proxies array
            try IChatterPayWalletFactory(oldFactories[i]).getProxies() returns (
                address[] memory proxies
            ) {
                console.log("  getProxies() array length: %d", proxies.length);

                if (reportedCount != proxies.length) {
                    console.log(
                        "  WARNING: Count mismatch! Using array length."
                    );
                }

                // Add each proxy, checking for duplicates
                uint256 addedFromFactory = 0;
                for (uint256 j = 0; j < proxies.length; j++) {
                    address wallet = proxies[j];

                    // Skip zero address
                    if (wallet == address(0)) {
                        continue;
                    }

                    // Check if already exists
                    bool isDuplicate = false;
                    for (uint256 k = 0; k < uniqueCount; k++) {
                        if (tempWallets[k] == wallet) {
                            isDuplicate = true;
                            break;
                        }
                    }

                    if (!isDuplicate) {
                        tempWallets[uniqueCount] = wallet;
                        uniqueCount++;
                        addedFromFactory++;
                    }
                }

                console.log("  Unique wallets added: %d", addedFromFactory);
                if (addedFromFactory != proxies.length) {
                    console.log(
                        "  ** %d duplicates/zeros removed **",
                        proxies.length - addedFromFactory
                    );
                }
            } catch {
                console.log("  ERROR: Failed to call getProxies()");
            }
        }

        // Create final array with exact size
        address[] memory finalWallets = new address[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            finalWallets[i] = tempWallets[i];
        }

        console.log("");
        console.log("=== ENUMERATION COMPLETE ===");
        console.log("Total unique wallets: %d", uniqueCount);

        return finalWallets;
    }

    /**
     * @notice Updates a single wallet with new tokens
     * @param wallet Address of the wallet to update
     * @param index Current wallet index (for logging)
     * @param total Total number of wallets (for logging)
     */
    /**
     * @notice Updates a single wallet using the bridge logic
     * @param wallet Address of the wallet to update
     * @param index Current wallet index
     * @param total Total wallets
     */
    function updateWallet(
        address wallet,
        uint256 index,
        uint256 total
    ) internal {
        console.log("---");
        console.log("[%d/%d] Updating wallet: %s", index, total, wallet);

        ChatterPay chatterPayWallet = ChatterPay(payable(wallet));

        // 1. Detect existing logic to restore it later
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address auditedImpl = address(
            uint160(uint256(vm.load(wallet, implSlot)))
        );

        // 2. Prepare migration data
        address[] memory tokens = new address[](newTokens.length);
        address[] memory feeds = new address[](newTokens.length);
        bool[] memory stables = new bool[](newTokens.length);

        for (uint256 i = 0; i < newTokens.length; i++) {
            tokens[i] = newTokens[i].token;
            feeds[i] = newTokens[i].priceFeed;
            stables[i] = newTokens[i].isStable;
        }

        // 3. The "Flash Migration"
        // We upgrade to the manageable logic, run the migration, and stay there.
        // Then we immediately upgrade back to the audited logic.
        try
            chatterPayWallet.upgradeToAndCall(
                manageableLogic,
                abi.encodeWithSignature(
                    "migrateTokens(address[],address[],bool[])",
                    tokens,
                    feeds,
                    stables
                )
            )
        {
            console.log("  [OK] Tokens migrated via bridge");

            // 4. Restore audited logic
            // Using upgradeToAndCall with empty bytes since upgradeTo is deprecated in OZ 5.x
            try chatterPayWallet.upgradeToAndCall(auditedImpl, "") {
                console.log(
                    "  [OK] Restored to audited logic: %s",
                    auditedImpl
                );
                successfulUpdates++;
            } catch {
                console.log(
                    "  [ERROR] Failed to restore audited logic! Wallet is stuck on manageable version."
                );
                failedUpdates++;
            }
        } catch Error(string memory reason) {
            console.log("  [ERROR] Migration failed: %s", reason);
            failedUpdates++;
        } catch {
            console.log("  [ERROR] Migration failed with unknown error");
            failedUpdates++;
        }
    }

    /**
     * @notice Parses a comma-separated string of addresses
     */
    function parseAddressList(
        string memory fList
    ) internal pure returns (address[] memory) {
        // Simple manual split (Foundry doesn't have split())
        bytes memory b = bytes(fList);
        uint256 count = 1;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == ",") count++;
        }

        address[] memory result = new address[](count);
        uint256 current = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= b.length; i++) {
            if (i == b.length || b[i] == ",") {
                bytes memory part = new bytes(i - start);
                for (uint256 j = 0; j < (i - start); j++) {
                    part[j] = b[start + j];
                }
                result[current] = parseAddress(string(part));
                current++;
                start = i + 1;
            }
        }
        return result;
    }

    function parseAddress(string memory s) internal pure returns (address) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 2; i < b.length; i++) {
            uint256 val = uint256(uint8(b[i]));
            if (val >= 48 && val <= 57)
                val -= 48; // 0-9
            else if (val >= 65 && val <= 70)
                val -= 55; // A-F
            else if (val >= 97 && val <= 102)
                val -= 87; // a-f
            else continue;
            result = result * 16 + val;
        }
        return address(uint160(result));
    }

    /**
     * @notice Prints the final summary
     */
    function printSummary() internal view {
        console.log("");
        console.log("=========================================");
        console.log("Update Summary");
        console.log("=========================================");
        console.log("Total wallets processed: %d", totalWallets);
        console.log("Successful updates: %d", successfulUpdates);
        console.log("Failed updates: %d", failedUpdates);
        console.log("=========================================");
    }
}
