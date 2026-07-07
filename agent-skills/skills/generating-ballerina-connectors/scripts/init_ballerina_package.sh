#!/usr/bin/env bash
# Initialise a Ballerina package in the output directory using `bal new .`.
# Removes the generated main.bal scaffold — the connector files (client.bal,
# types.bal, utils.bal) come from `bal openapi` in the client stage.
#
# Usage: init_ballerina_package.sh <output-dir>

set -euo pipefail

OUTPUT_DIR="${1:?Usage: init_ballerina_package.sh <output-dir>}"

cd "${OUTPUT_DIR}"

echo ">>> Running bal new . in ${OUTPUT_DIR}..."
bal new .

# Remove the main.bal scaffold — not needed for a connector package
if [ -f "main.bal" ]; then
    rm -f "main.bal"
    echo ">>> Removed scaffold main.bal"
fi

echo "✓ Ballerina package initialised"
