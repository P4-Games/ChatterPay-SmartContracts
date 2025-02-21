#!/bin/bash

# Load environment variables
source .env

# Colors for better visibility
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Ensure contract name is provided
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: You must provide a contract name as an argument.${NC}"
    echo "Usage: $0 <ContractName>"
    exit 1
fi

CONTRACT_NAME=$1
PROFILE=${FOUNDRY_PROFILE:-"local"}
MAX_RETRIES=1  # Maximum number of retries
RETRY_DELAY=10 # Seconds to wait before retrying

# Start time measurement
start_time=$(date +%s)

echo "🧪 Running tests for contract: '$CONTRACT_NAME' with profile: '$PROFILE'"

# Create a cache directory if it doesn't exist
mkdir -p .forge-cache

# Run tests only for the given contract
FOUNDRY_PROFILE=$PROFILE FOUNDRY_FUZZ_RUNS=0 forge test \
    --fork-url "$ARBITRUM_SEPOLIA_RPC_URL" \
    -vvv \
    --match-path "test/modules/${CONTRACT_NAME}.t.sol" \
    --ffi \
    -j 1 \
    --gas-report \
    --cache-path .forge-cache 2>&1 | tee test_results.log | grep -v 'testFail* has been removed'

# Extract failing tests
grep '\[FAIL:' test_results.log | awk '{print $2}' | sed 's/:.*//' | sort -u > failed_tests.log
num_fails=$(wc -l < failed_tests.log)

if [[ $num_fails -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests for $CONTRACT_NAME completed successfully on the first run.${NC}"
    exit 0
fi

echo -e "${RED}⚠️ $num_fails tests failed. Retrying failed tests...${NC}"

# Retry only the failing tests
attempt=1
while [[ $attempt -le $MAX_RETRIES && $num_fails -gt 0 ]]; do
    echo "🔄 Retry attempt $attempt of $MAX_RETRIES for failing tests in $CONTRACT_NAME..."
    
    # Run only the failed tests
    while IFS= read -r test_name; do
        echo "🔁 Retrying $test_name..."
        FOUNDRY_PROFILE=$PROFILE FOUNDRY_FUZZ_RUNS=0 forge test \
            --fork-url "$ARBITRUM_SEPOLIA_RPC_URL" \
            -vvv \
            --match-test "$test_name" \
            --ffi \
            -j 1 \
            --gas-report \
            --cache-path .forge-cache 2>&1 | tee test_results.log | grep -v 'testFail* has been removed'
    done < failed_tests.log

    # Check if any tests still fail
    FOUNDRY_PROFILE=$PROFILE forge test --fork-url "$ARBITRUM_SEPOLIA_RPC_URL" --match-path "test/modules/${CONTRACT_NAME}.t.sol" --ffi -j 1 --gas-report --cache-path .forge-cache 2>&1 | tee retry_results.log
    grep '\[FAIL:' retry_results.log | awk '{print $2}' | sed 's/:.*//' | sort -u > failed_tests.log
    num_fails=$(wc -l < failed_tests.log
