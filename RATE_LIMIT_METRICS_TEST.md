# Rate Limit Metrics Testing Guide

This guide explains how to test and query rate limit metrics using curl and Prometheus.

## Quick Start

### 1. Quick Query (No Rate Limit Triggering)
```bash
./curl-rate-limit-metrics.sh
```

This script shows all available curl commands and executes them to display current rate limit metrics.

### 2. Full Test (Triggers Rate Limits)
```bash
./test-rate-limit-metrics.sh
```

This script:
- Triggers rate limits by making rapid requests to different routes
- Queries metrics before and after triggering rate limits
- Shows metrics from both User Stats Exporter and Prometheus

## Manual Curl Commands

### Query User Stats Exporter Directly
```bash
# Get all rate limit metrics
curl http://localhost:9114/metrics | grep rate_limit

# Get all metrics
curl http://localhost:9114/metrics
```

### Query Prometheus API

#### Rate Limit Hits Per User
```bash
curl 'http://localhost:9090/api/v1/query?query=nginx_rate_limit_hits_total'
```

#### Global Rate Limit Hits
```bash
curl 'http://localhost:9090/api/v1/query?query=nginx_rate_limit_hits_global_total'
```

#### Rate Limit Hits by Route
```bash
curl 'http://localhost:9090/api/v1/query?query=sum(nginx_rate_limit_hits_global_total)%20by%20(route)'
```

#### Rate Limit Hit Rate (per minute)
```bash
curl 'http://localhost:9090/api/v1/query?query=rate(nginx_rate_limit_hits_global_total[1m])'
```

#### Rate Limit Hits Per User IP
```bash
curl 'http://localhost:9090/api/v1/query?query=sum(nginx_rate_limit_hits_total)%20by%20(user_ip)'
```

#### Rate Limit Hits by Route and Method
```bash
curl 'http://localhost:9090/api/v1/query?query=sum(nginx_rate_limit_hits_global_total)%20by%20(route,http_method)'
```

## Rate Limit Configuration

Current rate limits configured in nginx:

- **`/server1`**: 10 requests/second per IP, burst of 20
- **`/server2`**: 5 requests/second per IP, burst of 10
- **`/`** (root): 2 requests/second per IP, burst of 5

## Available Metrics

### Per-User Metrics
- `nginx_rate_limit_hits_total` - Rate limit hits per user
  - Labels: `user_ip`, `route`, `http_method`

### Global Metrics
- `nginx_rate_limit_hits_global_total` - Global rate limit hits (aggregated)
  - Labels: `route`, `http_method`

## Testing Rate Limits

To manually trigger rate limits:

```bash
# Trigger rate limit on /server1 (30 rapid requests)
for i in {1..30}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost/server1/; sleep 0.05; done

# Trigger rate limit on /server2 (20 rapid requests)
for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost/server2/; sleep 0.05; done

# Trigger rate limit on / (15 rapid requests)
for i in {1..15}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost/; sleep 0.05; done
```

## Prometheus UI

Access Prometheus UI at: http://localhost:9090

Useful PromQL queries in the UI:

```promql
# Total rate limit hits
nginx_rate_limit_hits_total

# Global rate limit hits
nginx_rate_limit_hits_global_total

# Rate limit hits by route
sum(nginx_rate_limit_hits_global_total) by (route)

# Rate limit hit rate
rate(nginx_rate_limit_hits_global_total[1m])

# Rate limit hits per user
sum(nginx_rate_limit_hits_total) by (user_ip)

# Top 10 users by rate limit hits
topk(10, sum(nginx_rate_limit_hits_total) by (user_ip))
```

## Troubleshooting

### No metrics appearing?
1. Check if services are running: `docker-compose ps`
2. Check if rate limits are being triggered (look for 429 status codes)
3. Wait a few seconds for metrics to be processed
4. Check User Stats Exporter logs: `docker-compose logs user-stats-exporter`

### Metrics not updating?
- Metrics are updated when nginx logs are processed
- There may be a delay of a few seconds
- Check that nginx is logging to the correct location

### Prometheus not scraping?
- Check Prometheus targets: http://localhost:9090/targets
- Verify user-stats-exporter is in the targets list
- Check Prometheus logs: `docker-compose logs prometheus`

