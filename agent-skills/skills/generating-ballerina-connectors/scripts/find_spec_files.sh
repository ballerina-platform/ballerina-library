#!/usr/bin/env bash
# Prints a newline-separated list of candidate OpenAPI spec files found in CWD.
# Priority: openapi.yaml/yml/json first, then docs/spec/, then any *.yaml/json (max 8 results).

CWD=$(pwd)

find_named() {
  find "$CWD" -maxdepth 4 \( -name "openapi.yaml" -o -name "openapi.yml" -o -name "openapi.json" \) \
    ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*"
}

find_docs_spec() {
  find "$CWD/docs/spec" -maxdepth 2 \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) 2>/dev/null \
    ! -path "*/.git/*"
}

find_any() {
  find "$CWD" -maxdepth 3 \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) \
    ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/.claude/*"
}

{ find_named; find_docs_spec; find_any; } | awk '!seen[$0]++' | head -8
