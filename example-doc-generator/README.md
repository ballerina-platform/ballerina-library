# Example Doc Generator

This project generates WSO2 Integrator example documentation with screenshots.
It can run one connector, run one trigger, or process a mixed batch queue.

The pipeline is:

```text
CLI input -> Claude prompt generation -> Claude Agent + Playwright MCP -> Markdown guide + screenshots
```

The Ballerina app orchestrates the pipeline. The Python agent server runs the
Claude Agent SDK and Playwright MCP against code-server.

## Prerequisites

Install these first:

| Tool | Required |
|------|----------|
| Ballerina | `2201.13.x` |
| Python | `3.11+` |
| uv | latest |
| Node.js | LTS+ |
| Claude Code CLI | latest |
| Anthropic API key | for Ballerina API calls and the Python agent server |

`code-server` is installed by the pipeline if it is missing.

## Setup

Run all commands from `example-doc-generator/`.

1. Create the Ballerina config:

```bash
cp Config.toml.example Config.toml
```

Set `llmApiKey` in `Config.toml`.

2. Create the Python scripts config:

```bash
cp .env.example .env
```

At minimum, set `DOCS_INTEGRATOR_FORK` if you plan to publish connector output.

3. Export the Anthropic key for the Python agent server:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

4. Install Python dependencies and build the Ballerina app:

```bash
cd python
uv venv
uv pip install -r requirements.txt
.venv/bin/playwright install chromium
cd ..
bal build
```

## Optional Claude Code Local Settings

`.claude/` is ignored because it contains local Claude Code preferences and
permissions. Keep shared MCP setup in the tracked `.mcp.json`; recreate
`.claude/settings.json` locally only if your Claude Code setup needs it.

## Run One Connector

Connector mode is the default.

```bash
bal run -- mysql
```

With extra guidance:

```bash
bal run -- zoom.meetings "Use BearerTokenConfig for authentication."
```

## Run One Trigger

Use `trigger` as the first argument. The pipeline derives the Ballerina Central
package path as `ballerinax/<trigger-name>`.

```bash
bal run -- trigger trigger.github
```

With extra guidance:

```bash
bal run -- trigger trigger.github "Use IssuesService and the onOpened handler."
```

Do not pass `--trigger` or `TRIGGER_PACKAGE`.

## Batch Runs

Batch runs process items sequentially and archive each run under
`artifacts_archive/`.

1. Create a batch config:

```bash
cp batch_items.json.example batch_items.json
```

2. Add connector and trigger entries:

```json
{
  "items": [
    { "type": "connector", "name": "mysql" },
    {
      "type": "connector",
      "name": "zoom.meetings",
      "instructions": "Use BearerTokenConfig for authentication."
    },
    {
      "type": "trigger",
      "name": "trigger.github",
      "instructions": "Use IssuesService and the onOpened handler."
    }
  ]
}
```

Rules:

- `type` is required and must be `connector` or `trigger`.
- `name` is required.
- `instructions` is optional.
- Batch mode does not resume, does not dry-run, and does not create PRs.
- Batch mode fails fast if `artifacts/` already exists to avoid archiving stale output.
- Pressing `Ctrl+C` stops the active child pipeline before the batch exits.

3. Make sure no current run artifacts are present:

```bash
rm -rf artifacts
```

4. Run the queue:

```bash
bal run -- batch config=batch_items.json
```

With a longer per-item timeout:

```bash
bal run -- batch config=batch_items.json timeout=7200
```

## What a Run Produces

Single runs write to `artifacts/`:

| Path | Contents |
|------|----------|
| `artifacts/execution-prompt/` | Generated execution prompt sent to the agent |
| `artifacts/workflow-docs/` | Final Markdown guide |
| `artifacts/screenshots/` | Captured and cropped screenshots |
| `artifacts/run-log/` | Target name, project path, timing, costs, and output paths |

Batch runs move each item's `artifacts/` directory to `artifacts_archive/<slug>`
or `artifacts_archive/<slug>_FAILED`. If a run produces no artifacts, the batch
runner creates a `<slug>_NO_ARTIFACTS/README.txt` placeholder.

At the end of a single pipeline run, the Python agent server is stopped
automatically.

## Publishing Connector Output

The publishing helpers are connector-focused Python scripts. Run them after
reviewing generated output.

```bash
python/.venv/bin/python python/publish_docs.py
python/.venv/bin/python python/publish_sample.py
python/.venv/bin/python python/publish_all.py
```

Dry-run variants:

```bash
python/.venv/bin/python python/publish_docs.py --dry-run
python/.venv/bin/python python/publish_sample.py --dry-run
python/.venv/bin/python python/publish_all.py --dry-run
```

For batch output, review each archived item under `artifacts_archive/`.
Connector publishing can still use the existing publish scripts after you
choose the artifact or project to publish. Trigger publish helpers are not
automated yet, so review and publish trigger artifacts manually.

## Run In GitHub Actions

Use the `Connector Documentation Automation` workflow from the Actions tab.
The workflow file is:

```text
.github/workflows/connector-example-doc-generation.yml
```

Required repository/environment secrets:

| Secret | Required for | Description |
|--------|--------------|-------------|
| `LLM_API_KEY` | generation | Anthropic API key used by Ballerina and Claude Code |
| `DOCS_INTEGRATOR_TOKEN` | connector publishing only | Token with permission to push to the docs-integrator fork and create PRs |

Workflow inputs:

| Input | Value |
|-------|-------|
| `mode` | `connector` or `trigger` |
| `name` | connector name like `mysql`, or trigger name like `trigger.twilio` |
| `instructions` | optional extra guidance |
| `publishConnector` | set to `true` only for connector runs that should publish docs |
| `docsIntegratorFork` | required when `publishConnector` is `true` |
| `docsIntegratorUpstream` | defaults to `wso2/docs-integrator` |
| `docsIntegratorBaseBranch` | defaults to `main` |

Examples:

```text
mode: connector
name: mysql
instructions:
publishConnector: false
```

```text
mode: trigger
name: trigger.twilio
instructions: Use the onReceived handler.
publishConnector: false
```

```text
mode: connector
name: zoom.meetings
instructions: Use BearerTokenConfig for authentication.
publishConnector: true
docsIntegratorFork: your-org/docs-integrator
```

After the workflow completes, open the workflow run summary and download the
artifact named `example-doc-generator-<mode>-<name>`. It contains the generated
Markdown guide, screenshots, run logs, and a README describing the output.

GitHub Actions intentionally does not support batch mode. Run batch queues
locally with `bal run -- batch config=batch_items.json`.

## Agent Server

The pipeline starts and stops the agent server automatically. For debugging:

```bash
cd python
unset CLAUDECODE
.venv/bin/python agent_server.py --port 8765
```

In another terminal:

```bash
curl http://localhost:8765/health
curl -s -X POST http://localhost:8765/shutdown
```

The server API is:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/run` | Submit `{ "prompt_path": "..." }` |
| `GET` | `/jobs/<id>` | Poll logs, status, and cost |
| `GET` | `/health` | Health check |
| `POST` | `/shutdown` | Stop the server |

## Optional Make Commands

Make targets exist as shortcuts for setup, runs, publishing, screenshots, and
cleanup. They are optional wrappers around the commands above. For the full list
of targets and override variables, run:

```bash
make help
```

Common shortcuts:

```bash
make setup
make run CONNECTOR=mysql
make run-trigger TRIGGER=trigger.github
make batch-run
make clean-artifacts
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| API key validation failed | Set `llmApiKey` in `Config.toml` and export `ANTHROPIC_API_KEY` |
| `claude` not found | Install Claude Code CLI and verify with `claude --version` |
| Batch fails because `artifacts/` exists | Move or delete `artifacts/` after reviewing it |
| Agent server not ready | Start `python/agent_server.py` manually and inspect the Python error |
| `uv` not found | Install uv from `https://docs.astral.sh/uv/` |
| Python dependency error | Run `uv pip install -r python/requirements.txt` inside the venv |
| Ballerina build error | Run `bal clean && bal build` |
| Playwright MCP error | Run `python/.venv/bin/playwright install chromium` |
| Need to clear generated output | Run `rm -rf artifacts` after reviewing the output |
