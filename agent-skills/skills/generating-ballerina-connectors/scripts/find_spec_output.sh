#!/usr/bin/env bash
# Locate the aligned OpenAPI spec output in a spec directory.
#
# Usage: find_spec_output.sh <spec_dir>
# Output (stdout): absolute path to the best available spec file
# Exit 1 if nothing found.

SPEC_DIR="${1:?Usage: find_spec_output.sh <spec_dir>}"

# Only accept the aligned spec — flattened_openapi.* is an intermediate artifact
# that has not been through bal openapi align and must not be fed to --mode client.
CANDIDATES=(
  "aligned_ballerina_openapi.json"
  "aligned_ballerina_openapi.yaml"
  "aligned_ballerina_openapi.yml"
)

for name in "${CANDIDATES[@]}"; do
  path="$SPEC_DIR/$name"
  if [ -f "$path" ]; then
    echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    exit 0
  fi
done

echo "ERROR: No aligned spec found in $SPEC_DIR" >&2
echo "Run Stage 01 (sanitize) first to produce aligned_ballerina_openapi.json" >&2
exit 1
