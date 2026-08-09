import base64
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from collect_screenshot import collect
from prepare_run import build_context
from publish_to_docs_site import (
    copy_screenshots,
    default_display_name,
    patch_sidebar_example,
    publish,
    rewrite_image_links,
)

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)

SUFFIXES = ["palette", "connection_form", "connections_list", "operations_panel", "operation_form", "completed_flow"]


def valid_document(prefix: str) -> str:
    images = "\n".join(
        f"![Milestone {number}](../screenshots/{prefix}_screenshot_{number:02d}_{suffix}.png)"
        for number, suffix in enumerate(SUFFIXES, 1)
    )
    return f"# Example\n\n## What you'll build\n\nDoes a thing.\n\n{images}\n"


def write_screenshots(context: dict) -> None:
    with tempfile.TemporaryDirectory() as source_dir:
        source = Path(source_dir) / "source.png"
        source.write_bytes(PNG)
        prefix = context["image_prefix"]
        for number, suffix in enumerate(SUFFIXES, 1):
            destination = Path(context["screenshots_dir"]) / f"{prefix}_screenshot_{number:02d}_{suffix}.png"
            collect(source, destination)


SIDEBARS_WITH_OVERVIEW = """export default {
  main: [
    {
      type: 'category',
      label: 'Connector Catalog',
      items: [
        {
          type: 'category',
          label: 'HubSpot Events Completions',
          link: { type: 'doc', id: 'connectors/catalog/crm-sales/hubspot.events.completions/overview' },
          items: [
            'connectors/catalog/crm-sales/hubspot.events.completions/setup-guide',
            'connectors/catalog/crm-sales/hubspot.events.completions/action-reference',
          ],
        },
        {
          type: 'category',
          label: 'Salesforce',
          link: { type: 'doc', id: 'connectors/catalog/crm-sales/salesforce/overview' },
          items: [
            'connectors/catalog/crm-sales/salesforce/example',
          ],
        },
      ],
    },
  ],
};
"""

SIDEBARS_WITHOUT_CONNECTOR = """export default {
  main: [
    {
      type: 'category',
      label: 'Connector Catalog',
      items: [
        {
          type: 'category',
          label: 'Salesforce',
          link: { type: 'doc', id: 'connectors/catalog/crm-sales/salesforce/overview' },
          items: [
            'connectors/catalog/crm-sales/salesforce/example',
          ],
        },
      ],
    },
  ],
};
"""


class RewriteImageLinksTests(unittest.TestCase):
    def test_rewrites_all_six_relative_links(self):
        prefix = "ballerinax_hubspot_events_completions"
        text = valid_document(prefix)
        rewritten, count = rewrite_image_links(text, "/img/connectors/catalog/crm-sales/hubspot.events.completions")
        self.assertEqual(count, 6)
        self.assertNotIn("../screenshots/", rewritten)
        for number, suffix in enumerate(SUFFIXES, 1):
            self.assertIn(
                f"/img/connectors/catalog/crm-sales/hubspot.events.completions/"
                f"{prefix}_screenshot_{number:02d}_{suffix}.png",
                rewritten,
            )

    def test_leaves_unrelated_links_untouched(self):
        text = "[HubSpot](https://www.hubspot.com/) and ![x](../screenshots/a_screenshot_01_palette.png)"
        rewritten, count = rewrite_image_links(text, "/img/connectors/catalog/crm-sales/hubspot")
        self.assertEqual(count, 1)
        self.assertIn("https://www.hubspot.com/", rewritten)


class CopyScreenshotsTests(unittest.TestCase):
    def test_copies_exactly_six_pngs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            context = build_context(
                "ballerinax/hubspot.events.completions",
                root,
                {"version": "1.0.0"},
                docs_repo_root=str(root / "docs-integrator"),
                category="crm-sales",
            )
            write_screenshots(context)
            copied = copy_screenshots(Path(context["screenshots_dir"]), Path(context["docs_static_img_dir"]))
            self.assertEqual(len(copied), 6)
            for path in copied:
                self.assertTrue(Path(path).is_file())

    def test_rejects_incomplete_screenshot_set(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            context = build_context(
                "ballerinax/hubspot.events.completions",
                root,
                {"version": "1.0.0"},
                docs_repo_root=str(root / "docs-integrator"),
                category="crm-sales",
            )
            source = root / "source.png"
            source.write_bytes(PNG)
            collect(
                source,
                Path(context["screenshots_dir"]) / f"{context['image_prefix']}_screenshot_01_palette.png",
            )
            with self.assertRaises(ValueError):
                copy_screenshots(Path(context["screenshots_dir"]), Path(context["docs_static_img_dir"]))


class SidebarPatchTests(unittest.TestCase):
    def test_appends_example_with_matching_sibling_indentation(self):
        # Regression test: the item must land on its own line with the same indentation as
        # its siblings, and the closing `],` must not be glued onto the new item's line.
        with tempfile.TemporaryDirectory() as temp:
            sidebars_path = Path(temp) / "sidebars.ts"
            sidebars_path.write_text(SIDEBARS_WITH_OVERVIEW, encoding="utf-8")
            patch_sidebar_example(sidebars_path, "crm-sales", "hubspot.events.completions", "HubSpot Events Completions")
            text = sidebars_path.read_text(encoding="utf-8")
            expected_block = (
                "          items: [\n"
                "            'connectors/catalog/crm-sales/hubspot.events.completions/setup-guide',\n"
                "            'connectors/catalog/crm-sales/hubspot.events.completions/action-reference',\n"
                "            'connectors/catalog/crm-sales/hubspot.events.completions/example',\n"
                "          ],\n"
                "        },"
            )
            self.assertIn(expected_block, text)

    def test_appends_example_to_existing_connector_block(self):
        with tempfile.TemporaryDirectory() as temp:
            sidebars_path = Path(temp) / "sidebars.ts"
            sidebars_path.write_text(SIDEBARS_WITH_OVERVIEW, encoding="utf-8")
            patched = patch_sidebar_example(sidebars_path, "crm-sales", "hubspot.events.completions", "HubSpot Events Completions")
            self.assertTrue(patched)
            text = sidebars_path.read_text(encoding="utf-8")
            self.assertIn("'connectors/catalog/crm-sales/hubspot.events.completions/example',", text)
            # The unrelated Salesforce block must be untouched.
            self.assertEqual(text.count("'connectors/catalog/crm-sales/salesforce/example',"), 1)

    def test_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            sidebars_path = Path(temp) / "sidebars.ts"
            sidebars_path.write_text(SIDEBARS_WITH_OVERVIEW, encoding="utf-8")
            patch_sidebar_example(sidebars_path, "crm-sales", "hubspot.events.completions", "HubSpot Events Completions")
            second_pass = patch_sidebar_example(sidebars_path, "crm-sales", "hubspot.events.completions", "HubSpot Events Completions")
            self.assertFalse(second_pass)
            text = sidebars_path.read_text(encoding="utf-8")
            self.assertEqual(text.count("hubspot.events.completions/example"), 1)

    def test_inserts_standalone_block_when_connector_absent(self):
        with tempfile.TemporaryDirectory() as temp:
            sidebars_path = Path(temp) / "sidebars.ts"
            sidebars_path.write_text(SIDEBARS_WITHOUT_CONNECTOR, encoding="utf-8")
            patched = patch_sidebar_example(sidebars_path, "crm-sales", "hubspot.events.completions", "HubSpot Events Completions")
            self.assertTrue(patched)
            text = sidebars_path.read_text(encoding="utf-8")
            self.assertIn("label: 'HubSpot Events Completions'", text)
            self.assertIn(
                "link: { type: 'doc', id: 'connectors/catalog/crm-sales/hubspot.events.completions/example' }",
                text,
            )
            # Existing Salesforce block must survive unchanged.
            self.assertIn("'connectors/catalog/crm-sales/salesforce/example',", text)

    def test_default_display_name_title_cases_dotted_slug(self):
        self.assertEqual(default_display_name("hubspot.events.completions"), "Hubspot Events Completions")


class PublishEndToEndTests(unittest.TestCase):
    def test_publish_writes_example_and_patches_sidebar(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            docs_repo_root = root / "docs-integrator"
            sidebars_path = docs_repo_root / "en" / "sidebars.ts"
            sidebars_path.parent.mkdir(parents=True, exist_ok=True)
            sidebars_path.write_text(SIDEBARS_WITH_OVERVIEW, encoding="utf-8")

            context = build_context(
                "ballerinax/hubspot.events.completions",
                root,
                {"version": "1.0.0"},
                docs_repo_root=str(docs_repo_root),
                category="crm-sales",
            )
            write_screenshots(context)
            Path(context["doc_path"]).write_text(valid_document(context["image_prefix"]), encoding="utf-8")

            result = publish(context)

            example_path = Path(result["docs_example_path"])
            self.assertTrue(example_path.is_file())
            content = example_path.read_text(encoding="utf-8")
            self.assertNotIn("../screenshots/", content)
            self.assertIn("/img/connectors/catalog/crm-sales/hubspot.events.completions/", content)
            self.assertTrue(result["sidebar_patched"])
            self.assertEqual(len(result["screenshots_copied"]), 6)
            for path in result["screenshots_copied"]:
                self.assertTrue(Path(path).is_file())

    def test_publish_requires_docs_target_in_context(self):
        with tempfile.TemporaryDirectory() as temp:
            context = build_context("ballerinax/hubspot.events.completions", Path(temp), {"version": "1.0.0"})
            with self.assertRaises(ValueError):
                publish(context)


if __name__ == "__main__":
    unittest.main()
