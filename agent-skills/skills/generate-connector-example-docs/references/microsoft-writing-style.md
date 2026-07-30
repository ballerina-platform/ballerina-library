# Microsoft writing style rules for connector examples

Apply every rule before finalization. The rules are ported from the connector documentation enforcement prompt.

## Headings and steps

- Use sentence case for H1, H2, and H3 headings. Preserve proper product and connector names, such as WSO2 Integrator, MySQL, HTTP, and Salesforce.
- Don't end a heading with a period. Use a question mark only for a genuine question.
- Begin each step instruction with an imperative verb. Avoid openings such as “you can,” “there is,” and passive constructions.
- Convert a prose step containing two or more sequential UI actions into a numbered sub-list. Keep parameter bullets and screenshots after that list.
- Keep sentences under 25 words. Split compound instructions joined by repeated “and” or “then.”

## Words and terminology

- Prefer contractions in natural explanatory prose.
- Replace “in order to” with “to,” “utilize” or “make use of” with “use,” “in addition” with “also,” and “at this point in time” with “now.”
- Remove unnecessary words such as “very,” “quite,” “easily,” and “simply.”
- Use **select**, not click, choose, or press. Use **enter**, not type, input, or fill in. Use **clear**, not uncheck.
- Use **configurable variable**, **connection**, and **run** consistently. Don't use “config var,” “env variable,” “connector instance,” “conn,” or user-facing “execute.”
- Use lowercase for generic technical terms such as configurable variable.
- Use the Oxford comma in a series of three or more items.
- Use em dashes without surrounding spaces for parenthetical phrases in prose. Keep ` : ` as the parameter-bullet separator.

## Numbers, lists, and formatting

- Spell out zero through nine in prose. Use numerals for 10 and above and for code, configuration, UI values, versions, ports, and step numbers.
- Spell out ordinals in prose.
- Start each bullet with a capital letter. Don't end a bullet with a semicolon, comma, or conjunction. End complete sentences with periods; leave short fragments unpunctuated.
- Bold visible UI element names. Don't append an element type unless it improves clarity: write “Select **Save**,” not “Select the **Save** button.”
- Put code elements, values, variables, types, connection strings, ports, file paths, and environment variables in backticks. Don't add backticks inside bold parameter labels.
- Use only these admonition labels: `> **Note:**`, `> **Tip:**`, `> **Warning:**`, and `> **Important:**`. Prefer normal prose when an admonition isn't necessary.
- Use descriptive link text. Never use “click here,” “here,” “this page,” “this guide,” or “learn more” as link text.
- Preserve the deterministic **Deploy to Devant** image link and **View source on GitHub** link exactly; they are post-processing output rather than authored instructions.

## Connector-document rules

- Format connection parameter bullets as `- **Visible field label** : Description.` Don't include literal or configurable values in these bullets.
- Include a final connection step named “Set actual values for your configurables.” Direct readers to **Configurations** under **Data Mappers** and list every configurable as `- **name** (\`type\`) : Description.`
- Keep the fixed setup blockquote unchanged.
- Use exactly one Mermaid `flowchart LR` in **Architecture**, ordered User → Operation → Connector → Target. Use at least four nodes. Use a cylinder for data stores and a circle for other targets.
- Place screenshots 01–06 in the action that produced the visible state and keep them in ascending order. Alt text must describe both the visible UI and its workflow milestone.
