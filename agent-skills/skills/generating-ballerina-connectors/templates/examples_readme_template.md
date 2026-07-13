# Examples

The `<BAL_ORG>/<BAL_PACKAGE>` connector provides practical examples illustrating usage in various scenarios.

| Example | Description |
|---------|-------------|
| [`<example-name>`](./<example-name>) | <USE_CASE one-liner> |

## Prerequisites

1. Build and push the connector to your local Ballerina repository:
   ```bash
   cd <BALLERINA_DIR>
   bal pack && bal push --repository=local
   ```

2. For each example, create a `Config.toml` in the example directory with the required credentials:
   ```toml
   <auth_field_1> = "<value>"
   <auth_field_2> = "<value>"
   ```

## Running an example

```bash
cd examples/<example-name>
bal run
```
