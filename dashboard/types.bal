// Copyright (c) 2024, WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
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

type List record {|
    Module[] library_modules;
    Module[] extended_modules;
    Module[] handwritten_connectors;
    Module[] generated_connectors;
    Module[] tools;
|};

type Module record {|
    string name;
    string module_version?;
    int level?;
    string default_branch?;
    string version_key?;
    boolean release?;
    string[] dependents?;
    string gradle_properties?;
|};

type WorkflowBadge record {|
    string name;
    string badgeUrl = NABADGE;
    string htmlUrl = "";
|};

type RepoBadges record {|
    WorkflowBadge release?;
    WorkflowBadge buildStatus?;
    WorkflowBadge trivy?;
    WorkflowBadge codeCov?;
    WorkflowBadge bugs?;
    WorkflowBadge pullRequests?;
    WorkflowBadge loadTests?;
    WorkflowBadge graalvmCheck?;
|};
