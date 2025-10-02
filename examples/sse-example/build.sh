#!/bin/bash

# SSE Example Build Script
# This script builds and runs the SSE example

echo "SSE Example Build Script"
echo "========================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    elif [ "$status" = "BUILD" ]; then
        echo -e "${BLUE}🔨${NC} $message"
    fi
}

# Function to check if Ballerina is installed
check_ballerina() {
    print_status "INFO" "Checking Ballerina installation..."
    if command -v bal &> /dev/null; then
        bal_version=$(bal version 2>&1 | head -n 1)
        print_status "SUCCESS" "Ballerina is installed: $bal_version"
        return 0
    else
        print_status "ERROR" "Ballerina is not installed or not in PATH"
        print_status "INFO" "Please install Ballerina from https://ballerina.io/downloads/"
        return 1
    fi
}

# Function to build the project
build_project() {
    print_status "BUILD" "Building SSE example..."
    if bal build; then
        print_status "SUCCESS" "Build completed successfully"
        return 0
    else
        print_status "ERROR" "Build failed"
        return 1
    fi
}

# Function to run the server
run_server() {
    print_status "INFO" "Starting SSE server..."
    print_status "INFO" "Server will run on http://localhost:9090"
    print_status "INFO" "Press Ctrl+C to stop the server"
    echo
    bal run sse_server.bal
}

# Function to run the client
run_client() {
    print_status "INFO" "Starting SSE client..."
    bal run sse_client.bal
}

# Function to run tests
run_tests() {
    print_status "INFO" "Running tests..."
    if [ -f "./test_sse.sh" ]; then
        ./test_sse.sh
    else
        print_status "ERROR" "Test script not found"
        return 1
    fi
}

# Function to show help
show_help() {
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  build     Build the project"
    echo "  server    Run the SSE server"
    echo "  client    Run the SSE client"
    echo "  test      Run tests"
    echo "  all       Build, run server, and run tests"
    echo "  help      Show this help message"
    echo
    echo "Examples:"
    echo "  $0 build"
    echo "  $0 server"
    echo "  $0 test"
}

# Main function
main() {
    case "${1:-help}" in
        "build")
            if check_ballerina; then
                build_project
            fi
            ;;
        "server")
            if check_ballerina; then
                run_server
            fi
            ;;
        "client")
            if check_ballerina; then
                run_client
            fi
            ;;
        "test")
            run_tests
            ;;
        "all")
            if check_ballerina; then
                build_project && run_tests
            fi
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run main function
main "$@"
