# Merges bal scan SARIF files (slurped) into a single run and fills in what GitHub code scanning renders.

def owasp_2025: {
  "A01": "Broken Access Control",
  "A02": "Security Misconfiguration",
  "A03": "Software Supply Chain Failures",
  "A04": "Cryptographic Failures",
  "A05": "Injection",
  "A06": "Insecure Design",
  "A07": "Authentication Failures",
  "A08": "Software or Data Integrity Failures",
  "A09": "Security Logging and Alerting Failures",
  "A10": "Mishandling of Exceptional Conditions"
};

def rule_kinds: {"VULNERABILITY": "Vulnerability", "CODE_SMELL": "Code smell", "BUG": "Bug"};

def cwe_links:
  [.properties.tags[]? | capture("^external/cwe/cwe-0*(?<id>[0-9]+)$")
    | "[CWE-\(.id)](https://cwe.mitre.org/data/definitions/\(.id).html)"];

def owasp_links:
  [.properties.tags[]? | capture("^external/owasp/owasp-(?<cat>a[0-9]{2})-(?<year>[0-9]{4})$")
    | (.cat | ascii_upcase) as $cat
    | if .year == "2025" and owasp_2025[$cat] then
        "[\($cat):2025 – \(owasp_2025[$cat])](https://top10.owasp.org/2025/\($cat)_2025-\(owasp_2025[$cat] | gsub(" "; "_"))/)"
      else "\($cat):\(.year)" end];

def plain_tags: [.properties.tags[]? | select(startswith("external/") or . == "security" or . == "maintainability" | not) | "`\(.)`"];

def help_markdown($desc):
  ([
    $desc,
    "",
    "- **Rule:** `\(.id)`",
    (rule_kinds[.properties.ruleKind // ""] // empty | "- **Type:** \(.)"),
    (cwe_links | select(length > 0) | "- **CWE:** \(join(", "))"),
    (owasp_links | select(length > 0) | "- **OWASP Top 10:** \(join(", "))"),
    (plain_tags | select(length > 0) | "- **Tags:** \(join(" "))"),
    (.helpUri // empty | "", "[Rule documentation](\(.))")
  ] | join("\n"));

# bal scan up to 0.12.x reports the rule's title as every result's message, not one about the finding.
def generic_messages:
  (.semanticVersion // "" | capture("^(?<major>[0-9]+)\\.(?<minor>[0-9]+)") | [(.major | tonumber), (.minor | tonumber)] <= [0, 12])
  // false;

def enrich:
  (.fullDescription.text // .shortDescription.text // .id) as $desc
  | .help //= {text: $desc, markdown: help_markdown($desc)}
  | .fullDescription //= {text: $desc}
  | if .properties.ruleKind == "VULNERABILITY" then .properties.tags = (((.properties.tags // []) + ["security"]) | unique)
    elif .properties.ruleKind == "CODE_SMELL" then .properties.tags = (((.properties.tags // []) + ["maintainability"]) | unique)
    else . end;

. as $all
| ($all[0].runs[0].tool.driver | generic_messages) as $generic
| ($all | map(.runs[0].tool.driver.rules[]?) | unique_by(.id)) as $tool_rules
| ($tool_rules | map(select(.fullDescription.text) | {key: .id, value: .fullDescription.text}) | from_entries) as $descriptions
| ($tool_rules | map(enrich)) as $rules
| {
    "$schema": $all[0]["$schema"],
    version: $all[0].version,
    runs: [{
      tool: ($all[0].runs[0].tool | .driver.rules = $rules),
      results: ($all | map(.runs[0].results[]?) | map(
        .ruleId as $id
        | .ruleIndex = ([$rules[].id] | index($id))
        | if $generic and $descriptions[$id] then .message.text = $descriptions[$id] else . end
      ))
    }]
  }
