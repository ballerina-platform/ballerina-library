# Task: Generate Action Reference — Phase 2b: Client Section

You are generating the complete documentation section for **one client** of the **{{name}}** Ballerina connector.

**Client to document:**
- **Package:** `{{clientPackage}}`
- **Client type:** `{{clientType}}`
- **Display name:** {{clientDisplayName}}

---

## Connector Identity (pre-filled — do not change these values)

- **Name:** {{name}}
- **Module slug:** {{module}}
- **Package:** {{packageName}}
- **Version:** {{version}}
- **GitHub Repo:** https://github.com/ballerina-platform/{{githubRepo}}

---

## Phase 1 Context

The following `overview.md` was already generated. Use it to understand the connector's overall structure:

```markdown
{{phase1Overview}}
```

---

## Research Instructions

The connector source code is cloned at `{{localRepoPath}}`. Use the `Read`, `Glob`, and `Grep` tools to explore it — no web browsing required.

1. Explore `{{localRepoPath}}` for the `{{clientType}}` client:
   - Use Glob to find source files for the `{{clientPackage}}` package (look for a subdirectory matching the sub-module name, e.g. `salesforce.bulk` → `ballerina/salesforce.bulk/`)
   - Find the `{{clientType}}` type and its config record — read the source file directly
   - Find **ALL** public remote functions and resource functions. **Read source code doc comments directly — do NOT guess or paraphrase**
   - Read the **`examples/`** folder for real-world usage patterns; use this code as the basis for sample_code snippets
2. **Document every operation** — do not skip or summarise operations to save space; this is an exhaustive reference
3. For each operation that returns data (records, maps, arrays, primitives), a **sample_response is required** — only omit it for `error?` or `()` (void) returns

---

## Section to Generate

Generate the complete `## {{clientDisplayName}}` section:

```markdown
## {{clientDisplayName}}

{One sentence client purpose}

### Configuration

{config_name: e.g. ConnectionConfig, OAuth2RefreshTokenGrantConfig}

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `fieldName` | <code>FieldType</code> | Required | {description} |
| `optionalField` | <code>string</code> | <code>"defaultValue"</code> | {description} |

{Default column rules:
  - Required fields → use the literal string "Required" (no code wrapping)
  - Optional fields with a default → wrap in <code>defaultValue</code>
  - Type column: always wrap in <code>TypeName</code> to prevent MDX parsing issues}

### Initializing the client

```ballerina
import {{clientPackage}};

{ConfigType} config = {
    {requiredField}: "{value}"
};
{moduleAlias}:{{clientType}} client = check new (config);
```

### Operations

#### {Operation Group Name — e.g. "Record CRUD", "Query Operations"}

<details>
<summary>{operation name}</summary>

<div>

**Signature:** `{httpMethod} /resource/path/[pathParam]`
{INCLUDE ONLY for resource functions. Omit this line entirely for remote functions.}

{One paragraph description}

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `paramName` | <code>ParamType</code> | Yes | {description} |

**Returns:** `ReturnType|error`

**Sample code:**

```ballerina
ReturnType result = check client->{functionName}({params});
```

**Sample response:**

```json
{
  "field": "value"
}
```

</div>
</details>
```

{{updateModeNote}}

---

## Formatting Conventions

| Pattern | Rule |
|---------|------|
| Type values in tables | Wrap in `<code>TypeName</code>` — NOT backticks |
| Required config field defaults | Use the literal string `Required` (no code wrapping) |
| Optional config field defaults | Wrap in `<code>defaultValue</code>` |
| `returns` / **Returns** field | Type expression only, e.g. `record {}&#124;error` |
| Sample code | Operation call and result assignment only — do NOT include `io:println()` |
| Sample response | Required for any operation returning data; omit only for `error?` or `()` |
| Operations | Each operation appears **exactly once** |
| Operation name (remote) | Exact function name (e.g. `send`, `query`) |
| Operation name (resource) | Short description from source code doc comment — NOT Ballerina Central |
| Operation signature | Resource functions: `get /path/[param]`; omit for remote functions |
| Pipe chars in table cells | Use `&#124;` instead of `\|` |
| Curly braces in table cells | Use `&#123;` and `&#125;` |

---

## Pre-output Checklist

- [ ] `<client_section>` contains the `## {{clientDisplayName}}` section
- [ ] Configuration table covers all config record fields
- [ ] Every operation for `{{clientType}}` is documented
- [ ] Every data-returning operation has a sample_response
- [ ] No `io:println()` in any sample_code
- [ ] Operation names sourced from source code doc comments, not Ballerina Central

---

## Output Format

Return **only** the client section block — no prose outside the tags.

```
<client_section>
## {{clientDisplayName}}
...complete section...
</client_section>
```

Rules:
- Output ONLY the `<client_section>` block
- Do NOT include frontmatter, `# Actions` heading, or the clients table — those are already in the header
- Start immediately with `<client_section>`
