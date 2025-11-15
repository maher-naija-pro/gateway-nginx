#!/bin/bash
# Test script for rate limiting and timeout metrics (global and per-user)

set -e

echo "=========================================="
echo "Testing Rate Limiting & Timeout Metrics"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if services are running
echo -e "${YELLOW}Checking if services are running...${NC}"
if ! docker ps | grep -q nginx-proxy; then
    echo -e "${RED}Error: nginx-proxy container is not running${NC}"
    echo "Please start services with: docker-compose up -d"
    exit 1
fi

if ! docker ps | grep -q otel-collector; then
    echo -e "${RED}Error: otel-collector container is not running${NC}"
    echo "Please start services with: docker-compose up -d"
    exit 1
fi

if ! docker ps | grep -q prometheus; then
    echo -e "${RED}Error: prometheus container is not running${NC}"
    echo "Please start services with: docker-compose up -d"
    exit 1
fi

echo -e "${GREEN}✓ Services are running${NC}"
echo ""

# Function to make requests from a specific container (simulating different users)
make_requests() {
    local container=$1
    local user_label=$2
    local route=$3
    local count=${4:-5}
    local delay=${5:-0.1}
    
    echo -e "${YELLOW}Generating $count requests from $user_label to $route (delay: ${delay}s)...${NC}"
    
    local success=0
    local rate_limited=0
    
    for i in $(seq 1 $count); do
        status_code=$(docker exec $container curl -s -o /dev/null -w "%{http_code}" \
            http://nginx-proxy:80$route 2>/dev/null || echo "000")
        
        if [ "$status_code" = "200" ] || [ "$status_code" = "404" ]; then
            success=$((success + 1))
        elif [ "$status_code" = "429" ]; then
            rate_limited=$((rate_limited + 1))
            echo -e "  ${RED}Request $i: Rate limited (429)${NC}"
        else
            echo -e "  ${YELLOW}Request $i: Status $status_code${NC}"
        fi
        
        sleep $delay
    done
    
    echo -e "${GREEN}✓ Generated $count requests: $success successful, $rate_limited rate limited${NC}"
    echo ""
}

# Function to trigger rate limiting by making rapid requests
trigger_rate_limiting() {
    local container=$1
    local user_label=$2
    local route=$3
    local rate_limit=${4:-10}  # Default rate limit per second
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Triggering Rate Limiting${NC}"
    echo -e "${BLUE}Route: $route${NC}"
    echo -e "${BLUE}User: $user_label${NC}"
    echo -e "${BLUE}Expected rate limit: ~${rate_limit} req/s${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Make requests faster than the rate limit to trigger 429 errors
    # Make 30 requests with minimal delay to exceed rate limit
    make_requests "$container" "$user_label" "$route" 30 0.05
}

# Step 1: Generate normal traffic first
echo -e "${YELLOW}Step 1: Generating normal traffic...${NC}"
echo ""

# Use prometheus container to make requests (simulates user 1)
if docker ps | grep -q prometheus; then
    make_requests prometheus "User 1 (Prometheus)" "/server1" 5 0.2
    make_requests prometheus "User 1 (Prometheus)" "/server2" 3 0.2
fi

# Use grafana container to make requests (simulates user 2)
if docker ps | grep -q grafana; then
    make_requests grafana "User 2 (Grafana)" "/server1" 3 0.2
fi

echo -e "${GREEN}✓ Normal traffic generated${NC}"
echo ""

# Step 2: Trigger rate limiting for different routes and users
echo -e "${YELLOW}Step 2: Triggering rate limiting...${NC}"
echo ""

# Trigger rate limiting on /server1 (10 req/s limit) from User 1
if docker ps | grep -q prometheus; then
    trigger_rate_limiting prometheus "User 1 (Prometheus)" "/server1" 10
fi

# Trigger rate limiting on /server2 (5 req/s limit) from User 2
if docker ps | grep -q grafana; then
    trigger_rate_limiting grafana "User 2 (Grafana)" "/server2" 5
fi

# Trigger rate limiting on root (2 req/s limit) from User 3
if docker ps | grep -q tempo; then
    trigger_rate_limiting tempo "User 3 (Tempo)" "/" 2
fi

echo -e "${GREEN}✓ Rate limiting tests completed${NC}"
echo ""

# Step 3: Wait for metrics to be processed
echo -e "${YELLOW}Step 3: Waiting for metrics to be processed (15 seconds)...${NC}"
sleep 15
echo ""

# Step 4: Check OTel Collector metrics endpoint
echo -e "${YELLOW}Step 4: Checking OTel Collector metrics endpoint...${NC}"
OTEL_METRICS=$(docker exec otel-collector curl -s http://localhost:8889/metrics 2>/dev/null || echo "")

if [ -z "$OTEL_METRICS" ]; then
    echo -e "${RED}✗ Could not fetch metrics from OTel Collector${NC}"
    echo "Checking collector logs..."
    docker logs otel-collector --tail 30
else
    echo -e "${GREEN}✓ Successfully fetched metrics from OTel Collector${NC}"
    echo ""
    
    # Check for per-user rate limit metrics
    echo -e "${BLUE}Per-user rate limit metrics:${NC}"
    if echo "$OTEL_METRICS" | grep -q "nginx_rate_limit_hits_total"; then
        echo -e "${GREEN}✓ Found nginx_rate_limit_hits_total metric${NC}"
        echo "$OTEL_METRICS" | grep "nginx_rate_limit_hits_total" | head -10
    else
        echo -e "${YELLOW}⚠ nginx_rate_limit_hits_total metric not found yet${NC}"
    fi
    echo ""
    
    # Check for global rate limit metrics
    echo -e "${BLUE}Global rate limit metrics:${NC}"
    if echo "$OTEL_METRICS" | grep -q "nginx_rate_limit_hits_global_total"; then
        echo -e "${GREEN}✓ Found nginx_rate_limit_hits_global_total metric${NC}"
        echo "$OTEL_METRICS" | grep "nginx_rate_limit_hits_global_total" | head -10
    else
        echo -e "${YELLOW}⚠ nginx_rate_limit_hits_global_total metric not found yet${NC}"
    fi
    echo ""
    
    # Check for per-user timeout metrics
    echo -e "${BLUE}Per-user timeout metrics:${NC}"
    if echo "$OTEL_METRICS" | grep -q "nginx_timeout_events_total"; then
        echo -e "${GREEN}✓ Found nginx_timeout_events_total metric${NC}"
        echo "$OTEL_METRICS" | grep "nginx_timeout_events_total" | head -10
    else
        echo -e "${YELLOW}⚠ nginx_timeout_events_total metric not found (this is normal if no timeouts occurred)${NC}"
    fi
    echo ""
    
    # Check for global timeout metrics
    echo -e "${BLUE}Global timeout metrics:${NC}"
    if echo "$OTEL_METRICS" | grep -q "nginx_timeout_events_global_total"; then
        echo -e "${GREEN}✓ Found nginx_timeout_events_global_total metric${NC}"
        echo "$OTEL_METRICS" | grep "nginx_timeout_events_global_total" | head -10
    else
        echo -e "${YELLOW}⚠ nginx_timeout_events_global_total metric not found (this is normal if no timeouts occurred)${NC}"
    fi
fi

echo ""

# Step 5: Query Prometheus for metrics
echo -e "${YELLOW}Step 5: Querying Prometheus for metrics...${NC}"
echo ""

# Query per-user rate limit hits
echo -e "${BLUE}Per-user rate limit hits:${NC}"
QUERY="sum(nginx_rate_limit_hits_total) by (user_ip, route, http_method)"
echo "Query: $QUERY"
PROM_QUERY=$(docker exec prometheus curl -s -G \
    --data-urlencode "query=$QUERY" \
    "http://localhost:9090/api/v1/query" 2>/dev/null || echo "")

if [ ! -z "$PROM_QUERY" ] && echo "$PROM_QUERY" | grep -q "result"; then
    echo -e "${GREEN}✓ Successfully queried Prometheus${NC}"
    echo "$PROM_QUERY" | python3 -m json.tool 2>/dev/null | grep -A 20 '"result"' || echo "$PROM_QUERY"
else
    echo -e "${YELLOW}⚠ Could not query Prometheus or no data yet${NC}"
fi
echo ""

# Query global rate limit hits
echo -e "${BLUE}Global rate limit hits:${NC}"
QUERY="sum(nginx_rate_limit_hits_global_total) by (route, http_method)"
echo "Query: $QUERY"
PROM_QUERY=$(docker exec prometheus curl -s -G \
    --data-urlencode "query=$QUERY" \
    "http://localhost:9090/api/v1/query" 2>/dev/null || echo "")

if [ ! -z "$PROM_QUERY" ] && echo "$PROM_QUERY" | grep -q "result"; then
    echo -e "${GREEN}✓ Successfully queried Prometheus${NC}"
    echo "$PROM_QUERY" | python3 -m json.tool 2>/dev/null | grep -A 20 '"result"' || echo "$PROM_QUERY"
else
    echo -e "${YELLOW}⚠ Could not query Prometheus or no data yet${NC}"
fi
echo ""

# Query per-user timeout events
echo -e "${BLUE}Per-user timeout events:${NC}"
QUERY="sum(nginx_timeout_events_total) by (user_ip, route, timeout_type)"
echo "Query: $QUERY"
PROM_QUERY=$(docker exec prometheus curl -s -G \
    --data-urlencode "query=$QUERY" \
    "http://localhost:9090/api/v1/query" 2>/dev/null || echo "")

if [ ! -z "$PROM_QUERY" ] && echo "$PROM_QUERY" | grep -q "result"; then
    echo -e "${GREEN}✓ Successfully queried Prometheus${NC}"
    echo "$PROM_QUERY" | python3 -m json.tool 2>/dev/null | grep -A 20 '"result"' || echo "$PROM_QUERY"
else
    echo -e "${YELLOW}⚠ Could not query Prometheus or no data yet (normal if no timeouts)${NC}"
fi
echo ""

# Query global timeout events
echo -e "${BLUE}Global timeout events:${NC}"
QUERY="sum(nginx_timeout_events_global_total) by (route, timeout_type)"
echo "Query: $QUERY"
PROM_QUERY=$(docker exec prometheus curl -s -G \
    --data-urlencode "query=$QUERY" \
    "http://localhost:9090/api/v1/query" 2>/dev/null || echo "")

if [ ! -z "$PROM_QUERY" ] && echo "$PROM_QUERY" | grep -q "result"; then
    echo -e "${GREEN}✓ Successfully queried Prometheus${NC}"
    echo "$PROM_QUERY" | python3 -m json.tool 2>/dev/null | grep -A 20 '"result"' || echo "$PROM_QUERY"
else
    echo -e "${YELLOW}⚠ Could not query Prometheus or no data yet (normal if no timeouts)${NC}"
fi
echo ""

# Step 6: Check nginx logs for 429 errors
echo -e "${YELLOW}Step 6: Checking nginx logs for rate limit events (429)...${NC}"
RATE_LIMIT_COUNT=$(docker exec nginx-proxy sh -c "grep -c ' 429 ' /var/log/nginx/access.log 2>/dev/null || echo 0")
echo "Total 429 (rate limit) responses in logs: $RATE_LIMIT_COUNT"

if [ "$RATE_LIMIT_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Found rate limit events in logs${NC}"
    echo ""
    echo "Sample rate limit log entries (last 5):"
    docker exec nginx-proxy sh -c "grep ' 429 ' /var/log/nginx/access.log | tail -5" 2>/dev/null || echo "Could not read logs"
else
    echo -e "${YELLOW}⚠ No rate limit events found in logs yet${NC}"
fi
echo ""

# Step 7: Check for timeout events in logs
echo -e "${YELLOW}Step 7: Checking nginx logs for timeout events (504, 408)...${NC}"
TIMEOUT_COUNT=$(docker exec nginx-proxy sh -c "grep -E ' (504|408) ' /var/log/nginx/access.log 2>/dev/null | wc -l || echo 0")
echo "Total timeout responses (504/408) in logs: $TIMEOUT_COUNT"

if [ "$TIMEOUT_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Found timeout events in logs${NC}"
    echo ""
    echo "Sample timeout log entries (last 5):"
    docker exec nginx-proxy sh -c "grep -E ' (504|408) ' /var/log/nginx/access.log | tail -5" 2>/dev/null || echo "Could not read logs"
else
    echo -e "${YELLOW}⚠ No timeout events found in logs (this is normal)${NC}"
fi
echo ""

# Step 8: Check OTel Collector logs
echo -e "${YELLOW}Step 8: Checking OTel Collector logs...${NC}"
echo "Recent collector logs (last 15 lines):"
docker logs otel-collector --tail 15 2>&1 | tail -15

echo ""
echo "=========================================="
echo -e "${GREEN}Test completed!${NC}"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Per-user metrics: nginx_rate_limit_hits_total, nginx_timeout_events_total"
echo "  - Global metrics: nginx_rate_limit_hits_global_total, nginx_timeout_events_global_total"
echo ""
echo "Next steps:"
echo "1. Check Prometheus UI: http://localhost:9090"
echo "   - Query: sum(nginx_rate_limit_hits_total) by (user_ip, route)"
echo "   - Query: sum(nginx_rate_limit_hits_global_total) by (route)"
echo "2. Check OTel Collector metrics: http://localhost:8889/metrics"
echo "3. Check Grafana: http://localhost:3000"
echo "4. View nginx logs: docker logs nginx-proxy"

