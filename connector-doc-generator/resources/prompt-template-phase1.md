# Task: Generate Connector Documentation — Phase 1 of 2

You are generating Docusaurus-ready documentation for the **{{name}}** Ballerina connector.
This is **Phase 1**: generate the overview, setup guide, and trigger reference.
The action reference will be generated separately in Phase 2.

---

## Connector Identity (pre-filled — do not change these values)

- **Name:** {{name}}
- **Module slug:** {{module}}
- **Package:** {{packageName}}
- **Version:** {{version}}
- **GitHub Repo:** https://github.com/ballerina-platform/{{githubRepo}}
- **Category slug:** {{category}}
- **Category label:** {{categoryLabel}}

---

## Research Instructions

The connector source code is cloned at `{{localRepoPath}}`. Use the `Read`, `Glob`, and `Grep` tools to explore it — no web browsing required.

1. Explore `{{localRepoPath}}`:
   - Use Glob (e.g. `{{localRepoPath}}/**/*.bal`) to list all source files
   - Identify all public **client types** and their config records from `.bal` source files
   - **Exclude Caller types** — these are only used inside listener/service callbacks and must NOT appear in the clients list
   - Check whether the connector exposes a **Listener** type and/or a **Service** type (set `has_triggers = true` if it does, `false` otherwise)
   - Read the **`examples/`** folder for real-world usage patterns
   - Read **`{{localRepoPath}}/ballerina/README.md`**, **`{{localRepoPath}}/ballerina/module.md`**, or **`{{localRepoPath}}/ballerina/Package.md`** (whichever exists) — note every image reference (`![alt](url)`) associated with each setup step so they can be included verbatim in `setup-guide.md`
2. If the connector ships as multiple Ballerina packages (subdirectories under `{{localRepoPath}}`), document all of them; otherwise treat it as a single package

---

## Files to Generate

### 1. `overview.md` (required)

```markdown
---
connector: true
connector_name: "{{module}}"
title: "{{name}}"
description: "Overview of the {{packageName}} connector for WSO2 Integrator."
---

{2-3 sentence narrative describing what the connector does and what service it integrates with}

## Key Features

{List 4-8 bullet strings — each is a short feature phrase}
- {Feature 1}
- {Feature 2}

## Actions

{1-2 sentence intro for the Actions section}

| Client | Actions |
|--------|---------|
| `ClientName` | {comma-separated list of capability areas} |

{Only include clients that users instantiate directly — do NOT include Caller types (used only inside listener/service callbacks)}

See the **[Action Reference](action-reference.md)** for the full list of operations, parameters, and sample code for each client.

## Triggers     {INCLUDE THIS SECTION ONLY IF has_triggers IS TRUE}

{1-2 sentence intro for the Triggers section}

Supported trigger events:

| Event | Callback | Description |
|-------|----------|-------------|
| {human-readable event name} | `{e.g. onCreate}` | {one sentence} |

See the **[Trigger Reference](trigger-reference.md)** for listener configuration, service callbacks, and the event payload structure.

## Documentation

* **[Setup Guide](setup-guide.md)**: {one sentence describing what the setup guide covers}   {INCLUDE ONLY IF setup steps exist}

* **[Action Reference](action-reference.md)**: Full reference for all clients — operations, parameters, return types, and sample code.

* **[Trigger Reference](trigger-reference.md)**: Reference for event-driven integration using the listener and service model.   {INCLUDE ONLY IF has_triggers IS TRUE}

## How to contribute

As an open source project, WSO2 welcomes contributions from the community.

To contribute to the code for this connector, please create a pull request in the following repository.

* [{{name}} Connector GitHub repository](https://github.com/ballerina-platform/{{githubRepo}})

Check the issue tracker for open issues that interest you. We look forward to receiving your contributions.
```

---

### 2. `setup-guide.md` (include only if there are service-side setup steps)

**Scope — external service configuration only.** The setup guide must describe only the steps to configure the **external service** (create accounts, generate API keys, set up credentials, configure service-side settings). Do NOT include any Ballerina-specific steps such as adding dependencies, writing code, running `bal` commands, or configuring the Ballerina client connection.

```markdown
---
connector: true
connector_name: "{{module}}"
title: "Setup Guide"
description: "How to set up and configure the {{packageName}} connector."
---

# Setup Guide

{1 sentence used as the setup-guide opening}

## Prerequisites

{One item per prerequisite — external service accounts or tools only}
- {Prerequisite 1}
- {Prerequisite 2}

## {Step Title — no "Step N:" prefix}

{service-side steps only — no Ballerina code or bal commands}

![{alt text}](/img/connectors/catalog/{{category}}/{{module}}/{filename})   {INCLUDE ONLY IF the source README has an image for this step}

:::note
{Optional admonition — plain prose content; type can be note, tip, or warning}
:::

## {Step Title 2}

{Body}

![{alt text}](/img/connectors/catalog/{{category}}/{{module}}/{filename})   {INCLUDE ONLY IF the source README has an image for this step}

## Next steps

- [Action Reference](action-reference.md) - Available operations
- [Trigger Reference](trigger-reference.md) - Event-driven integration   {INCLUDE ONLY IF has_triggers IS TRUE}
```

---

### 3. `trigger-reference.md` (include ONLY if has_triggers is true)

```markdown
---
connector: true
connector_name: "{{module}}"
---

# Triggers

{1-2 sentence intro}

Three components work together:

| Component | Role |
|-----------|------|
| `{{module}}:Listener` | {role description} |
| `{{module}}:Service` | {role description} |
| `{{module}}:Caller` | {role description — omit this row if there is no Caller type} |

For action-based operations, see the [Action Reference](action-reference.md).

---

## Listener

The `{{module}}:Listener` establishes the connection and manages event subscriptions.

### Configuration

The listener supports the following connection strategies:

| Config Type | Description |
|-------------|-------------|
| `ConfigType` | {description} |

**`ConfigType` fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `fieldName` | <code>FieldType</code> | Required | {description} |

### Initializing the listener

{ballerina listener init block — use real examples from the repo's examples/ folder}

**{Example title}:**

```ballerina
{listener init code}
```

---

## Service

{intro}

### Callbacks

{full remote function signatures exactly as defined in the connector source}

| Callback | Signature | Description |
|----------|-----------|-------------|
| `onEvent` | `remote function onEvent(...) returns error?` | {description} |

{First note — appears after callback table}

### Full example

{complete ballerina service block — use real examples from the repo's examples/ folder}

```ballerina
{complete service block}
```

{Second note — optional, appears after full example}

## Supporting Types

### {TypeName}

| Field | Type | Description |
|-------|------|-------------|
| `field` | `TypeName` | {description} |
```

{{updateModeNote}}

---

## Formatting Conventions

| Pattern | Rule |
|---------|------|
| Type values in tables | Wrap in `<code>TypeName</code>` — NOT backticks — to prevent MDX from parsing `<`, `>` as JSX |
| Required config field defaults | Use the literal string `Required` (no code wrapping) |
| Optional config field defaults | Wrap in `<code>defaultValue</code>` |
| Pipe chars in table cells | Use `&#124;` instead of `\|` |
| Curly braces in table cells | Use `&#123;` and `&#125;` |
| Images in setup-guide.md | Reference images as `/img/connectors/catalog/{category}/{module}/{filename}` — do NOT use the GitHub URL in the markdown; it will be downloaded and stored locally |

---

## Pre-output Checklist

Before returning, verify that your response contains all required elements:

- [ ] `<file name="overview.md">` with description, features (4-8), actions table, documentation links
- [ ] `<file name="setup-guide.md">` *(only if there are service-side setup steps)*
- [ ] `<file name="trigger-reference.md">` *(only if `has_triggers` is true)*
- [ ] `<category_entry>` JSON block
- [ ] `<images>` JSON array *(only if setup-guide.md uses images — list every image with its source URL and filename)*
- [ ] No Caller types in the overview clients table
- [ ] **No** `<file name="action-reference.md">` — that is generated in Phase 2

---

## Output Format

Return **only** the XML-tagged file blocks and the JSON blocks — no prose outside the tags.

```
<file name="overview.md">
...markdown content...
</file>

<file name="setup-guide.md">
...markdown content... (only if service-side setup steps exist)
</file>

<file name="trigger-reference.md">
...markdown content... (only if has_triggers is true)
</file>

<category_entry>
{"description": "one-line connector description for the catalog index table", "operations": "Create, Read, Update, Delete", "auth": "OAuth 2.0"}
</category_entry>

<images>
[
  {"url": "https://raw.githubusercontent.com/...", "filename": "step1-create-app.png"},
  {"url": "https://raw.githubusercontent.com/...", "filename": "step2-get-token.png"}
]
</images>
```

Rules:
- Include `setup-guide.md` only if there are meaningful service-side setup steps
- Include `trigger-reference.md` only if the connector exposes a Listener/Service
- The `category_entry` JSON must have exactly three keys: `description`, `operations`, `auth`
- `operations` — short comma-separated list, e.g. `"Create, Read, Update"`
- `auth` — e.g. `"OAuth 2.0"`, `"API Key"`, or `"None"` for built-in connectors
- Include `<images>` only if `setup-guide.md` references images; omit it entirely if there are no images
- Each entry in `<images>` must have `url` (the original GitHub raw URL from the source README) and `filename` (just the file name, e.g. `step1.png` — no path prefix)
- In `setup-guide.md`, image paths must be `/img/connectors/catalog/{{category}}/{{module}}/{filename}` — never the raw GitHub URL
- Do NOT include `action-reference.md` — it will be generated in Phase 2
- Do NOT include any markdown fences around the outer XML block
- Start immediately with `<file name="overview.md">`
