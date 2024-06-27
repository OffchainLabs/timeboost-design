#!/bin/bash

# Exit script on any error
set -e

OUT_DIR="./out"
BINDINGS_DIR="../bindings"

# Declare an array of contract names
declare -a CONTRACTS=("ExpressLaneAuction" "MockERC20")

echo "Compiling contracts..."
cd contracts && forge build

# Loop through all contracts and generate Go bindings for each
for CONTRACT in "${CONTRACTS[@]}"; do
    CONTRACT_GO=$(echo "$CONTRACT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g')  # sanitize contract name for Go variable naming conventions

    echo "Generating Go bindings for $CONTRACT..."
    jq '.abi' $OUT_DIR/$CONTRACT.sol/$CONTRACT.json > $OUT_DIR/$CONTRACT.sol/$CONTRACT.modified.json
    jq -r '.bytecode.object' $OUT_DIR/$CONTRACT.sol/$CONTRACT.json > $OUT_DIR/$CONTRACT.sol/$CONTRACT.abi
    abigen --abi $OUT_DIR/$CONTRACT.sol/$CONTRACT.modified.json --bin $OUT_DIR/$CONTRACT.sol/$CONTRACT.abi --pkg $CONTRACT --out $BINDINGS_DIR/$CONTRACT_GO.go

    echo "Go bindings for $CONTRACT generated successfully!"
done