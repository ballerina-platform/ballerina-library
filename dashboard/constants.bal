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

// README Contents
const DASHBOARD_TITLE = "## Status Dashboard";
const LIBRARY_DASHBOARD_HEDER = "| Level | Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs | Load Test Results | GraalVM Check |";
const EXTENDED_DASHBOARD_HEDER = "| Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs | Load Test Results | GraalVM Check |";
const CONNECTOR_DASHBOARD_HEDER = "| Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs | Load Test Results | GraalVM Check |";
const TOOLS_DASHBOARD_HEDER = "| Name | Latest Version | Build | Security Check | Code Coverage | Bugs | Open PRs |";

const LIBRARY_HEADER_SEPARATOR = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|\n";
const HEADER_SEPARATOR = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|\n";
const TOOLS_HEADER_SEPARATOR = "|:---:|:---:|:---:|:---:|:---:|:---:|:---:|\n";

const BAL_TITLE = "### Ballerina Modules";
const BALX_TITLE = "### Ballerina Extended Modules";
const CONNECTOR_TITLE = "### Ballerina Connector Modules";
const TOOLS_TITLE = "### Ballerina Tools";

// Workflow files
const WORKFLOW_MASTER_BUILD = "build-timestamped-master.yml";
const WORKFLOW_TRIVY = "trivy-scan.yml";
const WORKFLOW_MASTER_CI_BUILD = "daily-build.yml";
const WORKFLOW_PROCESS_LOAD_TESTS = "process-load-test-result.yml";
const WORKFLOW_BAL_TEST_GRAALVM = "build-with-bal-test-graalvm.yml";
