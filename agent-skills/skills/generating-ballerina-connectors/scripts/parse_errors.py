#!/usr/bin/env python3
"""
Parse Ballerina compilation errors from bal build stderr output.

Reads from stdin or a file path argument.
Output (stdout): JSON array of {fileName, line, col, message, errorType}

Matches lines of the form (range format, Ballerina 2201.x):
  ERROR [<file>:(<startLine>:<startCol>,<endLine>:<endCol>)] <message>
and the older single-position format:
  ERROR [<file>:(<line>,<col>)] <message>
"""

import sys
import json
import re

# Range format: [file:(18:40,18:52)] — capture the start position
RANGE_PATTERN = re.compile(
    r"^(ERROR|WARNING)\s+\[([^\]]+):\((\d+):(\d+),\d+:\d+\)\]\s+(.+)$",
    re.MULTILINE,
)

# Older single-position format: [file:(18,40)]
POSITION_PATTERN = re.compile(
    r"^(ERROR|WARNING)\s+\[([^\]]+):\((\d+),(\d+)\)\]\s+(.+)$",
    re.MULTILINE,
)

# Also catch plain "error:" lines for summary detection
PLAIN_ERROR = re.compile(r"^\s*error:", re.MULTILINE | re.IGNORECASE)


def parse(text: str) -> list:
    errors = []
    for pattern in (RANGE_PATTERN, POSITION_PATTERN):
        for m in pattern.finditer(text):
            error_type, file_name, line, col, message = m.groups()
            errors.append({
                "errorType": error_type,
                "fileName": file_name.strip(),
                "line": int(line),
                "col": int(col),
                "message": message.strip(),
            })
        if errors:
            break
    return errors


if __name__ == "__main__":
    if len(sys.argv) == 2:
        text = open(sys.argv[1], "r", encoding="utf-8").read()
    else:
        text = sys.stdin.read()

    errors = parse(text)
    print(json.dumps(errors, indent=2))
    if not errors and PLAIN_ERROR.search(text):
        # Unparsed errors exist — emit the raw lines so the agent sees them
        sys.stderr.write("WARNING: Some errors could not be parsed into structured form.\n")
        sys.exit(2)
