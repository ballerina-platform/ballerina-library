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

public function createSeparator(string char, int count) returns string {
    string sep = "";
    int i = 0;
    while i < count {
        sep += char;
        i += 1;
    }
    return sep;
}

