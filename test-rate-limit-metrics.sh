#!/bin/bash
# Test script for rate limit metrics in Prometheus
# This script triggers rate limits and queries metrics using curl

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NGINX_HOST="${NGINX_HOST:-localhost}"
NGINX_PORT="${NGINX_PORT:-80}"
USER_STATS_EXPORTER="${USER_STATS_EXPORTER:-localhost:9114}"
PROMETHEUS="${PROMETHEUS:-localhost:9090}"

echo -e "${BLUE}=== Rate Limit Metrics Test ===${NC}\n"

# Function to print section headers
print_section() {
    echo -e "\n${YELLOW}--- $1 ---${NC}"
}

# Function to check if service is available
check_service() {
    local service=$1
    local url=$2
    if curl -s -f "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $service is available"
        return 0
    else
        echo -e "${RED}✗${NC} $service is not available at $url"
        return 1
    fi
}

# Check services availability
print_section "Checking Services"
check_service "Nginx" "http://${NGINX_HOST}:${NGINX_PORT}/" || exit 1
check_service "User Stats Exporter" "http://${USER_STATS_EXPORTER}/metrics" || exit 1
check_service "Prometheus" "http://${PROMETHEUS}/api/v1/query?query=up" || exit 1

# Get initial metrics
print_section "Initial Rate Limit Metrics (Before Test)"

echo -e "\n${BLUE}From User Stats Exporter:${NC}"
echo "Querying: http://${USER_STATS_EXPORTER}/metrics"
curl -s "http://${USER_STATS_EXPORTER}/metrics" | grep -E "nginx_rate_limit_hits" || echo "No rate limit hits yet"

echo -e "\n${BLUE}From Prometheus (nginx_rate_limit_hits_total):${NC}"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_total" | python3 -m json.tool 2>/dev/null || curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_total"

echo -e "\n${BLUE}From Prometheus (nginx_rate_limit_hits_global_total):${NC}"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_global_total" | python3 -m json.tool 2>/dev/null || curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_global_total"

# Trigger rate limits
print_section "Triggering Rate Limits"

echo -e "\n${BLUE}Testing /server1 (limit: 10 req/s, burst: 20)${NC}"
echo "Making 30 rapid requests to trigger rate limiting..."
RATE_LIMIT_COUNT=0
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${NGINX_HOST}:${NGINX_PORT}/server1/")
    if [ "$HTTP_CODE" = "429" ]; then
        RATE_LIMIT_COUNT=$((RATE_LIMIT_COUNT + 1))
        echo -n "${RED}429${NC} "
    else
        echo -n "${GREEN}${HTTP_CODE}${NC} "
    fi
    sleep 0.05  # Small delay to avoid overwhelming
done
echo -e "\nRate limit hits: ${RATE_LIMIT_COUNT}/30"

echo -e "\n${BLUE}Testing /server2 (limit: 5 req/s, burst: 10)${NC}"
echo "Making 20 rapid requests to trigger rate limiting..."
RATE_LIMIT_COUNT=0
for i in {1..20}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${NGINX_HOST}:${NGINX_PORT}/server2/")
    if [ "$HTTP_CODE" = "429" ]; then
        RATE_LIMIT_COUNT=$((RATE_LIMIT_COUNT + 1))
        echo -n "${RED}429${NC} "
    else
        echo -n "${GREEN}${HTTP_CODE}${NC} "
    fi
    sleep 0.05
done
echo -e "\nRate limit hits: ${RATE_LIMIT_COUNT}/20"

echo -e "\n${BLUE}Testing / (limit: 2 req/s, burst: 5)${NC}"
echo "Making 15 rapid requests to trigger rate limiting..."
RATE_LIMIT_COUNT=0
for i in {1..15}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${NGINX_HOST}:${NGINX_PORT}/")
    if [ "$HTTP_CODE" = "429" ]; then
        RATE_LIMIT_COUNT=$((RATE_LIMIT_COUNT + 1))
        echo -n "${RED}429${NC} "
    else
        echo -n "${GREEN}${HTTP_CODE}${NC} "
    fi
    sleep 0.05
done
echo -e "\nRate limit hits: ${RATE_LIMIT_COUNT}/15"

# Wait a moment for metrics to be processed
print_section "Waiting for Metrics Processing"
echo "Waiting 5 seconds for metrics to be processed..."
sleep 5

# Get metrics after test
print_section "Rate Limit Metrics (After Test)"

echo -e "\n${BLUE}From User Stats Exporter (nginx_rate_limit_hits_total):${NC}"
curl -s "http://${USER_STATS_EXPORTER}/metrics" | grep -A 5 "nginx_rate_limit_hits_total" || echo "No rate limit metrics found"

echo -e "\n${BLUE}From User Stats Exporter (nginx_rate_limit_hits_global_total):${NC}"
curl -s "http://${USER_STATS_EXPORTER}/metrics" | grep -A 5 "nginx_rate_limit_hits_global_total" || echo "No global rate limit metrics found"

echo -e "\n${BLUE}From Prometheus - Rate Limit Hits Per User:${NC}"
echo "Query: nginx_rate_limit_hits_total"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_total" | python3 -m json.tool 2>/dev/null || curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_total"

echo -e "\n${BLUE}From Prometheus - Global Rate Limit Hits:${NC}"
echo "Query: nginx_rate_limit_hits_global_total"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_global_total" | python3 -m json.tool 2>/dev/null || curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_global_total"

echo -e "\n${BLUE}From Prometheus - Rate Limit Hits by Route:${NC}"
echo "Query: sum(nginx_rate_limit_hits_global_total) by (route)"
curl -s "http://${PROMETHEUS}/api/v1/query?query=sum(nginx_rate_limit_hits_global_total)%20by%20(route)" | python3 -m json.tool 2>/dev/null || curl -s "http://${PROMETHEUS}/api/v1/query?query=sum(nginx_rate_limit_hits_global_total)%20by%20(route)"

echo -e "\n${BLUE}From Prometheus - Rate Limit Hit Rate (per minute):${NC}"
echo "Query: rate(nginx_rate_limit_hits_global_total[1m])"
curl -s "http://${PROMETHEUS}/api/v1/query?query=rate(nginx_rate_limit_hits_global_total[1m])" | python3 -m json.tool 2>/dev/null || curl -s "http://${PROMETHEUS}/api/v1/query?query=rate(nginx_rate_limit_hits_global_total[1m])"

# Summary
print_section "Summary"
echo -e "${GREEN}Test completed!${NC}"
echo ""
echo "You can also query metrics directly:"
echo "  - User Stats Exporter: curl http://${USER_STATS_EXPORTER}/metrics | grep rate_limit"
echo "  - Prometheus UI: http://${PROMETHEUS}"
echo ""
echo "Useful PromQL queries:"
echo "  - Total rate limit hits: nginx_rate_limit_hits_total"
echo "  - Global rate limit hits: nginx_rate_limit_hits_global_total"
echo "  - Rate limit hits by route: sum(nginx_rate_limit_hits_global_total) by (route)"
echo "  - Rate limit hit rate: rate(nginx_rate_limit_hits_global_total[1m])"
echo "  - Rate limit hits per user: sum(nginx_rate_limit_hits_total) by (user_ip)"

