#!/usr/bin/env bash
# Generate a Ballerina service stub from an OpenAPI spec into tests/mock_service.bal.
#
# Usage: generate_mock_stub.sh <spec-path> <ballerina-dir> [operations] [license-path]
#   operations    Optional comma-separated operationIds (used when spec has >30 operations)
#   license-path  Optional path to a license header file passed to --license
#
# The stub is written to <ballerina-dir>/tests/mock_service.bal

set -euo pipefail

SPEC_PATH="${1:?Usage: generate_mock_stub.sh <spec-path> <ballerina-dir> [operations] [license-path]}"
BALLERINA_DIR="${2:?Usage: generate_mock_stub.sh <spec-path> <ballerina-dir> [operations] [license-path]}"
OPERATIONS="${3:-}"     # optional: comma-separated operationIds
LICENSE_PATH="${4:-}"   # optional: path to license header file
TESTS_DIR="${BALLERINA_DIR}/tests"

mkdir -p "$TESTS_DIR"

# Build the bal openapi command — --mode service generates only the service stub, not a client
CMD="bal openapi -i \"${SPEC_PATH}\" --mode service -o \"${TESTS_DIR}\""
if [ -n "$OPERATIONS" ]; then
  echo ">>> Filtering to operations: ${OPERATIONS}"
  CMD="$CMD --operations \"${OPERATIONS}\""
fi
if [ -n "$LICENSE_PATH" ]; then
  CMD="$CMD --license \"${LICENSE_PATH}\""
fi

echo ">>> Running bal openapi to generate service stub..."
eval $CMD

# Rename the generated service file to mock_service.bal
SERVICE_FILE="${TESTS_DIR}/aligned_ballerina_openapi_service.bal"
MOCK_FILE="${TESTS_DIR}/mock_service.bal"

if [ ! -f "${SERVICE_FILE}" ]; then
  echo "ERROR: Expected ${SERVICE_FILE} but it was not generated." >&2
  exit 1
fi

mv "${SERVICE_FILE}" "${MOCK_FILE}"
echo ">>> Renamed aligned_ballerina_openapi_service.bal → mock_service.bal"

# Remove generated types.bal and client.bal — root package types.bal is already in scope
rm -f "${TESTS_DIR}/types.bal" "${TESTS_DIR}/client.bal" "${TESTS_DIR}/utils.bal"

echo "✓ Stub written: ${MOCK_FILE}"
