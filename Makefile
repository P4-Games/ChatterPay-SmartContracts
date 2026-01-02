-include .env

# Common build command - removed 'forge clean' to allow incremental builds
BUILD = FOUNDRY_PROFILE=local forge build

# Deploy all contracts (Anvil)
deploy_anvil_all :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployAllContracts.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--private-key $(PRIVATE_KEY)

# Deploy all contracts
deploy_all :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployAllContracts.s.sol \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast

# Deploy and verify all contracts
deploy_verify_all :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployAllContracts.s.sol \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--etherscan-api-key $(NETWORK_EXPLORER_API_KEY) \
	--broadcast

# Deploy new ChatterPay Implementation and upgrade Factory
upgrade_chatterpay_and_factory :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/UpgradeImplementation.s.sol \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast

# Deploy and verify all contracts
upgrade_chatterpay_and_factory_wtih_verify :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/UpgradeImplementation.s.sol \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--etherscan-api-key $(NETWORK_EXPLORER_API_KEY) \
	--broadcast

# Update existing wallets with new tokens (dry run)
update_existing_wallets_dry_run :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/UpdateExistingWallets.s.sol \
	--rpc-url $(RPC_URL) \
	-vvvv

# Update existing wallets with new tokens (broadcasts transactions)
update_existing_wallets :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/UpdateExistingWallets.s.sol \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	-vvvv

# Deploy new factory with updated tokens
deploy_new_factory :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployAllContracts.s.sol \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--etherscan-api-key $(NETWORK_EXPLORER_API_KEY) \
	--broadcast