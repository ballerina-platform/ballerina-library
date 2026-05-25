#!/bin/bash
# Calculates the next semantic version given a change type and current version.
# Usage: update_version.sh <CHANGE_TYPE> <CURRENT_VERSION>
# Prints the new version string to stdout.
set -e

CHANGE_TYPE="$1"
CURRENT_VERSION="$2"

if [ -z "$CHANGE_TYPE" ] || [ -z "$CURRENT_VERSION" ]; then
    echo "Usage: update_version.sh <CHANGE_TYPE> <CURRENT_VERSION>" >&2
    exit 1
fi

BASE_VERSION=$(echo "$CURRENT_VERSION" | sed 's/-SNAPSHOT//')
IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE_VERSION"

case $CHANGE_TYPE in
    MAJOR)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    MINOR)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    PATCH)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo "Unknown change type: $CHANGE_TYPE" >&2
        exit 1
        ;;
esac

echo "${MAJOR}.${MINOR}.${PATCH}-SNAPSHOT"
