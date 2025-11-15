# Testing Per-User Metrics

This document explains how to test that per-user metrics are properly incremented.

## Quick Test with Curl

### 1. Check if metrics endpoint is accessible

```bash
curl http://localhost:9114/metrics
```

### 2. View all per-user metrics

```bash
# All per-user request metrics
curl -s http://localhost:9114/metrics | grep "^nginx_user_requests_total"

# Per-user bytes transferred
curl -s http://localhost:9114/metrics | grep "^nginx_user_bytes_total"

# Per-user rate limit hits
curl -s http://localhost:9114/metrics | grep "^nginx_rate_limit_hits_total"

# Per-user timeout events
curl -s http://localhost:9114/metrics | grep "^nginx_timeout_events_total"
```

### 3. Query metrics for a specific user

```bash
# Replace <IP_ADDRESS> with the user's IP
curl -s http://localhost:9114/metrics | grep 'user_ip="<IP_ADDRESS>"'
```

Example:
```bash
curl -s http://localhost:9114/metrics | grep 'user_ip="10.0.34.5"'
```

### 4. Use the provided test scripts

```bash
# Simple check script
./check_metrics_curl.sh

# Comprehensive integration test (requires sending log lines)
./test_metrics_integration.sh

# Python-based test script
python3 test_metrics_with_curl.py
```

## Test Scripts

### `check_metrics_curl.sh`
Simple script to check current metrics status using curl.

**Usage:**
```bash
./check_metrics_curl.sh [METRICS_ENDPOINT]
```

**Example:**
```bash
./check_metrics_curl.sh http://localhost:9114/metrics
```

### `test_metrics_integration.sh`
Comprehensive integration test that:
1. Sends test log lines for multiple users
2. Waits for metrics to be processed
3. Verifies metrics are incremented correctly per user

**Usage:**
```bash
./test_metrics_integration.sh
```

**Note:** This script attempts to send log lines to the exporter. If running in Docker, it will try to use `docker exec`. Otherwise, it will provide instructions for manual testing.

### `test_metrics_with_curl.py`
Python-based test script that provides detailed metrics analysis.

**Usage:**
```bash
python3 test_metrics_with_curl.py [--endpoint URL]
```

**Example:**
```bash
python3 test_metrics_with_curl.py --endpoint http://localhost:9114/metrics
```

## Unit Tests

Run the unit tests to verify metrics incrementation logic:

```bash
cd monitoring/user-stats-exporter
python3 -m pytest test_user_metrics.py -v
```

## Manual Testing

### 1. Send test log lines

If the exporter is running and reading from stdin or a log file, you can send test log lines:

**Example log line format:**
```
192.168.1.100 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"
```

**If using Docker:**
```bash
# Method 1: Write to log file (if mounted)
docker exec user-stats-exporter sh -c 'echo "<log_line>" >> /var/log/nginx/access.log'

# Method 2: Send via stdin (if exporter accepts it)
echo "<log_line>" | docker exec -i user-stats-exporter python3 -c "import sys; import user_stats_exporter; user_stats_exporter.process_log_line(sys.stdin.readline().strip())"
```

### 2. Verify metrics incremented

After sending log lines, wait a few seconds and check the metrics:

```bash
# Check specific user
curl -s http://localhost:9114/metrics | grep 'user_ip="192.168.1.100"'

# Check specific metric
curl -s http://localhost:9114/metrics | grep 'nginx_user_requests_total.*user_ip="192.168.1.100"'
```

## Expected Metrics

The following metrics should be available and properly incremented per user:

1. **`nginx_user_requests_total`** - Total requests per user
   - Labels: `user_ip`, `status`, `method`, `route`
   - Example: `nginx_user_requests_total{user_ip="192.168.1.100",status="200",method="GET",route="/server1"} 2.0`

2. **`nginx_user_bytes_total`** - Total bytes transferred per user
   - Labels: `user_ip`, `direction`
   - Example: `nginx_user_bytes_total{user_ip="192.168.1.100",direction="sent"} 3072.0`

3. **`nginx_rate_limit_hits_total`** - Rate limit hits per user
   - Labels: `user_ip`, `route`, `http_method`
   - Example: `nginx_rate_limit_hits_total{user_ip="192.168.1.100",route="/server1",http_method="POST"} 1.0`

4. **`nginx_timeout_events_total`** - Timeout events per user
   - Labels: `user_ip`, `route`, `timeout_type`, `http_method`
   - Example: `nginx_timeout_events_total{user_ip="192.168.1.200",route="/server2",timeout_type="gateway_timeout",http_method="GET"} 1.0`

## Verification Checklist

- [ ] Metrics endpoint is accessible
- [ ] Different users have separate metrics
- [ ] Request counts increment correctly per user
- [ ] Bytes transferred increment correctly per user
- [ ] Rate limit hits are tracked per user
- [ ] Timeout events are tracked per user
- [ ] Metrics persist across multiple requests
- [ ] Metrics are isolated between users (no cross-contamination)

## Troubleshooting

### Metrics endpoint not accessible
- Check if the service is running: `docker ps | grep user-stats-exporter`
- Check service logs: `docker logs user-stats-exporter`
- Verify port is exposed: `docker-compose ps`

### Metrics not incrementing
- Verify log lines are being sent to the exporter
- Check exporter logs for parsing errors
- Ensure log format matches expected format
- Wait a few seconds for metrics to be processed

### Metrics showing wrong values
- Check if metrics were reset (exporter restart resets in-memory metrics)
- Verify log lines are being parsed correctly
- Check for duplicate log lines being processed

