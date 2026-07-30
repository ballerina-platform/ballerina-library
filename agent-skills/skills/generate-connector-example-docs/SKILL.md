---
name: generate-connector-example-docs
description: Generate validated WSO2 Integrator connector example documentation, six low-code UI screenshots, and a preserved sample project from a full Ballerina Central package coordinate such as ballerinax/mysql or ballerinax/mysql:1.16.0. Use when creating or regenerating connector example guides through the WSO2 Integrator UI. Do not use for triggers, batch generation, publishing, commits, deployments, or pull requests.
---

# Generate Connector Example Docs

Create the integration and documentation directly in the current agent. Never start a nested agent, call an LLM API, publish artifacts, or run git commands.

## Inputs

Require a full Central coordinate in one of these forms:

- `organization/package`
- `organization/package:version`

Reject a bare package name. Treat an omitted version as `latest`. Accept optional user guidance for operation or authentication choices; it overrides the workflow's default selection heuristics.

## Run the workflow

1. Verify that the bundled `playwright` MCP server's `browser_*` tools are available. If they are unavailable, stop before creating artifacts. Tell the user to inspect `/mcp` and run `/reload-plugins`; do not run `claude mcp add` or modify personal Claude settings.
2. Resolve the requested coordinate and run `python3 "${CLAUDE_SKILL_DIR}/scripts/prepare_run.py" "ORGANIZATION/PACKAGE[:VERSION]" --root "${CLAUDE_PROJECT_DIR}"`. Stop on invalid input, missing Central metadata, or an existing completed or nonempty output directory.
3. Read the emitted context JSON. Use its absolute `run_dir`, `sample_dir`, `screenshots_dir`, and `doc_path` values throughout the run.
4. Check `node`, `npx`, `python3`, Pillow (`python3 -c "import PIL"`), `code-server`, and the `wso2.wso2-integrator` code-server extension (`code-server --list-extensions`). Ask before installing a missing prerequisite or downloading Chromium. Install Pillow only from `${CLAUDE_SKILL_DIR}/scripts/requirements.txt`. Do not install silently.
5. Reuse a healthy code-server on a user-specified port or port 8080. Otherwise start `code-server --auth none --bind-addr 127.0.0.1:PORT SAMPLE_PARENT`, redirect output to `run-log/code-server.log`, and record its PID. Stop only a server started by this run.
6. Read the [connector UI workflow](references/connector-ui-workflow.md) completely before browser interaction. Complete its clean-workspace gate before connector work: close the global Chat/Copilot secondary sidebar, integrated terminal, Welcome tab, unrelated editor/source tabs, and transient popups while keeping the WSO2 Integrator visual editor and left project-tree primary sidebar open. Treat that project sidebar as a blocking invariant through all six screenshots. Do not capture screenshot 01 until a fresh snapshot verifies the clean frame. Follow the reference through all six milestones. Use the bundled `playwright` MCP tools. Limit DOM evaluation to the reference's narrowly scoped scrolling and nested-canvas procedures; do not run arbitrary or page-wide browser code.
7. After every `browser_take_screenshot` call, immediately run `python3 "${CLAUDE_SKILL_DIR}/scripts/collect_screenshot.py" RETURNED_PATH SCREENSHOTS_DIR/FILENAME`. Keep filenames sequential from `01` through `06`.
8. Create the integration using the context's exact `sample_name` at `sample_dir`. Make `sample_dir` the project root: `Ballerina.toml` and the generated `.bal` files must live directly within it. Do not rename the directory or add a suffix. If the UI creates the project elsewhere or one level deeper, copy its contents into `sample_dir` before finalization.
9. Read the [documentation contract](references/documentation-contract.md) and [Microsoft writing style](references/microsoft-writing-style.md) completely before writing. Copy `${CLAUDE_SKILL_DIR}/assets/templates/connector-example-doc.md` to `doc_path`, then replace every placeholder with facts from the completed workflow. Remove template comments and inapplicable conditional sections. Do not author from a blank file, create an intermediate execution prompt, or use a second model for enforcement.
10. Run `python3 "${CLAUDE_SKILL_DIR}/scripts/finalize_run.py" --context CONTEXT_PATH`. It deterministically injects **Try it yourself**, calls `append_central_examples.py` to append examples from the cached Central API response, and validates the output. If it reports failures, correct the guide or artifacts and rerun until it succeeds.
11. Stop the code-server process only when this run started it. Report the guide, screenshot directory, sample directory, resolved package version, and validation status.

## Safety and boundaries

- Keep all generated files under `artifacts/<organization>-<package>/` in `${CLAUDE_PROJECT_DIR}`.
- Never overwrite a prior run automatically.
- Never put credentials or secret values in the guide, screenshots, sample, logs, or config files. Leave configurable values empty or use obvious non-secret placeholders.
- Generate **Try it yourself** links only through the finalization script. The links target the canonical future sample location; they do not publish the sample.
- Generate **More code examples** only through `append_central_examples.py`. Never author, summarize, or alter Central example content manually.
- Do not create branches, commits, pushes, deployments, issues, or pull requests.
- Do not support trigger packages or batch queues in this skill.
