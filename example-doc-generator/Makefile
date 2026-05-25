.PHONY: help setup setup-python setup-bal build run run-trigger \
        start-agent stop-agent \
        crop-screenshots crop-screenshots-dry crop-screenshots-backup \
        publish-docs publish-docs-dry publish-docs-no-preview publish-docs-no-pr \
        pr-preview pr-preview-no-preview pr-preview-no-pr pr-preview-dry \
        batch-commit-docs batch-commit-docs-dry \
        batch-pr-docs batch-pr-docs-dry \
        batch-commit-sample batch-commit-sample-dry \
        batch-pr-samples batch-pr-samples-dry \
        batch-run \
        publish-sample publish-sample-dry publish-sample-no-pr publish-sample-no-publish \
        publish-all publish-all-dry publish-all-no-preview publish-all-no-pr publish-all-open \
        cleanup cleanup-dry \
        clean clean-artifacts

# ── Default ──────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Connector Docs Automation — available targets"
	@echo ""
	@echo "  Setup"
	@echo "    make setup            Install all dependencies (Ballerina + Python)"
	@echo "    make setup-python     Create python/.venv and install Python deps"
	@echo "    make setup-bal        Build the Ballerina project"
	@echo ""
	@echo "  Run"
	@echo "    make run CONNECTOR=mysql                                      Run the full pipeline for a connector"
	@echo "    make run CONNECTOR=mysql ADDITIONAL_INSTRUCTIONS='...'        Run with per-connector guidance"
	@echo "    make run-trigger TRIGGER=trigger.github"
	@echo "                                                                Run the full pipeline for a trigger"
	@echo "    make run-trigger TRIGGER=trigger.github ADDITIONAL_INSTRUCTIONS='...'"
	@echo "                                                                Run a trigger with extra guidance"
	@echo "    make start-agent      Start the Python agent server in the foreground"
	@echo "    make stop-agent       Send shutdown request to the agent server"
	@echo ""
	@echo "  Publish"
	@echo "    make publish-docs             Publish docs + create PR (auto-detects docs-integrator path)"
	@echo "    make publish-docs-dry         Dry run — print planned actions, no changes"
	@echo "    make publish-docs-no-preview  Publish docs without Playwright preview screenshots"
	@echo "    make publish-docs-no-pr       Push branch + commit only, skip PR creation"
	@echo "    PUBLISH_ARGS='...'            Pass extra flags, e.g. PUBLISH_ARGS='--category security-identity'"
	@echo "    DOCS_REPO=PATH                Override docs-integrator path"
	@echo "    DOCS_UPSTREAM=OWNER/REPO      Override docs PR target repo (.env: DOCS_INTEGRATOR_UPSTREAM)"
	@echo "    DOCS_BASE_BRANCH=BRANCH       Override docs PR base branch (.env: DOCS_INTEGRATOR_BASE_BRANCH)"
	@echo ""
	@echo "  PR Preview (for already-committed remote branches)"
	@echo "    make pr-preview BRANCH=<branch>           Preview + PR for an existing remote branch"
	@echo "    make pr-preview-no-preview BRANCH=<branch> PR only, skip screenshots"
	@echo "    make pr-preview-no-pr BRANCH=<branch>     Screenshots only, skip PR creation"
	@echo "    make pr-preview-dry BRANCH=<branch>       Dry run"
	@echo "    BRANCH=<name>                             Required: the remote branch name"
	@echo ""
	@echo "  Batch Docs (commit multiple connectors to one branch, then one PR)"
	@echo "    make batch-commit-docs                   Commit current connector artifacts (default branch: docs/connector-docs)"
	@echo "    make batch-commit-docs BRANCH=<branch>   Commit to a custom branch"
	@echo "    make batch-commit-docs-dry               Dry run"
	@echo "    make batch-pr-docs BRANCH=<branch>       Create one PR from the shared branch"
	@echo "    make batch-pr-docs-dry BRANCH=<branch>   Dry run"
	@echo "    BRANCH=<name>                             Optional for commit (default: docs/connector-docs); required for PR"
	@echo "    CATEGORY=<cat>                            Override auto-detected connector category"
	@echo "    ARTIFACTS_DIR=<path>                      Override artifacts directory"
	@echo "    DOCS_FORK=<owner/repo>                    Override fork slug"
	@echo "    BATCH_COMMIT_DOCS_ARGS=<flags>            Extra flags for batch_commit_docs.py"
	@echo "    BATCH_PR_DOCS_ARGS=<flags>                Extra flags for batch_pr_docs.py"
	@echo "    Workflow: run pipeline for each connector → 'make batch-commit-docs' each time"
	@echo "              → 'make batch-pr-docs BRANCH=...' once when all connectors are committed"
	@echo ""
	@echo "  Batch Samples (commit multiple samples to one branch, then one PR)"
	@echo "    make batch-commit-sample                   Commit current sample (default branch: samples/connector-samples)"
	@echo "    make batch-commit-sample BRANCH=<branch>   Commit to a custom branch"
	@echo "    make batch-commit-sample-dry               Dry run"
	@echo "    make batch-pr-samples BRANCH=<branch>      Create one PR from the shared branch"
	@echo "    make batch-pr-samples-dry BRANCH=<branch>  Dry run"
	@echo "    BRANCH=<name>                               Optional for commit (default: samples/connector-samples); required for PR"
	@echo "    BATCH_COMMIT_SAMPLE_ARGS=<flags>            Extra flags for batch_commit_sample.py"
	@echo "    BATCH_PR_SAMPLES_ARGS=<flags>               Extra flags for batch_pr_samples.py"
	@echo "    Workflow: run pipeline for each connector → 'make batch-commit-sample' each time"
	@echo "              → 'make batch-pr-samples BRANCH=...' once when all samples are committed"
	@echo ""
	@echo "  Batch Run (queue connectors/triggers sequentially)"
	@echo "    make batch-run                    Run queue from batch_items.json"
	@echo "    BATCH_CONFIG=path.json            Override config file (default: batch_items.json)"
	@echo "    BATCH_RUN_ARGS='timeout=7200'     Extra flags for the Ballerina batch runner"
	@echo "    Workflow: 1) make batch-run  2) review artifacts_archive/  3) publish approved artifacts"
	@echo ""
	@echo "  Publish Sample"
	@echo "    make publish-sample               Publish integration sample PR + delete local project + close tabs"
	@echo "    make publish-sample-dry           Dry run — print planned actions, no changes"
	@echo "    make publish-sample-no-pr         Push branch + commit only, skip PR creation"
	@echo "    make publish-sample-no-publish    Delete local project + close tabs, skip sample publishing"
	@echo "    PUBLISH_SAMPLE_ARGS='...'         Pass extra flags to publish_sample.py"
	@echo "    CODE_SERVER_PORT=N                Override code-server port (.env: CODE_SERVER_PORT)"
	@echo "    SAMPLES_REPO=PATH                 Override integration-samples path (.env: INTEGRATION_SAMPLES_REPO)"
	@echo "    INTEGRATION_UPSTREAM=OWNER/REPO   Override samples PR target repo (.env: INTEGRATION_SAMPLES_UPSTREAM)"
	@echo "    INTEGRATION_BASE_BRANCH=BRANCH    Override samples PR base branch (.env: INTEGRATION_SAMPLES_BASE_BRANCH)"
	@echo "    PROJECT_PATH=PATH                 Manually set project path (writes created-project.txt)"
	@echo "    NO_PR=1                           Push branch but skip PR creation"
	@echo ""
	@echo "  Publish All (docs + sample together)"
	@echo "    make publish-all              Run publish-docs then publish-sample, show both PR links"
	@echo "    make publish-all-dry          Dry run for both scripts, no changes"
	@echo "    make publish-all-no-preview   Skip Playwright preview screenshots"
	@echo "    make publish-all-no-pr        Push both branches, skip PR creation"
	@echo "    make publish-all-open         Run both and open PR links in the browser automatically"
	@echo "    PUBLISH_ALL_ARGS='...'        Extra flags forwarded to publish_all.py"
	@echo "    (Docs + Sample overrides above all apply here too)"
	@echo ""
	@echo "  Artifacts"
	@echo "    make clean            Remove artifacts/, target/, Dependencies.toml, python/.venv"
	@echo "    make clean-artifacts  Remove only the artifacts/ directory"
	@echo ""

# ── Setup ────────────────────────────────────────────────────────────────────
setup: setup-python setup-bal
	@echo "Setup complete."

# Sentinel file: rebuilt whenever requirements.txt changes or .venv is missing.
python/.venv/.installed: python/requirements.txt
	@echo "→ Creating python/.venv and installing Python dependencies..."
	cd python && uv venv
	cd python && uv pip install -r requirements.txt
	cd python && .venv/bin/playwright install chromium
	touch python/.venv/.installed
	@echo "Python setup complete."

setup-python: python/.venv/.installed
	@echo "Python environment is ready. Activate with: source python/.venv/bin/activate"

setup-bal:
	@echo "→ Building Ballerina project..."
	bal build
	@echo "Ballerina build complete."

# ── Run ──────────────────────────────────────────────────────────────────────

AGENT_SERVER_PORT ?= 8765
ADDITIONAL_INSTRUCTIONS ?=

run:
	@[ "$(CONNECTOR)" ] || { echo "Usage: make run CONNECTOR=mysql"; exit 1; }
	@echo "→ Running full pipeline for connector: $(CONNECTOR)$(if $(ADDITIONAL_INSTRUCTIONS), (with additional instructions),)"
	bal run -- "$(CONNECTOR)" $(if $(ADDITIONAL_INSTRUCTIONS),"$(ADDITIONAL_INSTRUCTIONS)",)

run-trigger:
	@[ "$(TRIGGER)" ] || { echo "Usage: make run-trigger TRIGGER=trigger.github"; exit 1; }
	@echo "→ Running full pipeline for trigger: $(TRIGGER)$(if $(ADDITIONAL_INSTRUCTIONS), (with additional instructions),)"
	bal run -- trigger "$(TRIGGER)" $(if $(ADDITIONAL_INSTRUCTIONS),"$(ADDITIONAL_INSTRUCTIONS)",)

crop-screenshots: python/.venv/.installed
	python/.venv/bin/python python/crop_screenshots.py

crop-screenshots-dry: python/.venv/.installed
	python/.venv/bin/python python/crop_screenshots.py --dry-run

crop-screenshots-backup: python/.venv/.installed
	python/.venv/bin/python python/crop_screenshots.py --backup

start-agent: python/.venv/.installed
	@echo "→ Starting Python agent server (python/agent_server.py)..."
	cd python && unset CLAUDECODE && .venv/bin/python agent_server.py --port $(AGENT_SERVER_PORT)

stop-agent:
	@echo "→ Sending shutdown to agent server..."
	curl -s -X POST http://localhost:$(AGENT_SERVER_PORT)/shutdown || echo "Agent server not running."

# ── Publish docs ─────────────────────────────────────────────────────────────
# Defaults are read from .env by publish_docs.py.
# Set these Makefile vars to override .env values for a single run.
# DOCS_REPO          — override the docs-integrator path
# DOCS_UPSTREAM      — GitHub org/repo for docs-integrator PRs
# DOCS_BASE_BRANCH   — base branch for docs-integrator PRs
# PUBLISH_ARGS       — extra flags passed to publish_docs.py

DOCS_REPO ?=
DOCS_UPSTREAM ?=
DOCS_BASE_BRANCH ?=

_publish_docs_cmd = python/.venv/bin/python python/publish_docs.py \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_UPSTREAM),--upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--base-branch "$(DOCS_BASE_BRANCH)",) \
  $(PUBLISH_ARGS)

publish-docs: python/.venv/.installed
	@echo "→ Publishing connector docs..."
	$(_publish_docs_cmd)

publish-docs-dry: python/.venv/.installed
	@echo "→ Publishing connector docs (dry run)..."
	$(_publish_docs_cmd) --dry-run

publish-docs-no-preview: python/.venv/.installed
	@echo "→ Publishing connector docs (no preview)..."
	$(_publish_docs_cmd) --no-preview

publish-docs-no-pr: python/.venv/.installed
	@echo "→ Publishing connector docs (branch + commit only, no PR)..."
	$(_publish_docs_cmd) --no-pr

# ── PR Preview (for already-committed remote branches) ────────────────────────
# Use these targets when docs were already committed and pushed but the preview
# or PR step failed. Pass the remote branch name as BRANCH=<name>.
#
# Example:
#   make pr-preview BRANCH=docs/add-zoom.meetings-connector-example-documentation

_pr_preview_cmd = python/.venv/bin/python python/pr_preview.py \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_UPSTREAM),--upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--base-branch "$(DOCS_BASE_BRANCH)",) \
  --branch "$(BRANCH)" \
  $(PUBLISH_ARGS)

pr-preview: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required. Usage: make pr-preview BRANCH=docs/add-<slug>-connector-example-documentation" && exit 1)
	@echo "→ Taking preview screenshots and creating PR for branch: $(BRANCH)"
	$(_pr_preview_cmd)

pr-preview-no-preview: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required." && exit 1)
	@echo "→ Creating PR for branch (no preview): $(BRANCH)"
	$(_pr_preview_cmd) --no-preview

pr-preview-no-pr: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required." && exit 1)
	@echo "→ Taking preview screenshots for branch (no PR): $(BRANCH)"
	$(_pr_preview_cmd) --no-pr

pr-preview-dry: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required." && exit 1)
	@echo "→ Dry run for branch: $(BRANCH)"
	$(_pr_preview_cmd) --dry-run

# ── Batch docs (commit per connector → one PR) ────────────────────────────────
# Commit one connector's artifacts to a shared branch, then create one PR for all.
#
# Named overrides for batch_commit_docs.py:
#   CATEGORY=<cat>          Override auto-detected connector category
#   ARTIFACTS_DIR=<path>    Override artifacts directory (default: ./artifacts)
#   DOCS_FORK=<owner/repo>  Override fork slug (default: inferred from git remote)
#   BATCH_COMMIT_DOCS_ARGS  Extra flags forwarded verbatim to batch_commit_docs.py
#   BATCH_PR_DOCS_ARGS      Extra flags forwarded verbatim to batch_pr_docs.py
#
# Workflow:
#   Run pipeline for connector A → make batch-commit-docs
#   Run pipeline for connector B → make batch-commit-docs
#   ...
#   make batch-pr-docs BRANCH=docs/connector-docs

CATEGORY ?=
ARTIFACTS_DIR ?=
DOCS_FORK ?=
BATCH_COMMIT_DOCS_ARGS ?=
BATCH_PR_DOCS_ARGS ?=

_batch_commit_cmd = python/.venv/bin/python python/batch_commit_docs.py \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_FORK),--fork "$(DOCS_FORK)",) \
  $(if $(DOCS_UPSTREAM),--upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--base-branch "$(DOCS_BASE_BRANCH)",) \
  $(if $(BRANCH),--branch "$(BRANCH)",) \
  $(if $(CATEGORY),--category "$(CATEGORY)",) \
  $(if $(ARTIFACTS_DIR),--artifacts-dir "$(ARTIFACTS_DIR)",) \
  $(BATCH_COMMIT_DOCS_ARGS)

_batch_pr_cmd = python/.venv/bin/python python/batch_pr_docs.py \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_FORK),--fork "$(DOCS_FORK)",) \
  $(if $(DOCS_UPSTREAM),--upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--base-branch "$(DOCS_BASE_BRANCH)",) \
  --branch "$(BRANCH)" \
  $(BATCH_PR_DOCS_ARGS)

batch-commit-docs: python/.venv/.installed
	@echo "→ Committing connector docs to batch branch$(if $(BRANCH), $(BRANCH),: docs/connector-docs)..."
	$(_batch_commit_cmd)

batch-commit-docs-dry: python/.venv/.installed
	@echo "→ Dry run: commit connector docs to batch branch$(if $(BRANCH), $(BRANCH),: docs/connector-docs)..."
	$(_batch_commit_cmd) --dry-run

batch-pr-docs: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required. Usage: make batch-pr-docs BRANCH=docs/batch-april-2026" && exit 1)
	@echo "→ Creating PR from batch branch: $(BRANCH)"
	$(_batch_pr_cmd)

batch-pr-docs-dry: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required." && exit 1)
	@echo "→ Dry run: create PR from batch branch: $(BRANCH)"
	$(_batch_pr_cmd) --dry-run

# ── Publish sample ────────────────────────────────────────────────────────────
# Defaults are read from .env by publish_sample.py.
# Set these Makefile vars to override .env values for a single run.
# CODE_SERVER_PORT         — override code-server port
# SAMPLES_REPO             — override integration-samples path
# INTEGRATION_UPSTREAM     — GitHub org/repo for integration samples PRs
# INTEGRATION_BASE_BRANCH  — base branch for integration samples PRs
# NO_PR                    — set to 1 to push branch without creating a PR
# PUBLISH_SAMPLE_ARGS      — extra flags passed to publish_sample.py

CODE_SERVER_PORT ?=
SAMPLES_REPO ?=
PROJECT_PATH ?=
INTEGRATION_UPSTREAM ?=
INTEGRATION_BASE_BRANCH ?=
NO_PR ?=
PUBLISH_SAMPLE_ARGS ?=

_publish_sample_cmd = python/.venv/bin/python python/publish_sample.py \
  $(if $(CODE_SERVER_PORT),--url "http://localhost:$(CODE_SERVER_PORT)",) \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(PROJECT_PATH),--project-path "$(PROJECT_PATH)",) \
  $(if $(INTEGRATION_UPSTREAM),--upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  $(if $(NO_PR),--no-pr,) \
  $(PUBLISH_SAMPLE_ARGS)

publish-sample: python/.venv/.installed
	@echo "→ Publishing integration sample, deleting local project, closing tabs..."
	$(_publish_sample_cmd)

publish-sample-dry: python/.venv/.installed
	@echo "→ Publishing integration sample (dry run)..."
	$(_publish_sample_cmd) --dry-run

publish-sample-no-pr: python/.venv/.installed
	@echo "→ Publishing integration sample (branch + commit only, no PR)..."
	$(_publish_sample_cmd) --no-pr

publish-sample-no-publish: python/.venv/.installed
	@echo "→ Deleting local project and closing editor tabs (skip sample publishing)..."
	$(_publish_sample_cmd) --no-publish

# ── Batch samples (commit per connector → one PR) ─────────────────────────────
# Commit one sample to a shared branch, then create one PR for all.
#
# Named overrides:
#   BATCH_COMMIT_SAMPLE_ARGS  Extra flags forwarded verbatim to batch_commit_sample.py
#   BATCH_PR_SAMPLES_ARGS     Extra flags forwarded verbatim to batch_pr_samples.py
#   (CODE_SERVER_PORT, SAMPLES_REPO, PROJECT_PATH, INTEGRATION_UPSTREAM,
#    INTEGRATION_BASE_BRANCH are shared with the publish-sample targets above)
#
# Workflow:
#   Run pipeline for connector A → make batch-commit-sample
#   Run pipeline for connector B → make batch-commit-sample
#   ...
#   make batch-pr-samples BRANCH=samples/connector-samples

BATCH_COMMIT_SAMPLE_ARGS ?=
BATCH_PR_SAMPLES_ARGS ?=

_batch_commit_sample_cmd = python/.venv/bin/python python/batch_commit_sample.py \
  $(if $(CODE_SERVER_PORT),--url "http://localhost:$(CODE_SERVER_PORT)",) \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(PROJECT_PATH),--project-path "$(PROJECT_PATH)",) \
  $(if $(INTEGRATION_UPSTREAM),--upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  $(if $(BRANCH),--branch "$(BRANCH)",) \
  $(BATCH_COMMIT_SAMPLE_ARGS)

_batch_pr_samples_cmd = python/.venv/bin/python python/batch_pr_samples.py \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(INTEGRATION_UPSTREAM),--upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  --branch "$(BRANCH)" \
  $(BATCH_PR_SAMPLES_ARGS)

batch-commit-sample: python/.venv/.installed
	@echo "→ Committing connector sample to batch branch$(if $(BRANCH), $(BRANCH),: samples/connector-samples)..."
	$(_batch_commit_sample_cmd)

batch-commit-sample-dry: python/.venv/.installed
	@echo "→ Dry run: commit connector sample to batch branch$(if $(BRANCH), $(BRANCH),: samples/connector-samples)..."
	$(_batch_commit_sample_cmd) --dry-run

batch-pr-samples: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required. Usage: make batch-pr-samples BRANCH=samples/batch-april-2026" && exit 1)
	@echo "→ Creating PR from batch samples branch: $(BRANCH)"
	$(_batch_pr_samples_cmd)

batch-pr-samples-dry: python/.venv/.installed
	@test -n "$(BRANCH)" || (echo "[ERROR] BRANCH is required." && exit 1)
	@echo "→ Dry run: create PR from batch samples branch: $(BRANCH)"
	$(_batch_pr_samples_cmd) --dry-run

# ── Batch Run (queue multiple connectors/triggers) ────────────────────────────
BATCH_CONFIG ?= batch_items.json
BATCH_RUN_ARGS ?=

batch-run:
	@echo "→ Running batch pipeline from $(BATCH_CONFIG)..."
	bal run -- batch config="$(BATCH_CONFIG)" $(BATCH_RUN_ARGS)

# ── Publish all (docs + sample) ───────────────────────────────────────────────
# Reuses the same override vars as the individual publish targets.
# Extra flags: PUBLISH_ALL_ARGS — forwarded verbatim to publish_all.py.

PUBLISH_ALL_ARGS ?=

_publish_all_cmd = python/.venv/bin/python python/publish_all.py \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  $(if $(DOCS_UPSTREAM),--docs-upstream "$(DOCS_UPSTREAM)",) \
  $(if $(DOCS_BASE_BRANCH),--docs-base-branch "$(DOCS_BASE_BRANCH)",) \
  $(if $(CODE_SERVER_PORT),--url "http://localhost:$(CODE_SERVER_PORT)",) \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(PROJECT_PATH),--project-path "$(PROJECT_PATH)",) \
  $(if $(INTEGRATION_UPSTREAM),--samples-upstream "$(INTEGRATION_UPSTREAM)",) \
  $(if $(INTEGRATION_BASE_BRANCH),--samples-base-branch "$(INTEGRATION_BASE_BRANCH)",) \
  $(if $(NO_PR),--no-pr,) \
  $(PUBLISH_ALL_ARGS)

publish-all: python/.venv/.installed
	@echo "→ Publishing docs + sample, showing both PR links..."
	$(_publish_all_cmd)

publish-all-dry: python/.venv/.installed
	@echo "→ Publishing docs + sample (dry run)..."
	$(_publish_all_cmd) --dry-run

publish-all-no-preview: python/.venv/.installed
	@echo "→ Publishing docs + sample (no Playwright preview)..."
	$(_publish_all_cmd) --no-preview

publish-all-no-pr: python/.venv/.installed
	@echo "→ Publishing docs + sample (branch + commit only, no PR)..."
	$(_publish_all_cmd) --no-pr

publish-all-open: python/.venv/.installed
	@echo "→ Publishing docs + sample and opening PR links in browser..."
	$(_publish_all_cmd) --open

# Aliases for backward compatibility
cleanup: publish-sample
cleanup-dry: publish-sample-dry

# ── Artifacts ────────────────────────────────────────────────────────────────
clean:
	@echo "→ Cleaning artifacts/, target/, Dependencies.toml, python/.venv..."
	rm -rf artifacts/ target/ Dependencies.toml python/.venv
	@echo "Done."

clean-artifacts:
	@echo "→ Removing artifacts/ directory..."
	rm -rf artifacts/
