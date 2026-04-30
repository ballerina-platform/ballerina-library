"""
Centralized status dashboard for Java 25 compatibility test workflows.

For every module in stdlib_modules.json (excluding generated_connectors and driver_modules),
queries the latest `build-with-java25.yml` run on the `java-25` branch via the GitHub CLI
and prints a colour-coded summary table.

Usage:
    python3 check_java25_status.py
    python3 check_java25_status.py --json     # machine-readable JSON
    python3 check_java25_status.py --failures  # only show failed / not-started
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

from colorama import Fore, Style, init

init(autoreset=True)

SCRIPT_DIR = Path(__file__).parent
STDLIB_MODULES_JSON = SCRIPT_DIR.parent.parent / "release" / "resources" / "stdlib_modules.json"

GITHUB_ORG = "ballerina-platform"
WORKFLOW_FILE = "build-with-java25.yml"
BRANCH = "java-25"

STATUS_ICON = {
    "success":    f"{Fore.GREEN}✅ passed    {Style.RESET_ALL}",
    "failure":    f"{Fore.RED}❌ failed    {Style.RESET_ALL}",
    "cancelled":  f"{Fore.YELLOW}⚠️  cancelled {Style.RESET_ALL}",
    "timed_out":  f"{Fore.RED}⏰ timed_out {Style.RESET_ALL}",
    "in_progress": f"{Fore.CYAN}⏳ running   {Style.RESET_ALL}",
    "queued":     f"{Fore.CYAN}🕐 queued    {Style.RESET_ALL}",
    "not_started": f"{Fore.WHITE}⬜ not started{Style.RESET_ALL}",
    "unknown":    f"{Fore.WHITE}❓ unknown   {Style.RESET_ALL}",
}


def main():
    parser = argparse.ArgumentParser(description="Java 25 workflow status dashboard")
    parser.add_argument("--json", action="store_true", dest="output_json", help="Output as JSON")
    parser.add_argument("--failures", action="store_true", help="Only show failures and not-started")
    args = parser.parse_args()

    modules = load_modules()
    results = []

    for i, module in enumerate(modules):
        name = module["name"]
        status = get_run_status(name)
        results.append({"name": name, **status})
        if not args.output_json:
            print(f"\r  Fetching status… {i + 1}/{len(modules)}", end="", flush=True)

    if not args.output_json:
        print()  # newline after progress

    if args.output_json:
        print(json.dumps(results, indent=2))
        return

    # Compute summary counts
    conclusions = [r["conclusion"] for r in results]
    passed   = conclusions.count("success")
    failed   = conclusions.count("failure")
    running  = sum(1 for r in results if r["status"] in ("in_progress", "queued"))
    not_done = sum(1 for r in results if r["conclusion"] == "not_started")
    other    = len(results) - passed - failed - running - not_done

    print()
    print("=" * 90)
    print(f"  Java 25 Compatibility Test Dashboard — branch: {BRANCH}")
    print("=" * 90)
    print(f"  {'Module':<55} {'Status':<22} {'URL'}")
    print("-" * 90)

    for r in results:
        key = r["conclusion"] if r["status"] == "completed" else r["status"]
        if key not in STATUS_ICON:
            key = "unknown"

        if args.failures and key not in ("failure", "not_started", "timed_out"):
            continue

        icon = STATUS_ICON[key]
        url = r.get("url", "")
        print(f"  {r['name']:<55} {icon} {url}")

    print("-" * 90)
    print(f"  Total: {len(results)}  |  ✅ passed: {passed}  |  ❌ failed: {failed}  "
          f"|  ⏳ running/queued: {running}  |  ⬜ not started: {not_done}  |  other: {other}")
    print("=" * 90)


def get_run_status(repo_name):
    cmd = [
        "gh", "run", "list",
        "--repo", f"{GITHUB_ORG}/{repo_name}",
        "--workflow", WORKFLOW_FILE,
        "--branch", BRANCH,
        "--limit", "1",
        "--json", "status,conclusion,url",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return {"status": "unknown", "conclusion": "unknown", "url": ""}
        runs = json.loads(result.stdout)
        if not runs:
            return {"status": "not_started", "conclusion": "not_started", "url": ""}
        run = runs[0]
        return {
            "status": run.get("status", "unknown"),
            "conclusion": run.get("conclusion") or run.get("status", "unknown"),
            "url": run.get("url", ""),
        }
    except Exception as e:
        return {"status": "unknown", "conclusion": "unknown", "url": str(e)}


def load_modules():
    with open(STDLIB_MODULES_JSON) as f:
        data = json.load(f)
    modules = []
    for category in ("library_modules", "extended_modules", "handwritten_connectors", "tools"):
        modules.extend(data.get(category, []))
    return modules


if __name__ == "__main__":
    main()
