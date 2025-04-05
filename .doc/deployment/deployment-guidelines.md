# Deployment Guidelines

## Contracts Deployment

Find contract deployment addresses by network at these links:

- USDT: [Tethet Contracts Addresses](https://tether.to/es/supported-protocols) 
- USDC (Circle): [Circle Contracts Addresses](https://www.circle.com/blog/usdc-on-arbitrum-now-available)
- WETH:  [Arbitrum Contract Addresses](https://docs.arbitrum.io/build-decentralized-apps/reference/contract-addresses)
- EntryPoint: [eth Infinitism - Account Abstraction](https://github.com/eth-infinitism/account-abstraction/releases/tag/v0.6.0)
- Uniswap: [Uniswap Contract Deployments](https://docs.uniswap.org/contracts/v3/reference/deployments/) 
- Chainlink: [Price FeedsContract Addresses](https://docs.chain.link/data-feeds/price-feeds/addresses)
- Scroll: [Scroll Contract Addresses](https://docs.scroll.io/es/developers/scroll-contracts/)

## Paymaster Deployment

### Post-Deployment

After deploying a new Paymaster contract, you **MUST** perform the staking process to deposit ETH into the StakeManager of the EntryPoint. This step is essential for security purposes and is validated by the bundler to ensure the proper operation of the Paymaster contract. 🛡️

This is a critical step that you **cannot skip** after deployment. Failure to stake the required ETH will result in the bundler failing to validate the contract, and your transactions may not work correctly! 🚨

#### **How to Stake:**

1. **Run the following command to stake ETH in the Paymaster contract:**

```sh
cast send paymaster_contract_address "addStake(uint32)" 100000 --value 100000000000000000 --from backend_signer_wallet_address --rpc-url https://arb-sepolia.g.alchemy.com/v2/API_KEY_ALCHEMY --private-key _backend_signer_wallet_private_key
```

   - `100000` represents the amount of seconds of unstake time.
   - `100000000000000000` equals **0.1 ETH** to be staked.

   **Important Notes:**
   - Make sure you have enough ETH in the backend signer wallet to cover the stake.
   - The staking process is required for security validation and interaction with the EntryPoint.

2. **To check the balance and verify the stake:**

```sh
cast call entrypoint_contract_address "getDepositInfo(address)(uint112,bool,uint112,uint32,uint48)" paymaster_contract_address --rpc-url https://arb-sepolia.g.alchemy.com/v2/API_KEY_ALCHEMY
```

   This will return the deposit information, including the amount of staked ETH and other relevant details.

#### **Why Is This Important?**

- **Security:** The bundler validates this stake to ensure that the Paymaster contract can be used safely and securely within the ecosystem. 🛡️
- **Smooth Operations:** Without this staking, the contract will not pass bundler validation and operations will fail. ⚠️

#### **Additional Notes on StakeManager & Bundler**

The **StakeManager** within the EntryPoint is responsible for managing the ETH deposits that cover gas costs for Paymaster operations. By staking ETH in the StakeManager, you are essentially providing a guarantee that there are sufficient funds to pay for transaction fees. This step is critical for the bundler to validate and process transactions that the Paymaster is handling.

The **bundler** is a service that aggregates multiple transactions and ensures that gas is paid in an efficient manner. Without proper staking, the bundler will not validate the transactions, and the system will fail to function as intended.

Make sure you complete this step right after the Paymaster deployment, as it is a necessary part of the contract initialization. ✅
