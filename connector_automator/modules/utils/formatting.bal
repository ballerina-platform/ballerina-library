import ballerina/io;

public function repeat() {
    string sep = "";
    int i = 0;
    while i < 80 {
        sep += "=";
        i += 1;
    }
    io:println(sep);
}

