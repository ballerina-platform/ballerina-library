# Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.

"""
Claude Agent SDK HTTP server.

Runs the Claude agent with Playwright MCP browser automation and exposes a
simple REST API so the Ballerina pipeline can submit jobs and stream logs.

Routes
------
POST /run          { "prompt_path": "<path>", "model": "<model>" }  → { "job_id": "<uuid>" }
GET  /jobs/<id>    → { "status": "running|done", "logs": [...] }
GET  /health       → { "status": "ok" }
POST /shutdown     → { "status": "shutting down" }

Usage
-----
    uv run agent_server.py [--port 8765]
"""

import argparse
import asyncio
import json
import os
import uuid
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

# Unset CLAUDECODE so the SDK can spawn a Claude Code subprocess even when
# this server is launched from within an active Claude Code session.
os.environ.pop("CLAUDECODE", None)

from aiohttp import web
from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    SystemMessage,
    TextBlock,
    query,
)

# CWD for the Claude agent is the project root (one level above this file)
CWD = str(Path(__file__).parent.parent)
AI_MODEL = os.environ.get("AI_MODEL", "claude-sonnet-4-6")

jobs: dict[str, dict] = {}
running_tasks: set[asyncio.Task] = set()

AGENT_SYSTEM_PROMPT = """
You are a WSO2 Integrator documentation automation agent.

Follow the provided execution prompt as the source of truth. It may describe a
connector workflow or a trigger workflow; adapt your language, screenshots,
artifact names, and documentation structure to the workflow type in that prompt.

Use browser automation for WSO2 Integrator UI work, and use file tools only when
the execution prompt explicitly asks you to inspect or edit generated project
files. Keep generated artifacts under the paths given in the execution prompt.
Do not introduce extra setup notes, environment details, or undocumented
workflow sections beyond what the execution prompt requires.

CRITICAL — Never delegate this work to a sub-agent or Task tool:
You MUST perform every step of the execution prompt yourself, in this session,
using your own tool calls (Playwright MCP tools, Bash, Read, Write, Edit).
Do NOT spawn a sub-agent, invoke a "Task"/"Agent" tool, or otherwise hand off
the browser automation, file edits, or documentation writing to a separate
agent session — regardless of how long the workflow is, how many stages it
has, or how much time/output it may consume. There is no Task/Agent tool
available to you for this job; if you find yourself considering delegating
"given the scale of this task", stop and continue executing the remaining
stages directly instead. Long-running, multi-hour, multi-stage workflows are
expected and must be completed end-to-end in this same session.

CRITICAL — Nested canvas Add Step protocol:
The small "+" node between Start and Error Handler is rendered inside the
WSO2 Integrator flow canvas and a browser_click can report success without
opening the node palette. When adding a step to an Automation flow, follow
this protocol exactly:
1. Take a fresh browser_snapshot and confirm the detailed flow shows Start,
   Error Handler, and the intervening "+" node.
2. Try browser_click ONCE with the newest "+" reference. Take another
   snapshot. The click succeeded only if the node palette is visible with
   Connections, the saved client, or node-search controls.
3. If the palette did not open, do not reuse either failed reference. Hover
   Start, take a fresh boxed snapshot, and retry ONCE only if it exposes a new
   reference for the intervening "+" node.
4. If it is still closed, target the stable flow-canvas container with
   browser_evaluate. Inspect descendant bounding boxes for the small SVG/path
   centered vertically between Start and Error Handler. Use the center point
   with the target element's ownerDocument.elementFromPoint(), ascend to the
   nearest clickable ancestor, and call click() or dispatch a bubbling,
   cancelable MouseEvent('click'). Derive all geometry from the current DOM.
5. Take a fresh snapshot immediately. Continue only after the node palette is
   visibly open. If verification fails, repeat DOM discovery from that new
   snapshot; never reuse old references or coordinates.

For this recovery, NEVER use hard-coded top-page page.mouse coordinates,
hard-coded/generated iframe names or UUIDs, browser_run_code_unsafe, a switch
to Sequence view, repeated stale-reference clicks, or screenshots to analyze
the UI. Operate through browser_snapshot and a target-scoped browser_evaluate.
Do not select a connection or operation until the opened palette is verified.
""".strip()


def truncate_tool_input(tool_input: any, max_length: int = 500) -> str:
    """
    Truncate large tool inputs for readable logging.
    
    For Task tool with massive execution prompts, shows first ~500 chars.
    For other tools, shows the full input if short, truncated if long.
    """
    # Convert dict/object to JSON string for display
    if isinstance(tool_input, dict):
        text = json.dumps(tool_input, indent=None)
    else:
        text = str(tool_input)
    
    # Truncate if too long
    if len(text) > max_length:
        return text[:max_length] + f"... (truncated, {len(text)} total chars)"
    return text


async def run_agent(job_id: str, prompt_path: str, model: str) -> None:
    jobs[job_id]["status"] = "running"

    def log(label: str, text: str) -> None:
        jobs[job_id]["logs"].append(f"[{label}] {text}")

    try:
        prompt = Path(prompt_path).read_text()

        # Pre-create artifact directories so Playwright MCP can save screenshots
        for subdir in ["screenshots", "workflow-docs"]:
            (Path(CWD) / "artifacts" / subdir).mkdir(parents=True, exist_ok=True)

        async for message in query(
            prompt=prompt,
            options=ClaudeAgentOptions(
                model=model,
                cwd=CWD,
                system_prompt=AGENT_SYSTEM_PROMPT,
                allowed_tools=[
                    "Bash",
                    "Read",
                    "Write",
                    "Edit",
                    "mcp__playwright__browser_navigate",
                    "mcp__playwright__browser_navigate_back",
                    "mcp__playwright__browser_click",
                    "mcp__playwright__browser_type",
                    "mcp__playwright__browser_fill_form",
                    "mcp__playwright__browser_take_screenshot",
                    "mcp__playwright__browser_run_code",
                    "mcp__playwright__browser_snapshot",
                    "mcp__playwright__browser_evaluate",
                    "mcp__playwright__browser_wait_for",
                    "mcp__playwright__browser_select_option",
                    "mcp__playwright__browser_press_key",
                    "mcp__playwright__browser_hover",
                    "mcp__playwright__browser_drag",
                    "mcp__playwright__browser_tabs",
                    "mcp__playwright__browser_close",
                    "mcp__playwright__browser_resize",
                    "mcp__playwright__browser_handle_dialog",
                    "mcp__playwright__browser_file_upload",
                    "mcp__playwright__browser_install",
                    "mcp__playwright__browser_console_messages",
                    "mcp__playwright__browser_network_requests",
                ],
                # Structurally block sub-agent delegation. The agent must execute the
                # entire workflow itself — see AGENT_SYSTEM_PROMPT. Some models will
                # otherwise invoke Task/Agent to hand off long-running work to a fresh
                # sub-agent session, which loses grounding built up via prior
                # browser_snapshot calls and has caused UI-interaction regressions
                # (e.g. failing to locate the "+" icon inside automation entry point
                # nodes).
                disallowed_tools=["Task", "Agent"],
                mcp_servers={
                    "playwright": {
                        "command": "npx",
                        "args": [
                            "@playwright/mcp@latest",
                            "--headless",
                            "--viewport-size=1720,968",
                            f"--output-dir={CWD}/artifacts/screenshots",
                            "--output-mode",
                            "stdout",
                        ],
                    }
                },
                permission_mode="acceptEdits",
                max_buffer_size=32 * 1024 * 1024,  # 32 MB — screenshots at 1920x1080 can be 1.5–3 MB as base64
            ),
        ):
            if isinstance(message, SystemMessage):
                session_id = getattr(message, "session_id", None)
                subtype = getattr(message, "subtype", "unknown")
                label = "SESSION" if subtype == "init" else "SYSTEM"
                detail = f"id={session_id}" if session_id else f"subtype={subtype}"
                log(label, detail)

            elif isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        log("CLAUDE", block.text)
                    else:
                        tool_name = getattr(block, "name", block.__class__.__name__)
                        tool_input = getattr(block, "input", "")
                        truncated_input = truncate_tool_input(tool_input)
                        log("TOOL", f"{tool_name} → {truncated_input}")

            elif isinstance(message, ResultMessage):
                log("RESULT", message.result)

                usage = getattr(message, "usage", None)
                turns = getattr(message, "num_turns", None)

                if usage:
                    input_tokens = getattr(usage, "input_tokens", 0)
                    output_tokens = getattr(usage, "output_tokens", 0)
                    cache_read = getattr(usage, "cache_read_input_tokens", 0)
                    cache_write = getattr(usage, "cache_creation_input_tokens", 0)
                    log(
                        "USAGE",
                        f"input={input_tokens} output={output_tokens} "
                        f"cache_read={cache_read} cache_write={cache_write}",
                    )
                else:
                    input_tokens = output_tokens = cache_read = cache_write = 0

                if turns is not None:
                    log("USAGE", f"turns={turns}")

                # Store structured usage so it is returned in /jobs/<id> response.
                jobs[job_id]["usage"] = {
                    "inputTokens": input_tokens,
                    "outputTokens": output_tokens,
                    "cacheReadTokens": cache_read,
                    "cacheWriteTokens": cache_write,
                    "numTurns": turns,
                }

        jobs[job_id]["status"] = "done"
    except Exception as exc:
        log("ERROR", str(exc))
        jobs[job_id]["status"] = "error"


async def post_run(request: web.Request) -> web.Response:
    data = await request.json()
    prompt_path = data.get("prompt_path")
    model = data.get("model", AI_MODEL)
    if not prompt_path:
        return web.json_response({"error": "prompt_path required"}, status=400)
    # Resolve relative paths against the project root (CWD) so callers can
    # pass paths like "./artifacts/execution-prompt/..." regardless of which
    # directory the server process was started from.
    resolved = Path(prompt_path)
    if not resolved.is_absolute():
        resolved = Path(CWD) / prompt_path
    if not resolved.exists():
        return web.json_response(
            {"error": f"prompt file not found: {resolved}"}, status=404
        )
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"logs": [], "status": "queued", "usage": None}
    task = asyncio.create_task(run_agent(job_id, str(resolved), model))
    running_tasks.add(task)
    task.add_done_callback(running_tasks.discard)
    return web.json_response({"job_id": job_id})


async def get_job(request: web.Request) -> web.Response:
    job_id = request.match_info["job_id"]
    if job_id not in jobs:
        return web.json_response({"error": "not found"}, status=404)
    return web.json_response(jobs[job_id])


async def get_health(request: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


async def post_shutdown(request: web.Request) -> web.Response:
    for task in list(running_tasks):
        task.cancel()

    async def stop_later() -> None:
        if running_tasks:
            await asyncio.gather(*running_tasks, return_exceptions=True)
        asyncio.get_event_loop().stop()

    asyncio.create_task(stop_later())
    return web.json_response({"status": "shutting down"})


def main() -> None:
    parser = argparse.ArgumentParser(description="Claude Agent SDK HTTP server")
    parser.add_argument(
        "--port", type=int,
        default=int(os.environ.get("AGENT_SERVER_PORT", 8765)),
        help="Port to listen on (default: AGENT_SERVER_PORT env var, then 8765)",
    )
    args = parser.parse_args()

    app = web.Application()
    app.router.add_post("/run", post_run)
    app.router.add_get("/jobs/{job_id}", get_job)
    app.router.add_get("/health", get_health)
    app.router.add_post("/shutdown", post_shutdown)

    web.run_app(app, host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
