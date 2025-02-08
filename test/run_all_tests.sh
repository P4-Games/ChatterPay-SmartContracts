#!/bin/bash

# Load environment variables
source .env

# Colors for better visibility
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Determine profile based on environment variable (default to local)
PROFILE=${FOUNDRY_PROFILE:-"local"}

# Maximum retries and delay for handling RPC rate limits (429)
MAX_RETRIES=3  # Maximum number of retries
RETRY_DELAY=10 # Seconds to wait before retrying

# Start time measurement
start_time=$(date +%s)

echo "🧪 Running module tests with profile: $PROFILE..."

# Create a cache directory if it doesn't exist
mkdir -p .forge-cache

attempt=1
while [ $attempt -le $MAX_RETRIES ]; do
    echo "🔄 Attempt $attempt of $MAX_RETRIES..."

    # Execute tests with forge using environment variable
    FOUNDRY_PROFILE=$PROFILE forge test \
        --fork-url $ARBITRUM_SEPOLIA_RPC_URL \
        -vvv \
        --match-path "test/modules/*" \
        --ffi \
        -j 1 \
        --gas-report \
        --cache-path .forge-cache

    # Store test result
    test_result=$?

    if [ $test_result -eq 0 ]; then
        break
    fi

    echo -e "${RED}❌ Some tests failed, possible RPC rate limit (429). Retrying in $RETRY_DELAY seconds...${NC}"
    sleep $RETRY_DELAY

    attempt=$((attempt + 1))
done

# Calculate execution time
end_time=$(date +%s)
duration=$((end_time - start_time))

# Verify result with colored output
if [ $test_result -eq 0 ]; then
    echo -e "${GREEN}✅ All tests completed successfully${NC}"
    echo "⏱️  Total execution time: ${duration} seconds"
    echo "🔧 Profile used: $PROFILE"
else
    echo -e "${RED}❌ Some tests failed${NC}"
    echo "⏱️  Total execution time: ${duration} seconds"
    echo "🔧 Profile used: $PROFILE"
    exit 1
fi
