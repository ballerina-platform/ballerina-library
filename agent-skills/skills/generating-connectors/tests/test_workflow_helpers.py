from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def run(script: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPTS / script), *args], text=True,
                          capture_output=True, check=check)


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


class VersionAndExampleTests(unittest.TestCase):
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
            generated = root / "generated"
            generated.mkdir()
            (generated / "main.bal").write_text("", encoding="utf-8")
            (generated / "Ballerina.toml").write_text("", encoding="utf-8")
            preserved = root / "notes"
            preserved.mkdir()
            (preserved / "README.md").write_text("keep", encoding="utf-8")
            result = json.loads(run("manage_examples.py", "cleanup", str(root)).stdout)
            self.assertEqual(result["removed"], ["generated"])
            self.assertTrue(preserved.is_dir())


if __name__ == "__main__":
    unittest.main()
