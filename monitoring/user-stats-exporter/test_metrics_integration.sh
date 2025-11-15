#!/bin/bash
# Integration test script to verify per-user metrics incrementation
# This script sends test log lines and verifies metrics using curl

set -e

METRICS_ENDPOINT="http://localhost:9114/metrics"
CONTAINER_NAME="user-stats-exporter"

echo "=========================================="
echo "Per-User Metrics Integration Test"
echo "=========================================="
echo "Metrics endpoint: $METRICS_ENDPOINT"
echo ""

# Check if metrics endpoint is accessible
echo "Step 1: Checking metrics endpoint..."
if curl -s -f "$METRICS_ENDPOINT" > /dev/null 2>&1; then
    echo "✓ Metrics endpoint is accessible"
else
    echo "✗ Metrics endpoint is not accessible"
    echo "  Please ensure user-stats-exporter is running:"
    echo "    docker-compose up -d user-stats-exporter"
    exit 1
fi
echo ""

# Function to send log line to exporter
send_log_line() {
    local log_line="$1"
    
    # Try multiple methods to send the log line
    if docker ps | grep -q "$CONTAINER_NAME"; then
        # Method 1: Send via Docker exec (if container accepts stdin)
        echo "$log_line" | docker exec -i "$CONTAINER_NAME" python3 -c "
import sys
import user_stats_exporter
line = sys.stdin.readline().strip()
if line:
    user_stats_exporter.process_log_line(line)
" 2>/dev/null && return 0
        
        # Method 2: Write to log file if mounted
        docker exec "$CONTAINER_NAME" sh -c "echo '$log_line' >> /tmp/test_access.log" 2>/dev/null && return 0
    fi
    
    # Method 3: If running locally, write to log file
    if [ -w "/var/log/nginx/access.log" ]; then
        echo "$log_line" >> /var/log/nginx/access.log
        return 0
    fi
    
    echo "Warning: Could not send log line automatically"
    echo "  Please send this log line manually:"
    echo "  $log_line"
    return 1
}

# Function to get metric value
get_metric() {
    local metric_name="$1"
    local user_ip="$2"
    local additional_grep="$3"
    
    curl -s "$METRICS_ENDPOINT" | \
        grep "^${metric_name}" | \
        grep "user_ip=\"${user_ip}\"" | \
        ${additional_grep:+grep -E "$additional_grep"} | \
        head -1 | \
        awk '{print $2}' || echo "0"
}

# Function to wait for metrics to update
wait_for_metrics() {
    echo "Waiting 2 seconds for metrics to be processed..."
    sleep 2
}

# Get initial metrics state
echo "Step 2: Getting initial metrics state..."
INITIAL_USER1_REQUESTS=$(get_metric "nginx_user_requests_total" "192.168.1.100" 'status="200".*method="GET".*route="/server1"')
INITIAL_USER2_REQUESTS=$(get_metric "nginx_user_requests_total" "192.168.1.200" 'status="200".*method="GET".*route="/server2"')
echo "  Initial User 1 requests: $INITIAL_USER1_REQUESTS"
echo "  Initial User 2 requests: $INITIAL_USER2_REQUESTS"
echo ""

# Send test log lines for User 1
echo "Step 3: Sending test log lines for User 1 (192.168.1.100)..."
USER1_LOGS=(
    '192.168.1.100 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
    '192.168.1.100 - - [25/Dec/2023:10:00:01 +0000] "GET /server1 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.15 uct="0.08" uht="0.12" urt="0.15"'
    '192.168.1.100 - - [25/Dec/2023:10:00:02 +0000] "POST /server1 HTTP/1.1" 429 0 "referer" "user-agent" "x-forwarded-for" rt=0.01 uct="0.005" uht="0.008" urt="0.01"'
)

for log_line in "${USER1_LOGS[@]}"; do
    echo "  Sending: $(echo "$log_line" | cut -d' ' -f1,7,8)"
    send_log_line "$log_line"
done
echo ""

# Send test log lines for User 2
echo "Step 4: Sending test log lines for User 2 (192.168.1.200)..."
USER2_LOGS=(
    '192.168.1.200 - - [25/Dec/2023:10:00:10 +0000] "GET /server2 HTTP/1.1" 200 4096 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'
    '192.168.1.200 - - [25/Dec/2023:10:00:11 +0000] "GET /server2 HTTP/1.1" 504 0 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
)

for log_line in "${USER2_LOGS[@]}"; do
    echo "  Sending: $(echo "$log_line" | cut -d' ' -f1,7,8)"
    send_log_line "$log_line"
done
echo ""

wait_for_metrics

# Verify metrics
echo "Step 5: Verifying metrics incrementation..."
echo ""

# User 1 metrics
echo "User 1 (192.168.1.100) metrics:"
USER1_REQUESTS_200=$(get_metric "nginx_user_requests_total" "192.168.1.100" 'status="200".*method="GET".*route="/server1"')
USER1_REQUESTS_429=$(get_metric "nginx_user_requests_total" "192.168.1.100" 'status="429".*method="POST".*route="/server1"')
USER1_BYTES=$(get_metric "nginx_user_bytes_total" "192.168.1.100" 'direction="sent"')
USER1_RATE_LIMIT=$(get_metric "nginx_rate_limit_hits_total" "192.168.1.100" 'route="/server1".*http_method="POST"')

echo "  GET /server1 (200): $USER1_REQUESTS_200 (expected: 2)"
echo "  POST /server1 (429): $USER1_REQUESTS_429 (expected: 1)"
echo "  Bytes sent: $USER1_BYTES (expected: 3072)"
echo "  Rate limit hits: $USER1_RATE_LIMIT (expected: 1)"
echo ""

# User 2 metrics
echo "User 2 (192.168.1.200) metrics:"
USER2_REQUESTS_200=$(get_metric "nginx_user_requests_total" "192.168.1.200" 'status="200".*method="GET".*route="/server2"')
USER2_REQUESTS_504=$(get_metric "nginx_user_requests_total" "192.168.1.200" 'status="504".*method="GET".*route="/server2"')
USER2_BYTES=$(get_metric "nginx_user_bytes_total" "192.168.1.200" 'direction="sent"')
USER2_TIMEOUT=$(get_metric "nginx_timeout_events_total" "192.168.1.200" 'route="/server2".*timeout_type="gateway_timeout"')

echo "  GET /server2 (200): $USER2_REQUESTS_200 (expected: 1)"
echo "  GET /server2 (504): $USER2_REQUESTS_504 (expected: 1)"
echo "  Bytes sent: $USER2_BYTES (expected: 4096)"
echo "  Timeout events: $USER2_TIMEOUT (expected: 1)"
echo ""

# Validation
echo "Step 6: Validation..."
ERRORS=0

# Validate User 1
if [ "$USER1_REQUESTS_200" = "2.0" ] || [ "$USER1_REQUESTS_200" = "2" ]; then
    echo "✓ User 1: GET requests (200) correctly incremented"
else
    echo "✗ User 1: GET requests (200) = $USER1_REQUESTS_200 (expected: 2)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER1_REQUESTS_429" = "1.0" ] || [ "$USER1_REQUESTS_429" = "1" ]; then
    echo "✓ User 1: POST requests (429) correctly incremented"
else
    echo "✗ User 1: POST requests (429) = $USER1_REQUESTS_429 (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER1_BYTES" = "3072.0" ] || [ "$USER1_BYTES" = "3072" ]; then
    echo "✓ User 1: Bytes correctly incremented"
else
    echo "✗ User 1: Bytes = $USER1_BYTES (expected: 3072)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER1_RATE_LIMIT" = "1.0" ] || [ "$USER1_RATE_LIMIT" = "1" ]; then
    echo "✓ User 1: Rate limit hits correctly incremented"
else
    echo "✗ User 1: Rate limit hits = $USER1_RATE_LIMIT (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

# Validate User 2
if [ "$USER2_REQUESTS_200" = "1.0" ] || [ "$USER2_REQUESTS_200" = "1" ]; then
    echo "✓ User 2: GET requests (200) correctly incremented"
else
    echo "✗ User 2: GET requests (200) = $USER2_REQUESTS_200 (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER2_REQUESTS_504" = "1.0" ] || [ "$USER2_REQUESTS_504" = "1" ]; then
    echo "✓ User 2: GET requests (504) correctly incremented"
else
    echo "✗ User 2: GET requests (504) = $USER2_REQUESTS_504 (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER2_BYTES" = "4096.0" ] || [ "$USER2_BYTES" = "4096" ]; then
    echo "✓ User 2: Bytes correctly incremented"
else
    echo "✗ User 2: Bytes = $USER2_BYTES (expected: 4096)"
    ERRORS=$((ERRORS + 1))
fi

if [ "$USER2_TIMEOUT" = "1.0" ] || [ "$USER2_TIMEOUT" = "1" ]; then
    echo "✓ User 2: Timeout events correctly incremented"
else
    echo "✗ User 2: Timeout events = $USER2_TIMEOUT (expected: 1)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "✓ All tests passed! Metrics are properly incremented per user."
    echo "=========================================="
    exit 0
else
    echo "✗ $ERRORS test(s) failed."
    echo "=========================================="
    echo ""
    echo "Full metrics for test users:"
    curl -s "$METRICS_ENDPOINT" | grep -E "user_ip=\"(192.168.1.100|192.168.1.200)\"" | head -20
    exit 1
fi

