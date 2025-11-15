#!/bin/bash
# Simple script to check per-user metrics using curl

METRICS_ENDPOINT="${1:-http://localhost:9114/metrics}"

echo "=========================================="
echo "Checking Per-User Metrics with Curl"
echo "=========================================="
echo "Endpoint: $METRICS_ENDPOINT"
echo ""

# Check if endpoint is accessible
if ! curl -s -f "$METRICS_ENDPOINT" > /dev/null 2>&1; then
    echo "✗ Error: Cannot access metrics endpoint"
    echo "  Please ensure user-stats-exporter is running"
    exit 1
fi

echo "✓ Metrics endpoint is accessible"
echo ""

# Get all per-user metrics
echo "All per-user request metrics:"
echo "----------------------------"
curl -s "$METRICS_ENDPOINT" | grep "^nginx_user_requests_total" | head -20
echo ""

# Get per-user bytes
echo "Per-user bytes transferred:"
echo "---------------------------"
curl -s "$METRICS_ENDPOINT" | grep "^nginx_user_bytes_total" | head -10
echo ""

# Get rate limit hits
echo "Per-user rate limit hits:"
echo "-------------------------"
curl -s "$METRICS_ENDPOINT" | grep "^nginx_rate_limit_hits_total" | head -10
echo ""

# Get timeout events
echo "Per-user timeout events:"
echo "------------------------"
curl -s "$METRICS_ENDPOINT" | grep "^nginx_timeout_events_total" | head -10
echo ""

# Query specific user (example)
echo "Example: Metrics for user 10.0.34.5:"
echo "-------------------------------------"
curl -s "$METRICS_ENDPOINT" | grep 'user_ip="10.0.34.5"' | grep -E "^(nginx_user_|nginx_rate_limit_|nginx_timeout_)" | head -10
echo ""

# Summary
echo "Summary:"
echo "--------"
TOTAL_USERS=$(curl -s "$METRICS_ENDPOINT" | grep "^nginx_user_requests_total" | grep -o 'user_ip="[^"]*"' | sort -u | wc -l)
TOTAL_REQUESTS=$(curl -s "$METRICS_ENDPOINT" | grep "^nginx_user_requests_total" | awk '{sum+=$2} END {print sum}')
echo "Total unique users: $TOTAL_USERS"
echo "Total requests tracked: $TOTAL_REQUESTS"
echo ""

echo "To query a specific user, use:"
echo "  curl -s $METRICS_ENDPOINT | grep 'user_ip=\"<IP_ADDRESS>\"'"
echo ""
echo "To query a specific metric, use:"
echo "  curl -s $METRICS_ENDPOINT | grep '^nginx_user_requests_total'"
echo "  curl -s $METRICS_ENDPOINT | grep '^nginx_user_bytes_total'"
echo "  curl -s $METRICS_ENDPOINT | grep '^nginx_rate_limit_hits_total'"
echo "  curl -s $METRICS_ENDPOINT | grep '^nginx_timeout_events_total'"

