# Trigger evals

Tests whether the skill's `description` in `SKILL.md` causes Claude Code to invoke this skill on relevant prompts, and *not* invoke it on unrelated ones. Methodology: https://agentskills.io/skill-creation/optimizing-descriptions

## Files

- `trigger_queries.json` — full set of 20 labeled queries (10 `should_trigger: true`, 10 `should_trigger: false`), grounded in real details from this skill (`bal build --graalvm` / `bal test --graalvm`, the "Package is not verified with GraalVM" warning, `BTestMain` tracing, META-INF packing, `graalvmCompatible = true`, the reachability-metadata repo). Near-miss negatives share keywords but need something else: generating a Ballerina connector (the *other* skill), making a **Java** app a native image, plain `bal build`, installing GraalVM, or explaining AOT/closed-world concepts.
- `train_queries.json` / `validation_queries.json` — 60/40 split of the same set (12/8), balanced positives and negatives, for iterating on the description without overfitting to it.
- `run_trigger_eval.sh` — runs a queries file against `claude -p` and checks whether the `Skill` tool was invoked with `making-graalvm-compatible`.

## Quick start

**1. Check prerequisites** — you need the `claude` CLI, logged in, plus `jq` and `bc`:

```bash
claude --version    # if missing: https://claude.ai/code
jq --version         # if missing: brew install jq
bc --version          # if missing: brew install bc (usually preinstalled)
```

**2. Confirm the skill is installed** — the eval invokes Claude Code as a fresh process, so it only sees skills actually registered on this machine (not just files in this repo):

```bash
ls ~/.claude/skills/making-graalvm-compatible/SKILL.md
```

If that fails, symlink it first — see the install steps in `agent-skills/README.md` (repo root → `agent-skills/`).

**3. `cd` into this directory** — the script is run in place, and reads the queries file by relative path:

```bash
cd agent-skills/skills/making-graalvm-compatible/evals
```

**4. Run it** against one of the query files:

```bash
./run_trigger_eval.sh trigger_queries.json        # full set, 3 runs per query (default)
```

This makes `20 queries × 3 runs = 60` real Claude Code invocations, each ~20-40 seconds — so budget a few minutes total, plus API usage. The script runs with `--permission-mode bypassPermissions` specifically to keep this fast: headless `-p` mode denies filesystem tool calls by default, and without bypassing that, the model burns several retries working around each denial before it gives up (measured ~10 minutes for a single query versus ~30 seconds with the bypass). This is fine for these eval queries since they're read-only prompts you wrote yourself — don't reuse that flag for arbitrary/untrusted input. For a quick first check, use the smaller train set instead:

```bash
./run_trigger_eval.sh train_queries.json 1        # 12 queries × 1 run — fast smoke test
```

**5. Read the output.** It prints one line to stderr per query as it runs (progress), then a single JSON object to stdout when done. Save it to a file so you can inspect it:

```bash
./run_trigger_eval.sh train_queries.json 3 > result.json
jq '.summary' result.json                          # {"total":12,"passed":11,"failed":1,"pass_rate":0.9166...}
jq '.results[] | select(.passed == false)' result.json   # just the failures, with their trigger_rate
```

## What "pass" means

Each query is run `runs` times (default 3) since model behavior is nondeterministic — one run isn't reliable. A query **passes** if:
- `should_trigger: true` and the trigger rate (fraction of runs where the `Skill` tool fired) is **above** 0.5, or
- `should_trigger: false` and the trigger rate is **below** 0.5.

## Troubleshooting

- **Every query shows `trigger_rate: 0`, including obvious should-trigger ones** — first re-check step 2 (skill not installed/discoverable is the most common cause). If the skill *is* installed and this still happens, check that `run_trigger_eval.sh` is using `--output-format stream-json --verbose` (not `--output-format json`) — the plain `json` format only returns a final result summary with no tool-call transcript at all, so a Skill invocation can never show up in it.
- **`claude: command not found`** — install Claude Code (`claude --version` should work in a normal terminal first).
- **`jq: command not found` / `bc: command not found`** — `brew install jq bc`.
- **`Permission denied` running `./run_trigger_eval.sh`** — `chmod +x run_trigger_eval.sh`.
- **Script is much slower than the ~20-40s/query above** — check `check_triggered()` still passes `--permission-mode bypassPermissions`.

## Iterating on the description

1. Run `train_queries.json`, look at which queries failed.
2. Revise `SKILL.md`'s `description` field to address the *general* gap the failures point to — not specific keywords from the failed queries (that's overfitting). A common failure to guard here is the overlap with `generating-ballerina-connectors` (both are Ballerina library workflows) and with generic Java GraalVM requests (this skill is Ballerina-only).
3. Re-run `train_queries.json` until it passes, then run `validation_queries.json` to check the change generalizes.
4. Keep the description under the 1024-character limit.

See the [optimizing-descriptions](https://agentskills.io/skill-creation/optimizing-descriptions) guide for the full loop, and [evaluating-skills](https://agentskills.io/skill-creation/evaluating-skills) for testing output quality once triggering is reliable.
