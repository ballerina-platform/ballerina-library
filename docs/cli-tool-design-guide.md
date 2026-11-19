# Ballerina CLI Tool Design Guide

This guide defines how Ballerina CLI tools (`bal openapi`, `bal grpc`, `bal graphql`, `bal asyncapi`, etc., and any future tool) are named, invoked and behave, so that every tool feels the same to users and scripts. It applies to tools invoked as bal \<tool\>. Built-in commands (bal build, bal run, bal test, bal new) are out of scope.

This guide is version- and implementation-agnostic. It describes the behavior we want from every Ballerina CLI tool. Some Rules need platform APIs that SwanLake (jBallerina) may not provide, and the output rules in section 7 assume a platform layer that renders results, which exists only in NutCracker. NutCracker (nBallerina) must provide them, and follows the guide in full. The core `bal` command follows the same rules, starting with NutCracker.

**Open for discussion:** how to apply the guide to SwanLake and NutCracker. Applying the Rules to existing SwanLake tools (OpenAPI, gRPC, etc.) would be a breaking change, so whether to do it is undecided. Applying them only to NutCracker would make migrating from SwanLake to NutCracker less smooth. Until this is decided, the Rules describe the target, and existing SwanLake tools may not follow all of them.

The keywords **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT** and **MAY** are used as in RFC 2119\.

## How to read the Rules

Each Rule has an ID, a strength, and an "Applies to" tag:

| Tag           | Meaning                                                                                                                                                        |
| :------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **G**         | Generator: reads an external specification and writes Ballerina sources                                                                                        |
| **E**         | Exporter: reads Ballerina sources and writes non-Ballerina artifacts (specifications, schemas)                                                                 |
| **R**         | Read-only tool: does not modify Ballerina sources or any file it did not generate. It may write reports to the build directory (validators, linters, scanners) |
| **All**       | Every tool                                                                                                                                                     |
| **J** / **N** | Only jBallerina / only nBallerina                                                                                                                              |

A tag without J or N applies to both platforms.

## Principles

1. **Follow POSIX/GNU conventions** unless a Rule says otherwise: stdout carries results, stderr carries everything else, and exit codes mean the same thing in every tool.
2. **Fail fast.** Every check that can be done before writing is done before writing. Nothing touches the destination until the whole run is known to be possible.
3. **Never guess.** A tool works on exactly one target. It never searches upward, silently picks one of several candidates, or silently overwrites.
4. **Same behavior everywhere.** An interactive run, a CI run and a build-tool run follow the same pipeline.

---

## 1\. Naming

For a tool named `<name>`:

| Item                                              | Name                                                                |
| :------------------------------------------------ | :------------------------------------------------------------------ |
| Command                                           | `bal <name>`                                                        |
| Repository                                        | `<name>-tool` (`https://github.com/ballerina-platform/<name>-tool`) |
| Ballerina package (as shown in Ballerina Central) | `tool_<name>`                                                       |
| Maven artifact (GitHub Packages)                  | `io.ballerina:<name>-tool`                                          |

**NAM-1 (MUST, All)** The repository is named `<name>-tool` and lives under `ballerina-platform`.

**NAM-2 (MUST, All)** The Ballerina package published to Ballerina Central is named `tool_<name>`.

**NAM-3 (MUST, All)** The command name `<name>` is lowercase, matches the repository, package and Maven artifact names, and is the same in all four places. It is used in error messages and help (`bal <name>`).

**NAM-4 (MUST, All)** The tool's build output is published to the repository's GitHub Packages as the Maven artifact `io.ballerina:<name>-tool`: group `io.ballerina`, artifact ID the same as the repository name. The Gradle subproject that builds it is named `<name>-tool`, which Gradle uses as the artifact ID, or the publication sets `artifactId` explicitly.

---

## 2\. Invocation

**Command line terms.** A command line is made of command words, flags and positional arguments. The command words are `bal`, the tool's name and, if the tool has subcommands, the subcommand's name (`bal discover client`). They choose the operation and are not arguments. A flag starts with `-` or `--`, is followed by its value if it takes one, and may appear anywhere after the command words. A positional argument is any other word: the input the operation acts on or, for an introspection tool, the thing the answer is about. Where to look, what to include and how to print are flags, even when they are required.  
**INV-1 (MUST, All)** Every command and every subcommand responds to `-h, --help` by printing help to stdout and exiting 0\. The platform's tool executor SHOULD provide this, so tools do not each implement it.

**INV-2 (MUST, All)** `bal <tool> -V, --version` prints the tool's version to stdout and exits 0\. Subcommands do not need it. The platform's tool executor SHOULD provide this, since it already tracks the active version of each tool, so tools do not each implement version reporting.

**INV-3 (MUST, All)** Long flags are lowercase kebab-case (`--dry-run`). Both `--flag value` and `--flag=value` are accepted. Boolean flags take no value (`--force`, never `--force=true`). Flag order never matters. A bare `--` ends option parsing.

**INV-4 (MUST, All)** A flag that takes several values accepts both repetition (`--tag a --tag b`) and a comma-separated list (`--tag a,b`). In `Ballerina.toml` the equivalent is an array (BLD-9).

**INV-5 (MAY, All)** Short flags may be grouped (`-nq`).

**INV-6 (MUST, All)** A tool takes at most one **positional argument**, its input (see Command line terms). A required input is that positional argument, never a flag. Everything else is a flag, including a required scope, such as the package in `bal discover client Client -p ballerina/http`.

**INV-7 (MUST NOT, All)** `-` is not accepted as an input or output path (no implicit stdin/stdout paths).

**INV-8 (MUST, All)** A tool with a single purpose has no subcommands (`bal scan <path>`), except `add` (BLD-13). A tool with several operations has one subcommand per operation. An introspection tool, which describes something without changing anything, names each subcommand after the kind of thing it describes (`bal discover client`, `bal discover resource`), not after a verb.

**INV-9 (MUST, N)** A tool that both generates Ballerina sources and exports artifacts from them uses verb subcommands named exactly `generate` and `export`. Subcommands are one level deep: variants within an operation are selected with flags (INV-11), not with further subcommands.

**INV-10 (SHOULD, J)** A new tool with those two operations uses the same `generate` and `export` verbs. Tools that predate this guide and choose the operation another way (for example, from the type of the input) keep their current behavior, so existing users are not broken.

**INV-11 (MAY, G)** A Generator that can produce more than one kind of code from the same specification (for example, a client or a service from an OpenAPI specification) selects it with `--mode <kind>`. The values are defined by the tool, are lowercase single words named after what is generated (`client`, `service`), and are listed in `--help`. `--mode` is optional and has a documented default, since a required choice would be a required input (INV-6). An invalid `--mode` is a usage error. `--mode` is not used to choose between generating and exporting.

**INV-12 (MAY, All)** A tool whose output artifact comes in several formats (for example, the report format of `bal scan`) selects the format with `--<artifact>-format <name>`, for example `--report-format`. The flag name is never plain `--format`, to avoid confusion with `--output-format` (OUT-3). The values are defined by the tool and listed in `--help`. The flag is optional and has a documented default.

**INV-13 (MUST, All)** `bal <tool> --help/-h` lists the tool's subcommands, if it has any.

### Short flags

**SHF-1 (MUST, All)** Every option has a long form. Short forms are never required.

**SHF-2 (MUST, All)** These short flags are reserved and, if present, have exactly this meaning:

| Short | Long        | Meaning                 |
| :---- | :---------- | :---------------------- |
| `-h`  | `--help`    | print help              |
| `-V`  | `--version` | print version           |
| `-v`  | `--verbose` | more detail             |
| `-q`  | `--quiet`   | errors only             |
| `-n`  | `--dry-run` | show what would be done |
| `-o`  | `--output`  | output location         |

`-V` is uppercase following GNU convention (`-v` is verbose, `-V` is version).

**Open for discussion:** in the core `bal` commands `-v` prints the version, which differs from the `-v` (verbose) / `-V` (version) split above.

**SHF-3 (MUST NOT, All)** `--force` has no short form. A destructive flag has to be typed out.

**SHF-4 (MUST NOT, All)** `--module` has no short form, and `-m` is reserved: no tool may use it.

**SHF-5 (SHOULD NOT, All)** No other short flags. A short flag is acceptable only for an option expected in most invocations and unambiguous across tools, it needs a documented reason, and it must not collide with the reserved flags above. Rarely used and ambiguous options never get one. `--license` and `--service` are examples that do not.

---

## 3\. Targets and packages

A tool that reads or writes Ballerina sources works on a **target**: a Ballerina package, a workspace, or a standalone `.bal` file.

**TGT-1 (MUST, All)** Given a package, the tool gets the package. Given a standalone `.bal` file, it gets the file.

**TGT-2 (MUST NOT, All)** A tool does not implement its own check for "is this a package". It loads the target with the Ballerina Package API and decides from the result. On jBallerina, use `ProjectLoader.load` and check `Project.kind()`:

- `BUILD_PROJECT`: a package. Accepted.
- `SINGLE_FILE_PROJECT`: a standalone `.bal` file. Accepted.
- `WORKSPACE_PROJECT`: a workspace, or a package that belongs to one. Accepted (TGT-7).
- `BALA_PROJECT`: rejected (TGT-6).

A path that does not exist, or that cannot be loaded as a project, fails with a `ProjectException`, which the tool reports as exit 3 (TGT-6). A `.bal` file inside a package loads as the `BUILD_PROJECT` of that package, so to apply TGT-5 the tool compares the given path with the root of the loaded project. Any capability a tool needs that the Package API does not expose is a platform requirement, not a reason for the tool to implement its own check.

**Note:** Do not use `ProjectUtils.isBallerinaProject`: it only tests for `Ballerina.toml` and cannot tell a workspace from a package.

**TGT-3 (MUST, All)** The default target is the current directory. The tool does not search parent directories for a package. (The lookup in TGT-5, which finds the package containing a given `.bal` file, is a Package API call and the only upward lookup.)

**TGT-4 (MUST, G)** A tool that writes more than one `.bal` file requires a package as its target. A standalone file is acceptable only when the tool produces exactly one `.bal` file.

**TGT-5 (MUST, All)** If the given path is a `.bal` file that lies inside a package, the tool rejects it with exit code 3, names the package root, and asks the user to provide the package path instead.

**TGT-6 (MUST, All)** If the target is neither a valid package nor a `.bal` file, the tool fails with exit code 3\.

**TGT-7 (MUST, All)** A tool works with workspaces through the Package API. `ProjectLoader.load` returns a `WORKSPACE_PROJECT` both for a workspace root and for a package listed in a workspace, so the tool compares the given path with the project root to tell them apart. Given a package path, it works on that member only, found with `WorkspaceProject.projects()`. Given a workspace root, the tool documents in `--help` whether it processes every member or requires a package. A tool that processes every member does so in dependency order (`WorkspaceProject.getResolution().dependencyGraph()`), and its results and diagnostics name the package they belong to.

**TGT-8 (MUST, All)** If the target package does not exist, the tool fails (exit code 3). It never creates a package.

**TGT-9 (MUST, All)** TGT-1 to TGT-8 and TGT-10 apply only to Ballerina sources. Non-Ballerina inputs and outputs (specifications, schemas) have no package requirement.

**TGT-10 (MUST, All)** A tool that works on a package belonging to a workspace loads it with `ProjectLoader.load`, so the Package API resolves the sibling packages. The tool never resolves workspace dependencies itself (TGT-2).

### Modules

**MOD-1 (MUST, G, E)** Every command that generates from or exports a package accepts `--module <name>`, selecting `<package root>/modules/<name>`. Without the flag, the default module (the package root) is used.

**MOD-2 (MUST, G)** If the named module does not exist, the tool creates it. The plan (FF-4) lists the creation, and a dry run reports it.

**MOD-2a (MUST, E)** If the named module does not exist, the tool fails with exit code 3, writes no output files, and reports the error (OUT-7).

**MOD-3 (MUST, All)** A `--module` value that is not a valid module name is a usage error (exit 2).

**MOD-4 (MUST, All)** `--module` combined with a standalone file is a usage error (exit 2).

**MOD-5 (MUST, R)** A read-only tool does not create modules. If the named module does not exist or is not a valid module, it fails with exit code 3\. (An invalid module name is still a usage error, MOD-3.)

**MOD-6 (SHOULD, R)** A read-only tool accepts `--module <name>` as in MOD-1. Without the flag it processes every module of the package, and `--module` narrows the run to that module. It documents this in `--help`.

### Selecting constructs inside a package

**SEL-1 (SHOULD, All)** A tool that can act on a subset of the constructs in a package (`service`, `listener`, type) offers a selector flag named after the construct, such as `--service` or `--type`. A tool that always needs every candidate may omit selectors. Existing tools whose filters predate this guide keep their current flags.

**SEL-2 (SHOULD, All)** `--service <base path>` is the standard way to select services. It selects every service with that base path. If several services share a base path (rare, for example on different listeners), the tool processes all of them.

**SEL-3 (SHOULD, All)** If no selector is given, the tool processes every candidate. If a selector matches nothing, the tool fails with a runtime error (exit 1\) that lists the available candidates. A tool that can handle only one candidate and finds several fails with a usage error (exit 2\) listing them.

### Compiling Ballerina sources

These Rules apply to exporters and read-only tools that need a compilation of the package (E, R). They do not apply to generators, which do not compile the sources they generate, or to a tool run through the build (section 10), where `bal build` manages the dependencies.

**CMP-1 (MUST, E, R)** A tool that needs a compilation loads the project with the `HARD` locking mode, `BuildOptions.builder().setLockingMode(PackageLockingMode.HARD)`, passed to `ProjectLoader.load`. It compiles with the versions in `Dependencies.toml` and never updates dependencies. The tool has no flag to change the locking mode or to compile offline.

**CMP-2 (MUST, E, R)** Before compiling, the tool checks that `Dependencies.toml` exists, using `Package.dependenciesToml()`. The check is needed because `HARD` falls back to the latest compatible versions when nothing is locked. If the file is missing, the tool fails with exit 1 and the `kind` `dependencies-not-locked`, which falls under `runtime` (ERR-7). The `suggestion` is `Run 'bal build' to lock the dependencies, then re-run.` and the `command` is `bal build <package path>`.

`bal openapi: error: dependencies are not locked for package 'petstore'`  
`Run 'bal build' to lock the dependencies, then re-run.`  
`Try: bal build ./petstore`

`{"severity":"error","kind":"dependencies-not-locked","message":"dependencies are not locked for package 'petstore'","suggestion":"Run 'bal build' to lock the dependencies, then re-run.","command":"bal build ./petstore"}`

**CMP-3 (MUST NOT, E, R)** A tool never creates or modifies `Dependencies.toml`, and never calls `Project.save()`. Updating dependencies is not a tool's job.

**CMP-4 (SHOULD, E, R)** Warnings that the compilation reports about dependencies, such as a `Dependencies.toml` written by an older distribution, are passed on as warnings (ERR-10).

---

## 4\. Inputs and outputs

**IO-1 (MUST, G, E)** The output location is `-o, --output <path>`, defaulting to the current directory. For Ballerina output it follows the target rules in section 3\.

**IO-2 (MUST, G)** `--license <file>`: the file's content is inserted **verbatim**, followed by one blank line, at the top of every generated `.bal` file. There is no short form.

**IO-3 (MUST, G)** The license file must exist, be readable text, and contain only Ballerina comment lines and blank lines, so the generated sources compile. This is checked in phase 3 of the pipeline (FF-4). Failure is exit 1 and names the first offending line.

**IO-4 (MUST NOT, E, R)** Exporters and read-only tools do not take `--license`.

**IO-5 (MUST, R)** A read-only tool that writes a report writes it to `<package root>/target/<tool>/` by default, or to the path given with `-o, --output`. It never writes a report into the sources. The report format is selected as in INV-12.

**IO-6 (MUST, R)** If `-o, --output` names an existing file outside `target/`, FF-5 and FF-6 apply to that file.

---

## 5\. Writing files: the fail-fast pipeline

These Rules apply to every tool that writes files (G, E). FF-9 also applies to read-only tools that write reports (R).

**FF-1 (MUST, G, E)** The tool must know it can complete the run before it starts writing. All validation happens first.

**FF-2 (MUST, G, E)** The tool provides `--force` (overwrite existing files without asking) and `-n, --dry-run`.

**FF-3 (MUST, G, E)** A tool that changes an existing file either replaces it entirely, or merges newly generated code into it without removing or altering user-written code. For example, regenerating GraphQL service stubs adds the new stubs and keeps resolvers that are already implemented. A tool does not otherwise edit a file it did not generate. A merged file is treated like an overwritten one in the plan, the prompt and the dry-run output (FF-4, FF-5, FF-7).

**FF-4 (MUST, G, E)** The run goes through these phases in order. A failure stops the run with the shown exit code, before any later phase:

| \#  | Phase                                                                                 | Exit code on failure |
| :-- | :------------------------------------------------------------------------------------ | :------------------- |
| 1   | Parse arguments                                                                       | 2                    |
| 2   | Resolve and validate the target (Package API)                                         | 3                    |
| 3   | Read and validate input content, including the license file                           | 1                    |
| 4   | Plan: compute the full list of files to create or overwrite, and any module to create | 1                    |
| 5   | Check writability of every destination, including parent directories                  | 1                    |
| 6   | Overwrite check (FF-5)                                                                | 4                    |
| 7   | Dry run stops here (FF-7)                                                             | 0                    |
| 8   | Write                                                                                 | 1                    |

**FF-5 (MUST, G, E)** If the plan replaces existing files, the tool shows the full list of files and asks **once**: `Overwrite these file(s)? [y/N]`. The prompt goes to stderr and the default is **No**. The prompt is an interaction, not a result or an error. It is always plain text, even when the output format is JSON (OUT-1 does not apply to it). A "no" answer exits with code 4 before anything is written. `--force` skips the prompt.

**FF-6 (MUST, G, E)** The tool prompts only when stdin and stderr are both a terminal. Otherwise, if files would be replaced and `--force` is not given, it fails with exit code 4 and a message that points to `--force`.

**FF-7 (MUST, G, E)** A dry run performs the checks of phases 1–6 (but never prompts), writes nothing, and reports the planned files as the OUT-11 result with `dryRun: true`, marking those that would be overwritten and any module to be created. A dry run with `--force` lists overwrites without prompting. It exits with the code of the failing phase (1–5) if one of those phases fails. The overwrite check (phase 6) never fails a dry run: overwrites are listed as in the result and the exit code is 0\.

**FF-8 (SHOULD, G, E)** Write into a temporary directory and move into place, so a failure or interrupt while writing leaves the destination unchanged. Moving several files is not atomic: if a move fails part-way, the tool does not roll back. It exits 1 and the error lists the files already written and the files not written.

**FF-9 (MUST, G, E, R)** Files under `<package root>/target/` are build artifacts, not sources. A tool may create or replace them without a prompt and without `--force`, and they are not part of the overwrite check (FF-5, FF-6). They are still checked for writability (FF-4, phase 5\) and listed in the result (OUT-11). A tool that writes both sources and build artifacts applies FF-1 to FF-8 to the sources only.

---

## 6\. Generated output

**GEN-1 (MUST, G)** Output is deterministic: the same input and options give byte-identical files. No timestamps or unordered iteration.

**GEN-2 (MUST, G)** Generated Ballerina sources are formatted with the Ballerina formatter and use LF line endings.

**GEN-3 (SHOULD, G)** Each generated file contains a notice that it is generated and by which tool. The order is: license header (IO-2), a blank line, the notice, then the source.

---

## 7\. Output, errors and signals

The core `bal` command follows the same rules, starting with NutCracker. In NutCracker a tool returns a structured result and the platform renders it (OUT-4).

### Format

**OUT-1 (MUST, All)** Output is either text or JSON. One format is used for the whole run, for both stdout and stderr.

**OUT-2 (MUST, All)** The default format is text when stdout is a terminal, and JSON otherwise. Redirecting stderr does not change it.

**OUT-3 (MUST, All)** `--output-format <text|json>` overrides the default in either direction. It has no short form and every command accepts it.

**OUT-4 (MUST, All)** A tool returns a structured result, or a typed error that carries its exit code, and the platform renders it. A tool does not print its result, and does not exit the process itself.

| Command                                | stdout is a terminal? | Format (stdout and stderr) |
| :------------------------------------- | :-------------------- | :------------------------- |
| `bal openapi ...`                      | yes                   | text                       |
| `bal openapi ...                       | jq`                   | no                         | JSON |
| `bal openapi ... > out.json`           | no                    | JSON                       |
| `bal openapi ... 2> err.log`           | yes                   | text                       |
| `bal openapi ... --output-format json` | any                   | JSON                       |

### Streams

**OUT-5 (MUST, All)** stdout carries the result and nothing else (`--help`, `--version`, the list of files, a listing). Progress, warnings, prompts and errors go to stderr.

**OUT-6 (MUST, All)** stderr carries warnings and the error, each as its own report. A warning does not appear in the result on stdout, so a caller that needs warnings reads stderr.

**OUT-7 (MUST, All)** On failure stdout is empty, and stderr ends with one error report. That report lists every problem found (ERR-6) in its `diagnostics`. The exception is a tool that produced a complete result before a policy gate failed (ERR-12): the result stays on stdout, and stderr carries the one error.

A failed run with a warning and two input errors (exit 1, stdout empty). Text:

`bal openapi: warning: operation 'listPets' has no operationId; generated 'getPets'`  
`bal openapi: error: petstore.yaml has 2 errors`  
`petstore.yaml:12:5: error: unknown type 'strng'`  
`petstore.yaml:20:9: error: missing required field 'operationId'`

JSON, one line per report:

`{"severity":"warning","message":"operation 'listPets' has no operationId; generated 'getPets'"}`  
`{"severity":"error","kind":"invalid-input","message":"petstore.yaml has 2 errors","diagnostics":[{"path":"petstore.yaml","line":12,"column":5,"severity":"error","message":"unknown type 'strng'"},{"path":"petstore.yaml","line":20,"column":9,"severity":"error","message":"missing required field 'operationId'"}]}`

### JSON

**OUT-8 (MUST, All)** Each JSON report is one object on one line, with camelCase keys. There is no pretty-print flag.

**OUT-9 (MUST, All)** Keys are only added, never renamed or removed.

**OUT-10 (SHOULD, All)** A listing that is cut says so with `shown`, `total` and `next`, where `next` is a runnable command:

`{"shown":40,"total":112,"items":[],"next":"bal discover --offset 40"}`

(`items` is left empty here for brevity.)

### Commands that write files

**OUT-11 (MUST, G, E)** The result lists `files`, each with a `path` and an `action` (`created`, `overwritten` or `merged`). `dryRun: true` is present only on a dry run (FF-7). This shape is a draft, to be validated against real tools.

`$ bal openapi generate petstore.yaml --mode client`  
`created  client.bal`  
`created  types.bal`  
`Generated 2 files.`

`{"files":[{"path":"client.bal","action":"created"},{"path":"types.bal","action":"created"}]}`

A dry run:

`$ bal openapi generate petstore.yaml --mode client --dry-run`  
`would create  client.bal`  
`would create  types.bal`  
`Dry run: nothing was written.`

`{"dryRun":true,"files":[{"path":"client.bal","action":"created"},{"path":"types.bal","action":"created"}]}`

### Verbosity, color and signals

**OUT-12 (MAY, All)** `-q, --quiet` prints only errors. `-v, --verbose` adds detail. If provided they follow SHF-2. They have no effect on JSON, which is always complete.

**OUT-13 (SHOULD NOT, All)** Stack traces are not printed by default. They appear only with `--verbose`, in text mode.

**OUT-14 (MAY, All)** Colored output, only in text mode, when stderr is a terminal and `NO_COLOR` is unset.

**OUT-15 (SHOULD, G, E)** On SIGINT the tool leaves no partial output (see FF-8) and exits 130\.

**OUT-16 (MUST, All)** `--help` and `--version` are always text.

### Errors and warnings

**ERR-1 (MUST, All)** Every error has a `kind` and a `message`. The `message` says what went wrong. It names the path, flag or value involved, is one line, starts in lowercase, has no trailing period, and has no stack trace or internal class name.

**ERR-2 (SHOULD, All)** A `suggestion` says how to fix it, as one full imperative sentence, for example `Re-run with --force to overwrite.`

**ERR-3 (SHOULD, All)** A `command` is the correct command, present only when exactly one fix applies. It is the full command with the user's own arguments and runs as printed. If the fix needs a value only the user knows, put that in the `suggestion` and leave `command` out.

**ERR-4 (MUST, All)** In text mode an error is printed as `bal <tool>: error: <message>`, with the suggestion indented below it, and the command indented below that, prefixed with `Try:`.

`bal openapi: error: client.bal already exists`  
`Re-run with --force to overwrite.`  
`Try: bal openapi generate petstore.yaml --mode client --force`

`{"severity":"error","kind":"overwrite-refused","message":"client.bal already exists","suggestion":"Re-run with --force to overwrite.","command":"bal openapi generate petstore.yaml --mode client --force"}`

**ERR-5 (MUST, All)** A problem in an input file is a diagnostic. In text mode it is `<path>:<line>:<col>: <severity>: <message>`, so editors can parse it. In JSON it is an entry of the error's `diagnostics` array, with `path`, `line`, `column`, `severity` and `message`.

**ERR-6 (SHOULD, All)** Report all independent input errors in a single run, up to a cap (suggested: 50), rather than stopping at the first.

**ERR-7 (MUST, All)** A `kind` is one of the core kinds below, or a tool-specific kind that declares which core kind it falls under. The core kind decides the exit code (section 8).

| kind                     | Exit code |
| :----------------------- | :-------- |
| `usage`                  | 2         |
| `invalid-target`         | 3         |
| `overwrite-refused`      | 4         |
| `invalid-input, runtime` | 1         |

**ERR-8 (MUST, All)** A usage error (exit 2\) in text mode is followed by a one-line synopsis and a pointer such as `Try 'bal <tool> --help' for more information.` The full help is not printed. The JSON error is unchanged. No other error prints usage text.

`bal openapi: error: missing required argument <input>`  
`Usage: bal openapi generate <input> [options]`  
`Try 'bal openapi generate --help' for more information.`

`{"severity":"error","kind":"usage","message":"missing required argument <input>","suggestion":"Run 'bal openapi generate --help' for the usage."}`

**ERR-9 (MUST, All)** A tool never guesses a near match. When a name does not match, it fails and lists the candidates (see SEL-3).

**ERR-10 (MUST, All)** Warnings never change the exit code. A warning is a report with `"severity":"warning"` and a `message`.

**ERR-11 (MAY, All)** `--strict` promotes warnings to errors.

**ERR-12 (SHOULD, All)** A tool-specific outcome that needs its own signal, such as findings that exceed a gate in `bal scan`, exits with 1 and uses a tool-specific `kind` that declares `runtime` as its core kind (ERR-7). A tool never defines a new exit code.

`{"severity":"error","kind":"gate-failed","message":"3 findings at or above severity 'high'"}`

---

## 8\. Exit codes

The table is closed. A tool MUST NOT define other codes.

| Code | Name              | When                                                                                                                                                   |
| :--- | :---------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | Success           | The run succeeded, or a dry run passed all checks                                                                                                      |
| 1    | Runtime error     | Any other failure: invalid input content, unwritable destination, write failure, or a tool-specific failure such as findings exceeding a gate (ERR-12) |
| 2    | Usage error       | Invalid invocation: unknown flag, missing required argument, flag without a value, invalid value, conflicting flags                                    |
| 3    | Invalid target    | The target is not a valid package or standalone file, a .bal file is inside a package, or the named module does not exist                                                               |
| 4    | Overwrite refused | The user answered No, or the tool could not prompt and `--force` was absent                                                                            |
| 130  | Interrupted       | SIGINT                                                                                                                                                 |

**EXIT-1 (MUST, All)** A usage error (exit 2\) prints the error (ERR-4), then the synopsis and help pointer (ERR-8). It does not dump the full help.

**EXIT-2 (MUST, All)** A runtime error (exit 1, 3 or 4\) prints only the error. It never prints usage text. The exit code follows the error's `kind` (ERR-7).

---

## 9\. Help text

**HLP-1 (MUST, All)** `--help` output has these sections, in order:

1. A one-line description, no trailing period.
2. `Usage:` synopsis in the form `bal <tool> [OPTIONS] <input>` (`[ ]` optional, `< >` required, `...` repeatable).
3. `Options:` as two columns. Long and short forms go together. Required options first, then the rest alphabetically.
4. `Examples:` with at least two realistic invocations, each with a one-line comment.

**HLP-2 (MUST, All)** Each option description is one line, written in the imperative, starting in lowercase, with no trailing period. A default is shown as `(default: x)`. Lines stay within 80 columns.

**HLP-3 (MUST NOT, All)** Help does not list exit codes per tool. Section 8 of this guide is the single reference.

**HLP-4 (MAY, All)** Where the help text is stored (resource file, source code) is up to the tool's framework. These Rules constrain only the printed output.

---

## 10\. Build-tool integration

A tool may also run during `bal build` through a `[[tool.<name>]]` entry in `Ballerina.toml`.

**BLD-1 (MUST, G, E)** A tool run by the build never prompts. `--force` is implied.

**BLD-2 (MUST, G, E)** The tool's options come from the `Ballerina.toml` entry. `--dry-run` and the overwrite prompt do not apply. `--license` is available as a `license` option, with IO-3 validation.

**BLD-3 (MUST, G, E)** Errors are reported as build diagnostics: a runtime error is an error-severity diagnostic and fails the build, a warning stays a warning. A usage error (exit 2 on the command line) corresponds to an invalid `Ballerina.toml` entry.

**BLD-4 (MUST, G, E)** The fail-fast pipeline (FF-4) still runs, minus the prompt and the dry run.

**BLD-5 (SHOULD, G, E)** Generated files go to a location the tool documents (the package's generated area), never into hand-written sources unless the user configures it.

### Deriving the `Ballerina.toml` entry

A feature available both on the command line and in the build uses one definition. The `Ballerina.toml` entry is derived from the CLI command, not invented separately.

**BLD-6 (MUST, G, E)** The entry is `[[tool.<name>]]`, where `<name>` is the tool's command name (NAM-3). Every entry has an `id`, unique within the package.

**BLD-7 (MUST, G, E)** The positional argument of the CLI command (the input) maps to the key `input`. Paths in an entry are relative to the package root. (On the command line, paths are relative to the current directory.)

**BLD-8 (MUST, G, E)** `--module` maps to the key `targetModule`.

**BLD-9 (MUST, G, E)** Every other option flag maps to `options.<key>`, where `<key>` is the long flag name in camelCase (`--client-methods` becomes `options.clientMethods`). Boolean flags are TOML booleans. Multi-value flags are TOML arrays, never comma-joined strings (the comma form in INV-4 is a command-line convenience only).

**BLD-10 (MUST, G, E)** Parity: every flag that affects the generated content has a key, and every key has a flag. These flags have no key: `--output`, `--force`, `--dry-run`, `--help`, `--version`, `-q/--quiet`, `-v/--verbose`. The build decides the output location (BLD-5) and never prompts (BLD-1).

**BLD-11 (MUST, G, E)** Unknown keys, values of the wrong type and invalid values are reported as error diagnostics at the `Ballerina.toml` location, in the ERR-5 form (`Ballerina.toml:<line>:<col>: error: <message>`). The message names the key, not the flag. Unknown keys are never ignored. In the pipeline (FF-4), phase 1 is "parse the entry".

**BLD-12 (MUST, G, E)** A tool that integrates with the build publishes a table in its documentation, and keeps it in sync, with one row per flag: CLI flag, `Ballerina.toml` key, type, default.

**BLD-13 (MAY, G, E)** A tool that integrates with the build may provide `bal <tool> add`, which writes the matching `[[tool.<name>]]` entry. It takes the same positional input and option flags as the CLI command (the BLD-12 table), plus `--id`. It follows the fail-fast pipeline (FF-4): it validates first, supports `--dry-run`, and if the `id` already exists it asks before replacing the entry, with `--force` skipping the prompt. It is the one exception to INV-8.

#### Example (illustrative): OpenAPI client generation

Command line:

`bal openapi ./openapi.yaml --module delivery --mode client --nullable --tags tag1,tag2 --license ./license.txt`

The equivalent entry:

`[[tool.openapi]]`  
`id = "client01"`  
`input = "./openapi.yaml"`  
`targetModule = "delivery"`  
`options.mode = "client"`  
`options.nullable = true`  
`options.tags = ["tag1", "tag2"]`  
`options.license = "./license.txt"`

How the pieces map:

- `./openapi.yaml` (the positional argument) becomes `input`.
- `--module delivery` becomes `targetModule`.
- `--mode client` becomes `options.mode`.
- `--nullable` becomes `options.nullable = true`.
- `--tags tag1,tag2` becomes the array `options.tags`.
- `--license ./license.txt` becomes `options.license`.
- `id` has no flag on the generating command. It exists only on `bal openapi add` (`--id`).

---

## Appendix A. Reviewer checklist

For each new tool, tick every Rule that applies to its kind and platform.

- [ ] NAM-1 to NAM-4 repository, package, Maven artifact and command names
- [ ] INV-1 `-h/--help` on all commands
- [ ] INV-2 `--version`
- [ ] INV-3, INV-4 flag syntax, comma or repeated values
- [ ] INV-6 the input is the only positional
- [ ] INV-7 no `-` paths
- [ ] INV-8 to INV-13 subcommand shape, \--mode and \--\<artifact\>-format
- [ ] SHF-2 to SHF-5 short flags
- [ ] TGT-1 to TGT-10 (Package API only, no upward search, `.bal` inside a package rejected, workspaces)
- [ ] MOD-1 to MOD-6 `--module`
- [ ] SEL-1 to SEL-3 selectors (if applicable)
- [ ] CMP-1 to CMP-4 `HARD` locking mode, `Dependencies.toml` check (E, R)
- [ ] IO-1 `-o/--output`
- [ ] IO-2, IO-3 `--license` (generators)
- [ ] IO-5, IO-6 report location (read-only tools)
- [ ] FF-2 `--force`, `--dry-run`
- [ ] FF-9 build-directory files need no prompt
- [ ] FF-4 pipeline order, FF-5 one prompt, FF-6 non-TTY behavior, FF-7 dry-run result
- [ ] GEN-1 deterministic, GEN-2 formatted, GEN-3 notice
- [ ] OUT-1 to OUT-4 text or JSON by TTY, \--output-format, platform renders
- [ ] OUT-5 to OUT-7 streams, OUT-8 to OUT-10 JSON, OUT-11 file list (G, E)
- [ ] ERR-1 to ERR-4 error content (what went wrong, how to fix it, correct command), ERR-5 to ERR-8 diagnostics and kinds, ERR-12 tool-specific failures
- [ ] Section 8 exit codes only, EXIT-1 and EXIT-2 usage text
- [ ] HLP-1 to HLP-3 help text
- [ ] BLD-1 to BLD-4 build integration
- [ ] BLD-6 to BLD-12 Ballerina.toml entry derivation, BLD-13 add (if provided)

## Appendix B. Exit codes in code

Define the exit codes once, and use a single exception type that carries one, so every phase of the pipeline (FF-4) fails with the code from section 8:

```java
final class ExitCodes {
    static final int SUCCESS = 0, RUNTIME = 1, USAGE = 2,
                     INVALID_TARGET = 3, OVERWRITE_REFUSED = 4, INTERRUPTED = 130;
}

final class ToolException extends RuntimeException {
    final int exitCode;
    ToolException(int exitCode, String message) { super(message); this.exitCode = exitCode; }
}
```
