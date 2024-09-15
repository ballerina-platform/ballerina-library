// Copyright (c) 2022, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

// Names
const BALLERINA_ORG_NAME = "ballerina-platform";
const LIBRARY_REPO = "ballerina-library";

// Branches
const BRANCH_MAIN = "main";

// Links
const BALLERINA_ORG_URL = "https://github.com/ballerina-platform";
const GITHUB_BADGE_URL = "https://img.shields.io/github";
const CODECOV_BADGE_URL = "https://codecov.io/gh";

// Colors
const BADGE_COLOR_GREEN = "30c955";
const BADGE_COLOR_YELLOW = "yellow";

// File Paths
const MODULE_LIST_JSON = "../release/resources/module_list.json";
const STDLIB_MODULES_JSON = "../release/resources/stdlib_modules.json";
const README_FILE = "../README.md";
const GRADLE_PROPERTIES = "gradle.properties";

// Env variable Names
const BALLERINA_BOT_TOKEN = "BALLERINA_BOT_TOKEN";

// Misc
const ENCODING = "UTF-8";
const NABADGE = "https://img.shields.io/badge/-N%2FA-yellow";
const DISABLED_BADGE = "https://img.shields.io/badge/-disabled-red";
const MAX_LEVEL = 100;

// README Contents
const DASHBOARD_TITLE = "## Status Dashboard";
const HEADER_LIBRARY_MODULES_DASHBOARD = "| Level | Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs | Load Test Results | GraalVM Check |";
const HEADER_EXTENDED_MODULES_DASHBOARD = "| Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs | Load Test Results | GraalVM Check |";
const HEADER_HANDWRITTEN_CONNECTOR_DASHBOARD = "| Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs | Load Test Results | GraalVM Check |";
const HEADER_GENERATED_CONNECTOR_DASHBOARD = "| Name | Latest Version | Build | Security Check | Bugs | Open PRs | GraalVM Check |";
const HEADER_TOOLS_DASHBOARD = "| Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs |";

const HEADER_SEPARATOR_LIBRARY_MODULES = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|";
const HEADER_SEPARATOR_EXTENDED_MODULES = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|";
const HEADER_SEPARATOR_HANDWRITTEN_CONNECTORS = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|";
const HEADER_SEPARATOR_GENERATED_CONNECTORS = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|";
const HEADER_SEPARATOR_TOOLS = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|";

const TITLE_LIBRARY_MODULES = "### Ballerina Modules";
const TITLE_EXTENDED_MODULES = "### Ballerina Extended Modules";
const TITLE_HANDWRITTEN_CONNECTORS = "### Ballerina Handwritten Connector Modules";
const TITLE_GENERATED_CONNECTORS = "### Ballerina Generated Connector Modules";
const TITLE_TOOLS = "### Ballerina Tools";

const DESCRIPTION_LIBRARY_MODULES = "These modules are published under the `ballerina` organization and packed with the Ballerina distribution.";
const DESCRIPTION_EXTENDED_MODULES = "These modules are protocol modules that are not packed with the Ballerina distribution.";
const DESCRIPTION_HANDWRITTEN_CONNECTORS = "These are the handwritten Ballerina connector modules that are used to connect to third-party services. They are published under the `ballerinax` organization ";
const DESCRIPTION_GENERATED_CONNECTORS = "These are the generated Ballerina connector modules that are used to connect to third-party services. They are published under the `ballerinax` organization. The modules are generated using the Ballerina OpenAPI tool using the third-party service's OpenAPI definition. Since these are auto-generated, they only contain a smoke test suite rather than a comprehensive test suite. Due to this nature, the code coverage and load test results are not applicable for these modules. Some repositories such as `sap.s4hana.sales` contain multiple connectors which are highly co-related. These have multiple releases and thus not indicated here.";
const DESCRIPTION_TOOLS = "These are the Ballerina CLI tools maintained by the Ballerina Library team.";

// Workflow files
const WORKFLOW_MASTER_BUILD = "build-timestamped-master.yml";
const WORKFLOW_TRIVY = "trivy-scan.yml";
const WORKFLOW_MASTER_CI_BUILD = "daily-build.yml";
const WORKFLOW_PROCESS_LOAD_TESTS = "process-load-test-result.yml";
const WORKFLOW_BAL_TEST_GRAALVM = "build-with-bal-test-graalvm.yml";
