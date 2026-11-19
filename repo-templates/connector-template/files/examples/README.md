# Examples

The `ballerinax/{{MODULE_NAME_CC}}` connector provides practical examples illustrating usage in various scenarios.

[//]: # (TODO: Add examples)
1. 
2. 

## Prerequisites

[//]: # (TODO: Add prerequisites)

## Running an example

Execute the following commands to build an example from the source:

* To build an example:

    ```bash
    bal build
    ```

* To run an example:

    ```bash
    bal run
    ```

<!-- {{#RELEASED_DISTRIBUTION}} -->
## Building the examples with the local module

**Warning**: Due to the absence of support for reading local repositories for single Ballerina files, the Bala of the module is manually written to the central repository as a workaround. Consequently, the bash script may modify your local Ballerina repositories.

Execute the following commands to build all the examples against the changes you have made to the module locally:

* To build all the examples:

    ```bash
    ./build.sh build
    ```

* To run all the examples:

    ```bash
    ./build.sh run
    ```
<!-- {{/RELEASED_DISTRIBUTION}} -->
<!-- {{#TIMESTAMPED_DISTRIBUTION}} -->
## Building the examples with the local module

Execute the following command from the repository root to build all the examples against the changes you have made to the module locally:

```bash
./gradlew :{{MODULE_NAME_CC}}-examples:build
```
<!-- {{/TIMESTAMPED_DISTRIBUTION}} -->
