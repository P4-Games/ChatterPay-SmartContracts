#!/bin/bash

#---------------------------------------------------------
# set:
# export ENTRYPOINT_ADDRESS=0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
# export PAYMASTER_ADDRESS=0x33F43e0165f2B6Ad829594649FbdA70d878F1462
# export BACKEND_SIGNER_ADDRESS=0xe54b48F8caF88a08849dCdDE3D3d41Cd6D7ab369
# export BACKEND_SIGNER_SK=0xxxxxxxxxxx
# export RPC_URL=https://scroll-sepolia.g.alchemy.com/v2/cSwp__cy4eqSYmiiIMXtZ810r3AptmiL

# run:
# 
#---------------------------------------------------------

# Token addresses
#WETH_TOKEN="0xd5654b986d5aDba8662c06e847E32579078561dC"
WETH_TOKEN="0xC262f22bb6da71fC14c8914f0A3DC02e7bf6E5b0"
UDST_TOKEN="0x776133ea03666b73a8e3FC23f39f90e66360716E"

# Uniswap V3 factory
FACTORY="0xB856587fe1cbA8600F75F1b1176E44250B11C788"

# Fee tiers to check
FEES=(500 3000 10000)

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
    feeReadable=$(echo "scale=2; $fee / 10000" | bc)
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
