# Connector Doc Generator

Automatically generates Docusaurus documentation for Ballerina connectors using Claude AI.
Given a Ballerina connector repository and catalog category, it reads the connector metadata
from `Ballerina.toml`, clones the source repo, calls Claude to read the code, and
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

### 1. Optional: copy the example config

```bash
cp Config.toml.example Config.toml
```

### 2. Optional: fill in Config.toml

```toml
# Required. The repository is resolved under github.com/ballerina-platform.
# The package name, module slug, and connector name come from Ballerina.toml.
githubRepo       = "module-ballerinax-hubspot"
category         = "crm-sales"

# Optional — auto-fetched from Ballerina Central if omitted
# connectorVersion = "3.0.0"

# Path to the docs-integrator repo root
docsRepoRoot     = "/path/to/docs-integrator"

# Set true to overwrite existing doc files
# force = false
# generateOverviewSetup = true
# generateReference = true
# aiModel = "sonnet-4-6"

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

Run with the two required connector values as Ballerina CLI configurables:

```bash
cd connector-doc-generator
bal run -- \
  -CgithubRepo=module-ballerinax-hubspot \
  -Ccategory=crm-sales
```

`-C` values override values in `Config.toml`. Optional values not supplied on the CLI use
their `config.bal` defaults, or values from `Config.toml` when present. For example:

```bash
bal run -- \
  -CgithubRepo=module-ballerinax-hubspot \
  -Ccategory=crm-sales \
  -CdocsRepoRoot=/path/to/docs-integrator \
  -CdryRun=true
```

Progress is printed to the terminal as Claude works through each phase.

### Select documentation stages

The generator keeps its existing two-phase architecture while allowing the dispatcher to
select the published stages:

```bash
bal run -- \
  -CgithubRepo=module-ballerinax-hubspot \
  -Ccategory=crm-sales \
  -CdocsRepoRoot=/path/to/docs-integrator \
  -CgenerateOverviewSetup=true \
  -CgenerateReference=false
```

- `generateOverviewSetup=true` publishes the complete Phase 1 output bundle. This keeps
  `overview.md`, an applicable `setup-guide.md`, and an applicable `trigger-reference.md`
  coupled exactly as they are today.
- `generateReference=true` publishes `action-reference.md`. Phase 1 still runs once to
  provide context to the action-reference phase.
- When Overview & Setup Guide is unselected, an existing `overview.md` must already be
  present in the target docs directory. The generator fails before generation if that
  navigation anchor is missing.
- At least one connector-document stage must be enabled.

### Dry run

Set `dryRun = true` in `Config.toml`, or pass `-CdryRun=true`, to build the prompt and print
what would happen without cloning the versioned source repo or calling Claude. A short bootstrap
clone is still used to read `Ballerina.toml` and derive the connector metadata.

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
- Phase 1 (selected model): overview, setup guide, trigger reference
- Phase 2a (selected model): client discovery
- Phase 2b × N (selected model, parallel): one section per client

A typical single-client connector costs ~$0.50–$1.00. A large connector like Salesforce
(5 clients) costs ~$2.00–$3.00.

---

## Combined GitHub Actions dispatcher

The `Generate Connector Documentation` workflow coordinates connector documents and example
documents in parallel. Its manual inputs select Overview & Setup Guide, Action Reference, and
Examples independently. The `connector`/`trigger` mode input is passed only to the example
generator; it never suppresses the connector-document job.

The workflow creates one run-specific branch in `wso2/docs-integrator`, integrates the selected
outputs sequentially with guarded pushes, validates generated paths, attempts one rendered preview
per changed page, creates one PR, and requests eligible source-repository CODEOWNERS. Example mode
expects six workflow screenshots for connector examples and seven for trigger examples.
