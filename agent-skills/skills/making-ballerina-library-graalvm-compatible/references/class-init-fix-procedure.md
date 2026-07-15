# Class-Initialization Fix Procedure — Reusable Build-Time Error Fixer

This is a **reusable procedure**, not a stage. It is invoked inline by stage 01 (and any later stage that re-runs a native build) whenever `bal build --graalvm` / `bal test --graalvm` fails at **build time**.

The most common build-time failure is a class-initialization error: a class was initialized during image building but must be initialized at run time (or vice versa). See `troubleshooting.md` and the GraalVM [Class Initialization](https://www.graalvm.org/jdk21/reference-manual/native-image/optimizations-and-performance/ClassInitialization/) reference.

---

## When to Invoke

Invoke whenever a native `bal build`/`bal test` exits non-zero AND `parse_graalvm_errors.py` reports a non-empty `class_init` list (or `other` lines mentioning class initialization / "initialized at build time").

Pass `BUILD_DIR` = the directory where the build ran (usually `BALLERINA_DIR`).

---

## Procedure

### Step 1: Classify the failure

`run_bal_command.py` writes captured output to a temp file on failure and prints `>>> output saved to: <path>`. Classify it:

```bash
<PYTHON_CMD> <skill-root>/scripts/parse_graalvm_errors.py "<printed-output-path>"
```

Capture the JSON. Use:
- `class_init` → the classes GraalVM complained about
- `out_of_memory` → if true, this is a memory issue, not class init — retry the build with `--graalvm-build-options="-J-Xmx8g"` first
- `other` → raw lines to read if `class_init` is empty but the build still failed

### Step 2: Fix loop — up to 3 iterations

Repeat until the build passes or 3 iterations are exhausted:

#### 2a. Decide the initialization strategy (judgment)

For each class in `class_init`, decide — informed by the error text and `troubleshooting.md` — whether it should be:
- **deferred to run time**: `--initialize-at-run-time=<class>` (most common fix for classes touching sockets, threads, native handles, or random seeds), or
- **forced to build time**: `--initialize-at-build-time=<class>`, or
- **fully linked**: `--link-at-build-time` (rarely needed).

Combine multiple classes comma-separated: `--initialize-at-run-time=com.a.Foo,com.b.Bar`.

#### 2b. Re-run the native build with the accumulated flags

Carry forward all flags chosen so far in one `--graalvm-build-options` string:

```bash
<PYTHON_CMD> <skill-root>/scripts/run_bal_command.py \
  "bal build --graalvm --graalvm-build-options=\"--initialize-at-run-time=<classes>\"" \
  "<BUILD_DIR>"
```

- Exit 0 → build clean, exit loop, report success. **Record the flags** — they are load-bearing and may need to persist (see note below).
- Non-zero → re-classify, add the newly reported classes, continue.

### Step 3: After 3 iterations with no success

Print the remaining classified errors and ask:
> 1. Continue anyway (proceed / skip to tracing for runtime metadata)
> 2. Stop here and investigate manually

---

## Important: persisting the initialization flags

`--initialize-at-run-time` flags passed via `--graalvm-build-options` are **build invocation flags**, not packaged metadata. A downstream consumer building a native image from this library will not automatically inherit them. If a class genuinely must be initialized at run time for the library to work, that intent belongs in the library's own native-image config (a `--initialize-at-run-time` entry recorded in the packed configuration, or the class registered appropriately). Flag this to the user during Step 3 / packing (`pack-and-mark.md`) rather than assuming a one-off build flag is sufficient.

---

## Reporting

After the procedure completes, print:

```
  Class-init fix: <passed after N iteration(s) / escalated to user>
  Flags applied:  --initialize-at-run-time=<...>  (persist? <yes/review>)
```
