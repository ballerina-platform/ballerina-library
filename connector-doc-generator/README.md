# Connector Doc Generator

Automatically generates Docusaurus documentation for Ballerina connectors using Claude AI.
Given a connector identity, it clones the source repo, calls Claude to read the code, and
produces `overview.md`, `setup-guide.md`, `action-reference.md`, and `trigger-reference.md`
ready to drop into the docs site.

---

## Prerequisites

- [Ballerina](https://ballerina.io/downloads/) 2201.13.x or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — `npm install -g @anthropic-ai/claude-code`
- `git` on PATH (used for shallow-cloning the connector source repo)
- Access to the `docs-integrator` repository (the target docs site)

---

## Setup

### 1. Copy the example config

```bash
cp Config.toml.example Config.toml
```

### 2. Fill in Config.toml

```toml
# Required
connectorName    = "HubSpot"
moduleSlug       = "hubspot"
packageName      = "ballerinax/hubspot"
githubRepo       = "module-ballerinax-hubspot"
category         = "crm-sales"

# Optional — auto-fetched from Ballerina Central if omitted
# connectorVersion = "3.0.0"

# Path to the docs-integrator repo root
docsRepoRoot     = "/path/to/docs-integrator"

# Set true to overwrite existing doc files
# force = false

# Set true to print what would happen without calling Claude
# dryRun = false
```

**Category options:**
`ai-ml` · `built-in` · `cloud-infrastructure` · `communication` · `crm-sales` ·
`database` · `developer-tools` · `ecommerce` · `erp-business` · `finance-accounting` ·
`healthcare` · `hrms` · `marketing-social` · `messaging` · `productivity-collaboration` ·
`security-identity` · `storage-file`

---

## Running

```bash
cd connector-doc-generator
bal run
```

Progress is printed to the terminal as Claude works through each phase.

### Dry run

Set `dryRun = true` in `Config.toml` to build the prompt and print what would happen
without cloning the repo or calling Claude.

### Update mode

If docs already exist at `docsRepoRoot/en/docs/connectors/catalog/<category>/<moduleSlug>/`,
the generator automatically runs in update mode — Claude reads the existing files and only
changes what differs from the current source code.

---

## Output

Generated files are written to:
```text
<docsRepoRoot>/en/docs/connectors/catalog/<category>/<moduleSlug>/
├── overview.md
├── setup-guide.md          (only if service-side setup steps exist)
├── action-reference.md
└── trigger-reference.md    (only if the connector has a Listener/Service)
```

Intermediate files (prompts and raw Claude responses) are saved to `./output/` for debugging.

`sidebars.ts` and `catalog/index.mdx` in the docs repo are patched automatically.

---

## Cost

Each run makes **2 + N** Claude API calls (N = number of client types in the connector):
- Phase 1 (Opus): overview, setup guide, trigger reference
- Phase 2a (Opus): client discovery
- Phase 2b × N (Sonnet, parallel): one section per client

A typical single-client connector costs ~$0.50–$1.00. A large connector like Salesforce
(5 clients) costs ~$2.00–$3.00.
