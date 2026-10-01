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

# bal scan puts the rule's title in each result's message and a sentence in shortDescription; GitHub shows
# shortDescription as the alert heading, so the two are swapped while the message is still the generic title.
def titled($titles):
  ($titles[.id] // null) as $title
  | if $title and .fullDescription and $title != .shortDescription.text then
      .properties.sentence = .shortDescription.text | .shortDescription = {text: $title}
    else . end;

def enrich($titles):
  (.fullDescription.text // .shortDescription.text // .id) as $desc
  | .help //= {text: $desc, markdown: help_markdown($desc)}
  | titled($titles)
  | .fullDescription //= {text: $desc}
  | if .properties.ruleKind == "VULNERABILITY" then .properties.tags = (((.properties.tags // []) + ["security"]) | unique)
    elif .properties.ruleKind == "CODE_SMELL" then .properties.tags = (((.properties.tags // []) + ["maintainability"]) | unique)
    else . end;

. as $all
| ($all | map(.runs[0].results[]?)) as $results
| ($results | group_by(.ruleId) | map(select(map(.message.text) | unique | length == 1) | {key: .[0].ruleId, value: .[0].message.text}) | from_entries) as $titles
| ($all | map(.runs[0].tool.driver.rules[]?) | unique_by(.id) | map(enrich($titles))) as $rules
| ($rules | map({key: .id, value: .properties.sentence}) | from_entries) as $sentences
| {
    "$schema": $all[0]["$schema"],
    version: $all[0].version,
    runs: [{
      tool: ($all[0].runs[0].tool | .driver.rules = ($rules | map(del(.properties.sentence)))),
      results: ($results | map(
        .ruleId as $id
        | .ruleIndex = ([$rules[].id] | index($id))
        | if $sentences[$id] and .message.text == $titles[$id] then .message.text = $sentences[$id] else . end
      ))
    }]
  }
