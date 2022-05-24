import ballerina/io;

public type node record {|
    readonly string V;
    string[] E = [];
    int level = 1;
|};

class DiGraph {

    private table<node> key(V) graph = table [];

    public function init() {}

    public function addNode(string node){
        if !self.graph.hasKey(node){
            self.graph.add({V:node});
        }
    }

    public function addEdge(string v1, string v2) {
        if !self.graph.hasKey(v1){io:println("vertex "+v1+" doesn't exists");}
        else if !self.graph.hasKey(v2){io:println("vertex "+v2+" doesn't exists");}
        else {
            node n = self.graph.get(v1);
            n.E.push(v2);
        }
    }

    public function inDegree(string v) returns int{
        int count = 0;
        foreach node n in self.graph {
            if n.E.indexOf(v) is int {
                count += 1;
            }
        }
        return count;
    }

    public function successor(string v) returns string[] {
        return self.graph.get(v).E;
    }

    public function printGraph() {
        io:println(self.graph);
    }

    public function getGraph() returns table<node> key(V) {
        return self.graph;
    }

    public function setCurrentLevel(string v, int level) {
        node n = self.graph.get(v);
        n.level = level;
    }

    public function getCurrentLevel(string v) returns int{
        return self.graph.get(v).level;
    }

    public function getAllThePaths(string sourceNode, string targetNode) returns string[][]{
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

        foreach string item in self.successor(sourceNode) {
            if !(isVisited[item] is true){
                localPathList.push(item);
                self.getAllThePathUntil(item, targetNode, isVisited, localPathList, allPathList);

                // remove the current node
                int indexOfItem = <int> localPathList.indexOf(item);
                _ = localPathList.remove(indexOfItem);
            }
        }

        // Mark the current node
        isVisited[sourceNode] = false;
    }

    public function getLongestPath(string sourceNode, string targetNode) returns string[]{
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