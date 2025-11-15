#!/bin/bash
# Test that rate limiting metrics are incremented when rate limits are triggered

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

USER_STATS_EXPORTER="${USER_STATS_EXPORTER:-localhost:9114}"
PROMETHEUS="${PROMETHEUS:-localhost:9090}"
NGINX_HOST="${NGINX_HOST:-localhost}"

echo -e "${BLUE}=== Testing Rate Limit Metrics Increment ===${NC}\n"

# Function to get metric value from Prometheus
get_prometheus_metric() {
    local query=$1
    local result=$(curl -s "http://${PROMETHEUS}/api/v1/query?query=${query}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('data', {}).get('result', [])
    if results:
        # Sum all values
        total = sum(float(r.get('value', [None, '0'])[1]) for r in results if r.get('value'))
        print(int(total))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)
    echo $result
}

# Function to get metric value from exporter
get_exporter_metric() {
    local metric_name=$1
    local result=$(curl -s "http://${USER_STATS_EXPORTER}/metrics" | grep "^${metric_name}" | grep -v "^#" | python3 -c "
import sys
total = 0
for line in sys.stdin:
    line = line.strip()
    if line and not line.startswith('#'):
        parts = line.split()
        if len(parts) >= 2:
            try:
                total += float(parts[-1])
            except:
                pass
print(int(total))
" 2>/dev/null)
    echo ${result:-0}
}

echo -e "${YELLOW}Step 1: Getting baseline metrics${NC}"

# Get baseline metrics
baseline_total=$(get_prometheus_metric "nginx_rate_limit_hits_total")
baseline_global=$(get_prometheus_metric "nginx_rate_limit_hits_global_total")
baseline_exporter=$(get_exporter_metric "nginx_rate_limit_hits_total")

echo "Baseline - nginx_rate_limit_hits_total (Prometheus): ${baseline_total}"
echo "Baseline - nginx_rate_limit_hits_global_total (Prometheus): ${baseline_global}"
echo "Baseline - nginx_rate_limit_hits_total (Exporter): ${baseline_exporter}"

echo -e "\n${YELLOW}Step 2: Triggering rate limits on /server2 (limit: 5 req/s, burst: 10)${NC}"
echo "Making 25 rapid requests..."

rate_limit_count=0
for i in {1..25}; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${NGINX_HOST}/server2/")
    if [ "$http_code" = "429" ]; then
        rate_limit_count=$((rate_limit_count + 1))
        echo -n "${RED}429${NC} "
    else
        echo -n "${GREEN}${http_code}${NC} "
    fi
    sleep 0.02
done
echo ""
echo "Observed rate limit hits: ${rate_limit_count}"

echo -e "\n${YELLOW}Step 3: Waiting for metrics to be processed${NC}"
echo "Waiting 10 seconds for log processing..."
sleep 10

echo -e "\n${YELLOW}Step 4: Checking metrics after rate limit trigger${NC}"

# Get metrics after trigger
after_total=$(get_prometheus_metric "nginx_rate_limit_hits_total")
after_global=$(get_prometheus_metric "nginx_rate_limit_hits_global_total")
after_exporter=$(get_exporter_metric "nginx_rate_limit_hits_total")

echo "After - nginx_rate_limit_hits_total (Prometheus): ${after_total}"
echo "After - nginx_rate_limit_hits_global_total (Prometheus): ${after_global}"
echo "After - nginx_rate_limit_hits_total (Exporter): ${after_exporter}"

# Calculate increments
increment_total=$((after_total - baseline_total))
increment_global=$((after_global - baseline_global))
increment_exporter=$((after_exporter - baseline_exporter))

echo -e "\n${YELLOW}Step 5: Verifying metrics incremented${NC}"

success=true

if [ "$increment_total" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} nginx_rate_limit_hits_total incremented by ${increment_total}"
else
    echo -e "${RED}✗${NC} nginx_rate_limit_hits_total did not increment (still ${after_total})"
    success=false
fi

if [ "$increment_global" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} nginx_rate_limit_hits_global_total incremented by ${increment_global}"
else
    echo -e "${RED}✗${NC} nginx_rate_limit_hits_global_total did not increment (still ${after_global})"
    success=false
fi

if [ "$increment_exporter" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Exporter metric incremented by ${increment_exporter}"
else
    echo -e "${RED}✗${NC} Exporter metric did not increment (still ${after_exporter})"
    success=false
fi

# Show raw metrics for debugging
echo -e "\n${YELLOW}Step 6: Raw metrics output${NC}"
echo -e "\n${BLUE}From Exporter:${NC}"
curl -s "http://${USER_STATS_EXPORTER}/metrics" | grep -E "^nginx_rate_limit_hits" | head -10

echo -e "\n${BLUE}From Prometheus (nginx_rate_limit_hits_total):${NC}"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_total" | python3 -m json.tool 2>/dev/null | head -30

echo -e "\n${BLUE}From Prometheus (nginx_rate_limit_hits_global_total):${NC}"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_global_total" | python3 -m json.tool 2>/dev/null | head -30

# Check if logs are being processed
echo -e "\n${YELLOW}Step 7: Checking if logs contain 429 responses${NC}"
recent_429=$(docker-compose logs --tail=50 nginx-proxy 2>/dev/null | grep -c " 429 " || echo "0")
echo "Recent 429 responses in nginx logs: ${recent_429}"

if [ "$recent_429" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} 429 responses are being logged"
    echo "Sample log entry:"
    docker-compose logs --tail=50 nginx-proxy 2>/dev/null | grep " 429 " | tail -1
else
    echo -e "${RED}✗${NC} No 429 responses found in recent logs"
fi

# Final result
echo -e "\n${YELLOW}=== Test Result ===${NC}"
if [ "$success" = true ]; then
    echo -e "${GREEN}SUCCESS: Rate limit metrics are being incremented!${NC}"
    exit 0
else
    echo -e "${RED}FAILED: Rate limit metrics are not being incremented${NC}"
    echo ""
    echo "Possible issues:"
    echo "1. Exporter may not be reading logs from the named pipe"
    echo "2. Log processing may have delays"
    echo "3. Check exporter logs: docker-compose logs user-stats-exporter"
    exit 1
fi

