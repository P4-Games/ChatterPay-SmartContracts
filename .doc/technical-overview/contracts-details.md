# ChatterPay Contracts Details

## 1. [**ChatterPay.sol**](../../src/ChatterPay.sol)

### **High-Level Overview**:
The `ChatterPay` contract serves as the core of the ChatterPay ecosystem, acting as a smart wallet implementation that supports ERC-4337 account abstraction. It facilitates token transfers, fee management, Uniswap-based token swaps, and integration with price oracles for real-time token valuation.

### **Key Features**:
- **ERC-4337 Account Abstraction**: Supports user operations via the EntryPoint contract, enabling decentralized transaction validation.
- **Fee Management**: Implements a fee structure in USD cents, with customizable pool fees and slippage for token swaps.
- **Uniswap V3 Integration**: Executes token swaps with single-hop or multi-hop routes and customizable price tolerances.
- **Token Whitelisting and Price Feeds**: Allows only whitelisted tokens to be used, with price feeds from Chainlink oracles.
- **Batch Transfers**: Supports multiple token transfers in a single transaction.
- **Upgradeable**: Built using `UUPSUpgradeable` for future enhancements.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPayPaymaster**: Works alongside the Paymaster to manage fees and user operations.
- **ChatterPayWalletFactory**: Deployed wallets are created and managed by the factory contract.

### **External Contract Interactions**:
- **Uniswap V3 Router**: Interacts with the swap router for token exchanges.
- **Chainlink Oracles**: Retrieves token prices to calculate fees and ensure transaction accuracy.

---

## 2. [**ChatterPayNFT.sol**](../../src/ChatterPayNFT.sol)

### **High-Level Overview**:
The `ChatterPayNFT` contract enables the minting and management of both original NFTs and their limited copies. It incorporates robust features for URI management, copy limits, and upgradeability.

### **Key Features**:
- **ERC721 NFTs**: Implements the ERC721 standard for unique digital assets.
- **Original and Copy NFTs**: Allows the creation of original NFTs and associated copies with defined limits.
- **Base URI Management**: Supports dynamic updates to the base URI by the contract owner.
- **Upgradeable**: Built using `UUPSUpgradeable` for seamless updates.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPay**: NFTs can be linked to wallet activities for rewards or asset tracking.

### **External Contract Interactions**:
- **ERC721URIStorage**: Provides extended functionality for metadata management.

---

## 3. [**ChatterPayPaymaster.sol**](../../src/ChatterPayPaymaster.sol)

### **High-Level Overview**:
The `ChatterPayPaymaster` contract validates and manages user operations in collaboration with the EntryPoint contract. It uses signature-based authentication to ensure secure and authorized transactions.

### **Key Features**:
- **Paymaster Role**: Acts as a trusted intermediary to sponsor transaction costs for users.
- **Signature Validation**: Ensures operations are authorized via backend-signed messages.
- **Fee Management**: Integrates seamlessly with the `ChatterPay` wallet for fee processing.
- **Upgradeable**: Can be enhanced with new functionalities over time.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPay**: Handles operation validation and fee sponsorship for the wallet contract.

### **External Contract Interactions**:
- **EntryPoint**: Collaborates with the EntryPoint contract for operation validation.

---

## 4. [**ChatterPayWalletFactory.sol**](../../src/ChatterPayWalletFactory.sol)

### **High-Level Overview**:
The `ChatterPayWalletFactory` contract is responsible for deploying and managing wallet proxies for users. It leverages deterministic address computation for predictable wallet creation.

### **Key Features**:
- **Wallet Proxy Creation**: Deploys upgradeable wallet proxies using the ERC1967 standard.
- **Proxy Tracking**: Maintains a record of all deployed wallet proxies.
- **Upgradeable**: Built to support future enhancements.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPayWalletProxy**: Deploys and manages proxies for the core wallet.

---

## 5. [**ChatterPayWalletProxy.sol**](../../src/ChatterPayWalletProxy.sol)

### **High-Level Overview**:
The `ChatterPayWalletProxy` contract provides upgradeable functionality for wallets using the ERC1967 Proxy standard. It ensures that wallets can be updated without changing their addresses.

### **Key Features**:
- **Upgradeable Wallets**: Supports upgrades to wallet implementations while preserving state.
- **ERC1967 Standard**: Provides a reliable mechanism for proxy upgrades.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPayWalletFactory**: Proxies are deployed and managed by the factory.
- **ChatterPay**: Proxies delegate calls to the main wallet implementation.

---

## 6. [**AggregatorV3Interface.sol**](../../src/interfaces/AggregatorV3Interface.sol)

### **High-Level Overview**:
The `AggregatorV3Interface` defines the interface for Chainlink price feeds. It enables the retrieval of real-time token prices and metadata.

### **Key Features**:
- **Price Feeds**: Provides real-time token prices from decentralized oracles.
- **Metadata Access**: Retrieves additional information like price feed descriptions and versions.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPay**: Utilizes price feeds to calculate transaction fees and validate swaps.

### **External Contract Interactions**:
- **Chainlink Oracles**: Fetches price data for supported tokens.

---

## 7. [**ISwapRouter.sol**](../../src/interfaces/ISwapRouter.sol)

### **High-Level Overview**:
The `ISwapRouter` interface facilitates token swaps using the Uniswap V3 protocol. It supports both single-hop and multi-hop swaps with fine-grained control over slippage and fees.

### **Key Features**:
- **Token Swapping**: Enables efficient token exchanges within the ecosystem.
- **Customizable Parameters**: Supports exact input/output swaps with defined slippage tolerances.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPay**: Executes swaps for supported tokens using the router.

### **External Contract Interactions**:
- **Uniswap V3**: Provides the infrastructure for token swaps.

