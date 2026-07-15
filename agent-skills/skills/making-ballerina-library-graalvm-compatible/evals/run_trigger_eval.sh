#!/usr/bin/env bash
# Trigger-accuracy eval for the making-ballerina-library-graalvm-compatible skill.
#
# Runs each query in a queries file (evals/*.json) against Claude Code with
# the skill installed, and checks whether the "Skill" tool was invoked with
# this skill's name. Follows the methodology at:
# https://agentskills.io/skill-creation/optimizing-descriptions
#
# Usage: run_trigger_eval.sh <queries.json> [runs]
#   queries.json  Path to a query file (trigger_queries.json, train_queries.json,
#                 or validation_queries.json), each entry: {"id", "query", "should_trigger"}
#   runs          Number of times to run each query (default: 3) — model behavior
#                 is nondeterministic, so a single run isn't reliable.
#
# Output (stdout): JSON array, one object per query, with a trigger_rate and
# whether it passed (should_trigger query with rate > threshold, or
# should-not-trigger query with rate < threshold).
#
# Requires: claude CLI, jq, bc.

set -euo pipefail

QUERIES_FILE="${1:?Usage: $0 <queries.json> [runs]}"
RUNS="${2:-3}"
SKILL_NAME="making-ballerina-library-graalvm-compatible"
THRESHOLD="0.5"

if [[ ! "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: runs must be a positive integer." >&2
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' CLI not found on PATH." >&2
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "ERROR: 'jq' not found on PATH." >&2
  exit 1
fi
if ! command -v bc &>/dev/null; then
  echo "ERROR: 'bc' not found on PATH." >&2
  exit 1
fi

# Returns 0 (success) if the skill was invoked for this query, 1 otherwise.
#
# `--output-format json` only returns a final result summary (no tool-call
# transcript — no `.messages[]` at all), so it can never show a Skill
# invocation. `--output-format stream-json --verbose` emits NDJSON, one event
# per line, including `assistant` events with `tool_use` content blocks —
# that's where the Skill tool call actually shows up. jq -s slurps the NDJSON
# lines into a single array so we can search across all of them at once.
#
# `--permission-mode bypassPermissions`: headless `-p` runs deny filesystem
# tool calls by default, which sends the model into several retry attempts
# (trying alternate Read/Bash calls to work around the denial) before it
# gives up — measured at ~10 minutes for a single query. Bypassing
# permissions for these eval runs cut that to ~30 seconds with no change in
# trigger detection. Only do this for eval queries you've written yourself
# and trust (these are read-only informational prompts, not destructive
# requests) — don't reuse this flag for arbitrary/untrusted input.
check_triggered() {
  local query="$1"
  claude -p "$query" --output-format stream-json --verbose --permission-mode bypassPermissions 2>/dev/null \
    | jq -se --arg skill "$SKILL_NAME" \
      'any(.[]; .type == "assistant" and (.message.content[]? | .type == "tool_use" and .name == "Skill" and .input.skill == $skill))' \
      > /dev/null 2>&1
}

count=$(jq 'if type == "array" then length else -1 end' "$QUERIES_FILE")
if [ "$count" -lt 0 ]; then
  echo "ERROR: queries file must contain a JSON array." >&2
  exit 1
fi
if [ "$count" -eq 0 ]; then
  echo "ERROR: queries file contains no queries." >&2
  exit 1
fi
results="[]"

for i in $(seq 0 $((count - 1))); do
  id=$(jq -r ".[$i].id" "$QUERIES_FILE")
  query=$(jq -r ".[$i].query" "$QUERIES_FILE")
  should_trigger=$(jq -r ".[$i].should_trigger" "$QUERIES_FILE")
  triggers=0

  echo ">>> [$id] running $RUNS pass(es): ${query:0:70}..." >&2

  for run in $(seq 1 "$RUNS"); do
    if check_triggered "$query"; then
      triggers=$((triggers + 1))
    fi
  done

  trigger_rate=$(echo "scale=4; $triggers / $RUNS" | bc)

  passed="false"
  if [ "$should_trigger" = "true" ]; then
    (( $(echo "$trigger_rate > $THRESHOLD" | bc -l) )) && passed="true"
  else
    (( $(echo "$trigger_rate < $THRESHOLD" | bc -l) )) && passed="true"
  fi

  result=$(jq -n \
    --arg id "$id" \
    --arg query "$query" \
    --argjson should_trigger "$should_trigger" \
    --argjson triggers "$triggers" \
    --argjson runs "$RUNS" \
    --argjson trigger_rate "$trigger_rate" \
    --argjson passed "$passed" \
    '{id: $id, query: $query, should_trigger: $should_trigger, triggers: $triggers, runs: $runs, trigger_rate: $trigger_rate, passed: $passed}')

  results=$(echo "$results" | jq --argjson r "$result" '. + [$r]')
done

echo "$results" | jq \
  --arg total "$count" \
  '{
    results: .,
    summary: {
      total: ($total | tonumber),
      passed: (map(select(.passed == true)) | length),
      failed: (map(select(.passed == false)) | length),
      pass_rate: ((map(select(.passed == true)) | length) / ($total | tonumber))
    }
  }'
