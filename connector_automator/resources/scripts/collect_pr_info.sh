#!/bin/bash
# Collects PR details from each connector repository into a JSON file.
# Usage: collect_pr_info.sh <triggered_connectors_file> <workflow_start_time> <output_json_file>
set -e

TRIGGERED_FILE="${1:-triggered_connectors.txt}"
WORKFLOW_START_TIME="$2"
OUTPUT_FILE="${3:-connector_prs.json}"

if [ -z "$WORKFLOW_START_TIME" ]; then
    echo "Error: workflow_start_time argument is required" >&2
    exit 1
fi

echo "Collecting PR information from all triggered connectors..."
echo "Looking for PRs created after: $WORKFLOW_START_TIME"

echo "[]" > "$OUTPUT_FILE"

while IFS='|' read -r REPO SPEC VERSION; do
    echo "Checking repository: $REPO"

    PR_DATA=$(gh pr list \
        --repo "$REPO" \
        --state all \
        --limit 20 \
        --json number,title,url,state,createdAt,body \
        --jq "[.[] | select(.title | contains(\"Auto-generated connector\")) | select(.createdAt > \"$WORKFLOW_START_TIME\")] | sort_by(.createdAt) | reverse | .[0]" 2>/dev/null || echo "null")

    if [ -n "$PR_DATA" ] && [ "$PR_DATA" != "null" ] && [ "$PR_DATA" != "{}" ]; then
        PR_NUMBER=$(echo "$PR_DATA" | jq -r '.number')
        echo "  Found PR #$PR_NUMBER for $REPO (created at $(echo "$PR_DATA" | jq -r '.createdAt'))"

        CHANGE_TYPE=$(echo "$PR_DATA" | jq -r '.title' | grep -oE '\[(MAJOR|MINOR|PATCH|NONE)\]' | tr -d '[]' || echo "UNKNOWN")
        [ -z "$CHANGE_TYPE" ] && CHANGE_TYPE="UNKNOWN"

        BUILD_STATUS="Success"
        if echo "$PR_DATA" | jq -r '.title' | grep -q "BUILD FAILED"; then
            BUILD_STATUS="FAILED"
        elif [ "$CHANGE_TYPE" = "NONE" ]; then
            BUILD_STATUS="Up to date"
        fi

        DO_NOT_MERGE="false"
        if echo "$PR_DATA" | jq -r '.title' | grep -q "\[DO NOT MERGE\]"; then
            DO_NOT_MERGE="true"
            if [ "$BUILD_STATUS" != "FAILED" ] && [ "$BUILD_STATUS" != "Up to date" ]; then
                BUILD_STATUS="Partial"
            fi
        fi

        PR_BODY=$(echo "$PR_DATA" | jq -r '.body // ""')
        NEW_VERSION=$(echo "$PR_BODY" | grep -oP 'New Version.*?`\K[^`]+' || echo "")
        CODE_OWNERS=$(echo "$PR_BODY" | grep -oP 'Code Owners:.*?\K@[\w-]+(,\s*@[\w-]+)*' | tr -d '@' | sed 's/,/, /g' || echo "")
        CONNECTOR_NAME=$(echo "$REPO" | sed 's|^orgBBalLib/module-ballerinax-||')

        CONNECTOR_INFO=$(jq -n \
            --arg repo "$REPO" \
            --arg connectorName "$CONNECTOR_NAME" \
            --arg spec "$SPEC" \
            --arg version "$VERSION" \
            --arg changeType "$CHANGE_TYPE" \
            --arg buildStatus "$BUILD_STATUS" \
            --arg doNotMerge "$DO_NOT_MERGE" \
            --arg newVersion "$NEW_VERSION" \
            --arg codeOwners "$CODE_OWNERS" \
            --argjson prData "$PR_DATA" \
            '{
              repository: $repo,
              connectorName: $connectorName,
              specification: $spec,
              openapiVersion: $version,
              changeType: $changeType,
              buildStatus: $buildStatus,
              doNotMerge: $doNotMerge,
              expectedVersion: $newVersion,
              codeOwners: $codeOwners,
              pr: $prData
            }')
    else
        echo "  No PR found for $REPO — workflow may have failed before creating a PR"
        CONNECTOR_NAME=$(echo "$REPO" | sed 's|^orgBBalLib/module-ballerinax-||')

        CONNECTOR_INFO=$(jq -n \
            --arg repo "$REPO" \
            --arg connectorName "$CONNECTOR_NAME" \
            --arg spec "$SPEC" \
            --arg version "$VERSION" \
            '{
              repository: $repo,
              connectorName: $connectorName,
              specification: $spec,
              openapiVersion: $version,
              changeType: "FAILED",
              buildStatus: "Workflow Failed",
              expectedVersion: "N/A",
              codeOwners: "N/A",
              pr: {number: 0, title: "Not Created", url: "", state: "failed"}
            }')
    fi

    jq --argjson item "$CONNECTOR_INFO" '. += [$item]' "$OUTPUT_FILE" > tmp_prs.json && mv tmp_prs.json "$OUTPUT_FILE"
    echo "  Recorded info for $REPO"

done < "$TRIGGERED_FILE"

echo "PR collection complete — $(jq 'length' "$OUTPUT_FILE") connectors recorded"
cat "$OUTPUT_FILE" | jq '.'
