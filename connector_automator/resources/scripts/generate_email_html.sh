#!/bin/bash
# Generates the HTML email body from connector_prs.json and optional malformed specs.
# Usage: generate_email_html.sh <connector_prs_file> <malformed_specs_json> <email_body_file> <table_rows_file>
# Writes email_subject, email_date, total_connectors to $GITHUB_OUTPUT.
set -e

CONNECTOR_PRS_FILE="${1:-connector_prs.json}"
MALFORMED_SPECS_JSON="${2:-null}"
EMAIL_BODY_FILE="${3:-email_body.html}"
TABLE_ROWS_FILE="${4:-email_table_rows.html}"

echo "$MALFORMED_SPECS_JSON" > /tmp/malformed.json

MALFORMED_SECTION=""
MALFORMED_COUNT=$(jq 'if . == null then 0 else length end' /tmp/malformed.json)
if [ "$MALFORMED_COUNT" -gt 0 ]; then
    MALFORMED_ROWS=""
    while IFS= read -r item; do
        NAME=$(echo "$item" | jq -r '.name')
        VERSION=$(echo "$item" | jq -r '.version')
        REASON=$(echo "$item" | jq -r '.reason')
        MALFORMED_ROWS="${MALFORMED_ROWS}<tr><td><strong>${NAME}</strong></td><td><code>${VERSION}</code></td><td>${REASON}</td></tr>"
    done < <(jq -c '.[]' /tmp/malformed.json)

    MALFORMED_SECTION='<div class="malformed-box">
      <h3>Malformed Specs Detected</h3>
      <p>The following specs were found via heuristic fallback but were rejected by the Swagger parser — connectors were <strong>NOT</strong> generated for these:</p>
      <table>
        <thead><tr><th>Spec Name</th><th>Version</th><th>Rejection Reason</th></tr></thead>
        <tbody>'"${MALFORMED_ROWS}"'</tbody>
      </table>
    </div>'
fi

TABLE_ROWS=$(cat "$CONNECTOR_PRS_FILE" | jq -r '.[] |
    "<tr>" +
    "<td>" + .connectorName + "</td>" +
    "<td><code>" + .specification + "</code></td>" +
    "<td><code>" + .openapiVersion + "</code></td>" +
    "<td><code>" + (.expectedVersion // "N/A") + "</code></td>" +
    "<td><span class=\"change-" + (.changeType | ascii_downcase) + "\">" + (if .changeType == "NONE" then "No Version Change" elif .changeType == "UNKNOWN" then "Unknown" else .changeType end) + "</span></td>" +
    "<td>" + (if .buildStatus == "FAILED" or .buildStatus == "Workflow Failed" then "<span class=\"status-failed\">FAILED</span>" elif .buildStatus == "Partial" then "<span class=\"status-partial\">Partial</span>" elif .buildStatus == "Up to date" then "<span class=\"status-uptodate\">Up to date</span>" elif .buildStatus == "In Progress" then "In Progress" else "<span class=\"status-success\">Success</span>" end) + "</td>" +
    "<td>" + (if .pr.number > 0 then (if .doNotMerge == "true" then "<span class=\"do-not-merge\">DO NOT MERGE</span>" else "" end) + "<a href=\"" + .pr.url + "\">#" + (.pr.number | tostring) + "</a>" else "Not Created" end) + "</td>" +
    "<td>" + (.codeOwners // "N/A") + "</td>" +
    "</tr>"
')

echo "$TABLE_ROWS" > "$TABLE_ROWS_FILE"

CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_DATETIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
TOTAL_CONNECTORS=$(jq 'length' "$CONNECTOR_PRS_FILE")

echo "email_subject=Daily Connector Updates Summary - ${CURRENT_DATE}" >> "$GITHUB_OUTPUT"
echo "email_date=${CURRENT_DATETIME}" >> "$GITHUB_OUTPUT"
echo "total_connectors=${TOTAL_CONNECTORS}" >> "$GITHUB_OUTPUT"

cat > "$EMAIL_BODY_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; line-height: 1.6; color: #24292e; max-width: 1400px; margin: 0 auto; padding: 20px; }
    .header { border-bottom: 3px solid #0366d6; padding-bottom: 20px; margin-bottom: 30px; }
    .header h1 { margin: 0; color: #0366d6; font-size: 24px; }
    .header .date { color: #586069; font-size: 14px; margin-top: 5px; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); font-size: 12px; }
    th { background: #f6f8fa; border: 1px solid #d1d5da; padding: 10px 8px; text-align: left; font-weight: 600; color: #24292e; font-size: 13px; }
    td { border: 1px solid #d1d5da; padding: 10px 8px; font-size: 12px; }
    tr:hover { background: #f6f8fa; }
    .status-success { color: #28a745; font-weight: 600; }
    .status-failed { color: #d73a49; font-weight: 600; }
    .status-partial { color: #e36209; font-weight: 600; }
    .status-uptodate { color: #0366d6; font-weight: 600; }
    .do-not-merge { background: #d73a49; color: white; padding: 1px 5px; border-radius: 3px; font-size: 10px; font-weight: 600; margin-right: 4px; }
    .change-major { background: #d73a49; color: white; padding: 2px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; }
    .change-minor { background: #0366d6; color: white; padding: 2px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; }
    .change-patch { background: #28a745; color: white; padding: 2px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; }
    .change-none { background: #0366d6; color: white; padding: 2px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; }
    .change-failed, .change-pending, .change-unknown { background: #6c757d; color: white; padding: 2px 8px; border-radius: 3px; font-size: 11px; font-weight: 600; }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #d1d5da; color: #586069; font-size: 12px; }
    .summary-box { background: #f6f8fa; border: 1px solid #d1d5da; border-radius: 6px; padding: 15px; margin: 20px 0; }
    .summary-box h3 { margin: 0 0 10px 0; font-size: 16px; }
    .malformed-box { background: #fff8e1; border: 1px solid #f0ad4e; border-radius: 6px; padding: 15px; margin: 20px 0; }
    .malformed-box h3 { margin: 0 0 10px 0; font-size: 16px; color: #856404; }
  </style>
</head>
<body>
  <div class="header">
    <h1>Daily Connector Updates Summary</h1>
    <div class="date">Generated: ${CURRENT_DATETIME}</div>
  </div>
  <div class="summary-box">
    <h3>Summary</h3>
    <p>Total connectors updated: <strong>${TOTAL_CONNECTORS}</strong></p>
  </div>
  <table>
    <thead>
      <tr>
        <th>Connector</th>
        <th>Specification</th>
        <th>OpenAPI Version</th>
        <th>Expected Connector Version</th>
        <th>Change Type</th>
        <th>Build Status</th>
        <th>Pull Request</th>
        <th>Code Owners</th>
      </tr>
    </thead>
    <tbody>
${TABLE_ROWS}
    </tbody>
  </table>
${MALFORMED_SECTION}
  <div class="footer">
    <p>This is an automated message from the OpenAPI Dependabot system.</p>
    <p>For questions or issues, please contact the Ballerina team.</p>
  </div>
</body>
</html>
EOF

echo "Generated email body: $EMAIL_BODY_FILE"
