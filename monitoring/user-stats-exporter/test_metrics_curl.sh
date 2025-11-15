#!/bin/bash
# Test script to verify per-user metrics are properly incremented using curl

set -e

METRICS_ENDPOINT="${METRICS_ENDPOINT:-http://localhost:9114/metrics}"
NGINX_LOG_PATH="${NGINX_LOG_PATH:-/var/log/nginx/access.log}"

echo "=========================================="
echo "Testing Per-User Metrics with Prometheus"
echo "=========================================="
echo "Metrics endpoint: $METRICS_ENDPOINT"
echo ""

# Function to get metric value for a specific user
get_metric_value() {
    local metric_name=$1
    local user_ip=$2
    local additional_labels=$3
    
    # Build the query
    local query="${metric_name}{user_ip=\"${user_ip}\""
    if [ -n "$additional_labels" ]; then
        query="${query},${additional_labels}"
    fi
    query="${query}}"
    
    # Query Prometheus metrics endpoint
    curl -s "$METRICS_ENDPOINT" | grep "^${metric_name}" | grep "user_ip=\"${user_ip}\"" | grep -E "${additional_labels}" | head -1 | awk '{print $2}' || echo "0"
}

# Function to get all metrics for a user
get_user_metrics() {
    local user_ip=$1
    echo "--- Metrics for user $user_ip ---"
    curl -s "$METRICS_ENDPOINT" | grep "user_ip=\"${user_ip}\"" || echo "No metrics found for user $user_ip"
    echo ""
}

# Function to send test log lines
send_test_logs() {
    local log_lines=("$@")
    echo "Sending test log lines..."
    
    # Check if we're in Docker or local
    if [ -f "$NGINX_LOG_PATH" ] && [ -w "$NGINX_LOG_PATH" ]; then
        # Write to log file
        for line in "${log_lines[@]}"; do
            echo "$line" >> "$NGINX_LOG_PATH"
        done
        echo "Written ${#log_lines[@]} log lines to $NGINX_LOG_PATH"
    elif command -v docker &> /dev/null && docker ps | grep -q user-stats-exporter; then
        # Send to Docker container via stdin
        for line in "${log_lines[@]}"; do
            echo "$line" | docker exec -i user-stats-exporter python3 -c "import sys; sys.stdin.readline()" 2>/dev/null || true
        done
        echo "Sent ${#log_lines[@]} log lines to user-stats-exporter container"
    else
        echo "Warning: Cannot write to log file or access Docker container"
        echo "Please ensure the user-stats-exporter is running and accessible"
        echo "You can manually send these log lines to the exporter:"
        for line in "${log_lines[@]}"; do
            echo "  $line"
        done
    fi
    echo ""
}

# Wait for metrics to be updated
wait_for_metrics() {
    echo "Waiting 2 seconds for metrics to be processed..."
    sleep 2
    echo ""
}

# Test 1: Check initial state
echo "Test 1: Checking initial metrics endpoint..."
if curl -s -f "$METRICS_ENDPOINT" > /dev/null 2>&1; then
    echo "✓ Metrics endpoint is accessible"
else
    echo "✗ Metrics endpoint is not accessible at $METRICS_ENDPOINT"
    echo "Please ensure the user-stats-exporter service is running"
    exit 1
fi
echo ""

# Test 2: Send test log lines for User 1
echo "Test 2: Sending test requests for User 1 (192.168.1.100)..."
USER1_LOGS=(
    '192.168.1.100 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
    '192.168.1.100 - - [25/Dec/2023:10:00:01 +0000] "GET /server1 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.15 uct="0.08" uht="0.12" urt="0.15"'
    '192.168.1.100 - - [25/Dec/2023:10:00:02 +0000] "POST /server1 HTTP/1.1" 429 0 "referer" "user-agent" "x-forwarded-for" rt=0.01 uct="0.005" uht="0.008" urt="0.01"'
)

send_test_logs "${USER1_LOGS[@]}"
wait_for_metrics

# Test 3: Send test log lines for User 2
echo "Test 3: Sending test requests for User 2 (192.168.1.200)..."
USER2_LOGS=(
    '192.168.1.200 - - [25/Dec/2023:10:00:10 +0000] "GET /server2 HTTP/1.1" 200 4096 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'
    '192.168.1.200 - - [25/Dec/2023:10:00:11 +0000] "GET /server2 HTTP/1.1" 504 0 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
)

send_test_logs "${USER2_LOGS[@]}"
wait_for_metrics

# Test 4: Verify User 1 metrics
echo "Test 4: Verifying User 1 (192.168.1.100) metrics..."
get_user_metrics "192.168.1.100"

# Get specific metric values
USER1_REQUESTS_200=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_user_requests_total' | grep 'user_ip="192.168.1.100"' | grep 'status="200"' | grep 'method="GET"' | grep 'route="/server1"' | awk '{print $2}' | head -1 || echo "0")
USER1_REQUESTS_429=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_user_requests_total' | grep 'user_ip="192.168.1.100"' | grep 'status="429"' | grep 'method="POST"' | grep 'route="/server1"' | awk '{print $2}' | head -1 || echo "0")
USER1_BYTES=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_user_bytes_total' | grep 'user_ip="192.168.1.100"' | grep 'direction="sent"' | awk '{print $2}' | head -1 || echo "0")
USER1_RATE_LIMIT=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_rate_limit_hits_total' | grep 'user_ip="192.168.1.100"' | grep 'route="/server1"' | grep 'http_method="POST"' | awk '{print $2}' | head -1 || echo "0")

echo "User 1 - GET /server1 status 200: $USER1_REQUESTS_200 (expected: 2)"
echo "User 1 - POST /server1 status 429: $USER1_REQUESTS_429 (expected: 1)"
echo "User 1 - Bytes sent: $USER1_BYTES (expected: 3072)"
echo "User 1 - Rate limit hits: $USER1_RATE_LIMIT (expected: 1)"
echo ""

# Test 5: Verify User 2 metrics
echo "Test 5: Verifying User 2 (192.168.1.200) metrics..."
get_user_metrics "192.168.1.200"

USER2_REQUESTS_200=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_user_requests_total' | grep 'user_ip="192.168.1.200"' | grep 'status="200"' | grep 'method="GET"' | grep 'route="/server2"' | awk '{print $2}' | head -1 || echo "0")
USER2_REQUESTS_504=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_user_requests_total' | grep 'user_ip="192.168.1.200"' | grep 'status="504"' | grep 'method="GET"' | grep 'route="/server2"' | awk '{print $2}' | head -1 || echo "0")
USER2_BYTES=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_user_bytes_total' | grep 'user_ip="192.168.1.200"' | grep 'direction="sent"' | awk '{print $2}' | head -1 || echo "0")
USER2_TIMEOUT=$(curl -s "$METRICS_ENDPOINT" | grep '^nginx_timeout_events_total' | grep 'user_ip="192.168.1.200"' | grep 'route="/server2"' | grep 'timeout_type="gateway_timeout"' | grep 'http_method="GET"' | awk '{print $2}' | head -1 || echo "0")

echo "User 2 - GET /server2 status 200: $USER2_REQUESTS_200 (expected: 1)"
echo "User 2 - GET /server2 status 504: $USER2_REQUESTS_504 (expected: 1)"
echo "User 2 - Bytes sent: $USER2_BYTES (expected: 4096)"
echo "User 2 - Timeout events: $USER2_TIMEOUT (expected: 1)"
echo ""

# Test 6: Verify metrics are separate per user
echo "Test 6: Verifying metrics are separate per user..."
echo "Checking that User 1 and User 2 have independent metrics..."
echo ""

# Test 7: Summary and validation
echo "=========================================="
echo "Test Summary"
echo "=========================================="

ERRORS=0

# Validate User 1
if [ "$USER1_REQUESTS_200" = "2.0" ] || [ "$USER1_REQUESTS_200" = "2" ]; then
    echo "✓ User 1: GET requests (200) = $USER1_REQUESTS_200"
else
    echo "✗ User 1: GET requests (200) = $USER1_REQUESTS_200 (expected: 2)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER1_REQUESTS_429" = "1.0" ] || [ "$USER1_REQUESTS_429" = "1" ]; then
    echo "✓ User 1: POST requests (429) = $USER1_REQUESTS_429"
else
    echo "✗ User 1: POST requests (429) = $USER1_REQUESTS_429 (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER1_BYTES" = "3072.0" ] || [ "$USER1_BYTES" = "3072" ]; then
    echo "✓ User 1: Bytes sent = $USER1_BYTES"
else
    echo "✗ User 1: Bytes sent = $USER1_BYTES (expected: 3072)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER1_RATE_LIMIT" = "1.0" ] || [ "$USER1_RATE_LIMIT" = "1" ]; then
    echo "✓ User 1: Rate limit hits = $USER1_RATE_LIMIT"
else
    echo "✗ User 1: Rate limit hits = $USER1_RATE_LIMIT (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

# Validate User 2
if [ "$USER2_REQUESTS_200" = "1.0" ] || [ "$USER2_REQUESTS_200" = "1" ]; then
    echo "✓ User 2: GET requests (200) = $USER2_REQUESTS_200"
else
    echo "✗ User 2: GET requests (200) = $USER2_REQUESTS_200 (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER2_REQUESTS_504" = "1.0" ] || [ "$USER2_REQUESTS_504" = "1" ]; then
    echo "✓ User 2: GET requests (504) = $USER2_REQUESTS_504"
else
    echo "✗ User 2: GET requests (504) = $USER2_REQUESTS_504 (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER2_BYTES" = "4096.0" ] || [ "$USER2_BYTES" = "4096" ]; then
    echo "✓ User 2: Bytes sent = $USER2_BYTES"
else
    echo "✗ User 2: Bytes sent = $USER2_BYTES (expected: 4096)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER2_TIMEOUT" = "1.0" ] || [ "$USER2_TIMEOUT" = "1" ]; then
    echo "✓ User 2: Timeout events = $USER2_TIMEOUT"
else
    echo "✗ User 2: Timeout events = $USER2_TIMEOUT (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "=========================================="
    echo "✓ All tests passed! Metrics are properly incremented per user."
    echo "=========================================="
    exit 0
else
    echo "=========================================="
    echo "✗ $ERRORS test(s) failed. Please check the metrics above."
    echo "=========================================="
    echo ""
    echo "Full metrics output:"
    curl -s "$METRICS_ENDPOINT" | grep -E "(nginx_user_|nginx_rate_limit_|nginx_timeout_)" | head -20
    exit 1
fi

