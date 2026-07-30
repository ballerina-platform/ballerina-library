# Ballerina Library Development Skills

Skills that automate Ballerina library workflows. They are distributed as the `ballerina-libdev` Claude Code plugin and as standard Agent Skills for other supported coding agents.

## Available skills

| Skill | Description |
|---|---|
| [`generating-connectors`](skills/generating-connectors) | Generates a complete Ballerina connector from an OpenAPI specification — a five-stage pipeline (sanitize → client → tests → examples → docs) producing a production-ready connector package. |
| [`generate-connector-example-docs`](skills/generate-connector-example-docs) | Creates a WSO2 Integrator connector sample through the low-code UI, captures six screenshots, and generates a validated example guide from a full Ballerina Central package coordinate. |

## Prerequisites

| Requirement | Install |
|---|---|
| [Claude Code](https://claude.ai/code) | Download from claude.ai/code |
| Ballerina CLI (`bal`) | `brew install ballerina` or from [ballerina.io](https://ballerina.io/downloads/) — the `openapi` tool ships bundled with the distribution |
| Python 3.8+ | `brew install python` or system Python |
| Git | Pre-installed on most systems |

Verify after install:

```bash
bal tool list
python3 --version
```

## Installation

### Claude Code

Register the Ballerina Skills marketplace:

```bash
/plugin marketplace add ballerina-platform/skills
```

#### Choose an installation scope

Install for yourself across all projects (the default **User scope**):

```bash
/plugin install ballerina-libdev@ballerina-skills
```

To install at a different scope, run `/plugin`, open **Discover**, select `ballerina-libdev`, and choose one of the following options:

- **User scope:** Install for yourself across all projects.
- **Project scope:** Install for repository collaborators through `.claude/settings.json`.
- **Local scope:** Install for yourself in the current repository only; this is not shared with collaborators.

#### Marketplace and plugin updates

To manually update the plugin, first refresh the Ballerina Skills marketplace, then fetch the latest plugin version:

```bash
/plugin marketplace update ballerina-skills
/plugin update ballerina-libdev@ballerina-skills
```

If you update the plugin during an active session, reload it to use the new version without restarting Claude Code:

```bash
/reload-plugins
```

Auto-update is a client-side, per-user setting and is disabled by default for third-party marketplaces. To enable it, run `/plugin`, open **Marketplaces**, select `ballerina-skills`, and choose **Enable auto-update**. An organization can instead set `"autoUpdate": true` for the marketplace in managed `settings.json`. Claude Code checks for updates after startup and prompts you to run `/reload-plugins` when an installed plugin is updated.

For more details, see Anthropic's [plugin discovery and installation guide](https://code.claude.com/docs/en/discover-plugins).

#### Bundled Playwright MCP server

The plugin configures a pinned Playwright MCP server through `.mcp.json`. Claude Code starts it whenever `ballerina-libdev` is enabled, so Playwright is also available in sessions that use only `generating-connectors`. The first start can download `@playwright/mcp@0.0.78` through `npx -y`; browser installation remains an explicit prerequisite step.

Use `/mcp` to inspect the connection. After changing `.mcp.json` or updating the plugin in an active session, run:

```bash
/reload-plugins
```

### Other agents (Open Agent Skills CLI)

Install the standard skill folders for Codex, Cursor, Gemini CLI, GitHub Copilot, and other supported agents:

```bash
npx skills add ballerina-platform/ballerina-library
```

Pass `--agent <name>` to target a specific agent. This channel does not install Claude plugin artifacts such as `.mcp.json`. `generating-connectors` can run with ordinary file and shell tools; `generate-connector-example-docs` additionally requires an equivalent Playwright MCP configuration. The Claude Code plugin is the supported turnkey installation for the documentation workflow.

### Manual installation fallback

Clone the repository and symlink an individual skill when marketplace installation is unavailable:

```bash
git clone https://github.com/ballerina-platform/ballerina-library
mkdir -p ~/.claude/skills
ln -s /path/to/ballerina-library/agent-skills/skills/generating-connectors \
  ~/.claude/skills/generating-connectors
```

Update this fallback installation by pulling the cloned repository:

```bash
cd /path/to/ballerina-library
git pull
```

Repeat the symlink step for any additional directory under `agent-skills/skills/`.

Symlinking `generate-connector-example-docs` alone does not install its Playwright MCP server. Use the plugin installation or configure an equivalent Playwright MCP server separately.

## Usage

Start a Claude Code session in the project where you want the generated output, then invoke the relevant skill directly.

Generate a Ballerina connector:

```
/ballerina-libdev:generating-connectors
```

Or describe your goal in natural language:

```
Generate a Ballerina connector from this OpenAPI spec: ./hubspot-files.yaml
```

Generate WSO2 Integrator connector example documentation with an explicit Central version:

```text
/ballerina-libdev:generate-connector-example-docs ballerinax/mysql:1.16.0
```

Omit the version to resolve the latest package:

```text
/ballerina-libdev:generate-connector-example-docs ballerinax/mysql
```

The documentation skill also activates from a matching natural-language request:

```text
Generate a WSO2 Integrator connector example guide for ballerinax/mysql.
```

Use `organization/package` or `organization/package:version`; bare package names are rejected. Output is preserved under `artifacts/<organization>-<package>/` in the Claude project directory.

See each skill's own `SKILL.md` for its full stage breakdown and configuration options.

## Versioning and releases

Bump the `version` in `.claude-plugin/plugin.json` for every meaningful change under `agent-skills/`. Use semantic versioning: add skills or backward-compatible capabilities in a minor release, fixes in a patch release, and incompatible changes in a major release. Claude Code uses this version to detect marketplace plugin updates.

## Using with other agents

The skills use markdown instructions plus deterministic scripts. `generating-connectors` is agent-neutral. `generate-connector-example-docs` uses Claude path variables and the plugin-bundled Playwright MCP server; another agent needs equivalent skill-root/project-root substitution and browser tools.

### Generic (any agent)

1. Clone the repo (see [Install](#installation)) so the agent can read `agent-skills/skills/<skill-name>/`.
2. Tell the agent: "Read `/path/to/ballerina-library/agent-skills/skills/generating-connectors/SKILL.md` and follow it to generate a Ballerina connector from `<spec-path>`."
3. The agent should read `stages/*.md` in order, running each referenced script through its own shell/execute tool, substituting `<skill-root>` with the actual path to the skill directory.

### OpenAI Codex CLI

Codex CLI reads an `AGENTS.md` file (repo root or nearest ancestor) for standing project instructions. Add a pointer so Codex picks up the skill automatically:

```markdown
## Ballerina connector generation
When asked to generate a Ballerina connector from an OpenAPI spec, read and follow
/path/to/ballerina-library/agent-skills/skills/generating-connectors/SKILL.md.
```

You can also just paste the `SKILL.md` path directly into a Codex prompt instead of editing `AGENTS.md`.

### opencode

opencode also honors project-level standing instructions (`AGENTS.md`, or an equivalent under `.opencode/` depending on version) — add the same pointer shown above. Check opencode's docs for the exact file/location your version expects, since this has changed across releases.

### Antigravity

Point Antigravity's agent at the skill directory and ask it to follow `SKILL.md`, or add the same pointer to whichever standing-instructions file your version supports. Check Antigravity's current docs for the exact convention — this is a newer tool and its config surface is still evolving.

## Project structure

```
agent-skills/
  .claude-plugin/
    plugin.json
  .mcp.json
  skills/
    <skill-name>/
      SKILL.md              # Skill manifest and entry point
      stages/                # One file per pipeline stage (if applicable)
      scripts/                # Python + shell scripts for deterministic operations
      templates/              # Markdown scaffolds for generated docs
      references/             # Fix procedures, workflow rules
      assets/                 # Output templates and other static resources
```
