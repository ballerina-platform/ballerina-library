# Task: Generate Action Reference — Phase 2a: Discovery and Header

You are generating the **header section** of the action reference for the **{{name}}** Ballerina connector.
Do NOT generate any client sections — those will be generated separately in Phase 2b.

---

## Connector Identity (pre-filled — do not change these values)

- **Name:** {{name}}
- **Module slug:** {{module}}
- **Package:** {{packageName}}
- **Version:** {{version}}
- **GitHub Repo:** https://github.com/ballerina-platform/{{githubRepo}}
- **Category slug:** {{category}}

---

## Phase 1 Context

The following `overview.md` was already generated. Use it to understand the connector's package structure and client list:

```markdown
{{phase1Overview}}
```

---

## Research Instructions

The connector source code is cloned at `{{localRepoPath}}`. Use the `Read`, `Glob`, and `Grep` tools to explore it — no web browsing required.

1. Explore `{{localRepoPath}}`:
   - Use Glob to list `.bal` files and confirm whether the connector spans one or multiple Ballerina packages
   - Identify all public **client types** and their one-line purpose
   - **Exclude Caller types** — these are only used inside listener/service callbacks
   - Note whether the connector has a Listener/Service (for the trigger reference link)

---

## Output Instructions

Generate exactly two output blocks:

### 1. `<action_header>` — the intro section of action-reference.md

Everything before the first `## ClientName` section:

```markdown
<action_header>
---
connector: true
connector_name: "{{module}}"
toc_max_heading_level: 4
---

# Actions

{If single package: "The `ballerinax/{{module}}` package exposes the following clients:"}
{If multiple packages:
"The {{name}} connector spans {N} packages:
- `ballerinax/{{module}}`
- `ballerinax/{{module}}.sub`
"}

Available clients:

| Client | Purpose |
|--------|---------|
| [`DisplayName`](#anchor) | {one sentence purpose} |

{INCLUDE IF has_triggers: "For event-driven integration, see the [Trigger Reference](trigger-reference.md)."}

---
</action_header>
```

### 2. `<clients>` — JSON array of all clients to document in Phase 2b

```json
<clients>
[
  {
    "package": "ballerinax/{{module}}",
    "clientType": "{{module}}:ClientTypeName",
    "displayName": "Display Name"
  }
]
</clients>
```

**`displayName` rules:** strip the module prefix and split CamelCase with spaces:
- `salesforce:Client` → `"Client"`
- `nats:JetStreamClient` → `"JetStream Client"`
- `salesforce.apex:Client` → `"Apex Client"`

**Rules:**
- Do NOT include Caller types
- Do NOT generate any `## ClientName` sections — those are Phase 2b
- Start immediately with `<action_header>`
