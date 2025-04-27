-include .env

# Common build command with local profile to ensure AST generation
BUILD = FOUNDRY_PROFILE=local forge clean && FOUNDRY_PROFILE=local forge build

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

