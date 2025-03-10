-include .env

# Common build command with local profile to ensure AST generation
BUILD = FOUNDRY_PROFILE=local forge clean && FOUNDRY_PROFILE=local forge build

# Deploy all contracts
deploy_verify_arbitrum_sepolia_all :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployAllContracts.s.sol \
	--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--etherscan-api-key $(ARBISCAN_API_KEY) \
	--broadcast

deploy_arbitrum_sepolia_all :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployAllContracts.s.sol \
	--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast

# Deploy only ChatterPay contract
deploy_verify_arbitrum_sepolia_only_chatterpay :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployChatterPay.s.sol \
	--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--etherscan-api-key $(ARBISCAN_API_KEY) \
	--broadcast

deploy_arbitrum_sepolia_only_chatterpay :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployChatterPay.s.sol \
	--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast

# Deploy only Paymaster contract
deploy_verify_arbitrum_sepolia_only_paymaster :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployPaymaster.s.sol \
	--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--verify \
	--etherscan-api-key $(ARBISCAN_API_KEY) \
	--broadcast

deploy_arbitrum_sepolia_only_paymaster :; $(BUILD) && \
	FOUNDRY_PROFILE=local forge script script/DeployPaymaster.s.sol \
	--rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast