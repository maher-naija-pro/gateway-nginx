#!/bin/bash
# Test script for per-user metrics collection

set -e

echo "=========================================="
echo "Testing Per-User Metrics Collection"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

echo -e "${GREEN}✓ Services are running${NC}"
echo ""

# Function to make requests from a specific container (simulating different users)
make_requests() {
    local container=$1
    local user_label=$2
    local route=$3
    local count=${4:-5}
    
    echo -e "${YELLOW}Generating $count requests from $user_label to $route...${NC}"
    
    for i in $(seq 1 $count); do
        docker exec $container curl -s -o /dev/null -w "%{http_code}" \
            http://nginx-proxy:80$route > /dev/null 2>&1 || true
        sleep 0.2
    done
    
    echo -e "${GREEN}✓ Generated $count requests from $user_label${NC}"
}

# Generate test traffic from different "users" (containers)
echo -e "${YELLOW}Step 1: Generating test traffic...${NC}"
echo ""

# Use prometheus container to make requests (simulates user 1)
if docker ps | grep -q prometheus; then
    make_requests prometheus "User 1 (Prometheus)" "/server1" 10
    make_requests prometheus "User 1 (Prometheus)" "/server2" 5
    make_requests prometheus "User 1 (Prometheus)" "/" 3
fi

# Use grafana container to make requests (simulates user 2)
if docker ps | grep -q grafana; then
    make_requests grafana "User 2 (Grafana)" "/server1" 8
    make_requests grafana "User 2 (Grafana)" "/" 2
fi

# Use tempo container to make requests (simulates user 3)
if docker ps | grep -q tempo; then
    make_requests tempo "User 3 (Tempo)" "/server2" 7
    make_requests tempo "User 3 (Tempo)" "/server1" 4
fi

echo ""
echo -e "${GREEN}✓ Test traffic generated${NC}"
echo ""

# Wait for metrics to be processed
echo -e "${YELLOW}Step 2: Waiting for metrics to be processed (10 seconds)...${NC}"
sleep 10
echo ""

# Check OTel Collector metrics endpoint
echo -e "${YELLOW}Step 3: Checking OTel Collector metrics endpoint...${NC}"
OTEL_METRICS=$(docker exec otel-collector curl -s http://localhost:8889/metrics 2>/dev/null || echo "")

if [ -z "$OTEL_METRICS" ]; then
    echo -e "${RED}✗ Could not fetch metrics from OTel Collector${NC}"
    echo "Checking collector logs..."
    docker logs otel-collector --tail 20
else
    echo -e "${GREEN}✓ Successfully fetched metrics from OTel Collector${NC}"
    
    # Check for per-user metrics
    if echo "$OTEL_METRICS" | grep -q "nginx_user_requests_total"; then
        echo -e "${GREEN}✓ Found nginx_user_requests_total metric${NC}"
        echo ""
        echo "Per-user metrics found:"
        echo "$OTEL_METRICS" | grep "nginx_user_requests_total" | head -20
    else
        echo -e "${YELLOW}⚠ nginx_user_requests_total metric not found yet${NC}"
        echo "This might be normal if metrics are still being processed"
    fi
fi

echo ""

# Check Prometheus targets
echo -e "${YELLOW}Step 4: Checking Prometheus targets...${NC}"
PROM_TARGETS=$(docker exec prometheus curl -s http://localhost:9090/api/v1/targets 2>/dev/null || echo "")

if echo "$PROM_TARGETS" | grep -q "otel-collector-user-stats"; then
    echo -e "${GREEN}✓ Prometheus target 'otel-collector-user-stats' is configured${NC}"
else
    echo -e "${YELLOW}⚠ Prometheus target might not be configured yet${NC}"
fi

echo ""

# Query Prometheus for per-user metrics
echo -e "${YELLOW}Step 5: Querying Prometheus for per-user metrics...${NC}"
sleep 5

# Query total requests per user
QUERY="sum(nginx_user_requests_total) by (user_ip)"
echo "Query: $QUERY"
PROM_QUERY=$(docker exec prometheus curl -s -G \
    --data-urlencode "query=$QUERY" \
    "http://localhost:9090/api/v1/query" 2>/dev/null || echo "")

if [ ! -z "$PROM_QUERY" ] && echo "$PROM_QUERY" | grep -q "result"; then
    echo -e "${GREEN}✓ Successfully queried Prometheus${NC}"
    echo ""
    echo "Results:"
    echo "$PROM_QUERY" | python3 -m json.tool 2>/dev/null || echo "$PROM_QUERY"
else
    echo -e "${YELLOW}⚠ Could not query Prometheus or no data yet${NC}"
    echo "Response: $PROM_QUERY"
fi

echo ""

# Check nginx logs
echo -e "${YELLOW}Step 6: Checking nginx access logs...${NC}"
LOG_COUNT=$(docker exec nginx-proxy sh -c "wc -l < /var/log/nginx/access.log" 2>/dev/null || echo "0")
echo "Total log entries: $LOG_COUNT"

if [ "$LOG_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Nginx is logging requests${NC}"
    echo ""
    echo "Recent log entries (last 5):"
    docker exec nginx-proxy tail -5 /var/log/nginx/access.log 2>/dev/null || echo "Could not read logs"
else
    echo -e "${YELLOW}⚠ No log entries found${NC}"
fi

echo ""

# Check OTel Collector logs
echo -e "${YELLOW}Step 7: Checking OTel Collector logs...${NC}"
echo "Recent collector logs (last 10 lines):"
docker logs otel-collector --tail 10 2>&1 | tail -10

echo ""
echo "=========================================="
echo -e "${GREEN}Test completed!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Check Prometheus UI: http://localhost:9090"
echo "2. Query: sum(nginx_user_requests_total) by (user_ip)"
echo "3. Check Grafana: http://localhost:3000"
echo "4. View OTel Collector metrics: http://localhost:8889/metrics"

