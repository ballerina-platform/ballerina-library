from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def run(script: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPTS / script), *args], text=True,
                          capture_output=True, check=check)


def load_script_module(script: str):
    spec = importlib.util.spec_from_file_location(script.removesuffix(".py"), SCRIPTS / script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SchemaMappingTests(unittest.TestCase):
    def write_spec(self, directory: Path, schemas: dict) -> Path:
        path = directory / "aligned.json"
        spec = {
            "openapi": "3.0.0",
            "components": {"schemas": schemas},
            "paths": {
                "/items": {
                    "get": {
                        "responses": {
                            "200": {
                                "content": {
                                    "application/json": {
                                        "schema": {"$ref": "#/components/schemas/InlineResponse200"}
                                    }
                                }
                            }
                        }
                    }
                }
            },
        }
        path.write_text(json.dumps(spec), encoding="utf-8")
        return path

    def test_initial_and_rerun_mappings_are_stable_and_pruned(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory, {"InlineResponse200": {"type": "object"}, "User": {"type": "object"}})
            mappings, candidate, decisions = directory / "ai-mappings.json", directory / "candidate.json", directory / "decisions.json"
            prepared = json.loads(run("schema_mappings.py", "prepare", str(spec), str(mappings), str(candidate)).stdout)
            self.assertEqual({item["name"] for item in prepared["unseen_schemas"]}, {"InlineResponse200", "User"})
            decisions.write_text(json.dumps({"InlineResponse200": "UserListResponse", "User": "User"}), encoding="utf-8")
            run("schema_mappings.py", "apply", str(spec), str(candidate), str(decisions), str(mappings))
            generated = json.loads(spec.read_text(encoding="utf-8"))
            self.assertIn("UserListResponse", generated["components"]["schemas"])
            self.assertEqual(generated["paths"]["/items"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]["$ref"], "#/components/schemas/UserListResponse")
            persisted = json.loads(mappings.read_text(encoding="utf-8"))
            persisted["operationIds"] = {"/items": {"get": "listItems"}}
            mappings.write_text(json.dumps(persisted), encoding="utf-8")

            # A future flattened spec retains only known User plus a new schema.
            spec = self.write_spec(directory, {"User": {"type": "object"}, "Order": {"type": "object"}})
            prepared = json.loads(run("schema_mappings.py", "prepare", str(spec), str(mappings), str(candidate)).stdout)
            self.assertEqual([item["name"] for item in prepared["unseen_schemas"]], ["Order"])
            self.assertEqual(prepared["pruned_schema_names"], ["InlineResponse200"])
            decisions.write_text(json.dumps({"Order": "Order"}), encoding="utf-8")
            run("schema_mappings.py", "apply", str(spec), str(candidate), str(decisions), str(mappings))
            persisted = json.loads(mappings.read_text(encoding="utf-8"))
            self.assertEqual(set(persisted["schemaNames"]), {"User", "Order"})
            self.assertEqual(persisted["operationIds"], {"/items": {"get": "listItems"}})

    def test_collision_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory, {"A": {}, "B": {}})
            mappings, candidate, decisions = directory / "mappings.json", directory / "candidate.json", directory / "decisions.json"
            run("schema_mappings.py", "prepare", str(spec), str(mappings), str(candidate))
            decisions.write_text(json.dumps({"A": "Same", "B": "Same"}), encoding="utf-8")
            result = run("schema_mappings.py", "apply", str(spec), str(candidate), str(decisions), str(mappings), check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate", result.stderr)

    def test_duplicate_decision_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory, {"A": {}})
            mappings = directory / "mappings.json"
            candidate = directory / "candidate.json"
            decisions = directory / "decisions.json"
            run("schema_mappings.py", "prepare", str(spec), str(mappings), str(candidate))
            decisions.write_text('{"A": "A", "A": "Other"}', encoding="utf-8")
            result = run(
                "schema_mappings.py", "apply", str(spec), str(candidate),
                str(decisions), str(mappings), check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate JSON key", result.stderr)

    def test_schema_less_spec_prunes_stale_mappings(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = directory / "aligned.json"
            mappings = directory / "ai-mappings.json"
            candidate = directory / "candidate.json"
            spec.write_text(json.dumps({"openapi": "3.0.0", "paths": {}}), encoding="utf-8")
            mappings.write_text(json.dumps({
                "operationIds": {"/items": {"get": "listItems"}},
                "schemaNames": {"Removed": "Removed"},
                "custom": {"keep": True},
            }), encoding="utf-8")
            prepared = json.loads(run(
                "schema_mappings.py", "prepare", str(spec), str(mappings), str(candidate)).stdout)
            self.assertEqual(prepared["unseen_schemas"], [])
            self.assertEqual(prepared["pruned_schema_names"], ["Removed"])
            persisted = json.loads(mappings.read_text(encoding="utf-8"))
            self.assertEqual(persisted["schemaNames"], {})
            self.assertEqual(persisted["operationIds"], {"/items": {"get": "listItems"}})
            self.assertEqual(persisted["custom"], {"keep": True})
            self.assertEqual(next(iter(persisted)), "_warning")

    def test_schema_less_shapes_are_all_accepted(self) -> None:
        variants = [
            {},
            {"components": {}},
            {"components": {"schemas": []}},
            {"components": {"schemas": {}}},
        ]
        for index, variant in enumerate(variants):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as temp:
                directory = Path(temp)
                spec = directory / "aligned.json"
                mappings = directory / "mappings.json"
                candidate = directory / "candidate.json"
                document = {"openapi": "3.0.0", "paths": {}, **variant}
                spec.write_text(json.dumps(document), encoding="utf-8")
                prepared = json.loads(run(
                    "schema_mappings.py", "prepare", str(spec), str(mappings),
                    str(candidate)).stdout)
                self.assertEqual(prepared["unseen_schemas"], [])
                self.assertEqual(json.loads(mappings.read_text(encoding="utf-8"))["schemaNames"], {})


class OperationIdMappingTests(unittest.TestCase):
    def write_spec(self, directory: Path) -> Path:
        path = directory / "aligned.json"
        path.write_text(json.dumps({
            "openapi": "3.0.0",
            "paths": {
                "/v1.0/users/{id}": {
                    "get": {
                        "operationId": "getV10UsersId",
                        "summary": "Get a user",
                        "parameters": [{"name": "id", "in": "path", "required": True}],
                    },
                    "post": {"operationId": "postV10UsersId", "summary": "Update a user"},
                },
                "/removed-on-next-run": {"delete": {"operationId": "deleteItem"}},
            },
            "components": {"schemas": {"User": {"type": "object"}}},
        }), encoding="utf-8")
        return path

    def test_mappings_are_stable_partial_and_pruned(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            mappings = directory / "ai-mappings.json"
            candidate = directory / "candidate.json"
            decisions = directory / "decisions.json"
            mappings.write_text(json.dumps({
                "schemaNames": {"User": "User"},
                "operationIds": {
                    "/v1.0/users/{id}": {"get": "getUser"},
                    "/stale": {"get": "staleId"},
                },
                "custom": "keep",
            }), encoding="utf-8")
            prepared = json.loads(run(
                "operation_id_mappings.py", "prepare", str(spec), str(mappings), str(candidate)).stdout)
            self.assertEqual(prepared["reused_count"], 1)
            self.assertEqual(prepared["pruned_operations"], ["get /stale"])
            unseen = {(item["path"], item["method"]) for item in prepared["unseen_operations"]}
            self.assertEqual(unseen, {
                ("/v1.0/users/{id}", "post"),
                ("/removed-on-next-run", "delete"),
            })
            decisions.write_text(json.dumps({
                "/v1.0/users/{id}": {"post": "getUser"},
            }), encoding="utf-8")
            result = json.loads(run(
                "operation_id_mappings.py", "apply", str(spec), str(candidate),
                str(decisions), str(mappings)).stdout)
            self.assertEqual(result["applied_count"], 1)
            self.assertEqual(result["pending_count"], 1)
            generated = json.loads(spec.read_text(encoding="utf-8"))
            self.assertEqual(generated["paths"]["/v1.0/users/{id}"]["get"]["operationId"], "getUser")
            self.assertEqual(generated["paths"]["/v1.0/users/{id}"]["post"]["operationId"], "getUser1")
            persisted = json.loads(mappings.read_text(encoding="utf-8"))
            self.assertEqual(next(iter(persisted)), "_warning")
            self.assertEqual(persisted["schemaNames"], {"User": "User"})
            self.assertEqual(persisted["custom"], "keep")
            self.assertNotIn("/stale", persisted["operationIds"])

    def test_partial_apply_reserves_ids_from_omitted_operations(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = directory / "aligned.json"
            mappings = directory / "ai-mappings.json"
            candidate = directory / "candidate.json"
            decisions = directory / "decisions.json"
            spec.write_text(json.dumps({
                "openapi": "3.0.0",
                "paths": {
                    "/decided": {"post": {"operationId": "createItem"}},
                    "/omitted": {"get": {"operationId": "listItems"}},
                },
            }), encoding="utf-8")
            run("operation_id_mappings.py", "prepare", str(spec), str(mappings), str(candidate))
            decisions.write_text(json.dumps({
                "/decided": {"post": "listItems"},
            }), encoding="utf-8")

            result = json.loads(run(
                "operation_id_mappings.py", "apply", str(spec), str(candidate),
                str(decisions), str(mappings)).stdout)

            generated = json.loads(spec.read_text(encoding="utf-8"))
            persisted = json.loads(mappings.read_text(encoding="utf-8"))
            self.assertEqual(result["pending_count"], 1)
            self.assertEqual(generated["paths"]["/decided"]["post"]["operationId"], "listItems1")
            self.assertEqual(generated["paths"]["/omitted"]["get"]["operationId"], "listItems")
            self.assertEqual(persisted["operationIds"]["/omitted"]["get"], "listItems")

    def test_duplicate_persisted_ids_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            mappings = directory / "mappings.json"
            candidate = directory / "candidate.json"
            mappings.write_text(json.dumps({"operationIds": {
                "/v1.0/users/{id}": {"get": "same", "post": "same"},
            }}), encoding="utf-8")
            result = run("operation_id_mappings.py", "prepare", str(spec), str(mappings),
                         str(candidate), check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate persisted", result.stderr)

    def test_first_run_reviews_all_operations_and_persists_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            mappings = directory / "mappings.json"
            candidate = directory / "candidate.json"
            decisions = directory / "decisions.json"
            prepared = json.loads(run(
                "operation_id_mappings.py", "prepare", str(spec), str(mappings), str(candidate)).stdout)
            self.assertEqual(len(prepared["unseen_operations"]), 3)
            decisions.write_text(json.dumps({
                "/v1.0/users/{id}": {
                    "get": "getV10UsersId",
                    "post": "updateUser",
                },
                "/removed-on-next-run": {"delete": "deleteItem"},
            }), encoding="utf-8")
            result = json.loads(run(
                "operation_id_mappings.py", "apply", str(spec), str(candidate),
                str(decisions), str(mappings)).stdout)
            self.assertEqual(result["applied_count"], 3)
            self.assertEqual(result["pending_count"], 0)
            persisted = json.loads(mappings.read_text(encoding="utf-8"))
            self.assertEqual(
                persisted["operationIds"]["/v1.0/users/{id}"]["get"], "getV10UsersId")

    def test_malformed_and_unknown_decisions_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            mappings = directory / "mappings.json"
            candidate = directory / "candidate.json"
            decisions = directory / "decisions.json"
            mappings.write_text(json.dumps({
                "operationIds": {"/v1.0/users/{id}": {"FETCH": "bad"}},
            }), encoding="utf-8")
            malformed = run(
                "operation_id_mappings.py", "prepare", str(spec), str(mappings),
                str(candidate), check=False)
            self.assertNotEqual(malformed.returncode, 0)
            self.assertIn("unsupported", malformed.stderr)

            mappings.write_text("{}", encoding="utf-8")
            run("operation_id_mappings.py", "prepare", str(spec), str(mappings), str(candidate))
            decisions.write_text(json.dumps({"/unknown": {"get": "unknown"}}), encoding="utf-8")
            unknown = run(
                "operation_id_mappings.py", "apply", str(spec), str(candidate),
                str(decisions), str(mappings), check=False)
            self.assertNotEqual(unknown.returncode, 0)
            self.assertIn("unexpected operations", unknown.stderr)

            decisions.write_text(
                '{"/v1.0/users/{id}":{"get":"first","get":"second"}}',
                encoding="utf-8")
            duplicate = run(
                "operation_id_mappings.py", "apply", str(spec), str(candidate),
                str(decisions), str(mappings), check=False)
            self.assertNotEqual(duplicate.returncode, 0)
            self.assertIn("duplicate JSON key", duplicate.stderr)


class DescriptionTests(unittest.TestCase):
    def write_spec(self, directory: Path) -> Path:
        path = directory / "aligned.json"
        path.write_text(json.dumps({
            "openapi": "3.0.0",
            "info": {"title": "Files API", "description": "Manage files"},
            "paths": {
                "/files.v3/upload": {
                    "post": {
                        "operationId": "uploadFile",
                        "summary": "Upload a file",
                        "requestBody": {
                            "required": True,
                            "content": {
                                "multipart/form-data": {
                                    "schema": {"$ref": "#/components/schemas/FileUploadRequest"}
                                }
                            },
                        },
                    }
                },
                "/json": {
                    "post": {
                        "requestBody": {
                            "description": "TBD",
                            "content": {"application/json": {"schema": {
                                "type": "object", "properties": {"name": {"type": "string"}}
                            }}},
                        }
                    }
                },
                "/documented": {
                    "post": {"requestBody": {"description": "Existing payload", "content": {}}}
                },
                "/reference": {
                    "post": {"requestBody": {"$ref": "#/components/requestBodies/Upload"}}
                },
            },
            "components": {
                "schemas": {"FileUploadRequest": {"type": "object"}},
                "securitySchemes": {
                    "private.apps": {
                        "type": "apiKey", "name": "private-app", "in": "header",
                        "x-ballerina-name": "privateApp",
                    },
                    "queryKey": {
                        "type": "apiKey", "name": "api_key", "in": "query", "description": "-",
                    },
                    "cookieKey": {
                        "type": "apiKey", "name": "session_key", "in": "cookie",
                    },
                    "documented": {
                        "type": "apiKey", "name": "key", "in": "cookie",
                        "description": "Existing API key",
                    },
                    "oauth": {"type": "oauth2", "flows": {}},
                },
            },
        }), encoding="utf-8")
        return path

    def test_prepare_and_partial_apply(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            requests = directory / "requests.json"
            decisions = directory / "decisions.json"
            prepared = json.loads(run(
                "spec_descriptions.py", "prepare", str(spec), str(requests)).stdout)
            self.assertEqual(prepared["request_body_count"], 2)
            self.assertEqual(prepared["security_scheme_count"], 3)
            self.assertEqual(
                {item["context"]["in"] for item in prepared["requests"]
                 if item["type"] == "securityScheme"},
                {"header", "query", "cookie"})
            multipart = next(item for item in prepared["requests"]
                             if item["location"].get("path") == "/files.v3/upload")
            self.assertTrue(multipart["context"]["required"])
            self.assertEqual(multipart["context"]["content"][0]["media_type"], "multipart/form-data")
            self.assertEqual(multipart["context"]["content"][0]["schema"]["reference"], "FileUploadRequest")
            scheme = next(item for item in prepared["requests"]
                          if item["location"].get("scheme_name") == "private.apps")
            self.assertEqual(scheme["context"]["x_ballerina_name"], "privateApp")
            decisions.write_text(json.dumps({
                multipart["id"]: "File content and upload options.",
                scheme["id"]: "Private app token supplied in the request header.",
            }), encoding="utf-8")
            result = json.loads(run(
                "spec_descriptions.py", "apply", str(spec), str(requests), str(decisions)).stdout)
            self.assertEqual(result["request_bodies_updated"], 1)
            self.assertEqual(result["security_schemes_updated"], 1)
            self.assertEqual(result["pending_count"], 3)
            generated = json.loads(spec.read_text(encoding="utf-8"))
            self.assertEqual(
                generated["paths"]["/files.v3/upload"]["post"]["requestBody"]["description"],
                "File content and upload options")
            self.assertEqual(
                generated["components"]["securitySchemes"]["private.apps"]["description"],
                "Private app token supplied in the request header")
            self.assertEqual(
                generated["paths"]["/documented"]["post"]["requestBody"]["description"],
                "Existing payload")
            self.assertNotIn("description", generated["components"]["securitySchemes"]["oauth"])

    def test_unknown_decision_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            requests = directory / "requests.json"
            decisions = directory / "decisions.json"
            run("spec_descriptions.py", "prepare", str(spec), str(requests))
            decisions.write_text(json.dumps({"unknown": "Useful description"}), encoding="utf-8")
            result = run("spec_descriptions.py", "apply", str(spec), str(requests),
                         str(decisions), check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown description", result.stderr)

    def test_normalized_empty_and_placeholder_decisions_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            requests = directory / "requests.json"
            decisions = directory / "decisions.json"
            prepared = json.loads(run(
                "spec_descriptions.py", "prepare", str(spec), str(requests)).stdout)
            request_id = prepared["requests"][0]["id"]
            original = spec.read_text(encoding="utf-8")

            for description in ("TBD", "TBD.", "  TBD.  ", ".", "..."):
                with self.subTest(description=description):
                    decisions.write_text(json.dumps({request_id: description}), encoding="utf-8")
                    result = run(
                        "spec_descriptions.py", "apply", str(spec), str(requests),
                        str(decisions), check=False)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("non-placeholder descriptions", result.stderr)
                    self.assertEqual(spec.read_text(encoding="utf-8"), original)

    def test_apply_preserves_description_added_after_prepare_and_rejects_duplicates(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            spec = self.write_spec(directory)
            requests = directory / "requests.json"
            decisions = directory / "decisions.json"
            prepared = json.loads(run(
                "spec_descriptions.py", "prepare", str(spec), str(requests)).stdout)
            body = next(item for item in prepared["requests"]
                        if item["location"].get("path") == "/json")
            generated = json.loads(spec.read_text(encoding="utf-8"))
            generated["paths"]["/json"]["post"]["requestBody"]["description"] = "Added by another step"
            spec.write_text(json.dumps(generated), encoding="utf-8")
            decisions.write_text(json.dumps({body["id"]: "Replacement"}), encoding="utf-8")
            result = json.loads(run(
                "spec_descriptions.py", "apply", str(spec), str(requests), str(decisions)).stdout)
            self.assertEqual(result["skipped_documented_count"], 1)
            preserved = json.loads(spec.read_text(encoding="utf-8"))
            self.assertEqual(
                preserved["paths"]["/json"]["post"]["requestBody"]["description"],
                "Added by another step")

            decisions.write_text(
                f'{{"{body["id"]}":"first","{body["id"]}":"second"}}',
                encoding="utf-8")
            duplicate = run(
                "spec_descriptions.py", "apply", str(spec), str(requests),
                str(decisions), check=False)
            self.assertNotEqual(duplicate.returncode, 0)
            self.assertIn("duplicate JSON key", duplicate.stderr)


class MetadataTests(unittest.TestCase):
    def test_request_bodies_security_schemes_and_no_schemas(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "spec.json"
            path.write_text(json.dumps({
                "openapi": "3.0.0",
                "info": {"title": "API"},
                "paths": {"/items": {"post": {"requestBody": {
                    "required": True,
                    "content": {"application/json": {
                        "schema": {"$ref": "#/components/schemas/Input"}
                    }},
                }}}},
                "components": {"securitySchemes": {"key": {
                    "type": "apiKey", "name": "X-Key", "in": "header",
                    "x-ballerina-name": "apiKey",
                }}},
            }), encoding="utf-8")
            metadata = json.loads(run("parse_openapi_spec.py", str(path)).stdout)
            self.assertEqual(metadata["schemas"], [])
            self.assertTrue(metadata["paths"][0]["requestBody"]["required"])
            self.assertEqual(
                metadata["paths"][0]["requestBody"]["content"][0]["schema"]["reference"], "Input")
            self.assertEqual(metadata["securitySchemes"][0]["xBallerinaName"], "apiKey")


class VersionAndExampleTests(unittest.TestCase):
    def create_example(self, root: Path, name: str) -> Path:
        example = root / name
        example.mkdir()
        (example / "main.bal").write_text("", encoding="utf-8")
        (example / "Ballerina.toml").write_text("", encoding="utf-8")
        return example

    def create_quarantine(self, root: Path, name: str) -> Path:
        quarantine = root / f".generated-examples-quarantine-{name}"
        quarantine.mkdir()
        return quarantine

    def test_baseline_ignores_comment_only_client_and_normalizes_line_endings(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "client.bal").write_text("// generated\n# comment\n", encoding="utf-8")
            baseline = directory / "baseline.json"
            run("client_version_summary.py", "capture", str(directory), str(baseline))
            result = json.loads(run("client_version_summary.py", "diff", str(directory), str(baseline)).stdout)
            self.assertEqual(result["skipped"], "no meaningful previous client.bal")

            with open(directory / "client.bal", "w", encoding="utf-8", newline="") as client:
                client.write("public class Client {}\r\n")
            run("client_version_summary.py", "capture", str(directory), str(baseline))
            (directory / "client.bal").write_text("public class Client {}\n", encoding="utf-8")
            result = json.loads(run("client_version_summary.py", "diff", str(directory), str(baseline)).stdout)
            self.assertEqual(result["skipped"], "no client/types changes")

    def test_example_cleanup_only_removes_recognized_packages(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.create_example(root, "generated")
            preserved = root / "notes"
            preserved.mkdir()
            (preserved / "README.md").write_text("keep", encoding="utf-8")
            result = json.loads(run("manage_examples.py", "cleanup", str(root)).stdout)
            self.assertEqual(result["removed"], ["generated"])
            self.assertTrue(preserved.is_dir())

    def test_example_names_are_snake_case_and_unique(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "file_upload_workflow").mkdir()
            (root / "file_upload_workflow_2").write_text("reserved", encoding="utf-8")
            result = json.loads(run(
                "example_names.py", "resolve", str(root), " File--Upload Workflow! ", "example_1").stdout)
            self.assertEqual(result["base_name"], "file_upload_workflow")
            self.assertEqual(result["name"], "file_upload_workflow_3")
            fallback = json.loads(run(
                "example_names.py", "resolve", str(root), "---", "example_1").stdout)
            self.assertEqual(fallback["name"], "example_1")

    def test_example_cleanup_restores_packages_when_quarantine_deletion_fails(self) -> None:
        module = load_script_module("manage_examples.py")

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first = self.create_example(root, "first")
            second = self.create_example(root, "second")
            preserved = root / "notes"
            preserved.mkdir()
            (preserved / "README.md").write_text("keep", encoding="utf-8")
            output = io.StringIO()

            with patch.object(module.shutil, "rmtree", side_effect=OSError("simulated deletion failure")):
                with contextlib.redirect_stdout(output), self.assertRaises(SystemExit) as exit_info:
                    module.cleanup(root)

            result = json.loads(output.getvalue())
            self.assertEqual(exit_info.exception.code, 1)
            self.assertEqual(result["removed"], [])
            self.assertTrue(result["failures"])
            self.assertFalse(result["complete"])
            for example in (first, second):
                self.assertTrue((example / "main.bal").is_file())
                self.assertTrue((example / "Ballerina.toml").is_file())
            self.assertTrue((preserved / "README.md").is_file())

    def test_example_scan_recovers_stale_quarantine(self) -> None:
        module = load_script_module("manage_examples.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            quarantine = self.create_quarantine(root, "interrupted")
            self.create_example(quarantine, "recovered")
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                module.scan(root)

            result = json.loads(output.getvalue())
            self.assertEqual(result, {"examples": ["recovered"], "count": 1})
            self.assertTrue((root / "recovered" / "main.bal").is_file())
            self.assertFalse(quarantine.exists())

    def test_example_cleanup_reports_stale_quarantine_conflicts_without_deleting(self) -> None:
        module = load_script_module("manage_examples.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            visible = self.create_example(root, "duplicate")
            quarantine = self.create_quarantine(root, "interrupted")
            self.create_example(quarantine, "duplicate")
            output = io.StringIO()

            with patch.object(module.shutil, "rmtree") as delete_quarantine:
                with contextlib.redirect_stdout(output), self.assertRaises(SystemExit) as exit_info:
                    module.cleanup(root)

            result = json.loads(output.getvalue())
            self.assertEqual(exit_info.exception.code, 1)
            self.assertEqual(result["removed"], [])
            self.assertTrue(result["failures"])
            self.assertFalse(result["complete"])
            self.assertTrue((visible / "main.bal").is_file())
            self.assertTrue((quarantine / "duplicate" / "main.bal").is_file())
            delete_quarantine.assert_not_called()

    def test_example_cleanup_marks_failed_rollback_as_removed(self) -> None:
        module = load_script_module("manage_examples.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.create_example(root, "first")
            original_rename = Path.rename
            output = io.StringIO()

            def fail_rollback(path: Path, target: Path) -> Path:
                if path.parent.name.startswith(module.QUARANTINE_PREFIX) and path.name == "first":
                    raise OSError("simulated restore failure")
                return original_rename(path, target)

            with patch.object(module.shutil, "rmtree", side_effect=OSError("simulated deletion failure")):
                with patch.object(Path, "rename", new=fail_rollback):
                    with contextlib.redirect_stdout(output), self.assertRaises(SystemExit) as exit_info:
                        module.cleanup(root)

            result = json.loads(output.getvalue())
            self.assertEqual(exit_info.exception.code, 1)
            self.assertEqual(result["removed"], ["first"])
            self.assertTrue(any("restore failed" in failure for failure in result["failures"]))
            self.assertFalse((root / "first").exists())

    def test_bal_runner_uses_argv_without_a_shell(self) -> None:
        module = load_script_module("run_bal_command.py")
        with tempfile.TemporaryDirectory() as temp:
            command = ["bal", "openapi", "-i", "spec with spaces.yaml"]
            with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess(command, 0, "", "")) as run_command:
                with patch.object(sys, "argv", ["run_bal_command.py", "--cwd", temp, *command]):
                    with self.assertRaises(SystemExit) as exit_info:
                        module.main()

            self.assertEqual(exit_info.exception.code, 0)
            run_command.assert_called_once_with(
                command, shell=False, cwd=temp, capture_output=True, text=True,
                timeout=module.DEFAULT_TIMEOUT_SECONDS,
            )

    def test_bal_runner_decodes_byte_timeout_output(self) -> None:
        module = load_script_module("run_bal_command.py")
        with tempfile.TemporaryDirectory() as temp:
            command = ["bal", "build"]
            timeout = subprocess.TimeoutExpired(command, 1, output=b"stdout\xff", stderr=b"stderr\xff")
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.object(module.subprocess, "run", side_effect=timeout):
                with patch.object(sys, "argv", ["run_bal_command.py", "--cwd", temp, *command]):
                    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                        with self.assertRaises(SystemExit) as exit_info:
                            module.main()

            self.assertEqual(exit_info.exception.code, 124)
            self.assertIn("stdout�", stdout.getvalue())
            self.assertIn("stderr�", stderr.getvalue())
            self.assertIn("Command timed out after", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
