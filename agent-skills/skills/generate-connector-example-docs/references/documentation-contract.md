# Connector documentation contract

Use `../assets/templates/connector-example-doc.md` as the canonical document skeleton. Copy it to the run's `doc_path`, fill it from the actual workflow, and remove all `{{PLACEHOLDER}}` tokens and HTML template comments before finalization. Read `microsoft-writing-style.md` and apply every rule there; this contract defines the connector-specific structure and content.

## Contents

1. Required structure
2. Section content
3. Step format
4. Screenshot rules
5. Style and terminology
6. Forbidden content
7. Final review

## Required structure

Start at the first byte of the file with:

```markdown
# Example
```

Use exactly these H2 sections in this order, replacing bracketed names:

1. `## What you'll build`
2. `## Architecture`
3. `## Prerequisites` only when an external service, account, or credentials are required
4. `## Setting up the [Connector name] integration`
5. `## Adding the [Connector name] connector`
6. `## Configuring the [Connector name] connection`
7. `## Configuring the [Connector name] [Operation name] operation`
8. `## Try it yourself`, added only by deterministic finalization
9. `## More code examples` only when `append_central_examples.py` extracts it from the cached Central API response

Do not add a summary, conclusion, next steps, metadata, frontmatter, or timestamp footer. Do not author **Try it yourself** manually; finalization inserts its exact Markdown.

## Section content

### What you'll build

Write two or three concise sentences describing the integration. Add an **Operations used:** bullet list. List only operations that are actually configured in a numbered step.

### Architecture

Include one Mermaid `flowchart LR` block and nothing else. Show the initiator, selected operation, connector, and external system. Use spaces rather than literal `\n` sequences inside nodes.

### Prerequisites

Include only connector-specific external requirements. Do not mention WSO2 Integrator installation, VS Code, code-server, Playwright, ports, or local tooling. Omit the section when no external dependency exists.

### Setting up the integration

Use exactly this blockquote and no other content:

> **New to WSO2 Integrator?** Follow the [Create a New Integration](../../../../develop/create-integrations/create-new-integration.md) guide to set up your integration first, then return here to add the connector.

### Adding the connector

Describe opening the palette and selecting the connector. Start global step numbering at Step 1. Embed screenshot 01 in the palette-opening step.

### Configuring the connection

Include only binding connection parameters, saving the connection, and reviewing empty configurable entries. Embed screenshot 02 before save and screenshot 03 after save. Use parameter bullets rather than tables.

### Configuring the operation

Keep entry-point creation as its own step. Combine operation selection and parameter configuration when that reads clearly, while keeping screenshot 04 with the expanded-operation action and screenshot 05 with the filled form. Finish with the saved flow and screenshot 06. Add no closing prose; deterministic post-processing appends **Try it yourself** and optional **More code examples**.

### Try it yourself

Finalization must add this section immediately after the operation section and before optional **More code examples**:

```markdown
## Try it yourself

Try this sample in WSO2 Integration Platform.

[![Deploy to Devant](https://openindevant.choreoapps.dev/images/DeployDevant-White.svg)](https://console.devant.dev/new?gh=wso2/integration-samples/tree/main/integrator-default-profile/connectors/<sample_name>)

[View source on GitHub](https://github.com/wso2/integration-samples/tree/main/integrator-default-profile/connectors/<sample_name>)
```

Use the exact directory basename from `sample_dir` for `<sample_name>`. This fenced block documents the post-processing contract; it must not appear as a fence in the generated guide.

## Step format

Use sequential H3 headings across the whole guide:

```markdown
### Step N: Imperative sentence-case description

Describe the action with an imperative opening verb.

- **Visible field label** : One-line explanation

![Specific screenshot description](../screenshots/prefix_screenshot_NN_suffix.png)
```

- Do not reset or skip step numbers.
- Convert two or more sequential UI instructions into a numbered sub-list.
- Keep parameter bullets and images after any numbered sub-list.
- Use the visible UI display label for parameters.
- Use ` : ` between a bold parameter label and its description.
- Do not use Markdown tables in steps.

## Screenshot rules

- Reference all six screenshots exactly once and in ascending order.
- Use only `../screenshots/<filename>.png` paths.
- Preserve the actual collected filenames.
- Use meaningful alt text describing the visible UI and milestone.
- Place each image in the step that performed the depicted action.
- Reject screenshots that show the global VS Code Chat/Copilot secondary sidebar, integrated terminal, Welcome tab, source tabs, unrelated editor tabs, popups, or split editors. Close these surfaces in the UI before capture rather than cropping them out afterward.

## Style and terminology

- Use sentence case for every heading; retain capitalization only for proper product and connector names.
- Omit periods at the end of headings.
- Begin action sentences with imperative verbs such as **Select**, **Enter**, **Expand**, **Save**, or **Open**.
- Prefer **select** to **click**, and **enter** to **type**.
- Use contractions in explanatory prose where natural.
- Use concise wording and the Oxford comma.
- Spell out zero through nine in prose except UI values, versions, and step numbers.
- Bold UI element names.
- Write generic terms such as configurable variable in lowercase.
- Use `configurable string` and `configurable int` in that declaration order if Ballerina syntax must be described.
- End complete-sentence bullets with periods; leave short fragments without punctuation.

## Forbidden content

Remove all references to:

- code-server, localhost, port numbers, local paths, artifacts directories, or operating-system setup
- Playwright, MCP tools, browser tool names, automation internals, snapshots, or agent instructions
- `.bal` filenames or source-editing mechanics
- real secrets or credential values
- publishing, branches, commits, or pull requests, except the exact deterministic GitHub sample URL and Devant deployment button in **Try it yourself**
- WSO2 Integrator BI; use **WSO2 Integrator**
- Ballerina as the end-user platform name

Allow fenced code only for the single Mermaid block in the authored guide. The optional **More code examples** appendix is copied verbatim by `append_central_examples.py` from the resolved package's cached Ballerina Central metadata and may contain its own source examples.

## Final review

Before finalization, verify that:

1. Each listed operation appears in a numbered implementation step.
2. Each parameter bullet uses a visible UI label.
3. The six images exist, are ordered, and resolve from the guide.
4. The sample contains no credentials.
5. The document contains no forbidden internal details.
6. The fixed setup blockquote is unchanged.
7. No screenshot contains the global Chat/Copilot sidebar, terminal, Welcome tab, source editor, unrelated tab, popup, or split editor.
8. The final deterministic validator succeeds.
9. No template placeholder or HTML comment remains.
10. Every objective Microsoft writing-style rule passes validation, and the remaining prose rules have been reviewed manually.
11. **Try it yourself** contains the exact button and GitHub URLs for the `sample_dir` basename.
