# ChatterPay Contracts Overview

## Summary

These smart contracts collectively create a robust ecosystem for wallet management, token price feeds, and NFT handling. They provide flexibility, upgradeability, and security by implementing key features like account abstraction, secure wallet deployment, NFT minting, and real-time price data management. The system allows for efficient wallet creation, management of user operations, and the minting of original and copy NFTs, all while ensuring that transaction fees and external data feeds are properly handled.

## Contracts List:

1. [**ChatterPay.sol**](../../src/ChatterPay.sol)  
Core wallet contract for ChatterPay, handling user operations, token transfers, and transaction fee management.

# ChatterPay Contracts Overview

## Summary

These smart contracts collectively form a powerful ecosystem for wallet management, token price feeds, NFT handling, and transaction facilitation. They offer flexibility, upgradeability, and security by implementing advanced features like account abstraction, Uniswap V3 integration, secure wallet deployment, NFT minting, password-protected vaults, and real-time price feed management. The system enables efficient wallet creation, user operations management, token swaps, and NFT minting with robust mechanisms to handle fees, slippage, and external data feeds.

## Contracts List:

1. [**ChatterPay.sol**](../../src/ChatterPay.sol)  
   Core wallet contract for ChatterPay, supporting ERC-4337 account abstraction, Uniswap integration, transaction fee management, and token whitelisting.

2. [**ChatterPayNFT.sol**](../../src/ChatterPayNFT.sol)  
   Manages the minting of original NFTs and their limited copies. Includes functionality for copy limits, metadata updates, and ownership management, using an upgradeable proxy structure.

3. [**ChatterPayPaymaster.sol**](../../src/ChatterPayPaymaster.sol)  
   Paymaster contract that validates and manages user operations with signature-based authentication and fee handling, integrated with the EntryPoint contract.

4. [**ChatterPayWalletFactory.sol**](../../src/ChatterPayWalletFactory.sol)  
   Factory contract for deploying and managing ChatterPay wallet proxies. Provides deterministic address computation, proxy tracking, and upgradeability.

5. [**ChatterPayWalletProxy.sol**](../../src/ChatterPayWalletProxy.sol)  
   An upgradeable proxy contract for ChatterPay wallets, leveraging the ERC-1967 Proxy standard to enable wallet upgrades and version control.

6. [**AggregatorV3Interface.sol**](../../src/interfaces/AggregatorV3Interface.sol)  
   Interface for interacting with Chainlink price feed aggregators, providing methods to fetch price data and metadata for token feeds.

7. [**ISwapRouter.sol**](../../src/interfaces/ISwapRouter.sol)  
   Interface for the Uniswap V3 swap router, enabling precise control over token swaps, slippage, and multi-hop routing.

---

Representation of Chatterpay's Smart Contracts Flow:


![ChatterPay Smart Contracts Flow](./images/chatterpay-contracts-flow.png)


[Here](./contracts-details.md) you can see a detailed breakdown of the provided smart contracts used for ChatterPay. 
