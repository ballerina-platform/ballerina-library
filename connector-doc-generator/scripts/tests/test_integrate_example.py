import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from integrate_example import add_example_link_to_overview
from validate_docs import validate


class AddExampleLinkTests(unittest.TestCase):
    def test_adds_bullet_before_next_heading_using_frontmatter_title(self):
        with tempfile.TemporaryDirectory() as temp:
            overview = Path(temp) / "overview.md"
            overview.write_text(
                '---\ntitle: "HubSpot Events Completions"\n---\n\n'
                "Intro.\n\n## Documentation\n\n"
                "* **[Setup Guide](setup-guide.md)**: Guide.\n\n"
                "## How to contribute\n\nText.\n",
                encoding="utf-8",
            )
            changed = add_example_link_to_overview(overview, "hubspot.events.completions")
            self.assertTrue(changed)
            text = overview.read_text(encoding="utf-8")
            self.assertIn(
                "* **[Example](example.md)**: Learn how to build and configure an integration "
                "using the **HubSpot Events Completions** connector",
                text,
            )
            # Must land inside Documentation, before the next section.
            self.assertLess(text.index("[Example]"), text.index("## How to contribute"))
            self.assertGreater(text.index("[Example]"), text.index("## Documentation"))

    def test_falls_back_to_module_slug_without_frontmatter_title(self):
        with tempfile.TemporaryDirectory() as temp:
            overview = Path(temp) / "overview.md"
            overview.write_text(
                "## Documentation\n\n* **[Setup Guide](setup-guide.md)**: Guide.\n",
                encoding="utf-8",
            )
            add_example_link_to_overview(overview, "hubspot.events.completions")
            self.assertIn("**hubspot.events.completions** connector", overview.read_text(encoding="utf-8"))

    def test_appends_at_end_of_file_when_no_trailing_heading(self):
        with tempfile.TemporaryDirectory() as temp:
            overview = Path(temp) / "overview.md"
            overview.write_text(
                '---\ntitle: "MySQL"\n---\n\n## Documentation\n\n* **[Setup Guide](setup-guide.md)**: Guide.\n',
                encoding="utf-8",
            )
            add_example_link_to_overview(overview, "mysql")
            self.assertIn("[Example](example.md)", overview.read_text(encoding="utf-8"))

    def test_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            overview = Path(temp) / "overview.md"
            overview.write_text(
                '---\ntitle: "MySQL"\n---\n\n## Documentation\n\n* **[Setup Guide](setup-guide.md)**: Guide.\n',
                encoding="utf-8",
            )
            self.assertTrue(add_example_link_to_overview(overview, "mysql"))
            self.assertFalse(add_example_link_to_overview(overview, "mysql"))
            self.assertEqual(overview.read_text(encoding="utf-8").count("[Example](example.md)"), 1)


class ValidateDocsExampleLinkTests(unittest.TestCase):
    def _make_repo(self, temp: Path, overview_body: str) -> Path:
        repo = temp / "docs-integrator"
        doc_dir = repo / "en/docs/connectors/catalog/crm-sales/hubspot.events.completions"
        doc_dir.mkdir(parents=True)
        (doc_dir / "overview.md").write_text(overview_body, encoding="utf-8")
        (doc_dir / "action-reference.md").write_text("# Actions\n", encoding="utf-8")
        (doc_dir / "example.md").write_text("# Example\n", encoding="utf-8")
        sidebars = repo / "en/sidebars.ts"
        sidebars.parent.mkdir(parents=True, exist_ok=True)
        sidebars.write_text(
            "'connectors/catalog/crm-sales/hubspot.events.completions/overview',"
            "'connectors/catalog/crm-sales/hubspot.events.completions/action-reference',"
            "'connectors/catalog/crm-sales/hubspot.events.completions/example',",
            encoding="utf-8",
        )
        return repo

    def test_rejects_overview_missing_example_link(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = self._make_repo(Path(temp), "# Overview\n\n## Documentation\n\nNo example link here.\n")
            args = argparse_namespace(str(repo), "crm-sales", "hubspot.events.completions", True, True)
            with self.assertRaisesRegex(RuntimeError, "does not link to example.md"):
                validate(args)

    def test_accepts_overview_with_example_link(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = self._make_repo(
                Path(temp), "# Overview\n\n## Documentation\n\n* **[Example](example.md)**: Learn more.\n"
            )
            args = argparse_namespace(str(repo), "crm-sales", "hubspot.events.completions", True, True)
            result = validate(args)
            self.assertTrue(result["valid"])


def argparse_namespace(docs_repo, category, module, reference, examples):
    import argparse

    return argparse.Namespace(docs_repo=docs_repo, category=category, module=module, reference=reference, examples=examples)


if __name__ == "__main__":
    unittest.main()
