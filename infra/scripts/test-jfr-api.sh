#!/bin/bash

# JFR API Testing Script
# Tests the Go sidecar API endpoints for JFR profiling

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
POD_NAME="${POD_NAME:-java-jfr-with-sidecar-0}"
NAMESPACE="${NAMESPACE:-default}"
API_PORT="${API_PORT:-8081}"
LOCAL_PORT="${LOCAL_PORT:-8081}"

# Base URL
BASE_URL="http://localhost:${LOCAL_PORT}"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if port-forward is running
check_port_forward() {
    if ! nc -z localhost ${LOCAL_PORT} 2>/dev/null; then
        return 1
    fi
    return 0
}

# Function to setup port-forward
setup_port_forward() {
    print_info "Setting up port-forward to pod ${POD_NAME}..."

    # Kill existing port-forward if any
    pkill -f "kubectl.*port-forward.*${POD_NAME}" 2>/dev/null || true
    sleep 1

    # Start new port-forward in background
    kubectl port-forward -n ${NAMESPACE} ${POD_NAME} ${LOCAL_PORT}:${API_PORT} > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!

    # Wait for port-forward to be ready
    print_info "Waiting for port-forward to be ready..."
    for i in {1..10}; do
        if check_port_forward; then
            print_success "Port-forward established (PID: ${PORT_FORWARD_PID})"
            return 0
        fi
        sleep 1
    done

    print_error "Port-forward failed to establish"
    return 1
}

# Function to test health endpoint
test_health() {
    print_info "Testing health endpoint..."
    response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/health")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "Health check passed"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        print_error "Health check failed (HTTP $http_code)"
        echo "$body"
        return 1
    fi
}

# Function to create a JFR profile
test_create_profile() {
    local duration="${1:-30s}"
    local filename="${2:-profile-$(date +%s).jfr}"

    print_info "Creating JFR profile (duration: $duration, filename: $filename)..."
    response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/create" \
        -H "Content-Type: application/json" \
        -d "{\"duration\": \"$duration\", \"filename\": \"$filename\"}")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "JFR profile created successfully"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        print_error "Failed to create JFR profile (HTTP $http_code)"
        echo "$body"
        return 1
    fi
}

# Function to list running JFR profiles
test_list_running() {
    print_info "Listing running JFR profiles..."
    response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/running")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "Running JFR profiles retrieved"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        print_error "Failed to list running profiles (HTTP $http_code)"
        echo "$body"
        return 1
    fi
}

# Function to stop a JFR profile
test_stop_profile() {
    local recording_name="${1}"

    if [ -z "$recording_name" ]; then
        print_error "Recording name is required"
        return 1
    fi

    print_info "Stopping JFR profile: $recording_name..."
    response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/stop" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$recording_name\"}")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "JFR profile stopped successfully"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        print_error "Failed to stop JFR profile (HTTP $http_code)"
        echo "$body"
        return 1
    fi
}

# Function to list profile files
test_list_files() {
    print_info "Listing profile files..."
    response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/list")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "Profile files retrieved"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        print_error "Failed to list profile files (HTTP $http_code)"
        echo "$body"
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [ ! -z "$PORT_FORWARD_PID" ]; then
        print_info "Cleaning up port-forward (PID: ${PORT_FORWARD_PID})..."
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
}

# Register cleanup on exit
trap cleanup EXIT

# Main script
main() {
    local action="${1:-all}"

    echo ""
    print_info "=== JFR API Testing Script ==="
    print_info "Pod: ${POD_NAME}"
    print_info "Namespace: ${NAMESPACE}"
    print_info "API Port: ${API_PORT}"
    print_info "Local Port: ${LOCAL_PORT}"
    echo ""

    # Setup port-forward
    setup_port_forward || exit 1
    sleep 2

    case "$action" in
        health)
            test_health
            ;;
        create)
            test_create_profile "$2" "$3"
            ;;
        running)
            test_list_running
            ;;
        stop)
            test_stop_profile "$2"
            ;;
        list)
            test_list_files
            ;;
        all)
            print_info "Running all tests..."
            echo ""
            test_health
            echo ""
            test_list_running
            echo ""
            test_create_profile "30s" "test-profile.jfr"
            echo ""
            sleep 2
            test_list_running
            echo ""
            test_list_files
            ;;
        *)
            print_error "Unknown action: $action"
            echo "Usage: $0 [health|create|running|stop|list|all] [args...]"
            echo ""
            echo "Examples:"
            echo "  $0 health                           # Check API health"
            echo "  $0 create 60s myprofile.jfr         # Create a profile"
            echo "  $0 running                          # List running profiles"
            echo "  $0 stop \"Recording 1\"               # Stop a profile by name"
            echo "  $0 list                             # List profile files"
            echo "  $0 all                              # Run all tests"
            exit 1
            ;;
    esac

    echo ""
    print_success "Test completed!"
}

# Run main function
main "$@"
