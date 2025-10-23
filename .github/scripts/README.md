# Area Label Sync Script

This directory contains a script to sync Area labels from the repository to issue templates.

## Overview

The `sync-area-labels.py` script ensures that issue templates always have the latest Area labels from the repository, eliminating the need to manually update templates when labels change.

## How It Works

1. **Fetches Area labels**: The script uses GitHub CLI (`gh`) to fetch all labels that start with `Area/` from the repository
2. **Updates templates**: It updates all issue templates (`.github/ISSUE_TEMPLATE/*.yml`) with the current list of Area labels
3. **Maintains order**: Labels are sorted alphabetically for consistency

## Prerequisites

- Python 3.x
- GitHub CLI (`gh`) installed and authenticated
- Repository access (for fetching labels)

## Manual Execution

Run the script manually whenever you add, edit, or remove Area labels:

```bash
# Make sure you're in the repository root
cd /path/to/ballerina-library

# Run the sync script
python3 .github/scripts/sync-area-labels.py
```

The script will:
- Fetch all Area labels from the repository
- Update all issue templates with the current list
- Show which templates were updated

## Workflow

### When Adding New Area Labels

1. Go to repository Settings → Labels
2. Create a new label with name starting with `Area/` (e.g., `Area/NewFeature`)
3. Run the sync script: `python3 .github/scripts/sync-area-labels.py`
4. Commit the updated templates

### When Removing Area Labels

1. Delete the Area label from GitHub (Settings → Labels)
2. Run the sync script: `python3 .github/scripts/sync-area-labels.py`
3. Commit the updated templates

### When Renaming Area Labels

1. Edit the label name in GitHub (Settings → Labels)
2. Run the sync script: `python3 .github/scripts/sync-area-labels.py`
3. Commit the updated templates

## Templates Updated

The script updates the following issue templates:

- `.github/ISSUE_TEMPLATE/bug.yml`
- `.github/ISSUE_TEMPLATE/improvement.yml`
- `.github/ISSUE_TEMPLATE/new-feature.yml`
- `.github/ISSUE_TEMPLATE/task.yml`

## Issue Label Assignment

When users create issues using the templates:

1. They select an Area from the dropdown menu
2. The selected Area appears in the issue body under the "Area" section
3. **Manual step**: Add the corresponding Area label to the issue based on the selection

> **Note**: Automatic label assignment can be added later with a GitHub Actions workflow if needed.
