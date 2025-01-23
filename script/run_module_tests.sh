#!/bin/bash

# Load environment variables
source .env

# Find and execute all test files in test/modules
echo "🧪 Running module tests..."

# Execute tests with forge using environment variable
forge test --fork-url $ARBITRUM_SEPOLIA_RPC_URL -vvv --match-path "test/modules/*" --ffi -j 5

# Verify result
if [ $? -eq 0 ]; then
    echo "✅ All tests completed successfully"
else
    echo "❌ Some tests failed"
    exit 1
fi