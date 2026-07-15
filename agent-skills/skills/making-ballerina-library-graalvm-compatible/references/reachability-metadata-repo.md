# Using the oracle/graalvm-reachability-metadata Repository

The [`oracle/graalvm-reachability-metadata`](https://github.com/oracle/graalvm-reachability-metadata/tree/master/metadata) repository publishes vetted native-image metadata for many common Java libraries. The Ballerina GraalVM compatibility guide explicitly points to it. **This is the primary source of metadata for a library's third-party Java dependencies** — prefer it over the tracing agent, which should only fill the gaps the repo does not cover.

Why prefer it: the configs are maintainer-vetted, versioned, and deterministic — no noisy JDK/runtime entries to filter, no need to exercise services by hand.

---

## Repository layout

```
metadata/
└── <groupId>/                       # groupId keeps its dots, e.g. com.h2database
    └── <artifactId>/                # e.g. h2
        ├── index.json               # list of metadata-versions + tested-versions
        └── <metadata-version>/      # e.g. 2.1.210
            ├── index.json           # (optional) list of config files present
            ├── reachability-metadata.json      # unified (newer)
            └── reflect-config.json  ...         # legacy split (older)
```

The top-level `<groupId>/<artifactId>/index.json` is an array of entries like:

```json
[
  { "latest": true, "metadata-version": "2.1.210",
    "module": "com.h2database:h2",
    "tested-versions": ["2.1.210", "2.2.220", "2.2.224"] }
]
```

---

## Lookup procedure (stage 02)

For each dependency in `THIRD_PARTY_DEPS` (the `[[platform.javaXX.dependency]]` entries from `Ballerina.toml`):

```bash
<PYTHON_CMD> <skill-root>/scripts/lookup_reachability_metadata.py --deps-json deps.json
```

`deps.json` is a JSON list of `{groupId, artifactId, version}`. The script returns, per dependency:
- `has_metadata` — whether the repo publishes metadata for these coordinates
- `metadata_version` — the directory to fetch from (exact tested-version match if possible, else the entry marked `latest`)
- `version_tested` — whether the library's exact version was among the tested versions

**Version substitution**: the library's exact dependency version is often not among the tested versions. When `version_tested` is false, the script falls back to the `latest` published metadata. Flag this substitution to the user — the metadata is usually still correct, but confirm for major-version gaps.

**Graceful degradation**: if GitHub is unreachable or rate-limited, the script returns `has_metadata: false` with an `error` note and exits 0. Fall back to the tracing agent for those dependencies and log which were skipped — never fail the whole run on a network hiccup.

---

## Fetch procedure (feeds stage 05)

For each dependency with `has_metadata: true`, download its config files into a staging directory:

```bash
<PYTHON_CMD> <skill-root>/scripts/fetch_reachability_metadata.py \
  --group-id "<g>" --artifact-id "<a>" --metadata-version "<v>" \
  --out "<staging-dir>/<g>__<a>"
```

Record the staging dirs in `REACHABILITY_REPO_HITS`. In stage 05, these are packed (merged) into the module's `META-INF/native-image/<groupId>/<artifactId>/` alongside any filtered tracing output. Prefer repo-sourced entries when they overlap with traced ones. See `pack-and-mark.md`.

## Sources

- https://github.com/oracle/graalvm-reachability-metadata/tree/master/metadata
- Ballerina GraalVM compatibility guide: `docs/graalvm-compatibility-in-ballerina-libraries.md`
