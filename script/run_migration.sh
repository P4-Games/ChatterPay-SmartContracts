#!/bin/bash

# ==============================================================================
# ChatterPay Wallet Flash Migration Runner
# ==============================================================================
# This script executes the token whitelist update in manageable batches.
# It handles bridge deployment reuse and provides progress tracking.
# ==============================================================================

# --- Configuration ---
BATCH_SIZE=50
TOTAL_WALLETS=1700 # Approximate, the script will handle the actual count
START_OFFSET=0
RPC_URL="${RPC_URL:-https://rpc.scroll.io}" # Default to Scroll Mainnet if not set

# Colors for UI
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}           CHATTERPAY WALLET MIGRATION - MAINNET RUNNER               ${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo -e "Batch Size: ${YELLOW}$BATCH_SIZE${NC}"
echo -e "RPC URL:    ${YELLOW}$RPC_URL${NC}"

# Check for Private Key
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}ERROR: PRIVATE_KEY environment variable is not set.${NC}"
    exit 1
fi

# 1. Deploy/Confirm Bridge Logic
echo -e "\n${BLUE}[1/2] Initializing Migration Bridge...${NC}"
# We run a tiny batch of 0 to just handle the bridge deployment/detection
BRIDGE_OUTPUT=$(OFFSET=0 BATCH_SIZE=0 make update_existing_wallets 2>&1)
BRIDGE_ADDR=$(echo "$BRIDGE_OUTPUT" | grep -oE "0x[a-fA-F0-9]{40}" | tail -n 1)

if [ -z "$BRIDGE_ADDR" ]; then
    echo -e "${RED}Failed to detect Bridge Logic address. Check your connection/Admin key.${NC}"
    echo "$BRIDGE_OUTPUT"
    exit 1
fi

echo -e "Bridge Logic Address: ${GREEN}$BRIDGE_ADDR${NC}"
export BRIDGE_LOGIC=$BRIDGE_ADDR

# 2. Start Looping
echo -e "\n${BLUE}[2/2] Starting Execution Loop...${NC}"
echo -e "----------------------------------------------------------------------"

# Calculate total iterations
ITERATIONS=$(( (TOTAL_WALLETS + BATCH_SIZE - 1) / BATCH_SIZE ))
CURRENT_BATCH=0

for (( i=$START_OFFSET; i<$TOTAL_WALLETS; i+=$BATCH_SIZE )); do
    CURRENT_BATCH=$((CURRENT_BATCH + 1))
    PERCENT=$(( (CURRENT_BATCH * 100) / ITERATIONS ))
    
    echo -e "${YELLOW}Batch $CURRENT_BATCH/$ITERATIONS${NC} [Offset: $i] - ${GREEN}$PERCENT% Complete${NC}"
    echo -e "Executing update for wallets $i to $((i + BATCH_SIZE))..."
    
    # EXECUTION COMMAND
    # Note: Using -vv for cleaner output in the loop
    export OFFSET=$i
    export BATCH_SIZE=$BATCH_SIZE
    
    # Trigger the forge script
    # We use 'make update_existing_wallets' which handles the build and broadcast
    make update_existing_wallets
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Batch failed at offset $i. Stopping to prevent nonce issues.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Batch $CURRENT_BATCH successful.${NC}\n"
    
    # Progress UI
    echo -e "Estimated remaining time: ${YELLOW}$(( (ITERATIONS - CURRENT_BATCH) * 1 )) minute(s)${NC}" # Rough ETA
    echo -e "----------------------------------------------------------------------"
    
    # Cooldown to let the RPC/Mempool sync
    sleep 3
done

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}             MIGRATION COMPLETE - ALL BATCHES PROCESSED               ${NC}"
echo -e "${GREEN}======================================================================${NC}"
