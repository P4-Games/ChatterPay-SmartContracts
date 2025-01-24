#!/usr/bin/env bash

# Colors for better visibility
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create abi directory if it doesn't exist
mkdir -p abi

# Clean existing ABIs
rm -rf abi/*

echo -e "${YELLOW}Generating ABIs for all contracts in src/...${NC}"

# Find all .sol files in src/, excluding interfaces
find src -type f -name "*.sol" ! -path "*/interfaces/*" -print0 | while IFS= read -r -d '' file; do
    # Get the contract name from the file name (removing path and extension)
    contract_name=$(basename "$file" .sol)
    
    echo "Processing $contract_name..."
    
    # Generate ABI and save to file
    FOUNDRY_PROFILE=local forge inspect "$contract_name" abi > "abi/${contract_name}.json"
done

echo -e "${GREEN}✅ ABI generation complete! Files saved in abi/ directory${NC}"