#!/bin/sh

# This script is only used by `pnpm deploy:foundry`.
set -e

PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
SHARED_SIGNAL_SERVICE=0x0000000000000000000000000000000000000000 \
SHARED_BRIDGE=0x0000000000000000000000000000000000000000 \
PROPOSER=0x0000000000000000000000000000000000000000 \
PROPOSER_ONE=0x0000000000000000000000000000000000000000 \
GUARDIAN_PROVERS="0x1000777700000000000000000000000000000001,0x1000777700000000000000000000000000000002,0x1000777700000000000000000000000000000003,0x1000777700000000000000000000000000000004,0x1000777700000000000000000000000000000005" \
OWNER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
TAIKO_L2_ADDRESS=0x1000777700000000000000000000000000000001 \
L2_SIGNAL_SERVICE=0x1000777700000000000000000000000000000007 \
TAIKO_TOKEN_PREMINT_RECIPIENT=0xa0Ee7A142d267C1f36714E4a8F75612F20a79720 \
TIER_PROVIDER=0x1 \
L2_GENESIS_HASH=0xee1950562d42f0da28bd4550d88886bc90894c77c9c9eaefef775d4c8223f259 \
forge script script/DeployOnL1.s.sol:DeployOnL1 \
    --fork-url http://localhost:8545 \
    --broadcast \
    --ffi \
    -vvvv \
    --block-gas-limit 100000000
