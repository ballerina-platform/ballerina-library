---
name: generating-sap-s4hana-connectors
description: Build Ballerina connectors for SAP S/4HANA OData APIs (ballerinax/sap.s4hana.* packages in the module-ballerinax-sap.s4hana.<area> repos) from an api.sap.com spec, end to end - spec sanitization, operation IDs, client generation on ballerinax/sap 1.4.0, mock service and tests, docs.json/README with the communication-scenario setup guide, and repo registration (Gradle, workflows, README). Use this whenever the user wants a new S/4HANA connector or package (API_*_SRV, CE_*_0001, OData V2 or V4), wants to add an S/4HANA API to the inventory/qm/delivery/procurement/sales repos or a new area repo, wants to regenerate or re-sanitize an existing S/4HANA client, or mentions an S/4HANA API ID with "connector", even if they do not say "skill" or "generate".
---

# SAP S/4HANA connector

S/4HANA connectors live in one repo per business area
(`ballerina-platform/module-ballerinax-sap.s4hana.<area>`: inventory, qm, delivery, procurement,
sales, ...). Each SAP API becomes one package, `ballerinax/sap.s4hana.<api_id lower case>`,
generated from the api.sap.com spec with the repo's own sanitizer scripts and then adjusted for
`ballerinax/sap` 1.4.0. All packages in all area repos follow the same shape, so the goal is a
package indistinguishable from its siblings. The scripts below reproduce the published
connectors exactly; lean on them instead of hand-editing generated code.

`<skill-root>` below is the directory that holds this `SKILL.md` (with Claude Code,
`${CLAUDE_SKILL_DIR}`). You will usually run commands from the area repo, so always call the
scripts by that full path, `python3 <skill-root>/scripts/<script>.py`, never as a bare
`scripts/...` relative to the current directory. Each script prints what it did and exits
non-zero on failure.

| Script | Does |
|---|---|
| `spec_info.py <spec>` | API ID, module name, service path, OData version, communication scenario(s), operation counts, list/create/action paths |
| `register_package.py` | adds the package to Ballerina.toml/build.gradle/settings.gradle/gradle.properties/ballerina/build.gradle/workflows/README |
| `fix_type_titles.py <spec>` | renames spaced inline schema titles that would become escaped type names (run by the `sanitize` stage) |
| `generate_client.py --stage ...` | runs the repo's sanitizers, `bal openapi`, `clientSanitations.bal`, the sap 1.4.0 update, format and build |
| `modernize_connection_config.py <pkg>` | the sap 1.4.0 `ConnectionConfig`/init update (called by `generate_client.py`) |
| `make_mock_spec.py` | writes `docs/spec/<API_ID>_MOCK.json` with only the paths the tests call |
| `generate_mock.py` | generates `modules/mock` and wires the 9090 TLS listener and CSRF `HEAD` handler |
| `render_readmes.py <repo>` | renders package READMEs from `docs.json` like the Gradle task does |
| `check_quickstart.py <repo> <module>` | compiles the README quickstart against a local push of the package |

## Before you start

- **Spec.** The user downloads it from api.sap.com (needs an SAP login; you cannot fetch it).
  It is named `<API_ID>.json`, for example `API_INSPECTIONMETHOD_SRV.json` or
  `CE_APIRESERVATIONDOCUMENT_0001.json`. Ask where it is if they did not say.
- **Repo.** Find the user's clone of the area repo (`module-ballerinax-sap.s4hana.<area>`;
  ask for the path if it is not in the current directory or the conversation). Run
  `spec_info.py` on the spec to see what the API is about, and if the area is unclear, ask the
  user which repo it belongs in. If no repo fits, follow `<skill-root>/references/new-repo.md`.
- **Branch.** Create a branch for the package (for example `add-<module>`). Never commit to
  `main`. If the clone has a `fork` remote (the user's fork), that is where it gets pushed later.
- **Distributions.** Generation uses Ballerina 2201.10.3; building and testing use the repo's
  `ballerinaLangVersion` (2201.13.0 today). The scripts find both under the distributions
  folder (`/Library/Ballerina/distributions` on macOS, `/usr/lib/ballerina/distributions` on
  Linux, or `$BALLERINA_DIST_ROOT`) and never change the global `bal`; `bal dist pull 2201.10.3`
  installs the missing one. Why two: from 2201.12 on, `bal openapi` camel-cases operation IDs
  (`listA_InspectionMethods` becomes `listAInspectionMethods`), while every published S/4HANA
  connector keeps the underscore names. If 2201.10.3 is missing, tell the user rather than
  silently generating with a newer one. The spec stages run the repo's sanitizer scripts with
  the build distribution; that is expected.
- **Pre-revamp repos.** Some repos (sales, today) have not been moved to `ballerinax/sap` 1.4.0
  yet: their clients still build an `http:ClientConfiguration`, their `docs.json` has no
  `communication-scenario-id` or image keys, and their README template has no setup-guide
  placeholders. Still generate the new package on 1.4.0 with the full `docs.json` shape (the
  older Gradle task ignores keys it does not use), and copy the siblings for everything
  repo-level (README list style, Gradle task names; `register_package.py` does this). Tell the
  user the new package is ahead of its siblings, so a later revamp of the repo knows.

## Workflow

Commit after each numbered step that changes files, with messages like the repo history:
"Register api_x_srv package", "Add api_x_srv spec", "Sanitize api_x_srv spec", "Add operation id
to api_x_srv spec", "Generate http client from api_x_srv api", "Add test cases for api_x_srv
api", "Add documentation for api_x_srv". Reviewers diff the generated code step by step, so
separate commits matter more than usual here.

### 1. Inspect the spec

```bash
python3 <skill-root>/scripts/spec_info.py <path>/<API_ID>.json
```

Keep the output; later steps use `module`, `api_postfix`, `scenarios`, `title`, `list_paths`
and `create_paths`. If `scenarios` is empty, the spec has no communication scenario; ask the
user which arrangement exposes the service before writing the setup guide.

### 2. Register the package

```bash
python3 <skill-root>/scripts/register_package.py --repo <repo> --module <module> --api-id <API_ID> \
  --name "<Display Name>" --api-title "<title from spec_info>" \
  --keywords "<Business Object>" "<extra term>" \
  --description "The service allows to <what it does, in one sentence>."
```

`--name` is what follows "SAP S/4HANA" in the package title (`Inspection Method`, `Material
Stock`): usually the business object, without "API" or "- Read". If a sibling already uses that
name (common for a `CE_*_0001` OData V4 API next to its older V2 `API_*_SRV`), make it distinct,
for example by keeping the spec title's qualifier ("Reservation Document (A2X)"). Keywords add
the business object and one or two search terms on top of the area keywords from the template.

Write the `--description` sentence once and reuse it verbatim as the second sentence of the
`docs.json` description in step 6, so the root README and the package README agree.

Also add a line for the package to `changelog.md` if the repo keeps one per release (look at
how siblings were added). If it already has an entry for the package, it was released before
(being re-added or regenerated): leave the entry alone and pass `--version` with the siblings'
current version (from `gradle.properties`) instead of the 1.0.0 default.

`register_package.py` always writes the `Name/SAP S/4HANA <Name>` and `S/4HANA` keywords. A
pre-revamp repo's siblings lack them; keep them anyway and mention it with the other
"ahead of its siblings" notes.

### 3. Add and sanitize the spec

Copy the download to `docs/spec/<API_ID>.json` unchanged and commit it. Then:

```bash
python3 <skill-root>/scripts/generate_client.py --repo <repo> --api-id <API_ID> --stage sanitize   # commit
python3 <skill-root>/scripts/generate_client.py --repo <repo> --api-id <API_ID> --stage opid       # commit
```

**Operation ID clashes.** The `opid` stage stops if two operations get the same ID or one gets
an empty ID. The repo's `operationId.bal` has an exception list (`/$batch`, approval paths); a
new clash usually means an entity set and a navigation property pluralize to the same name.
Fix it in `docs/sanitation/operationId.bal` with an explicit `match` case, note it in
`docs/sanitations.md`, and rerun from `--stage sanitize` on a fresh copy of the spec. Changing
the shared script affects every package in the repo, so regenerate one sibling afterwards and
check that its client is unchanged.

### 4. Generate the client

```bash
python3 <skill-root>/scripts/generate_client.py --repo <repo> --api-id <API_ID> --stage client
```

It ends by printing `N remote functions for M spec operations`. A mismatch means `bal openapi`
dropped operations; its output (printed above) says which and why. The script stops if
`types.bal` contains an escaped type name (`Modified\ A_XType`, `Collection\ of\ X`): the repo
sanitizer leaves such titles alone and 11 published packages carry them, but new packages must
not. The `sanitize` stage already renames the two known patterns (`UpdateA_XWrapper`,
`CollectionOfX`) via `fix_type_titles.py`; if a new pattern appears, add it there and rerun from
`--stage sanitize`. A bare `Wrapper` type warning means a response title was not sanitized;
mention it to the user. Commit generation and post-processing together as
"Generate http client from <module> api"; the script does both. The client always uses remote
methods (`--client-methods remote`), like every published S/4HANA connector.

### 5. Mock service and tests

Pick one list path (from `list_paths`) and, if the API supports create, one create path or
action. Then:

```bash
python3 <skill-root>/scripts/make_mock_spec.py <repo>/docs/spec/<API_ID>.json <repo>/docs/spec/<API_ID>_MOCK.json /A_Entity:get /A_Entity:post
python3 <skill-root>/scripts/generate_mock.py --repo <repo> --api-id <API_ID>
```

`generate_mock.py` refuses to overwrite an existing `modules/mock` (it may already hold your
sample data); pass `--force` only when you mean to regenerate it from scratch.

Fill the generated resource bodies in `modules/mock/<module>_mock_service.bal` with realistic
sample data:

- **OData V2** (`/sap/opu/odata/...`): the list returns `{"d": {"results": [ {...}, ... ]}}`
  (or `{"d": {...}}` as older mocks do), create returns `{"d": {...}}`.
- **OData V4** (`/sap/opu/odata4/...`): the list returns `{"value": [ {...} ]}`, create returns
  the entity.
- Use field names and plausible values from the entity schema in `types.bal`. If a create needs
  master data a mock cannot know, the reference repos return an error response and the test
  asserts the error; either style is fine as long as the test is honest about it.

Write `tests/test.bal` from `<skill-root>/assets/test.bal.template` (a few older packages call it
`tests.bal`; `test.bal` is what most use). Replace the `@...@` placeholders: the
list method and return type come from `client.bal` (for example `listA_InspectionMethods` and
`CollectionOfA_InspectionMethodWrapper`), `ENVELOPE_FIELD` is `d` for V2 and `value` for V4, and
`@YEAR@` is the current year. The read test only asserts that a payload came back, so it also
holds on a live tenant with no data; assert on the mock's sample values in an extra mock-only
test if you want more. The template's live flag compares with `"true"`; older packages compare
with `"false"` (a known inversion), so do not copy theirs. Before running the tests, check
that no placeholder is left: `grep -n '@[A-Z_]*@' tests/test.bal` must print nothing.

Add a create or action test when the mock has one, with `enable: !isTestOnLiveServer`:

- **Create:** send a minimal entity and assert on the key the mock assigns.
- **Action (function import, from `spec_info.py`'s `action_paths`):** the generated method is
  `create<Action>` (operation IDs prefix every POST with `create`). Its parameters are OData
  literals, so string values must carry their quotes (`DeliveryDocument = "'80000012'"`). A V2
  action response is wrapped as `{"d": {"<ActionName>": {...}}}`.
- **Nullable fields (V2 and V4):** optional fields typed `string? X?` need `?.` access
  (`item?.X`), or the mock and test do not compile. Check `types.bal` before writing either.
- **Entity-set POST vs action:** a POST on an entity set that takes the entity as its body
  (`create_paths`, for example a simulation or deep insert) is a normal create with a record
  payload; the quoted-literal and `{"d": {"<ActionName>": ...}}` rules are only for
  `action_paths`.

```bash
cd <repo>/ballerina/<module> && IS_BAL_BUILD=true <distributions>/ballerina-<build>/bin/bal test
```

`IS_BAL_BUILD=true` makes the mock and the test find `../resources` certs; without it they look
in a Docker path. A modifying call that fails with `CSRF token not found` means the mock lacks
the CSRF `HEAD .()` resource (`generate_mock.py` adds it when the mock spec has a POST). Commit.

Harmless output you will see: `bal openapi --mode service` prints `ERROR: HTTP status code
'4XX' is not supported in Ballerina` (it only skips the error responses), and 2201.13.0 warns
that `--export-endpoints` needs 2201.13.3 or later.

### 6. Docs

Write `ballerina/<module>/docs.json`, matching the sibling packages' files:

```json
{
  "description": "WSO2 SAP S/4HANA <Name> provides a way to interact with the [<title> API](https://api.sap.com/api/<API_ID>/overview). The service allows to <...>.",
  "communication-scenario": "<scenario name from spec_info>",
  "communication-scenario-id": "SAP_COM_xxxx",
  "scenario-search-image": "s4-3-search-scenario-sap-com-xxxx.png",
  "new-arrangement-image": "s4-4-new-arrangement-sap-com-xxxx.png",
  "arrangement-details-image": "s4-5-arrangement-details-sap-com-xxxx.png",
  "import-statement": "import ballerinax/sap.s4hana.<module> as <alias>;",
  "client-init": "<alias>:Client <alias>Client = check new (",
  "api-invocation": "<alias>:<ListReturnType> <variable> = check <alias>Client-><listMethod>();",
  "key-features": ["three short capability bullets from the spec's entity sets and operations"]
}
```

- Always write all of these keys. A pre-revamp repo's README template uses fewer of them and
  its Gradle task ignores the rest; the extra keys are what the later revamp needs. In such a
  repo `render_readmes.py` cannot list missing screenshots (the template has no image
  placeholders), so name the three expected files to the user yourself.
- The alias is a short lower-camel name for the business object, in the style of the siblings
  (`inspectionmethod`, `outbDel`, `salesorder` for `ce_salesorder_0001`). Check the sibling
  `docs.json` files and match them; never keep `api_`, `ce_`, `_srv` or version suffixes.
- If the call passes OData query options, escape them as `\\$top` in JSON (Ballerina needs
  `\$top`).
- No em dashes in any docs text.

Then:

```bash
python3 <skill-root>/scripts/render_readmes.py <repo> <module>
python3 <skill-root>/scripts/check_quickstart.py <repo> <module>
```

`render_readmes.py` lists any `docs/setup/s4-3/4/5-...-sap-com-xxxx.png` screenshots that do
not exist yet. If a sibling already uses the same scenario, they exist. Otherwise the user has
to capture them in their S/4HANA tenant (Communication Arrangements app: scenario search, new
arrangement dialog, arrangement details). Tell them the exact file names, and remind them that
the details screen shows "Last Changed By" with a person's name, which must be redacted before
the image goes into a public repo. Commit.

### 7. Wrap up

- Check `git status`: no `Config.toml`, `target/` or stray `main.bal`. Dependencies.toml is
  tracked; keep the regenerated one.
- Report: operations generated vs spec, tests passing, quickstart compiled, screenshots still
  needed, and anything unusual (dropped operations, odd type names, sanitizer changes).
- Pushing, opening a PR and releasing to Central are separate decisions. Push and open PRs
  (draft by default) only when the user asks, and never release without explicit confirmation.

## Live tenant (optional)

Live tests need a communication user on an arrangement for the package's scenario. A 403 "no
start authorization for R3TR IWSV ..." means the user is not on that arrangement; it is not a
connector bug. Run only read tests live unless the user approves writes. Never write a password
into a file yourself: ask the user to put `isTestOnLiveServer = true`, `hostname`, `username`
and `password` into `tests/Config.toml` (git-ignored), run `bal test`, then delete the file.
Repeated 401s lock the SAP user, so try one request first.

## Regenerating an existing package

Same steps 3 to 5 against the original spec. The original is in the repo history (the
"Add <module> spec" commit; `git log -- docs/spec/<API_ID>.json`). The sanitizers are
deterministic: rerun on the original spec, they reproduce the committed client and types, apart
from a few `bal format` blank lines. (Some committed specs were trimmed later by hand, so compare
the generated code, not the spec files.)
