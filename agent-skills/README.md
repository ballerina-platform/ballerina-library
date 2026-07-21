# Ballerina Library Agent Skills

Skills that automate Ballerina library workflows. They are distributed as the `ballerina-libdev` Claude Code plugin and as standard Agent Skills for other supported coding agents.

## Available skills

| Skill | Description |
|---|---|
| [`generating-connectors`](skills/generating-connectors) | Generates a complete Ballerina connector from an OpenAPI specification — a five-stage pipeline (sanitize → client → tests → examples → docs) producing a production-ready connector package. |

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

#### Activate the plugin

Claude Code discovers the skills and other plugin artifacts under `agent-skills/`. Run the following command after installing, enabling, disabling, or updating a plugin during a session to apply the change without restarting Claude Code:

```bash
/reload-plugins
```

#### Marketplace and plugin updates

To manually refresh the Ballerina Skills marketplace and retrieve its latest plugin listings and version changes, run:

```bash
/plugin marketplace update ballerina-skills
```

To enable automatic marketplace and installed-plugin updates, run `/plugin`, open **Marketplaces**, select `ballerina-skills`, and choose **Enable auto-update**. Auto-update is disabled by default for third-party marketplaces. Claude Code checks after startup and, when an installed plugin is updated, prompts you to run `/reload-plugins` before using the new version in the current session.

For more details, see Anthropic's [plugin discovery and installation guide](https://code.claude.com/docs/en/discover-plugins).

### Other agents (Open Agent Skills CLI)

Install the connector-generation skill for Codex, Cursor, Gemini CLI, GitHub Copilot, and other supported agents:

```bash
npx skills add ballerina-platform/ballerina-library
```

Pass `--agent <name>` to target a specific agent. This channel installs the connector-generation skill only; Claude Code plugin artifacts such as MCP support and hooks are not included.

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

## Usage

Start a Claude Code session in the directory where you want the connector generated (or where one already exists), then invoke the skill directly:

```
/ballerina-libdev:generating-connectors
```

Or describe your goal in natural language:

```
Generate a Ballerina connector from this OpenAPI spec: ./hubspot-files.yaml
```

See each skill's own `SKILL.md` for its full stage breakdown and configuration options.

## Versioning and releases

Bump the `version` in `.claude-plugin/plugin.json` for every meaningful change under `agent-skills/`. Use semantic versioning: add skills or backward-compatible capabilities in a minor release, fixes in a patch release, and incompatible changes in a major release. Claude Code uses this version to detect marketplace plugin updates.

## Using with other agents

Each skill is just markdown instructions plus deterministic scripts — nothing here is Claude Code-specific. Any coding agent that can read files and execute shell commands can run one.

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
  skills/
    <skill-name>/
      SKILL.md              # Skill manifest and entry point
      stages/                # One file per pipeline stage (if applicable)
      scripts/                # Python + shell scripts for deterministic operations
      templates/              # Markdown scaffolds for generated docs
      references/             # Fix procedures, workflow rules
```
