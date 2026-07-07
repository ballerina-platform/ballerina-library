#!/usr/bin/env bash
# Check that the environment has the required tools for the generating-ballerina-connectors skill.
# Mirrors sdk_workflow.bal and utils/ai_service.bal environment validation logic.
#
# Usage: check_environment.sh
# Output: status lines per check. Exits 1 if any required check fails.

FAILED=0

check() {
  local label="$1"
  local ok="$2"   # "true" or "false"
  local detail="${3:-}"

  if [ "$ok" = "true" ]; then
    echo "  ✓ $label${detail:+  ($detail)}"
  else
    echo "  ✗ $label${detail:+  — $detail}" >&2
    FAILED=1
  fi
}

echo "Checking environment..."

# bal CLI
if command -v bal &>/dev/null; then
  BAL_VER=$(bal version 2>/dev/null | head -1 || echo "unknown")
  check "Ballerina (bal)" "true" "$BAL_VER"
else
  check "Ballerina (bal)" "false" "not found — install from https://ballerina.io/downloads/"
fi

# python3
if command -v python3 &>/dev/null; then
  PY_VER=$(python3 --version 2>&1)
  check "Python 3" "true" "$PY_VER"
else
  check "Python 3" "false" "not found — required to run skill scripts"
fi

# PyYAML (needed for YAML→JSON conversion)
if python3 -c "import yaml" &>/dev/null 2>&1; then
  check "PyYAML" "true"
else
  check "PyYAML" "false" "not installed — run: pip install pyyaml  (or yq will be used as fallback)"
  # Not fatal — yq is a fallback
  FAILED=0
fi

if [ $FAILED -ne 0 ]; then
  echo ""
  echo "One or more required tools are missing. Please resolve the issues above before continuing." >&2
  exit 1
fi

echo ""
echo "Environment OK."
