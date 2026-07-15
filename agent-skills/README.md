# Agent Skills

Claude Code skills that automate Ballerina library workflows. Each skill lives in its own directory under `skills/` and is installed independently by symlinking it into Claude Code's global skill directory.

## Available skills

| Skill                                                                                                | Description                                                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`generating-ballerina-connectors`](skills/generating-ballerina-connectors)                         | Generates a complete Ballerina connector from an OpenAPI specification — a five-stage pipeline (sanitize → client → tests → examples → docs) producing a production-ready connector package.                                                                                    |
| [`making-ballerina-library-graalvm-compatible`](skills/making-ballerina-library-graalvm-compatible) | Takes a Ballerina library to a verified, warning-free `bal build --graalvm` / `bal test --graalvm` — build/test baseline, class-init fixes, reachability metadata (repo-sourced first, then the tracing agent), META-INF packing, and marking the package `graalvmCompatible`. |

## Prerequisites

| Requirement                          | Install                                                                                                                                       |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| [Claude Code](https://claude.ai/code) | Download from claude.ai/code                                                                                                                  |
| Ballerina CLI (`bal`)              | `brew install ballerina` or from [ballerina.io](https://ballerina.io/downloads/) — the `openapi` tool ships bundled with the distribution |
| Python 3.8+                          | `brew install python` or system Python                                                                                                      |
| Git                                  | Pre-installed on most systems                                                                                                                 |

Verify after install:

```bash
bal tool list
python3 --version
```

## Install

Clone the `ballerina-library` repo somewhere convenient (it does not need to live under `~/.claude/`):

```bash
git clone https://github.com/ballerina-platform/ballerina-library
```

Then symlink the specific skill you want into Claude Code's global skill directory — do not symlink the whole repo, only the skill's own folder:

```bash
mkdir -p ~/.claude/skills

ln -s /path/to/ballerina-library/agent-skills/skills/generating-ballerina-connectors \
  ~/.claude/skills/generating-ballerina-connectors
```

Verify:

```bash
ls ~/.claude/skills/generating-ballerina-connectors/SKILL.md
```

Claude Code loads skills from `~/.claude/skills/` automatically — start a new session and the skill is available immediately.

### Updating

```bash
cd /path/to/ballerina-library
git pull
```

No reinstall needed — the symlink always points at the latest cloned state.

### Installing another skill

Repeat the `ln -s` step for any other directory under `agent-skills/skills/`, pointing at that skill's folder instead.

## Usage

Start a Claude Code session in the directory where you want the connector generated (or where one already exists), then invoke the skill directly:

```
/generating-ballerina-connectors
```

Or describe your goal in natural language:

```
Generate a Ballerina connector from this OpenAPI spec: ./hubspot-files.yaml
```

See each skill's own `SKILL.md` for its full stage breakdown and configuration options.

## Using with other agents

Each skill is just markdown instructions plus deterministic scripts — nothing here is Claude Code-specific. Any coding agent that can read files and execute shell commands can run one.

### Generic (any agent)

1. Clone the repo (see [Install](#install)) so the agent can read `agent-skills/skills/<skill-name>/`.
2. Tell the agent: "Read `/path/to/ballerina-library/agent-skills/skills/generating-ballerina-connectors/SKILL.md` and follow it to generate a Ballerina connector from `<spec-path>`."
3. The agent should read `stages/*.md` in order, running each referenced script through its own shell/execute tool, substituting `<skill-root>` with the actual path to the skill directory.

### OpenAI Codex CLI

Codex CLI reads an `AGENTS.md` file (repo root or nearest ancestor) for standing project instructions. Add a pointer so Codex picks up the skill automatically:

```markdown
## Ballerina connector generation
When asked to generate a Ballerina connector from an OpenAPI spec, read and follow
/path/to/ballerina-library/agent-skills/skills/generating-ballerina-connectors/SKILL.md.
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
