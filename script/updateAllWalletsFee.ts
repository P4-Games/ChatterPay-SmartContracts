import { ethers, Contract, Wallet } from "ethers";
import "dotenv/config";
import * as cliProgress from "cli-progress";

const chatterPayAbi = [
    {
        "inputs": [
            {
                "internalType": "uint256",
                "name": "_newFeeInCents",
                "type": "uint256"
            }
        ],
        "name": "updateFee",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
];

const factoryAbi = [
    {
        "inputs": [],
        "name": "getProxies",
        "outputs": [
            {
                "internalType": "address[]",
                "name": "",
                "type": "address[]"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    }
];

// --- Configuration from .env ---
const { RPC_URL, BACKEND_PK, DEPLOYED_FACTORY } = process.env;

if (!RPC_URL || !BACKEND_PK || !DEPLOYED_FACTORY) {
    throw new Error("Please ensure RPC_URL, BACKEND_PK, and DEPLOYED_FACTORY are set in your .env file");
}

const provider = new ethers.JsonRpcProvider(RPC_URL);
const adminWallet: Wallet = new ethers.Wallet(BACKEND_PK, provider);

// --- USER-DEFINED CONFIGURATION ---
const NEW_FEE_IN_CENTS: number = 8;
const GAS_LIMIT_PER_TX: number = 150000;
const BATCH_SIZE: number = 10; // Number of transactions to send in parallel

/**
 * Formats seconds into a MM:SS string for the ETA display.
 * @param totalSeconds - The total seconds to format.
 * @returns A formatted string e.g., "02:35".
 */
function formatEta(totalSeconds: number): string {
    if (isNaN(totalSeconds) || totalSeconds < 0) {
        return "00:00";
    }
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = Math.floor(totalSeconds % 60);
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

/**
 * Fetches all wallet addresses from the ChatterPay Wallet Factory.
 * @param factoryContract - The factory contract instance.
 * @returns A promise that resolves to an array of wallet addresses.
 */
async function getAllWallets(factoryContract: Contract): Promise<string[]> {
    console.log("Fetching wallet list from factory...");
    try {
        const walletAddresses: string[] = await factoryContract.getProxies.staticCall();
        console.log(`Found ${walletAddresses.length} wallets.`);
        return walletAddresses;
    } catch (error) {
        console.error("Error fetching proxies from factory:", error);
        throw error;
    }
}

/**
 * Updates the fee for a single ChatterPay wallet.
 * @param walletAddress - The address of the wallet to update.
 * @param signer - The admin wallet to sign the transaction.
 * @param nonce - The nonce to use for the transaction.
 * @returns A promise that resolves to true for success and false for failure.
 */
async function updateWalletFee(walletAddress: string, signer: Wallet, nonce: number): Promise<boolean> {
    try {
        const walletContract = new Contract(walletAddress, chatterPayAbi, signer);
        const tx = await walletContract.updateFee(NEW_FEE_IN_CENTS, {
            gasLimit: GAS_LIMIT_PER_TX,
            nonce: nonce,
        });
        await tx.wait();
        return true;
    } catch (error: any) {
        return false;
    }
}

/**
 * Main function to execute the script.
 */
async function main(): Promise<void> {
    console.log("Starting wallet fee update process...");
    console.log(`Connecting to RPC: ${RPC_URL}`);
    console.log(`Using admin wallet: ${adminWallet.address}`);
    console.log(`Factory contract at: ${DEPLOYED_FACTORY}`);
    console.log(`New fee to be set: ${NEW_FEE_IN_CENTS} cents`);

    if (!DEPLOYED_FACTORY) {
        throw new Error("DEPLOYED_FACTORY environment variable not set.");
    }

    const factory = new Contract(DEPLOYED_FACTORY, factoryAbi, adminWallet);
    const allWallets = await getAllWallets(factory);

    if (allWallets.length === 0) {
        console.log("No wallets found in the factory. Exiting.");
        return;
    }

    console.log(`\nStarting update for ${allWallets.length} wallets...`);

    const progressBar = new cliProgress.SingleBar({
        format: 'Updating | {bar} | {percentage}% || {value}/{total} Wallets || Success: {success} | Failed: {failed} || ETA: {custom_eta}',
        barCompleteChar: '\u2588',
        barIncompleteChar: '\u2591',
        hideCursor: true
    });

    let successCount = 0;
    let failedCount = 0;

    progressBar.start(allWallets.length, 0, { success: 0, failed: 0, custom_eta: "Calculating..." });

    let currentNonce = await adminWallet.getNonce();

    const startTime = Date.now();
    const testSuccess = await updateWalletFee(allWallets[0], adminWallet, currentNonce);
    const timePerTx = (Date.now() - startTime) / 1000; // time in seconds

    if (testSuccess) successCount++; else failedCount++;

    const remainingWallets = allWallets.slice(1);
    const timePerBatchWithMargin = timePerTx * 1.20;
    let etaSeconds = Math.ceil(remainingWallets.length / BATCH_SIZE) * timePerBatchWithMargin;

    progressBar.update(1, { success: successCount, failed: failedCount, custom_eta: formatEta(etaSeconds) });

    if (!testSuccess) {
        progressBar.stop();
        console.error("\nTest transaction failed. Aborting.");
        return;
    }

    currentNonce++;

    if (remainingWallets.length > 0) {
        for (let i = 0; i < remainingWallets.length; i += BATCH_SIZE) {
            const batch = remainingWallets.slice(i, i + BATCH_SIZE);

            const promises = batch.map(async (address, index) => {
                const success = await updateWalletFee(address, adminWallet, currentNonce + index);
                if (success) successCount++; else failedCount++;
            });
            await Promise.all(promises);

            etaSeconds -= timePerBatchWithMargin;
            progressBar.update(successCount + failedCount, { success: successCount, failed: failedCount, custom_eta: formatEta(etaSeconds) });

            currentNonce += batch.length;
        }
    }

    progressBar.stop();
    console.log("\nAll wallet updates processed.");
}

main().catch((error) => {
    console.error("\nAn unrecoverable error occurred:", error);
    process.exit(1);
}); 