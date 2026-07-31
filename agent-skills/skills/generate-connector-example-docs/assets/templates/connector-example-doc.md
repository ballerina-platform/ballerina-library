# Example

## What you'll build

{{WHAT_YOU_WILL_BUILD}}

**Operations used:**
- **{{OPERATION_NAME}}** : {{OPERATION_DESCRIPTION}}

## Architecture

```mermaid
flowchart LR
    A((User)) --> B[{{OPERATION_DISPLAY_NAME}}]
    B --> C[{{CONNECTOR_DISPLAY_NAME}} Connector]
    C --> D{{TARGET_NODE}}
```

<!-- Remove this section when the connector has no external prerequisites. -->
## Prerequisites

- {{CONNECTOR_PREREQUISITE}}

## Setting up the {{CONNECTOR_DISPLAY_NAME}} integration

> **New to WSO2 Integrator?** Follow the [Create a New Integration](../../../../develop/create-integrations/create-new-integration.md) guide to set up your integration first, then return here to add the connector.

## Adding the {{CONNECTOR_DISPLAY_NAME}} connector

### Step 1: Open the connector palette

Select **Add Connection** in the **Connections** section.

![{{CONNECTOR_DISPLAY_NAME}} connector palette open before selection](../screenshots/{{SCREENSHOT_PREFIX}}_screenshot_01_palette.png)

### Step 2: Select the {{CONNECTOR_DISPLAY_NAME}} connector

1. Enter `{{CONNECTOR_SEARCH_TERM}}` in the search field.
2. Select the **{{CONNECTOR_DISPLAY_NAME}}** connector card.

## Configuring the {{CONNECTOR_DISPLAY_NAME}} connection

### Step 3: Bind the connection parameters to configurable variables

Bind every required connection field to a configurable variable.

- **{{CONNECTION_FIELD_LABEL}}** : {{CONNECTION_FIELD_DESCRIPTION}}

![{{CONNECTOR_DISPLAY_NAME}} connection form with all parameters bound before saving](../screenshots/{{SCREENSHOT_PREFIX}}_screenshot_02_connection_form.png)

### Step 4: Save the connection

Select **Save** and verify that the connection appears in the **Connections** section.

![{{CONNECTOR_DISPLAY_NAME}} connection visible after saving](../screenshots/{{SCREENSHOT_PREFIX}}_screenshot_03_connections_list.png)

### Step 5: Set actual values for your configurables

1. Select **Configurations** at the bottom of the project tree under **Data Mappers**.
2. Enter a value for each configurable listed below before you run the integration.

- **{{CONFIGURABLE_NAME}}** (`{{CONFIGURABLE_TYPE}}`) : {{CONFIGURABLE_DESCRIPTION}}

## Configuring the {{CONNECTOR_DISPLAY_NAME}} {{OPERATION_DISPLAY_NAME}} operation

### Step 6: Add an automation entry point

1. Select **Add Entry Point** next to **Entry Points**.
2. Select **Automation**.
3. Select **Create** to accept the settings.

### Step 7: Expand the connection and configure the {{OPERATION_DISPLAY_NAME}} operation

1. Select **Add Step** in the automation flow.
2. Expand **{{CONNECTION_NAME}}** to display its operations.

![{{CONNECTOR_DISPLAY_NAME}} connection expanded to display operations before selection](../screenshots/{{SCREENSHOT_PREFIX}}_screenshot_04_operations_panel.png)

3. Select **{{OPERATION_DISPLAY_NAME}}** and enter its required values.

- **{{OPERATION_FIELD_LABEL}}** : {{OPERATION_FIELD_DESCRIPTION}}

![{{CONNECTOR_DISPLAY_NAME}} {{OPERATION_DISPLAY_NAME}} operation with all values entered before saving](../screenshots/{{SCREENSHOT_PREFIX}}_screenshot_05_operation_form.png)

4. Select **Save**.

<!-- Keep the following step only when the operation returns a value. Otherwise, place screenshot 06 at the end of the preceding step. -->
### Step 8: Log the {{OPERATION_DISPLAY_NAME}} result

Add a log action for the returned value, then return to the visual flow.

![Completed {{CONNECTOR_DISPLAY_NAME}} flow with the configured operation](../screenshots/{{SCREENSHOT_PREFIX}}_screenshot_06_completed_flow.png)

<!-- Do not author "Try it yourself" or "More code examples". Finalization adds both sections deterministically. -->
