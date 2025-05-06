#!/bin/bash

# Token addresses
#WETH_TOKEN="0xd5654b986d5aDba8662c06e847E32579078561dC"
WETH_TOKEN="0xC262f22bb6da71fC14c8914f0A3DC02e7bf6E5b0"
UDST_TOKEN="0x776133ea03666b73a8e3FC23f39f90e66360716E"

# Uniswap V3 factory
FACTORY="0x0287f57A1a17a725428689dfD9E65ECA01d82510"

# Fee tiers to check
FEES=(1000 3000 10000)

# Helper: clean number
clean_number() {
    echo "$1" | sed 's/ .*//'
}

# Helper: get decimals of a token
get_decimals() {
    local token=$1
    local decimals=$(cast call "$token" "decimals()(uint8)" --rpc-url "$RPC_URL" | sed 's/ .*//')
    echo "$decimals"
}

# Helper: search pool
find_pool() {
    local tokenA=$1
    local tokenB=$2
    local fee=$3

    pool=$(cast call "$FACTORY" "getPool(address,address,uint24)(address)" "$tokenA" "$tokenB" "$fee" --rpc-url "$RPC_URL")
    echo "$pool"
}

# Helper: show pool details
show_pool_info() {
    local pool=$1
    local tokenA=$2
    local tokenB=$3
    local feeReadable=$4

    echo "✅ Pool found for fee ${feeReadable}% between $tokenA and $tokenB"
    echo "Pool Address: $pool"

    liquidity_raw=$(cast call "$pool" "liquidity()(uint128)" --rpc-url "$RPC_URL")
    liquidity=$(clean_number "$liquidity_raw")

    echo "Liquidity raw value: $liquidity_raw"

    # Fetch decimals dynamically
    decimals_tokenA=$(get_decimals "$tokenA")
    decimals_tokenB=$(get_decimals "$tokenB")

    # Token balances
    balance0_raw=$(cast call "$tokenA" "balanceOf(address)(uint256)" "$pool" --rpc-url "$RPC_URL")
    balance1_raw=$(cast call "$tokenB" "balanceOf(address)(uint256)" "$pool" --rpc-url "$RPC_URL")

    balance0=$(clean_number "$balance0_raw")
    balance1=$(clean_number "$balance1_raw")

    balance0_human=$(echo "scale=$decimals_tokenA; $balance0 / (10^$decimals_tokenA)" | bc)
    balance1_human=$(echo "scale=$decimals_tokenB; $balance1 / (10^$decimals_tokenB)" | bc)

    echo "Token0 ($tokenA)"
    echo "  - Raw balance       : $balance0"
    echo "  - Decimals          : $decimals_tokenA"
    echo "  - Adjusted balance  : $balance0_human"

    echo "Token1 ($tokenB)"
    echo "  - Raw balance       : $balance1"
    echo "  - Decimals          : $decimals_tokenB"
    echo "  - Adjusted balance  : $balance1_human"

    echo "-----------------------------------------"
}

# Main execution
for fee in "${FEES[@]}"; do
    feeReadable=$(echo "scale=1; $fee / 10000" | bc)
    echo "🔎 Searching pools for fee ${feeReadable}%..."

    # Check WETH -> UDST
    poolA=$(find_pool "$WETH_TOKEN" "$UDST_TOKEN" "$fee")
    if [ "$poolA" != "0x0000000000000000000000000000000000000000" ]; then
        show_pool_info "$poolA" "$WETH_TOKEN" "$UDST_TOKEN" "$feeReadable"
    fi

    # Check UDST -> WETH
    poolB=$(find_pool "$UDST_TOKEN" "$WETH_TOKEN" "$fee")
    if [ "$poolB" != "0x0000000000000000000000000000000000000000" ]; then
        show_pool_info "$poolB" "$UDST_TOKEN" "$WETH_TOKEN" "$feeReadable"
    fi
done
