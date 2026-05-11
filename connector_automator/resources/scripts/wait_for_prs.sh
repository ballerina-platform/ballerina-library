#!/bin/bash
# Polls each connector repository until a PR is created or timeout is reached.
# Usage: wait_for_prs.sh <triggered_connectors_file> <workflow_start_time>
set -e

TRIGGERED_FILE="${1:-triggered_connectors.txt}"
WORKFLOW_START_TIME="$2"

if [ -z "$WORKFLOW_START_TIME" ]; then
    echo "Error: workflow_start_time argument is required" >&2
    exit 1
fi

TOTAL_CONNECTORS=$(wc -l < "$TRIGGERED_FILE")
echo "Monitoring $TOTAL_CONNECTORS connector repositories..."
echo "Looking for PRs created after: $WORKFLOW_START_TIME"

INITIAL_WAIT=600
echo "Waiting ${INITIAL_WAIT} seconds (10 minutes) for connector generation workflows to process..."
sleep $INITIAL_WAIT

MAX_WAIT=4800
CHECK_INTERVAL=30
ELAPSED=0

echo "Now checking for PR creation every ${CHECK_INTERVAL} seconds..."

while [ $ELAPSED -lt $MAX_WAIT ]; do
    COMPLETED=0
    echo "=== Check at $((INITIAL_WAIT + ELAPSED)) seconds total elapsed ==="

    while IFS='|' read -r REPO SPEC VERSION; do
        PR_COUNT=$(gh pr list \
            --repo "$REPO" \
            --state all \
            --limit 20 \
            --json createdAt,title \
            --jq "[.[] | select(.title | contains(\"Auto-generated connector\")) | select(.createdAt > \"$WORKFLOW_START_TIME\")] | length" 2>/dev/null || echo "0")

        if [ "$PR_COUNT" -gt 0 ]; then
            COMPLETED=$((COMPLETED + 1))
            echo "  $REPO - PR found"
        else
            echo "  $REPO - Waiting..."
        fi
    done < "$TRIGGERED_FILE"

    echo "Progress: $COMPLETED/$TOTAL_CONNECTORS connectors have created PRs"

    if [ "$COMPLETED" -eq "$TOTAL_CONNECTORS" ]; then
        echo "All connectors have created PRs"
        break
    fi

    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "Timeout reached after $((INITIAL_WAIT + MAX_WAIT)) total seconds. Proceeding with available data..."
else
    echo "All connectors completed. Waiting 30 seconds for PR metadata to stabilize..."
    sleep 30
fi
