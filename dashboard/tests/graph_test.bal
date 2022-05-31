import ballerina/test;

@test:Config
function getLongestPathTest() {
    DiGraph graph = new DiGraph();
    graph.addNode("A");
    graph.addNode("B");
    graph.addNode("C");
    graph.addNode("D");

    graph.addEdge("A", "B");
    graph.addEdge("A", "C");
    graph.addEdge("A", "D");
    graph.addEdge("C", "B");
    graph.addEdge("B", "D");

    test:assertEquals(graph.getLongestPath("A", "C"), ["A", "C"]);
    test:assertEquals(graph.getLongestPath("A", "B"), ["A", "C", "B"]);
    test:assertEquals(graph.getLongestPath("A", "D"), ["A", "C", "B", "D"]);
}
