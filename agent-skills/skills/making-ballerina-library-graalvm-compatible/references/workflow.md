# Making a Ballerina Library GraalVM Compatible — Internal Agent Workflow Guide

This document is for the agent's internal use. It describes the decision tree, routing rules, and behavioural contracts across stages. Unlike a linear pipeline, this workflow branches based on what the baseline build/test reveals.

---

## Stage routing (decision tree)

```
00. setup              → always runs (cannot be skipped)
01. build-and-test     → always runs; establishes the baseline
        │
        ├─ build-time errors ──► class-init-fix-procedure.md (loop) ─► re-run 01
        │
        ├─ all green + no warning ─────────────────────────► jump to 06 (mark)
        │
        └─ runtime/test failures OR not-verified warning ──► continue
02. reachability-repo  → if THIRD_PARTY_DEPS non-empty; look up published metadata first
03. trace-jar          → if HAS_MAIN or HAS_SERVICE, and gaps remain after 02
04. trace-tests        → if HAS_TESTS, and test failures remain after 02/03
05. filter-and-pack    → if 02/03/04 produced configs to keep
06. mark-compatible    → always runs last
```

**Prefer the reachability-metadata repo (02) over tracing (03/04).** Repo configs are maintainer-vetted and deterministic. Only trace for what the repo does not cover.

---

## Baseline classification (stage 01)

Run `parse_graalvm_errors.py` on the captured output and classify:

| Signal | Route |
|---|---|
| `not_verified_warning: true` | package/dep not marked compatible → resolve via 02 + 06 |
| `class_init` non-empty | build-time → `class-init-fix-procedure.md` loop |
| `out_of_memory: true` | raise builder memory (`-J-Xmx8g`) and retry |
| `missing_metadata` non-empty | runtime → 02 (repo) then 03/04 (trace) |
| all empty, build+test pass | ready to mark (06) |

---

## Class-init fix loop

Build-time class-initialization errors are resolved **inline in stage 01** using `class-init-fix-procedure.md` (analogous to the connector skill's fix procedure). There is no separate stage. Up to N iterations, then escalate to the user.

---

## Tracing agent contract

Two distinct paths, both in `tracing-agent.md`:
- **JAR path (03)** — for a `main` or a service. Requires the user to *exercise* the running artifact so the agent observes real dynamic-feature usage.
- **Tests path (04)** — version-sensitive `BTestMain` invocation. `build_btest_command.py` is the single source of truth for the command; show it and confirm the resolved update branch before running (a wrong signature silently yields bad metadata).

Always validate collected config by rebuilding with `--graalvm-build-options="-H:ConfigurationFileDirectories=<CONFIG_DIR>"` before packing.

---

## Filtering & packing contract

- `filter_trace_configs.py` prunes JDK/Ballerina-runtime noise. The keep/drop decision is judgment — review the report; over-packing bloats the binary, under-packing reintroduces runtime errors. Use conditional (`typeReached`) entries.
- Pack into `META-INF/native-image/<groupId>/<artifactId>/`. If no native module exists, scaffold one, build a resources jar, and add it as a `[[platform.javaXX.dependency]]`. See `pack-and-mark.md`.

---

## Interactive mode

When `INTERACTIVE_MODE` is enabled, after each stage print what changed and ask: "Proceed to the next stage? [Y/n/q]".

---

## Guardrails

- Never mark the package compatible (06) if the last `bal build --graalvm` failed — print why and stop.
- Degrade gracefully if the reachability repo is unreachable (network/rate-limit): fall back to tracing and log which deps were skipped.
- Surface (never silently drop) the darwin-aarch64 experimental warning and any GraalVM-JDK/required-JDK mismatch.

---

## Final Summary Format

At the end (or on abort), print:

```
=== Ballerina GraalVM Compatibility — Run Summary ===
Package:        <org>/<name>  (distribution <BAL_DISTRIBUTION>)
GraalVM:        JDK <GRAALVM_JDK_ACTUAL> (required <REQUIRED_GRAALVM_JDK>)  <ok/mismatch>
Baseline:       build <pass/fail>  test <pass/fail>  not-verified-warning <yes/no>
Repo metadata:  <n> dep(s) matched, <m> missed
Tracing:        jar <run/skip>  tests <run/skip>
Packed configs: META-INF/native-image/<groupId>/<artifactId>/  (<files>)
Ballerina.toml: [platform.<javaXX>] graalvmCompatible = true  <set/already>
Final verify:   bal build --graalvm <pass/fail>   bal test --graalvm <pass/fail>

Next steps:
  1. Review the packed reachability-metadata.json for over/under-inclusion.
  2. Commit the native config files and Ballerina.toml change.
  3. Confirm the module's GraalVM Check workflow passes in CI.
```
