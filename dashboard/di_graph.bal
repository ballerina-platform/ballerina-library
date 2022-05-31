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

import ballerina/log;

public type Node record {|
    readonly string vertex;
    string[] edges = [];
    int level = 1;
|};

class DiGraph {

    private table<Node> key(vertex) graph = table [];

    public function addNode(string node) {
        if !self.graph.hasKey(node) {
            self.graph.add({vertex: node});
        }
    }

    public function addEdge(string vertex1, string vertex2) {
        if !self.graph.hasKey(vertex1) {
            log:printError(string `vertex ${vertex1} doesn't exists`);
        }
        else if !self.graph.hasKey(vertex2) {
            log:printError(string `vertex ${vertex2} doesn't exists`);
        }
        else {
            Node n = self.graph.get(vertex1);
            n.edges.push(vertex2);
        }
    }

    public function inDegree(string vertex) returns int {
        int count = 0;
        foreach Node node in self.graph {
            if node.edges.indexOf(vertex) is int {
                count += 1;
            }
        }
        return count;
    }

    public function successor(string vertex) returns string[]? {
        if !self.graph.hasKey(vertex) {
            log:printError(string `vertex ${vertex} doesn't exists`);
            return;
        }
        return self.graph.get(vertex).edges;
    }

    public function getGraph() returns table<Node> key(vertex) {
        return self.graph;
    }

    public function setCurrentLevel(string vertex, int level) {
        if !self.graph.hasKey(vertex) {
            log:printError(string `vertex ${vertex} doesn't exists`);
            return;
        }
        Node node = self.graph.get(vertex);
        node.level = level;
    }

    public function getCurrentLevel(string vertex) returns int? {
        if !self.graph.hasKey(vertex) {
            log:printError(string `vertex ${vertex} doesn't exists`);
            return;
        }
        return self.graph.get(vertex).level;
    }

    public function getAllThePaths(string sourceNode, string targetNode) returns string[][] {
        map<boolean> isVisited = {};
        string[][] allPathList = [];
        string[] pathList = [];

        pathList.push(sourceNode);
        self.getAllThePathUntil(sourceNode, targetNode, isVisited, pathList, allPathList);
        return allPathList;
    }

    public function getAllThePathUntil(string sourceNode, string targetNode,
                        map<boolean> isVisited, string[] localPathList, string[][] allPathList) {
        if sourceNode == targetNode {
            allPathList.push(localPathList.clone());
            return;
        }

        // Mark the current node
        isVisited[sourceNode] = true;

        string[] successors = [];
        string[]? successorsOfNode = self.successor(sourceNode);
        if successorsOfNode is string[] {
            successors = successorsOfNode;
        }

        foreach string item in successors {
            if !(isVisited[item] is true) {
                localPathList.push(item);
                self.getAllThePathUntil(item, targetNode, isVisited, localPathList, allPathList);

                // remove the current node
                int indexOfItem = <int>localPathList.indexOf(item);
                _ = localPathList.remove(indexOfItem);
            }
        }

        // Mark the current node
        isVisited[sourceNode] = false;
    }

    public function getLongestPath(string sourceNode, string targetNode) returns string[] {
        string[][] allThePaths = self.getAllThePaths(sourceNode, targetNode);

        string[] longestPath = [];
        foreach string[] path in allThePaths {
            if path.length() > longestPath.length() {
                longestPath = path;
            }
        }
        return longestPath;
    }
}
