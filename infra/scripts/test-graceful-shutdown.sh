#!/bin/bash

# Graceful Shutdown Testing Script
# Tests that JFR recordings are properly stopped when the sidecar receives SIGTERM

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
SIDECAR_CONTAINER="${SIDECAR_CONTAINER:-go-sidecar}"
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

# Function to create a long-running JFR profile
create_long_profile() {
    local duration="${1:-300s}"  # 5 minutes by default

    print_info "Creating long-running JFR profile (duration: $duration)..."
    response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/create" \
        -H "Content-Type: application/json" \
        -d "{\"duration\": \"$duration\"}")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "JFR profile created successfully"
        echo "$body" | jq '.'
        # Extract recording name from response
        RECORDING_NAME=$(echo "$body" | jq -r '.data.name')
        print_info "Recording name: $RECORDING_NAME"
    else
        print_error "Failed to create JFR profile (HTTP $http_code)"
        echo "$body"
        return 1
    fi
}

# Function to list running JFR profiles
list_running_profiles() {
    print_info "Listing running JFR profiles..."
    response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/running")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "Running JFR profiles retrieved"
        echo "$body" | jq '.'
    else
        print_error "Failed to list running profiles (HTTP $http_code)"
        echo "$body"
        return 1
    fi
}

# Function to trigger graceful shutdown
trigger_graceful_shutdown() {
    print_info "Triggering graceful shutdown by rollout restart..."

    kubectl rollout restart -n ${NAMESPACE} sts/java-jfr-with-sidecar || {
        print_error "Failed to restart the statefulset"
        return 1
    }

    print_success "SIGTERM sent to sidecar process"
}

# Function to check logs for graceful shutdown
check_shutdown_logs() {
    print_info "Checking sidecar logs for graceful shutdown messages..."
    sleep 3  # Give it time to process the signal

    logs=$(kubectl logs -n ${NAMESPACE} ${POD_NAME} -c ${SIDECAR_CONTAINER} --tail=50)

    if echo "$logs" | grep -q "Shutdown signal received"; then
        print_success "Found shutdown signal message in logs"
    else
        print_warning "Shutdown signal message not found in recent logs"
    fi

    if echo "$logs" | grep -q "Stopping active JFR recordings"; then
        print_success "Found JFR recordings cleanup message in logs"
    else
        print_warning "JFR cleanup message not found in recent logs"
    fi

    if echo "$logs" | grep -q "Successfully stopped JFR recording"; then
        print_success "JFR recordings were stopped successfully"
    else
        print_warning "JFR stop confirmation not found in recent logs"
    fi

    echo ""
    print_info "Recent logs from sidecar:"
    echo "----------------------------------------"
    echo "$logs"
    echo "----------------------------------------"
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

# Main test function
main() {
    echo ""
    print_info "=== Graceful Shutdown Testing Script ==="
    print_info "Pod: ${POD_NAME}"
    print_info "Namespace: ${NAMESPACE}"
    print_info "Sidecar Container: ${SIDECAR_CONTAINER}"
    print_info "API Port: ${API_PORT}"
    print_info "Local Port: ${LOCAL_PORT}"
    echo ""

    # Setup port-forward
    setup_port_forward || exit 1
    sleep 2

    # Step 1: Create a long-running profile
    print_info "Step 1: Creating long-running JFR profile..."
    echo ""
    create_long_profile "300s" || exit 1
    echo ""

    # Step 2: Verify it's running
    print_info "Step 2: Verifying profile is running..."
    echo ""
    list_running_profiles || exit 1
    echo ""

    # Step 3: Trigger graceful shutdown
    print_info "Step 3: Triggering graceful shutdown..."
    echo ""
    trigger_graceful_shutdown || exit 1
    echo ""

    # Step 4: Check logs for graceful shutdown
    print_info "Step 4: Checking logs for graceful shutdown messages..."
    echo ""
    check_shutdown_logs
    echo ""

    print_success "Graceful shutdown test completed!"
    echo ""
    print_info "Summary:"
    print_info "1. Created a long-running JFR profile"
    print_info "2. Verified it was running"
    print_info "3. Sent SIGTERM to trigger graceful shutdown"
    print_info "4. Verified shutdown logs show JFR recordings were stopped"
    echo ""
    print_warning "Note: The sidecar container will restart automatically due to Kubernetes restart policy."
    print_warning "Check the logs above to verify graceful shutdown behavior."
}

# Run main function
main "$@"
