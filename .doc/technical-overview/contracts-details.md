# ChatterPay Contracts Details

## 1. [**ChatterPay.sol**](../../src/ChatterPay.sol)

### **High-Level Overview**:
The `ChatterPay` contract is the core implementation of an account abstraction-based wallet. It allows users to execute transactions, manage token transfers, and interact with a paymaster for fee management. It includes mechanisms for validating user operations, performing token transfers, and interacting with external price feeds.

### **Key Features**:
- **Account Abstraction**: Implements `IAccount` interface for user operations in an abstracted account model.
- **Transaction Execution**: Facilitates generic and token-specific transaction executions with fee management.
- **Fee Calculation**: Calculates fees based on the token type (stable or non-stable) and integrates with external price feeds.
- **EntryPoint Integration**: Interacts with the `EntryPoint` contract for validating user operations and facilitating prefund transfers.
- **Support for Multiple Tokens**: Supports stable tokens (e.g., USDT) and non-stable tokens (e.g., WETH, WBTC).
- **Withdrawal Mechanism**: Allows the contract owner to withdraw balances in supported tokens or ETH.
- **Upgradeable**: Uses `UUPSUpgradeable` to allow for contract upgrades.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPayPaymaster**: Interacts with the paymaster for validating transaction fees and handling the prefund process.
- **ITokensPriceFeeds**: Integrates with external price feeds to fetch token prices for fee calculations.

### **External Contract Interactions**:
- **ERC20**: Interacts with ERC20 tokens to manage transfers and balance checks.
- **API3 Price Feed**: Retrieves token prices for non-stable tokens through the API3 price feed contract.

---

## 2. [**ChatterPayPaymaster.sol**](../../src/ChatterPayPaymaster.sol)

### **High-Level Overview**:
The `ChatterPayPaymaster` contract is responsible for handling the payment of transaction fees on behalf of users. It validates and processes user operations by checking the signature and expiration of paymaster data, ensuring only authorized parties can execute the payment logic.

### **Key Features**:
- **Paymaster Functionality**: Implements `IPaymaster` interface to manage fee payments for user operations.
- **Signature Validation**: Validates paymaster data through signature verification, ensuring the operation is legitimate and not expired.
- **Fee Management**: Ensures that fees are properly handled and paid for during user operations.
- **Owner Control**: Only the owner can execute transactions and withdraw funds.
- **EntryPoint Integration**: Ensures that only the `EntryPoint` contract can call certain functions to ensure proper flow of funds.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPay**: Integrates with the `ChatterPay` contract for fee-related operations, ensuring that paymaster fees are properly handled.

### **External Contract Interactions**:
- **ERC20**: May interact with ERC20 tokens if required for fee handling (though not explicitly mentioned in this contract).

---

## 3. [**ChatterPayNFT.sol**](../../src/ChatterPayNFT.sol)

### **High-Level Overview**:
The `ChatterPayNFT` contract allows for the creation and management of NFTs associated with the ChatterPay platform. Users can mint original NFTs and create copies of these NFTs, with the ability to set limits on how many copies can be minted.

### **Key Features**:
- **ERC721 NFTs**: Implements the ERC721 standard for NFTs, allowing for unique token creation.
- **Original and Copy NFTs**: Supports minting original NFTs and limited copies of these NFTs.
- **Minting Logic**: Only the original minter can mint copies, and the copy limit can be adjusted by the original minter.
- **Base URI Management**: Allows the contract owner to set a base URI for all NFTs.
- **Upgradeable**: Uses `UUPSUpgradeable` to allow for contract upgrades.

### **Relations with Other ChatterPay Contracts**:
- **ChatterPay**: While the `ChatterPayNFT` contract does not directly interact with `ChatterPay`, NFTs can be used in conjunction with wallet operations for various use cases, such as rewards or unique assets linked to the user's wallet.

### **External Contract Interactions**:
- **ERC721**: Inherits from `ERC721Upgradeable` to support the minting and management of NFTs.
- **ERC721URIStorage**: Uses `ERC721URIStorageUpgradeable` to store and retrieve metadata URIs for NFTs.

---

## 4. [**ChatterPayVault.sol**](../../src/ChatterPayNFT.sol)

### High-Level Summary:
The `ChatterPayNFT` contract is an ERC721-based non-fungible token (NFT) contract that supports minting both original tokens and copies of those tokens. The contract uses upgradeable OpenZeppelin contracts and includes functionality to set a base URI for metadata, mint original tokens, mint copies, and set limits on the number of copies that can be minted. It also restricts certain actions, such as changing copy limits, to the original minter of a token.

### Key Features:
- **Upgradeable Contract**: The contract uses the UUPS (Universal Upgradeable Proxy Standard) to allow future upgrades to the contract logic.
- **Original and Copy Tokens**: It allows the minting of original tokens and their copies. Each original token can have a specific number of copies, and the limit on copies can be adjusted.
- **Base URI for Metadata**: The contract uses a base URI to store and retrieve metadata associated with each token.
- **Ownership and Authorization**: The contract restricts certain functions to the owner and the original minter of the tokens, ensuring secure control over token management.

### Functions:
- **initialize()**: The constructor function to initialize the contract with the initial owner and base URI for metadata.
- **_authorizeUpgrade()**: This function is required by the UUPS module to control who can upgrade the contract. Only the contract owner can authorize upgrades.
- **_baseURI()**: This function returns the base URI for metadata, which can be overridden for custom token metadata retrieval.
- **mintOriginal()**: This function mints an original token to a specified address. It also sets a default copy limit for the original token and records the original minter.
- **mintCopy()**: This function mints a copy of an existing original token, provided the original token has been minted and the copy limit has not been exceeded. The copy is linked to the original token and has a unique copy identifier.
- **setBaseURI()**: This function allows the owner to update the base URI for token metadata.
- **setCopyLimit()**: This function allows the original minter to set a new copy limit for the original token, ensuring it does not exceed the current number of copies already minted.
  
### Events:
- There are no custom events explicitly defined in this contract, but standard ERC721 events such as `Transfer` and `Approval` will be emitted when tokens are minted, transferred, or approved.

### Errors:
- **ChatterPayNFT__Unauthorized**: This error is thrown if an unauthorized user tries to modify the copy limit for a token.
- **ChatterPayNFT__TokenAlreadyMinted**: This error is thrown if an attempt is made to mint a token that has already been minted.
- **ChatterPayNFT__OriginalTokenNotMinted**: This error is thrown if an attempt is made to mint a copy of a token that has not been minted yet.
- **ChatterPayNFT__LimitExceedsCopies**: This error is thrown if the new copy limit is lower than the number of copies already minted for a token.

### Considerations:
- **Copy Token ID Calculation**: Copy token IDs are derived from the original token ID, with a unique copy identifier appended, ensuring that copy tokens are easily distinguishable from original tokens.
- **Minting Restrictions**: The contract imposes restrictions on the number of copies that can be minted for an original token, with limits that can only be changed by the original minter.
- **Upgradeable Logic**: The contract is designed to be upgradeable, allowing future changes to its logic without losing state or functionality. This is achieved through the UUPS upgradeable proxy pattern.

---

## 5. [**ChatterPayWalletFactory.sol**](../../src/ChatterPayWalletFactory.sol)

### High-Level Summary:
The `ChatterPayWalletFactory` contract is responsible for creating and managing `ChatterPayWalletProxy` instances. It enables the deployment of proxy contracts that are initialized with specific wallet implementations. The contract allows for flexible wallet creation with different owners and manages the proxy contracts. It also supports the updating of wallet implementations and tracks the deployed proxies.

### Key Features:
- **Proxy Creation**: The factory contract can create new `ChatterPayWalletProxy` instances for different wallet owners. Each proxy is deployed with its own specific initialization.
- **Implementation Management**: The factory allows the owner to update the wallet implementation address used by the proxies.
- **Proxy Tracking**: The contract tracks all the deployed proxies and provides a way to retrieve them, along with the count of deployed proxies.
- **Custom Initialization**: Each proxy is initialized with specific parameters such as entry point, owner, and paymaster.

### Functions:
- **Constructor**: The constructor sets the initial values for the wallet implementation, entry point, owner, and paymaster. It calls the `Ownable` constructor to set the owner of the factory.
- **createProxy()**: This public function creates a new `ChatterPayWalletProxy` for a given owner. The owner must be a valid address, and the function reverts with an error if it is not. The new proxy is initialized with specific parameters and added to the list of proxies.
- **getProxyOwner()**: This function allows querying the owner of a proxy by calling the `owner()` function on the proxy contract.
- **setImplementationAddress()**: This function allows the owner of the factory to update the address of the wallet implementation contract.
- **computeProxyAddress()**: This function computes the address of a potential proxy for a given owner based on the salt (derived from the owner's address) and the bytecode.
- **getProxyBytecode()**: This internal function returns the bytecode used to deploy a new proxy, including the initialization code.
  
### External Interactions:
- **Creating Proxies**: Users can interact with the `createProxy()` function to deploy new proxies with specific owner and wallet configurations.
- **Updating Implementation**: The contract owner can call `setImplementationAddress()` to update the wallet implementation used by all future proxies.
- **Querying Proxies**: Users can retrieve the list of deployed proxies and their count via the `getProxies()` and `getProxiesCount()` functions.

### Events:
- **ProxyCreated**: This event is emitted whenever a new proxy is created, including the owner and the address of the created proxy.
- **NewImplementation**: This event is emitted when the wallet implementation address is updated.

### Considerations:
- **Proxy Deployment**: The `createProxy()` function uses a salt derived from the owner's address to ensure each deployed proxy has a unique address.
- **Implementation Upgrades**: The factory contract allows for the update of the wallet implementation, meaning proxies can be upgraded with new logic without changing their address.
- **Proxies List**: The contract maintains a list of all created proxies, allowing users to track all wallet instances deployed by the factory.

---

## 6. [**ChatterPayWalletProxy.sol**](../../src/ChatterPayWalletProxy.sol)

### High-Level Summary:
The `ChatterPayWalletProxy` contract is an upgradeable proxy that delegates calls to a logic contract. It uses the [ERC-1967 proxy pattern](https://docs.openzeppelin.com/contracts/4.x/api/proxy#ERC1967Proxy), which is a widely used standard for creating upgradeable contracts. The proxy allows the logic of the contract to be upgraded without changing the address that users interact with. This contract includes the necessary functionality to receive Ether and to view the current implementation address.

### Key Features:
- **Upgradeable Contract**: This contract follows the [ERC-1967 proxy pattern](https://docs.openzeppelin.com/contracts/4.x/api/proxy#ERC1967Proxy), allowing it to delegate function calls to an implementation contract. This enables upgrades to the contract logic without changing the proxy address that users interact with.
- **Receive Ether**: The contract includes an explicit `receive` function, allowing it to accept incoming Ether transfers.
- **Implementation View**: The `getImplementation` function allows anyone to view the current logic contract (implementation) address. This function is useful for tracking the active version of the contract's logic.

### Functions:
- **Constructor**: The constructor takes two parameters: the address of the implementation (logic) contract and any initialization data to be passed to the logic contract. It calls the constructor of `ERC1967Proxy` to set the implementation.
- **getImplementation()**: This public function returns the address of the current implementation contract, allowing users to check which contract is being used for logic execution.
- **receive()**: This is an explicit `receive` function, which allows the contract to accept Ether. The contract does not perform any specific actions with the Ether received, it just accepts it.

### External Interactions:
- **Proxy Delegation**: Calls to functions on this contract are delegated to the implementation contract specified in the constructor. Users interact with the proxy, and the proxy forwards the calls to the logic contract.
- **Receiving Ether**: The contract can accept Ether through the `receive()` function, though the Ether is not used or stored within the proxy itself.

### Considerations:
- **Implementation Upgrades**: The proxy can be upgraded by changing the implementation address. This allows the logic of the contract to evolve without requiring users to interact with a new address.
- **Ether Handling**: The contract can accept Ether, but it does not define specific behavior for it. If the implementation contract does not include logic for handling the Ether, it may accumulate in the proxy.


---

## 7. [**SimpleSwap.sol**](../../src/SimpleSwap.sol)

### High-Level Summary:
The `SimpleSwap` contract allows users to swap between WETH (Wrapped Ether) and USDT (Tether USD). It supports liquidity provision where users can add WETH and USDT to the contract's liquidity pool and facilitate swaps between the two tokens. This contract uses the `SafeERC20` library for safe token transfers and includes a reentrancy guard to prevent reentrancy attacks.

### Key Features:
- **Swap Functionality**: Users can swap between WETH and USDT, either from WETH to USDT or from USDT to WETH.
- **Liquidity Provision**: Users can add liquidity to the pool by providing WETH and USDT tokens. This liquidity is used for performing token swaps.
- **Reentrancy Protection**: The contract uses the `ReentrancyGuard` modifier to prevent reentrancy attacks during token swaps.
- **Safe Transfers**: Token transfers are made using the `SafeERC20` library, ensuring that the transfers succeed or revert correctly.
- **Reserves Tracking**: The contract maintains internal reserves for both WETH and USDT, which are updated as users add liquidity or perform swaps.
- **Events**: The contract emits events when liquidity is added or a swap is made, making it easy to track actions on the contract.

### Functions:
- **Constructor**: The constructor takes the addresses of the WETH and USDT tokens as parameters. It ensures the provided addresses are valid.
- **addLiquidity(uint256 wethAmount, uint256 usdtAmount)**: This function allows users to add liquidity to the pool by transferring WETH and USDT to the contract. It updates the internal reserves for both tokens and emits a `LiquidityAdded` event.
- **swapWETHforUSDT(uint256 wethAmount)**: This function allows users to swap WETH for USDT. The amount of USDT received is proportional to the current reserve ratio between WETH and USDT. It updates the reserves and emits a `Swap` event.
- **swapUSDTforWETH(uint256 usdtAmount)**: This function allows users to swap USDT for WETH. The amount of WETH received is proportional to the current reserve ratio between USDT and WETH. It updates the reserves and emits a `Swap` event.
- **getReserves()**: This function allows anyone to view the current reserves of WETH and USDT in the liquidity pool.

### Events:
- **LiquidityAdded(address indexed user, uint256 wethAmount, uint256 usdtAmount)**: Emitted when liquidity is added to the contract.
- **Swap(address indexed user, uint256 wethAmount, uint256 usdtAmount)**: Emitted when a swap between WETH and USDT occurs.

### External Interactions:
- **Add Liquidity**: Users can interact with the `addLiquidity` function to add WETH and USDT to the contract in exchange for contributing to the liquidity pool.
- **Swapping**: Users can call `swapWETHforUSDT` or `swapUSDTforWETH` to exchange one token for the other, with amounts being determined based on the reserve ratios.
- **Token Transfers**: All token transfers in the contract are handled via the `SafeERC20` library, ensuring secure and accurate transfers.

### Considerations:
- **Slippage**: The contract does not implement a mechanism to prevent excessive slippage during swaps, meaning the user might receive fewer tokens than expected due to changes in reserve balances.
- **Liquidity Management**: The contract assumes liquidity is always sufficient to process swaps, but if reserves are depleted, swaps will fail.

---

## 8. [**USDT.sol**](../../src/USDT.sol)

### High-Level Summary:
The `USDT` contract is an ERC20 token representing Tether USD (USDT). It allows for the creation of USDT tokens and provides a minting function for the contract owner to generate more tokens. The contract is based on the ERC20 standard, which is widely used for tokenizing assets in decentralized finance (DeFi) applications. The initial supply is set at 10 million USDT tokens.

### Key Features:
- **ERC20 Token**: The contract implements the ERC20 standard, enabling it to be used in various DeFi protocols that accept ERC20 tokens.
- **Owner Role**: The contract uses OpenZeppelin's `Ownable` pattern, giving the contract owner the exclusive right to mint additional tokens.
- **Initial Supply**: The contract mints 10 million USDT tokens upon deployment, which are assigned to the specified initial account.
- **Minting**: The contract allows the owner to mint new tokens, increasing the total supply of USDT as needed.
- **Transferability**: USDT can be transferred to other accounts, supporting its use in exchanges, dApps, and other protocols that support ERC20 tokens.

### Functions:
- **Constructor**: The contract is initialized with the name "Tether USD" and the symbol "USDT". The initial supply of 10 million tokens is minted to the specified `initialAccount`.
- **mint(address to, uint256 amount)**: This function allows the owner to mint new USDT tokens and send them to a specified address, thus increasing the total supply of USDT.

### Relationship with Other Contracts:
- **ERC20 Standard**: As an ERC20 token, USDT can be easily integrated into other contracts or decentralized applications that support ERC20-compatible tokens.
- **Ownable**: The contract uses OpenZeppelin's `Ownable` contract, which means the owner has control over specific actions, such as minting new tokens.

### External Interactions:
- **Minting**: The owner can call the `mint` function to create new USDT tokens and assign them to any address. This function is restricted to the contract owner.
- **Token Transfers**: USDT can be transferred to other accounts, exchanged, or used in various dApps and DeFi protocols that support ERC20 tokens.

---

## 9. [**WETH.sol**](../../src/WETH.sol)

### High-Level Summary:
The `WETH` contract is an ERC20 token that represents Wrapped Ether (WETH). Its purpose is to allow users to mint and transfer WETH tokens, which are commonly used in DeFi applications to wrap Ether (ETH) into a token compatible with the ERC20 standard. The contract is based on the ERC20 standard and allows the owner to mint new tokens. The initial supply is fixed at 10 million tokens.

### Key Features:
- **ERC20 Token**: Implements the ERC20 standard with a minting function.
- **Owner Role**: The contract uses OpenZeppelin's `Ownable` pattern, giving the owner the ability to mint new tokens.
- **Initial Supply**: The contract starts with an initial supply of 10 million WETH tokens, assigned to the account specified during deployment.
- **Minting**: The owner can mint additional tokens at any time, increasing the total supply. This function is only available to the contract owner.
- **Transferability**: As an ERC20 token, WETH can be transferred between accounts and used in other DeFi applications that support the ERC20 standard.

### Functions:
- **Constructor**: Initializes the contract with the name "Wrapped Ether" and the symbol "WETH". The initial supply of 10 million tokens is minted to the specified `initialAccount`.
- **mint(address to, uint256 amount)**: Allows the owner to mint new tokens and assign them to a specified address. This function increases the total supply of WETH.
  
### Relationship with Other Contracts:
- **ERC20 Standard**: The contract adheres to the ERC20 standard, meaning it can be interacted with by other contracts or decentralized applications (dApps) that support ERC20 tokens.
- **Ownable**: It uses OpenZeppelin's `Ownable` contract, meaning the owner has control over certain functions like minting tokens.
  
### External Interactions:
- **Minting**: The `mint` function can be called externally (but only by the owner) to create new WETH tokens.
- **Token Transfers**: The WETH token can be transferred to other addresses and used in DeFi protocols that accept ERC20 tokens.

---

## 10. [**PackedUserOperation.sol**](../../src/utils/PackedUserOperation.sol)

### High-Level Summary:
The `PackedUserOperation` struct is designed to bundle and pack various data points related to a user operation in a blockchain environment. This data is used in transactions or operations that involve smart contracts, particularly in systems such as account abstraction or meta-transactions. The struct captures necessary information such as the sender's address, the operation's nonce, gas limits, call data, and the user's fee preferences.

### Key Fields:
- **sender**: The address of the sender executing the operation.
- **nonce**: A unique identifier for the operation, often used to prevent replay attacks by ensuring that operations are processed in a specific order.
- **initCode**: The initialization code used for setting up the operation. This could be used to initialize a contract or perform setup tasks.
- **callData**: The data used for executing the actual function or operation on a smart contract.
- **callGasLimit**: The maximum gas the operation is allowed to use for the main call.
- **verificationGasLimit**: The gas limit for verifying the operation, likely used in the context of gas estimation or verification of the user's intent.
- **preVerificationGas**: The gas used before the main verification and execution phase of the operation.
- **maxFeePerGas**: The maximum fee the sender is willing to pay per gas unit, allowing for optimization based on current network conditions.
- **maxPriorityFeePerGas**: The maximum priority fee the sender is willing to pay for the operation, which can be used for incentivizing miners or validators to prioritize the transaction.
- **paymasterAndData**: Optional data associated with a paymaster, which may be used to pay for the transaction fees on behalf of the sender.
- **signature**: The cryptographic signature of the operation, ensuring that the operation was authorized by the sender.

### Purpose and Use Cases:
- **Meta-Transactions**: This struct is typically used in meta-transaction systems, where users can delegate the responsibility for paying gas fees to another party (a paymaster), while still retaining control over the content of the transaction.
- **Account Abstraction**: In systems supporting account abstraction, user operations might be bundled in a similar format to allow for complex user interactions with smart contracts while abstracting away the complexities of gas payments and transaction management.

### Considerations:
- **Gas Efficiency**: The struct packs various parameters into a single structure to streamline the user operation, optimizing gas usage by keeping the data compact.
- **Security**: The signature field ensures that only authorized users can submit operations, preventing unauthorized access or execution of arbitrary operations.

### Struct Design:
This struct is particularly useful for operations that need to pass a variety of parameters to a smart contract in a single transaction, while maintaining flexibility for the user in terms of gas pricing and fee management.

---

## 11. [**L1Keystore.sol**](../../src/Ethereum/L1Keystore.sol)

### High-Level Summary:
The `L1Keystore` contract manages the registration and key-value storage for user accounts associated with smart contract wallets. It also facilitates the management of wallet versions and implementations, including integration with Layer 2 rollups for key updates. The contract allows users to register wallets, store and update keys, and manage wallet access for multiple blockchains.

### Key Components:
1. **WalletEntry**: A struct that stores the owner of the wallet and the mapping of chain IDs to wallet implementations.
2. **UserAccount**: A struct that holds the user’s account details, including keys, wallet information, and the associated Layer 2 rollup contract for key updates.
3. **Key-Value Storage**: Each user account has a key-value map that stores various data, including special keys for wallet salt, version, and initialization data.

### Errors:
- **L1Keystore__NotAuthorized**: Reverts if the sender is not authorized to perform actions on the specified account.
- **L1Keystore__InvalidSalt**: Reverts if an invalid salt is provided during account registration.
- **L1Keystore__InvalidInitData**: Reverts if the length of `initKeys` does not match the length of `initValues`.
- **L1Keystore__InvalidWalletVersion**: Reverts if the wallet version is not recognized or is invalid.
- **L1Keystore__AccountAlreadyExisted**: Reverts if the account already exists.
- **L1Keystore__KeyAlreadyExisted**: Reverts if the key already exists in the account.
- **L1Keystore__InvalidKey**: Reverts if an invalid key operation is attempted (e.g., attempting to modify the salt key).
- **L1Keystore__InvalidOldValue**: Reverts if the old value provided for key updates does not match the current value.
- **L1Keystore__WalletAlreadyRegistered**: Reverts if the wallet version is already registered.
- **L1Keystore__ImplementationNotRegistered**: Reverts if no implementation is registered for a given wallet version and chain ID.

### Public Functions:
1. **registerAccount**:
   - Registers a new user account with a specific wallet version, salt, and initial key-value pairs.
   - Supports integration with Layer 2 rollups for key updates.
   
2. **writeKey**:
   - Allows writing a new key-value pair to a user's account, provided the caller has authorization.
   
3. **updateKey**:
   - Allows updating an existing key in a user's account, checking that the old value matches and ensuring no modifications to restricted keys.
   
4. **updateAccess**:
   - Allows updating the contract that can modify the account's keys (usually a Layer 2 contract).
   
5. **registerWallet**:
   - Registers a new wallet version with the specified owner and implementation address for a given chain ID.

### View Functions:
1. **getRegisteredWalletImplementation**:
   - Returns the wallet implementation address for a given wallet version and chain ID.
   
2. **loadKey**:
   - Loads a value associated with a specific key for a user account.
   
3. **getWalletImplementation**:
   - Retrieves the current wallet implementation address for a user account based on their wallet version and the current chain ID.

### Modifiers:
- **canWrite**: Ensures that only the account owner or a designated Layer 2 rollup contract can modify the account's data.

### Events:
- **WalletRegistered**: Emitted when a new wallet version is registered, along with the owner and implementation details.
- **AccountRegistered**: Emitted when a new user account is registered, including the owner and wallet version.
- **KeyStored**: Emitted when a new key-value pair is written to a user account.
- **KeyUpdated**: Emitted when an existing key is updated.
- **AccessUpdated**: Emitted when the Layer 2 contract for key updates is changed.

### Purpose and Use Cases:
- **User Account Management**: This contract manages user account information for smart contract wallets (SCWs), including supporting the integration with Layer 2 solutions for key management and rollup functionalities.
- **Multi-Chain Support**: It allows the management of wallet implementations and key data across multiple blockchains, ensuring flexibility for cross-chain operations.
- **Key and Data Storage**: The contract provides an efficient key-value storage mechanism, which can be extended to store arbitrary data related to each user account.

### Security Considerations:
- **Access Control**: The use of the `canWrite` modifier ensures that only authorized parties (owners or L2 rollup contracts) can modify sensitive data.
- **Chain Independence**: The use of mappings for wallet versions and chain IDs allows the contract to manage wallet implementations across multiple blockchains, enhancing scalability and flexibility.

### Conclusion:
The `L1Keystore` contract is designed to serve as a central registry for smart contract wallets, with features for wallet versioning, key-value storage, and integration with Layer 2 solutions. It provides robust management and flexibility for decentralized user accounts across various blockchains.

---

## 12. [**TokensPriceFeeds.sol**](../../src/Ethereum/TokensPriceFeeds.sol)

### High-Level Summary:
The `TokensPriceFeeds` contract provides a mechanism for reading token price data feeds for ETH/USD and BTC/USD from external proxy contracts. It allows the owner to set and update the addresses of the proxies, ensuring that data feeds are valid and up to date. This contract primarily acts as a bridge between external price feed proxies and users who need token price data.

### Key Components:
1. **ETH_USD_Proxy & BTC_USD_Proxy**: These are addresses of the proxy contracts responsible for providing the ETH/USD and BTC/USD price feeds.
2. **Event - ProxyAddressSet**: Emitted when the address of a price feed proxy is set or updated by the owner.

### Errors:
- **TokensPriceFeeds__ValueNotPositive**: Reverts if the value fetched from the proxy feed is non-positive, indicating invalid price data.
- **TokensPriceFeeds__TimestampTooOld**: Reverts if the timestamp of the price feed is older than 1 day, ensuring the data is recent.
- **TokenPriceFeeds___InvalidAddress**: Reverts if the provided proxy address is invalid (i.e., address(0)).

### Public Functions:
1. **setETHProxyAddress**:
   - Allows the owner to set the address of the ETH/USD price feed proxy.
   - Emits `ProxyAddressSet` with the new proxy address.
   
2. **setBTCProxyAddress**:
   - Allows the owner to set the address of the BTC/USD price feed proxy.
   - Emits `ProxyAddressSet` with the new proxy address.
   
3. **readDataFeed**:
   - Fetches the price data (in uint256 format) and timestamp from a specified proxy address.
   - Validates the proxy address, checks if the fetched price is positive, and ensures the timestamp is not outdated (not older than 1 day).
   - Returns the price and timestamp.

### View Functions:
- **ETH_USD_Proxy**: Returns the address of the ETH/USD price feed proxy.
- **BTC_USD_Proxy**: Returns the address of the BTC/USD price feed proxy.

### Purpose and Use Cases:
- **Price Feed Integration**: This contract enables fetching real-time price data for ETH/USD and BTC/USD from proxy contracts, which could be part of an oracle network.
- **Proxy Management**: The contract allows the owner to manage the proxy addresses, ensuring flexibility to update the price feed sources if necessary.
- **Secure and Validated Price Retrieval**: Price data is validated for non-negative values and freshness (within 1 day), providing reliable and up-to-date information for other contracts or decentralized applications.

### Security Considerations:
- **Access Control**: The `onlyOwner` modifier ensures that only the owner can set the proxy addresses, preventing unauthorized modifications.
- **Price Data Validation**: The contract ensures that only valid price data (positive values and fresh timestamps) is accepted, preventing the use of outdated or incorrect price information.

### Conclusion:
The `TokensPriceFeeds` contract provides a secure and flexible way to read real-time price data for ETH/USD and BTC/USD from external proxies. It allows the owner to configure the proxy addresses and ensures that the data retrieved is both valid and up-to-date, making it a reliable source for token price information in decentralized applications.

