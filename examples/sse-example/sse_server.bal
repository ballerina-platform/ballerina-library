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
import ballerina/time;

// Configuration for the SSE server
configurable int port = 9090;

// Global message storage for the chat-like example
isolated json[] messages = [];

// Type definitions
public type ChatMessage record {
    string user;
    string message;
    string timestamp;
};

public type ChatRequest record {
    string user;
    string message;
};

// SSE Event Generator for real-time chat messages
class ChatEventGenerator {
    private int lastMessageIndex = 0;
    private boolean isClosed = false;

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        if self.isClosed {
            return ();
        }

        // Check for new messages
        lock {
            if messages.length() > self.lastMessageIndex {
                json newMessage = messages[self.lastMessageIndex];
                self.lastMessageIndex += 1;
                
                http:SseEvent sseEvent = {
                    data: newMessage.toString(),
                    id: self.lastMessageIndex.toString(),
                    event: "chat-message"
                };
                return {value: sseEvent};
            }
        }

        // No new messages, wait a bit
        runtime:sleep(0.5);
        return self.next();
    }

    public isolated function close() returns error? {
        self.isClosed = true;
        io:println("SSE connection closed");
    }
}

// SSE Event Generator for time-based events
class TimeEventGenerator {
    private boolean isClosed = false;

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        if self.isClosed {
            return ();
        }

        // Generate time-based event
        time:Utc currentTime = time:utcNow();
        http:SseEvent sseEvent = {
            data: "Current time: " + currentTime.toString(),
            id: currentTime.toString(),
            event: "time-update"
        };

        // Wait 5 seconds before next event
        runtime:sleep(5);
        return {value: sseEvent};
    }

    public isolated function close() returns error? {
        self.isClosed = true;
        io:println("Time SSE connection closed");
    }
}

// Main HTTP service with SSE endpoints
service /sse on new http:Listener(port) {
    
    // SSE endpoint for real-time chat messages
    isolated resource function get chat() returns stream<http:SseEvent, error?>|error {
        io:println("New chat SSE connection established");
        stream<http:SseEvent, error?> chatStream = new (new ChatEventGenerator());
        return chatStream;
    }

    // SSE endpoint for time updates
    isolated resource function get time() returns stream<http:SseEvent, error?>|error {
        io:println("New time SSE connection established");
        stream<http:SseEvent, error?> timeStream = new (new TimeEventGenerator());
        return timeStream;
    }

    // Endpoint to add new chat messages
    isolated resource function post messages(ChatRequest request) returns http:Ok|http:BadRequest|error {
        if request.user == "" || request.message == "" {
            return <http:BadRequest>{
                body: {error: "User and message cannot be empty"}
            };
        }

        ChatMessage chatMessage = {
            user: request.user,
            message: request.message,
            timestamp: time:utcNow().toString()
        };

        lock {
            messages.push(chatMessage);
        }

        io:println("New message from ", request.user, ": ", request.message);
        
        return <http:Ok>{
            body: {status: "Message added successfully", message: chatMessage}
        };
    }

    // Endpoint to get all messages
    isolated resource function get messages() returns http:Ok|error {
        json[] allMessages;
        lock {
            allMessages = messages.clone();
        }
        
        return <http:Ok>{
            body: {messages: allMessages}
        };
    }

    // Health check endpoint
    isolated resource function get health() returns http:Ok {
        return <http:Ok>{
            body: {status: "SSE Server is running", port: port}
        };
    }
}
