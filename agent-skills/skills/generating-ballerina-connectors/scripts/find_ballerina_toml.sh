#!/usr/bin/env bash
# Prints a newline-separated list of directories (relative to CWD) that already
# contain a Ballerina.toml, found downstream from CWD. Used to recommend
# BALLERINA_DIR when the connector workspace is an existing Ballerina package
# nested below the repo root (e.g. ballerina-library modules keep the package
# under a `ballerina/` subdirectory, separate from `docs/`, `examples/`, etc.)

CWD=$(pwd)

find "$CWD" -maxdepth 4 -name "Ballerina.toml" \
  ! -path "*/.git/*" ! -path "*/target/*" ! -path "*/build/*" ! -path "*/node_modules/*" \
  ! -path "*/build-config/*" \
  -exec dirname {} \; \
  | sed "s|^$CWD\$|.|; s|^$CWD/|./|" \
  | awk '!seen[$0]++' \
  | head -5
