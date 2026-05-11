#!/bin/bash
# Adds the appropriate labels to a connector update PR.
# Usage: add_labels.sh <PR_NUMBER> <HAS_CODE_CHANGES> <GRADLE_BUILD_FAILED> <ANALYSIS_FAILED> <PIPELINE_SUCCEEDED>
set -e

PR_NUMBER="$1"
HAS_CODE_CHANGES="$2"
GRADLE_BUILD_FAILED="$3"
ANALYSIS_FAILED="$4"
PIPELINE_SUCCEEDED="$5"

if [ -z "$PR_NUMBER" ]; then
    echo "Usage: add_labels.sh <PR_NUMBER> <HAS_CODE_CHANGES> <GRADLE_BUILD_FAILED> <ANALYSIS_FAILED> <PIPELINE_SUCCEEDED>" >&2
    exit 1
fi

LABELS="manual-review-required"

if [ "$HAS_CODE_CHANGES" != "true" ]; then
    LABELS="$LABELS,up-to-date"
else
    if [ "$GRADLE_BUILD_FAILED" = "true" ]; then LABELS="$LABELS,build-failed"; fi
    if [ "$ANALYSIS_FAILED" = "true" ]; then LABELS="$LABELS,analysis-failed"; fi
fi

if [ "$PIPELINE_SUCCEEDED" != "true" ]; then
    LABELS="$LABELS,do-not-merge"
fi

echo "Adding labels to PR #$PR_NUMBER: $LABELS"
gh issue edit "$PR_NUMBER" --add-label "$LABELS"
