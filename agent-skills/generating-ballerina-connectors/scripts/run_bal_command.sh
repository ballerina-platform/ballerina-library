#!/usr/bin/env bash
# Wrapper for Ballerina CLI commands.
# Usage: run_bal_command.sh "<full command>" [<working-dir>]
# Prints stdout/stderr to terminal and exits with the command's exit code.

set -euo pipefail

COMMAND="${1:?Usage: run_bal_command.sh \"<command>\" [<working-dir>]}"
WORKDIR="${2:-$(pwd)}"

if [ ! -d "$WORKDIR" ]; then
  mkdir -p "$WORKDIR"
fi

echo ">>> Running: $COMMAND"
echo ">>> Working dir: $WORKDIR"
echo ""

cd "$WORKDIR"
eval "$COMMAND"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "" >&2
  echo ">>> Command failed with exit code $EXIT_CODE" >&2
fi

exit $EXIT_CODE
