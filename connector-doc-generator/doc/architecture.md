# Connector Doc Generator — Architecture

## Overview

The generator runs a 7-step pipeline that derives connector metadata from its repository,
clones the connector source, calls Claude in
multiple focused phases, and writes Docusaurus-ready markdown to the docs repository.

```
[1/7] Read metadata        — bootstrap clone + Ballerina.toml ([package].org and name)
[2/7] Resolve version      — Ballerina Central API or Config.toml
[3/7] Check existing docs  — Determines fresh generation vs update mode
[4/7] Clone source repo    — git clone --depth 1 --branch v<version>
[5a/7] Phase 1             — overview.md, setup-guide.md, trigger-reference.md
[5b/7] Phase 2a            — action-reference header + client discovery
[5c/7] Phase 2b            — per-client sections, all clients run in parallel
[6/7] Write files          — write to docs repo (skip if force=false and file exists)
[7/7] Patch sidebar        — sidebars.ts + catalog/index.mdx
```

---

## Module Structure

```
connector-doc-generator/
├── main.bal              — Pipeline orchestration
├── config.bal            — Configurable variables (reads Config.toml)
├── resources/
│   ├── prompt-template-phase1.md    — Phase 1 prompt template
│   ├── prompt-template-phase2a.md   — Phase 2a prompt template
│   └── prompt-template-phase2b.md   — Phase 2b prompt template
└── modules/
    ├── claude/    — Claude Code CLI invocation
    ├── central/   — Ballerina Central version fetch
    ├── prompts/   — Prompt building + variable substitution
    ├── extractor/ — Response parsing (XML tags → files map)
    ├── sidebar/   — sidebars.ts patcher
    └── category/  — catalog/index.mdx patcher
```

---

## Phase Design

### Why three phases?

Large connectors (e.g. Salesforce) have 5+ client types with 50+ operations each.
A single Claude call cannot generate the full action reference without hitting output
token limits. Every phase uses the configured `aiModel`, with a phase-specific turn budget.

| Phase | Model | Max turns | Purpose |
|-------|-------|-----------|---------|
| 1 | Configured `aiModel` | 15 | Overview, setup guide, trigger reference |
| 2a | Configured `aiModel` | 8 | Discover all client types + write action-reference header |
| 2b × N | Configured `aiModel` | 15 | One section per client — all run in parallel |

Phase 2b runs N concurrent `claude -p` processes (Ballerina `start`/`wait`). Results are
collected in client-list order so the assembled `action-reference.md` is stable.

### Phase 1 → Phase 2 context

Phase 1 produces `overview.md`. Its content is passed verbatim to phases 2a and 2b as
`{{phase1Overview}}` so Claude understands the connector structure without re-reading it.

---

## Source Repository

The user supplies the repository name and category. The generator first shallow-clones the
repository default branch to read `[package].org` and `[package].name` from `Ballerina.toml`
(at the repository root or in the `ballerina` directory). It derives the package name,
module slug, and connector name from that metadata.

It then shallow-clones the connector repo at the exact version tag (`v<version>`) before any
Claude calls:

```
git clone --depth 1 --branch v8.6.0 https://github.com/ballerina-platform/<repo> /tmp/conn_doc_<slug>_<ts>
```

Claude is given `Read`, `Glob`, `Grep`, and `WebFetch` tools. Local reads are fast (no
network per file); `WebFetch` is available for supplementary web lookups if needed.

The cloned directory is deleted after all phases complete.

---

## Update Mode

If `docsRepoRoot/en/docs/connectors/catalog/<category>/<moduleSlug>/` already exists,
the generator runs in update mode. Instead of embedding existing file content in the
prompt (expensive), it passes only the directory path:

```
Existing docs are at: `/path/to/docs/.../salesforce/`
Relevant files to read first:
- `/path/to/docs/.../salesforce/overview.md`
- ...
```

Claude reads the existing files using the `Read` tool and updates only what has changed.
This avoids embedding ~40KB of existing markdown into every prompt.

---

## Response Parsing (`extractor` module)

Claude wraps each output file in XML tags:

```xml
<file name="overview.md">
...markdown...
</file>

<category_entry>
{"description": "...", "operations": "Create, Read", "auth": "OAuth 2.0"}
</category_entry>
```

Phase 2a output uses:
```xml
<action_header>...frontmatter + clients table...</action_header>
<clients>[{"package": "...", "clientType": "...", "displayName": "..."}]</clients>
```

Phase 2b output uses:
```xml
<client_section>## Client Name...full section...</client_section>
```

The extractor handles graceful truncation: if a closing tag is missing (Claude hit the
output limit), the partial content is saved and a `__truncated__` marker is set.

---

## Token Counting

The generator uses `--output-format stream-json --verbose` to capture per-call stats.

- **model** — read from the `system` init event (accurate resolved model name)
- **input tokens** — sum of `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` from the `result` event usage
- **output tokens** — `output_tokens` from the `result` event usage
- **cost** — `total_cost_usd` from the `result` event

Running totals are accumulated across all calls and printed in the Done summary.

---

## Sidebar + Catalog Patching

### `sidebar` module

Finds the `"Connector Catalog"` label in `sidebars.ts`, locates the correct category
block using bracket counting, then inserts the connector alphabetically. Skips if the
connector already exists.

### `category` module

Finds the category heading (e.g. `### CRM & Sales`) in `catalog/index.mdx`, locates
the markdown table below it, and inserts a new row alphabetically. Skips if already present.
