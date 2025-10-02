#!/bin/bash

# SSE Example Test Script
# This script tests the SSE server functionality

echo "SSE Example Test Script"
echo "======================"

# Configuration
SERVER_URL="http://localhost:9090"
TEST_USER="TestUser"
TEST_MESSAGE="Hello from test script!"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "SUCCESS" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "ERROR" ]; then
        echo -e "${RED}✗${NC} $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${YELLOW}ℹ${NC} $message"
    fi
}

# Function to check if server is running
check_server() {
    print_status "INFO" "Checking if server is running..."
    if curl -s "$SERVER_URL/sse/health" > /dev/null 2>&1; then
        print_status "SUCCESS" "Server is running on $SERVER_URL"
        return 0
    else
        print_status "ERROR" "Server is not running on $SERVER_URL"
        print_status "INFO" "Please start the server with: bal run sse_server.bal"
        return 1
    fi
}

# Function to test health endpoint
test_health() {
    print_status "INFO" "Testing health endpoint..."
    response=$(curl -s "$SERVER_URL/sse/health")
    if echo "$response" | grep -q "SSE Server is running"; then
        print_status "SUCCESS" "Health check passed"
        echo "Response: $response"
    else
        print_status "ERROR" "Health check failed"
        echo "Response: $response"
    fi
}

# Function to test message posting
test_post_message() {
    print_status "INFO" "Testing message posting..."
    response=$(curl -s -X POST "$SERVER_URL/sse/messages" \
        -H "Content-Type: application/json" \
        -d "{\"user\":\"$TEST_USER\",\"message\":\"$TEST_MESSAGE\"}")
    
    if echo "$response" | grep -q "Message added successfully"; then
        print_status "SUCCESS" "Message posted successfully"
        echo "Response: $response"
    else
        print_status "ERROR" "Failed to post message"
        echo "Response: $response"
    fi
}

# Function to test message retrieval
test_get_messages() {
    print_status "INFO" "Testing message retrieval..."
    response=$(curl -s "$SERVER_URL/sse/messages")
    
    if echo "$response" | grep -q "messages"; then
        print_status "SUCCESS" "Messages retrieved successfully"
        echo "Response: $response"
    else
        print_status "ERROR" "Failed to retrieve messages"
        echo "Response: $response"
    fi
}

# Function to test SSE connection (basic)
test_sse_connection() {
    print_status "INFO" "Testing SSE connection (5 second timeout)..."
    
    # Start SSE connection in background
    timeout 5s curl -s -N "$SERVER_URL/sse/chat" > /tmp/sse_output.txt 2>&1 &
    sse_pid=$!
    
    # Wait a bit for connection to establish
    sleep 2
    
    # Send a message to trigger SSE event
    curl -s -X POST "$SERVER_URL/sse/messages" \
        -H "Content-Type: application/json" \
        -d "{\"user\":\"SSETest\",\"message\":\"SSE test message\"}" > /dev/null
    
    # Wait for SSE to process
    sleep 2
    
    # Check if SSE connection received data
    if [ -s /tmp/sse_output.txt ]; then
        print_status "SUCCESS" "SSE connection is working"
        echo "SSE Output:"
        cat /tmp/sse_output.txt
    else
        print_status "ERROR" "SSE connection failed or no data received"
    fi
    
    # Clean up
    kill $sse_pid 2>/dev/null
    rm -f /tmp/sse_output.txt
}

# Function to test invalid message
test_invalid_message() {
    print_status "INFO" "Testing invalid message handling..."
    response=$(curl -s -X POST "$SERVER_URL/sse/messages" \
        -H "Content-Type: application/json" \
        -d "{\"user\":\"\",\"message\":\"\"}")
    
    if echo "$response" | grep -q "error"; then
        print_status "SUCCESS" "Invalid message properly rejected"
        echo "Response: $response"
    else
        print_status "ERROR" "Invalid message was not properly rejected"
        echo "Response: $response"
    fi
}

# Main test execution
main() {
    echo
    print_status "INFO" "Starting SSE server tests..."
    echo
    
    # Check if server is running
    if ! check_server; then
        exit 1
    fi
    
    echo
    print_status "INFO" "Running API tests..."
    echo
    
    # Run tests
    test_health
    echo
    
    test_post_message
    echo
    
    test_get_messages
    echo
    
    test_invalid_message
    echo
    
    test_sse_connection
    echo
    
    print_status "SUCCESS" "All tests completed!"
    echo
    print_status "INFO" "To test the web client, open sse_client.html in a web browser"
    print_status "INFO" "To test the Ballerina client, run: bal run sse_client.bal"
}

# Run main function
main "$@"
