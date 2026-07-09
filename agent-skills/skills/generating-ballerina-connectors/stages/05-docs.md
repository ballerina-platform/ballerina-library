# Stage 05 — Documentation

Generate README files and Ballerina Central publishing documentation.

Skip this stage if `docs` is in `EXCLUDED_STAGES`.

---

## Placeholder mapping

All templates use `{{PLACEHOLDER}}` variables. Resolve them from shared state before filling any template:

| Template placeholder | Source |
|----------------------|--------|
| `{{MODULE_NAME_PC}}` | `BAL_PACKAGE` in PascalCase — convert underscores to title case (e.g. `sharepoint_admin` → `SharepointAdmin`) |
| `{{MODULE_NAME_CC}}` | `BAL_PACKAGE` as-is (already snake_case) |
| `{{REPO_NAME}}` | `ballerina-platform/module-ballerinax-<BAL_PACKAGE with underscores replaced by dots>` (e.g. `ballerina-platform/module-ballerinax-sharepoint.admin`) |
| `{{MODULE_VERSION}}` | `TOML_META.version` (from `parse_ballerina_toml.py` output) |
| `{{BAL_VERSION}}` | `TOML_META.distribution` |

The `[//]: # (TODO: ...)` markers in each template are the sections the LLM must replace with generated content. All other structural content (badges, Build from source, Contributing, Useful links sections) must be copied verbatim from the template without modification.

---

## Step 1: Gather context

Collect the following (already in context from prior stages):
- `SPEC_METADATA`: title, version, description, paths, schemas, security schemes
- `BAL_ORG`, `BAL_PACKAGE`
- `TOML_META` (from `parse_ballerina_toml.py`) — if not already loaded, run:
  ```bash
  <PYTHON_CMD> <skill-root>/scripts/parse_ballerina_toml.py "<BALLERINA_DIR>/Ballerina.toml"
  ```
- `EXAMPLE_DIR` file list (from stage 04)
- `CLIENT_ANALYSIS.methods` (from stage 02/03)
- The exact `bal openapi` command run in Stage 02

Do **not** re-read the entire source files — use the structured metadata and file paths only.

---

## Step 2: Generate root README

Check if `<BALLERINA_DIR>/README.md` already exists:
- **Exists** → use it as the base. It may already have some or all `[//]: # (TODO: ...)` sections and `{{PLACEHOLDER}}` variables filled. Only replace what is still unfilled — do not overwrite content that is already present.
- **Absent** → read `<skill-root>/templates/readme_template.md` and proceed as below.

Replace all `{{PLACEHOLDER}}` variables using the mapping above.

Replace each `[//]: # (TODO: ...)` section with generated content:
- **Overview**: 3–5 sentences describing what the API does and what this connector enables. Derived from `SPEC_METADATA.description` and title.
- **Setup guide**: Numbered steps to obtain credentials and configure the connector. Derived from `SPEC_METADATA.securitySchemes` — list the required fields (API keys, OAuth tokens, etc.) and how to get them.
- **Quickstart**: One short Ballerina code snippet showing a single representative API call. Use a simple GET or list operation from `CLIENT_ANALYSIS.methods`. Include the `Config.toml` snippet needed.
- **Examples**: Bullet list of example names and one-line descriptions from `EXAMPLE_DIR` subdirectory names. Format: `[example-name](examples/example-name) — <one liner>`.

Copy all other sections (Build from source, Build options, Contribute, Code of conduct, Useful links) verbatim from the template.

Write to `<BALLERINA_DIR>/README.md`.

---

## Step 3: Generate Module.md (Ballerina Central)

Check if `<BALLERINA_DIR>/Module.md` already exists:
- **Exists** → use it as the base. Only replace sections that still contain unfilled `[//]: # (TODO: ...)` markers or unresolved `{{PLACEHOLDER}}` variables. Do not overwrite already-filled content.
- **Absent** → read `<skill-root>/templates/module_readme_template.md` and proceed as below.

Replace all `{{PLACEHOLDER}}` variables using the mapping above.

Replace each `[//]: # (TODO: ...)` section with generated content using the same content as Step 2 (Overview, Setup guide, Quickstart, Examples) — the module README mirrors the root README but is shorter (no build/contribute sections).

Write to `<BALLERINA_DIR>/Module.md`.

---

## Step 4: Generate sub-READMEs

### Tests README

Check if `<BALLERINA_DIR>/tests/README.md` already exists:
- **Exists** → use it as the base. Only fill in `AI_GENERATED_TESTING_APPROACH` if it still appears as the bare marker. Do not overwrite content that is already filled.
- **Absent** → read `<skill-root>/templates/tests_readme_template.md` and proceed as below.

Fill in `AI_GENERATED_TESTING_APPROACH` with a short description of what the test suite covers — derived from `CLIENT_ANALYSIS.methods` method names.

Write to `<BALLERINA_DIR>/tests/README.md`.

### Examples README

Check if `<EXAMPLE_DIR>/README.md` already exists:
- **Exists** → use it as the base. Update or add example table rows for any new examples added since the last run. Only replace `<angle-bracket>` placeholders that are still unfilled. Do not overwrite content that is already present.
- **Absent** → read `<skill-root>/templates/examples_readme_template.md` and proceed as below.

Fill in:
- `<BAL_ORG>/<BAL_PACKAGE>` → from shared state
- Example table rows — one row per subdirectory in `EXAMPLE_DIR`
- Auth field names from `SPEC_METADATA.securitySchemes`

Write to `<EXAMPLE_DIR>/README.md`.

### Per-example READMEs (generate if time permits)

For each example subdirectory that does not already have a `README.md`, read `<skill-root>/templates/example_readme_template.md` and fill in:
- `<EXAMPLE_TITLE>` → human-readable name from the directory kebab slug
- `AI_GENERATED_DESCRIPTION` → 2–3 sentences describing the use case

---

## Step 5: Generate sanitations.md

Read `<skill-root>/templates/sanitations_template.md`.

Replace `{{MODULE_NAME_PC}}` with the resolved value from the placeholder mapping.

Fill in the TODO sections:
- `_Author_` → leave blank (to be filled by the developer)
- `_Created_` → today's date in `YYYY/MM/DD` format
- `_Updated_` → today's date in `YYYY/MM/DD` format
- Numbered sanitation list → each entry from Stage 01 Step 4 (AI-assisted enhancements: operationIds improved/restored, schemas renamed, descriptions enhanced). Format each as:
  ```
  N. <Change type>
  - **Original**: <what was there before>
  - **Updated**: <what it became>
  - **Reason**: <why the change was made>
  ```
- OpenAPI CLI command → the exact `bal openapi` command used in Stage 02 (with all flags that were passed)

Write to `<SPEC_DIR>/sanitations.md`. If a `sanitations.md` already exists (from a previous run that the user chose to preserve in Stage 01 Step 0), **append** new auto-generated sections rather than overwriting human-authored ones.

---

## Step 6: Generate Ballerina.toml keywords

Classify this connector for Ballerina Central discoverability and write the result into `<BALLERINA_DIR>/Ballerina.toml`'s `keywords` array. Runs unconditionally, after all README/Module.md/sub-README generation above — this is deterministic classification + write, not user-prompted.

Inputs already in context — do not re-read raw source:
- `SPEC_METADATA.title` / `SPEC_METADATA.description`
- `CLIENT_ANALYSIS.methods`
- `TOML_META.keywords` (existing keywords, if any — preserve any conformant `Cost/*`/`Vendor/*`/`Area/*` values already present rather than guessing a worse replacement)
- `TOML_META.description` (existing Ballerina.toml package description, if any)

Classify exactly one value for each of the following three fields, per this taxonomy:

**cost** — pick exactly one:
- `Cost/Free` — completely free, no meaningful usage limits
- `Cost/Freemium` — free tier exists; paid plans unlock more features or capacity
- `Cost/Paid` — no meaningful free tier; paid subscription required

**vendor** — pick exactly one: `Vendor/<Brand>`, using the vendor's proper public brand name. For multi-product suites use the parent brand (e.g. `Vendor/Google` not `Vendor/Gmail`, `Vendor/Microsoft` not `Vendor/Azure`).

**area** — pick exactly one, based on the platform's PRIMARY PURPOSE, not incidental API operations:

| Value | When to use | Key signals |
|---|---|---|
| `Area/CRM & Sales` | CRM platforms, sales pipelines, lead/deal/contact/account management | contacts, deals, leads, pipelines, quotes, owners, engagements |
| `Area/Marketing & Social Media` | Marketing automation, email campaign delivery, social platforms, ad networks | campaigns, bulk email, social, ads, forms, subscriptions |
| `Area/Communication` | Team chat, personal email clients, SMS/voice calls, video conferencing, push notifications | slack, gmail, teams, twilio, discord, zoom, outlook.mail, sns |
| `Area/Productivity & Collaboration` | Project/task management, calendars, document signing, spreadsheets, note-taking | jira, asana, trello, calendar, docusign, excel, smartsheet, notion |
| `Area/Finance & Accounting` | Payment processing, billing, invoicing, subscriptions, accounting ledgers | stripe, paypal, xero, quickbooks, zuora, invoices, payments |
| `Area/E-Commerce` | Online storefronts, product catalogs, cart/order management | shopify, woocommerce, standalone commerce storefronts |
| `Area/ERP & Business Operations` | Enterprise resource planning, supply chain, manufacturing, insurance core systems | sap, netsuite, guidewire, dynamics365.scm |
| `Area/HRMS` | HR management, payroll, workforce planning, employee records | dayforce, peoplehr, workday, successfactors, dynamics365.hr |
| `Area/Developer Tools` | Source control, CI/CD, API management portals, issue tracking, developer portals | github, gitlab, bitbucket, wso2.apim |
| `Area/Database` | SQL, NoSQL, time-series, in-memory, data warehouse, ORM adapters | postgresql, mysql, mssql, mongodb, redis, dynamodb, snowflake |
| `Area/Messaging` | Message brokers, event streaming, pub/sub queues | kafka, rabbitmq, nats, sqs, servicebus, pubsub, ibmmq, confluent |
| `Area/Storage & File Management` | Object storage, cloud drives, file sync, document repositories | s3, drive, dropbox, onedrive, sharepoint, .files |
| `Area/AI & Machine Learning` | LLMs, generative AI, embeddings, vector databases, ML inference platforms | openai, anthropic, mistral, azure.ai, milvus, weaviate, pinecone |
| `Area/Cloud & Infrastructure` | Cloud marketplace, managed infrastructure, observability, monitoring | elastic.elasticcloud, aws.marketplace, jaeger, prometheus, newrelic |
| `Area/Security & Identity` | Identity management, user provisioning, SSO, secrets management | scim, okta, auth0, secretmanager, azure.ad |
| `Area/Other` | Utility connectors that truly don't fit any category above | aws.lambda, azure.functions |

Common classification pitfalls — read carefully:
- HubSpot commerce/engagements/extensions sub-modules → `Area/CRM & Sales` (they live inside HubSpot CRM, not standalone storefronts or email clients)
- HubSpot `.files` module → `Area/Storage & File Management` (file storage API, not CRM data)
- AWS SES → `Area/Marketing & Social Media` (bulk transactional/marketing delivery, not a personal email client)
- Gmail → `Area/Communication` (personal inbox API, not bulk marketing)
- Azure Event Hub → `Area/Messaging` (event streaming broker, not storage)
- SharePoint (lists/pages/sites/files) → `Area/Storage & File Management` (document repository, not productivity tool)

NEVER use these shorthand forms — they are invalid: `Area/AI`, `Area/CRM`, `Area/Finance`, `Area/Productivity`.

Append the hardcoded literal `Type/Connector` as the 4th keyword, then write all four:

```bash
<PYTHON_CMD> <skill-root>/scripts/write_ballerina_keywords.py "<BALLERINA_DIR>/Ballerina.toml" "<cost>" "<vendor>" "<area>" "Type/Connector"
```

---

## Step 7: Stage completion

Print:
```
✓ Documentation complete
  README.md:            <BALLERINA_DIR>/README.md
  Module.md:            <BALLERINA_DIR>/Module.md
  tests/README.md:      <BALLERINA_DIR>/tests/README.md
  examples/README.md:   <EXAMPLE_DIR>/README.md
  sanitations.md:       <SPEC_DIR>/sanitations.md
  Ballerina.toml keywords: <cost> <vendor> <area> Type/Connector
```

Then print the **Final Run Summary** from `references/workflows.md` (section: "Final Summary Format"), filled in with actual values.
