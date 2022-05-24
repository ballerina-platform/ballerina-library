import ballerina/io;

public type node record {|
    readonly string V;
    string[] E = [];
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
}