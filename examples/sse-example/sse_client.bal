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

import ballerina/http;
import ballerina/io;
import ballerina/data.jsondata;

// Configuration
configurable string serverUrl = "http://localhost:9090";
configurable string username = "ClientUser";

// Type definitions
public type ChatRequest record {
    string user;
    string message;
};

public function main() returns error? {
    io:println("SSE Client Example");
    io:println("==================");
    
    // Create HTTP client
    http:Client sseClient = check new (serverUrl);
    
    // Test health endpoint
    io:println("Testing health endpoint...");
    http:Response healthResponse = check sseClient->get("/sse/health");
    io:println("Health check: ", healthResponse.getTextPayload());
    
    // Test getting existing messages
    io:println("\nGetting existing messages...");
    http:Response messagesResponse = check sseClient->get("/sse/messages");
    io:println("Existing messages: ", messagesResponse.getTextPayload());
    
    // Send a test message
    io:println("\nSending a test message...");
    ChatRequest chatRequest = {
        user: username,
        message: "Hello from SSE client!"
    };
    http:Response postResponse = check sseClient->post("/sse/messages", chatRequest);
    io:println("Message sent: ", postResponse.getTextPayload());
    
    // Connect to SSE stream for chat messages
    io:println("\nConnecting to chat SSE stream...");
    stream<http:SseEvent, error?> chatStream = check sseClient->get("/sse/chat");
    
    // Listen for SSE events
    io:println("Listening for chat messages (press Ctrl+C to stop)...");
    check listenToSseStream(chatStream, "chat");
    
    // Clean up
    check sseClient.close();
}

// Function to listen to SSE stream
isolated function listenToSseStream(stream<http:SseEvent, error?> sseStream, string streamType) returns error? {
    record {|http:SseEvent value;|}?|error event = sseStream.next();
    
    while event is record {|http:SseEvent value;|} {
        http:SseEvent sseEvent = event.value;
        
        io:println(`[${streamType.toUpperAscii()}] Event ID: ${sseEvent.id}`);
        io:println(`[${streamType.toUpperAscii()}] Event Type: ${sseEvent.event}`);
        io:println(`[${streamType.toUpperAscii()}] Data: ${sseEvent.data}`);
        io:println("---");
        
        event = sseStream.next();
    }
    
    if event is error {
        io:println("Error in SSE stream: ", event.message());
    } else {
        io:println("SSE stream ended");
    }
    
    return;
}
