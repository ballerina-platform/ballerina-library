#!/bin/bash
# Dispatches openapi-update events to each connector repository.
# Usage: trigger_connectors.sh <connectors_file> <output_file>
# Writes successfully triggered repos to output_file as REPO|SPEC|VERSION lines.
# Writes triggered_count to $GITHUB_OUTPUT.
set -e

CONNECTORS_FILE="${1:-connectors_to_update.json}"
OUTPUT_FILE="${2:-triggered_connectors.txt}"

> "$OUTPUT_FILE"

jq -c '.[]' "$CONNECTORS_FILE" | while read -r connector; do
    REPO=$(echo "$connector" | jq -r '.repository')
    SPEC=$(echo "$connector" | jq -r '.specification')
    VERSION=$(echo "$connector" | jq -r '.version')
    OPENAPI_URL=$(echo "$connector" | jq -r '.openapi_url')

    echo "Triggering: $REPO (spec=$SPEC version=$VERSION)"

    if gh api \
        repos/"$REPO"/dispatches \
        -X POST \
        -f event_type=openapi-update \
        -f client_payload[sender]=orgBBalLib/ballerina-library \
        -f client_payload[openapi_url]="$OPENAPI_URL" \
        -f client_payload[spec_version]="$VERSION" \
        -f client_payload[spec_path]="$SPEC"; then
        echo "Triggered: $REPO"
        echo "${REPO}|${SPEC}|${VERSION}" >> "$OUTPUT_FILE"
    else
        echo "Failed to trigger: $REPO"
    fi
done

TRIGGERED_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
echo "Successfully triggered $TRIGGERED_COUNT connectors"
echo "triggered_count=$TRIGGERED_COUNT" >> "$GITHUB_OUTPUT"

if [ "$TRIGGERED_COUNT" -eq 0 ]; then
    echo "No connectors were triggered successfully"
    exit 1
fi
