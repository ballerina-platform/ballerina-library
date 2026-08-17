import tempfile
import unittest
from pathlib import Path

import sys

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from prepare_sample_publish import copy_sample_files, prepare, set_package_org


def make_sample_project(root: Path, org: str = "danesh") -> Path:
    sample = root / "ballerinax_hubspot_events_completions_connector_sample"
    sample.mkdir()
    (sample / "Ballerina.toml").write_text(
        f'[package]\norg = "{org}"\nname = "sample"\nversion = "0.1.0"\n', encoding="utf-8"
    )
    (sample / ".gitignore").write_text("target/\nConfig.toml\n", encoding="utf-8")
    (sample / "main.bal").write_text("public function main() {}\n", encoding="utf-8")
    (sample / "connections.bal").write_text("// connections\n", encoding="utf-8")
    (sample / "Dependencies.toml").write_text("[ballerina]\n", encoding="utf-8")
    (sample / "Config.toml").write_text("accessToken = \"real-secret\"\n", encoding="utf-8")
    (sample / ".vscode").mkdir()
    (sample / ".vscode" / "settings.json").write_text("{}", encoding="utf-8")
    return sample


class CopySampleFilesTests(unittest.TestCase):
    def test_copies_only_gitignore_toml_and_bal_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sample = make_sample_project(root)
            target = root / "published"
            copied = copy_sample_files(sample, target)
            self.assertEqual(
                sorted(copied), sorted([".gitignore", "Ballerina.toml", "connections.bal", "main.bal"])
            )
            self.assertFalse((target / "Dependencies.toml").exists())
            self.assertFalse((target / "Config.toml").exists())
            self.assertFalse((target / ".vscode").exists())

    def test_rejects_non_ballerina_project(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            not_a_project = root / "not_a_project"
            not_a_project.mkdir()
            with self.assertRaises(ValueError):
                copy_sample_files(not_a_project, root / "published")


class SetPackageOrgTests(unittest.TestCase):
    def test_replaces_org_and_reports_change(self):
        with tempfile.TemporaryDirectory() as temp:
            toml = Path(temp) / "Ballerina.toml"
            toml.write_text('[package]\norg = "danesh"\nname = "sample"\n', encoding="utf-8")
            changed = set_package_org(toml, "wso2")
            self.assertTrue(changed)
            self.assertIn('org = "wso2"', toml.read_text(encoding="utf-8"))

    def test_reports_no_change_when_already_correct(self):
        with tempfile.TemporaryDirectory() as temp:
            toml = Path(temp) / "Ballerina.toml"
            toml.write_text('[package]\norg = "wso2"\nname = "sample"\n', encoding="utf-8")
            self.assertFalse(set_package_org(toml, "wso2"))

    def test_raises_when_no_org_field(self):
        with tempfile.TemporaryDirectory() as temp:
            toml = Path(temp) / "Ballerina.toml"
            toml.write_text("[package]\nname = \"sample\"\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                set_package_org(toml, "wso2")


class PrepareEndToEndTests(unittest.TestCase):
    def test_prepare_copies_and_fixes_org(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            sample = make_sample_project(root)
            target = root / "integration-samples" / "integrator-default-profile" / "connectors" / "hubspot.events.completions_connector_sample"
            result = prepare(sample, target, "wso2")
            self.assertTrue(result["org_updated"])
            self.assertIn("main.bal", result["files_copied"])
            self.assertIn('org = "wso2"', (target / "Ballerina.toml").read_text(encoding="utf-8"))
            # No secrets or local-only files ever reach the target directory.
            all_target_files = {p.name for p in target.rglob("*") if p.is_file()}
            self.assertNotIn("Config.toml", all_target_files)
            self.assertNotIn("Dependencies.toml", all_target_files)


if __name__ == "__main__":
    unittest.main()
