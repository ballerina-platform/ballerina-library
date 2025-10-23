#!/usr/bin/env python3
"""
Script to sync Area labels from repository to issue templates.
This ensures templates always have the latest Area labels.
"""

import json
import subprocess
import sys
from pathlib import Path
import re

def get_area_labels():
    """Fetch all Area labels from the repository using gh CLI."""
    try:
        result = subprocess.run(
            ['gh', 'label', 'list', '--limit', '500', '--json', 'name'],
            capture_output=True,
            text=True,
            check=True
        )
        labels = json.loads(result.stdout)
        area_labels = sorted([
            label['name']
            for label in labels
            if label['name'].startswith('Area/')
        ])
        return area_labels
    except subprocess.CalledProcessError as e:
        print(f"Error fetching labels: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing label JSON: {e}", file=sys.stderr)
        sys.exit(1)

def update_template(template_path, area_labels):
    """Update a single issue template with the latest Area labels."""
    try:
        with open(template_path, 'r') as f:
            lines = f.readlines()

        # Find the Area dropdown section and update its options
        updated_lines = []
        i = 0
        found_area_section = False

        while i < len(lines):
            line = lines[i]
            updated_lines.append(line)

            # Check if we found the area dropdown
            if '- type: dropdown' in line:
                # Look ahead to confirm this is the area dropdown
                if i + 1 < len(lines) and 'id: area' in lines[i + 1]:
                    found_area_section = True
                    # Copy lines until we hit 'options:'
                    i += 1
                    while i < len(lines) and 'options:' not in lines[i]:
                        updated_lines.append(lines[i])
                        i += 1

                    # Add the options: line
                    if i < len(lines):
                        updated_lines.append(lines[i])  # options: line
                        i += 1

                        # Skip old Area options
                        while i < len(lines) and lines[i].strip().startswith('- Area/'):
                            i += 1

                        # Insert new Area labels
                        for label in area_labels:
                            updated_lines.append(f'        - {label}\n')

                        # Continue with remaining lines (validations, etc.)
                        continue

            i += 1

        if not found_area_section:
            print(f"⚠ Warning: No Area dropdown found in {template_path}")
            return False

        with open(template_path, 'w') as f:
            f.writelines(updated_lines)

        return True
    except FileNotFoundError:
        print(f"⚠ Warning: {template_path} not found")
        return False
    except Exception as e:
        print(f"Error updating {template_path}: {e}", file=sys.stderr)
        return False

def main():
    """Main function to sync Area labels to all issue templates."""
    print("Fetching Area labels from repository...")
    area_labels = get_area_labels()

    if not area_labels:
        print("Error: No Area labels found in repository", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(area_labels)} Area labels")

    # Define template paths
    templates = [
        '.github/ISSUE_TEMPLATE/bug.yml',
        '.github/ISSUE_TEMPLATE/improvement.yml',
        '.github/ISSUE_TEMPLATE/new-feature.yml',
        '.github/ISSUE_TEMPLATE/task.yml',
    ]

    # Update each template
    updated_count = 0
    for template in templates:
        if update_template(template, area_labels):
            print(f"✓ Updated {template}")
            updated_count += 1

    print()
    if updated_count > 0:
        print(f"✓ Area labels sync completed successfully!")
        print(f"Updated {updated_count} template(s) with {len(area_labels)} Area labels")
    else:
        print("⚠ No templates were updated")
        sys.exit(1)

if __name__ == '__main__':
    main()
