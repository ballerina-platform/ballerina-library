#!/bin/bash
# Builds a PR description file from analysis_result.json and pads lines to
# satisfy the Ballerina update_changelog.bal substring(0, 50) precondition.
# Usage: build_changelog_description.sh <analysis_result.json> <output_file>
set -e

ANALYSIS_FILE="${1:-analysis_result.json}"
OUTPUT_FILE="${2:-pr_description.txt}"

if [ ! -f "$ANALYSIS_FILE" ]; then
    echo "Error: Analysis file not found: $ANALYSIS_FILE" >&2
    exit 1
fi

echo "Building PR description from $ANALYSIS_FILE..."

echo "### Summary" > "$OUTPUT_FILE"
jq -r '.summary' "$ANALYSIS_FILE" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "### Breaking Changes" >> "$OUTPUT_FILE"
BREAKING_COUNT=$(jq -r '.breakingChanges | length' "$ANALYSIS_FILE")
if [ "$BREAKING_COUNT" -gt 0 ]; then
    jq -r '.breakingChanges[]' "$ANALYSIS_FILE" | while IFS= read -r line; do
        echo "- $line" >> "$OUTPUT_FILE"
    done
else
    echo "- None" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "### New Features" >> "$OUTPUT_FILE"
FEATURES_COUNT=$(jq -r '.newFeatures | length' "$ANALYSIS_FILE")
if [ "$FEATURES_COUNT" -gt 0 ]; then
    jq -r '.newFeatures[]' "$ANALYSIS_FILE" | while IFS= read -r line; do
        echo "- $line" >> "$OUTPUT_FILE"
    done
else
    echo "- None" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "### Improvements" >> "$OUTPUT_FILE"
FIXES_COUNT=$(jq -r '.bugFixes | length' "$ANALYSIS_FILE")
if [ "$FIXES_COUNT" -gt 0 ]; then
    jq -r '.bugFixes[]' "$ANALYSIS_FILE" | while IFS= read -r line; do
        echo "- $line" >> "$OUTPUT_FILE"
    done
else
    echo "- None" >> "$OUTPUT_FILE"
fi

echo ""
echo "=== Generated PR Description ==="
cat "$OUTPUT_FILE"
echo "================================"

# Pad every line to at least 50 chars so Ballerina's substring(0, 50) is always safe.
python3 - "$OUTPUT_FILE" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "r") as f:
    lines = f.readlines()
with open(path, "w") as f:
    for line in lines:
        stripped = line.rstrip("\n")
        if len(stripped) < 50:
            stripped = stripped.ljust(50)
        f.write(stripped + "\n")
PYEOF

echo "PR description written to $OUTPUT_FILE"
