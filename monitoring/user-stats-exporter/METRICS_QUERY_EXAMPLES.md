# Nginx User Stats Exporter - Metrics Query Examples

This document provides examples for each metric exposed by the user-stats-exporter and how to query them in Prometheus.

## Table of Contents

1. [Request Metrics](#request-metrics)
2. [Bandwidth Metrics](#bandwidth-metrics)
3. [Performance Metrics](#performance-metrics)
4. [Connection Metrics](#connection-metrics)
5. [Rate Limiting Metrics](#rate-limiting-metrics)
6. [Timeout Metrics](#timeout-metrics)
7. [Common Query Patterns](#common-query-patterns)

---

## Request Metrics

### `nginx_user_requests_total`

**Type:** Counter  
**Description:** Total number of requests per user  
**Labels:** `user_ip`, `status`, `method`, `route`

#### Basic Queries

```promql
# Total requests for a specific user IP
nginx_user_requests_total{user_ip="192.168.1.100"}

# Total requests by status code for all users
sum by (status) (nginx_user_requests_total)

# Total requests by route
sum by (route) (nginx_user_requests_total)

# Total requests by HTTP method
sum by (method) (nginx_user_requests_total)

# Requests per user (top 10)
topk(10, sum by (user_ip) (nginx_user_requests_total))
```

#### Rate Queries (Requests per second)

```promql
# Request rate per user (requests per second)
rate(nginx_user_requests_total[5m])

# Request rate for a specific user
rate(nginx_user_requests_total{user_ip="192.168.1.100"}[5m])

# Request rate by status code
sum by (status) (rate(nginx_user_requests_total[5m]))

# Request rate by route
sum by (route) (rate(nginx_user_requests_total[5m]))

# Top 10 users by request rate
topk(10, sum by (user_ip) (rate(nginx_user_requests_total[5m])))
```

#### Filtered Queries

```promql
# Successful requests (2xx status codes)
sum(rate(nginx_user_requests_total{status=~"2.."}[5m]))

# Error requests (4xx and 5xx status codes)
sum(rate(nginx_user_requests_total{status=~"[45].."}[5m]))

# Requests to a specific route
nginx_user_requests_total{route="/server1"}

# GET requests only
nginx_user_requests_total{method="GET"}

# POST requests to /server2
nginx_user_requests_total{method="POST", route="/server2"}
```

---

## Bandwidth Metrics

### `nginx_user_bytes_total`

**Type:** Counter  
**Description:** Total bytes transferred per user  
**Labels:** `user_ip`, `direction` (values: `sent`)

#### Basic Queries

```promql
# Total bytes sent for all users
sum(nginx_user_bytes_total)

# Total bytes sent per user
sum by (user_ip) (nginx_user_bytes_total)

# Top 10 users by bytes transferred
topk(10, sum by (user_ip) (nginx_user_bytes_total))
```

#### Rate Queries (Bandwidth per second)

```promql
# Bytes per second per user
rate(nginx_user_bytes_total[5m])

# Total bandwidth usage (bytes per second)
sum(rate(nginx_user_bytes_total[5m]))

# Bandwidth per user (bytes per second)
sum by (user_ip) (rate(nginx_user_bytes_total[5m]))

# Top 10 users by bandwidth usage
topk(10, sum by (user_ip) (rate(nginx_user_bytes_total[5m])))

# Bandwidth in MB/s
sum(rate(nginx_user_bytes_total[5m])) / 1024 / 1024
```

#### Filtered Queries

```promql
# Bytes sent for a specific user
nginx_user_bytes_total{user_ip="192.168.1.100"}

# Bandwidth for a specific user (bytes per second)
rate(nginx_user_bytes_total{user_ip="192.168.1.100"}[5m])
```

---

## Performance Metrics

### `nginx_user_request_duration_seconds`

**Type:** Histogram  
**Description:** Request duration per user  
**Labels:** `user_ip`, `route`  
**Buckets:** 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0

#### Basic Queries

```promql
# Average request duration per user
rate(nginx_user_request_duration_seconds_sum[5m]) / rate(nginx_user_request_duration_seconds_count[5m])

# Average request duration by route
sum by (route) (rate(nginx_user_request_duration_seconds_sum[5m])) / 
sum by (route) (rate(nginx_user_request_duration_seconds_count[5m]))

# Request count per user
sum by (user_ip) (rate(nginx_user_request_duration_seconds_count[5m]))
```

#### Percentile Queries

```promql
# 50th percentile (median) request duration per user
histogram_quantile(0.50, sum by (user_ip, le) (rate(nginx_user_request_duration_seconds_bucket[5m])))

# 95th percentile request duration per user
histogram_quantile(0.95, sum by (user_ip, le) (rate(nginx_user_request_duration_seconds_bucket[5m])))

# 99th percentile request duration per user
histogram_quantile(0.99, sum by (user_ip, le) (rate(nginx_user_request_duration_seconds_bucket[5m])))

# 95th percentile by route
histogram_quantile(0.95, sum by (route, le) (rate(nginx_user_request_duration_seconds_bucket[5m])))

# 99th percentile for a specific user
histogram_quantile(0.99, sum by (le) (rate(nginx_user_request_duration_seconds_bucket{user_ip="192.168.1.100"}[5m])))
```

#### Filtered Queries

```promql
# Average duration for a specific route
sum(rate(nginx_user_request_duration_seconds_sum{route="/server1"}[5m])) / 
sum(rate(nginx_user_request_duration_seconds_count{route="/server1"}[5m]))

# Requests slower than 1 second (99th percentile > 1s)
histogram_quantile(0.99, sum by (user_ip, le) (rate(nginx_user_request_duration_seconds_bucket[5m]))) > 1
```

---

## Connection Metrics

### `nginx_user_active_connections`

**Type:** Gauge  
**Description:** Number of active connections per user  
**Labels:** `user_ip`

#### Basic Queries

```promql
# Active connections per user
nginx_user_active_connections

# Total active connections across all users
sum(nginx_user_active_connections)

# Top 10 users by active connections
topk(10, nginx_user_active_connections)

# Users with active connections
nginx_user_active_connections > 0
```

#### Filtered Queries

```promql
# Active connections for a specific user
nginx_user_active_connections{user_ip="192.168.1.100"}

# Users with more than 5 active connections
nginx_user_active_connections > 5
```

---

### `nginx_user_requests_per_second`

**Type:** Gauge  
**Description:** Requests per second per user  
**Labels:** `user_ip`

#### Basic Queries

```promql
# Requests per second per user
nginx_user_requests_per_second

# Top 10 users by requests per second
topk(10, nginx_user_requests_per_second)

# Total requests per second across all users
sum(nginx_user_requests_per_second)
```

#### Filtered Queries

```promql
# Requests per second for a specific user
nginx_user_requests_per_second{user_ip="192.168.1.100"}

# Users with high request rate (> 10 req/s)
nginx_user_requests_per_second > 10
```

---

### `nginx_user_last_request_time`

**Type:** Gauge  
**Description:** Unix timestamp of last request per user  
**Labels:** `user_ip`

#### Basic Queries

```promql
# Last request time per user (Unix timestamp)
nginx_user_last_request_time

# Time since last request per user (in seconds)
time() - nginx_user_last_request_time

# Users who haven't made a request in the last 5 minutes
(time() - nginx_user_last_request_time) > 300

# Users active in the last minute
(time() - nginx_user_last_request_time) < 60
```

#### Filtered Queries

```promql
# Last request time for a specific user
nginx_user_last_request_time{user_ip="192.168.1.100"}

# Time since last request for a specific user
time() - nginx_user_last_request_time{user_ip="192.168.1.100"}
```

---

## Rate Limiting Metrics

### `nginx_rate_limit_hits_total`

**Type:** Counter  
**Description:** Total number of rate limit hits (429 status codes) per user  
**Labels:** `user_ip`, `route`, `http_method`

#### Basic Queries

```promql
# Total rate limit hits per user
sum by (user_ip) (nginx_rate_limit_hits_total)

# Rate limit hits per user per second
sum by (user_ip) (rate(nginx_rate_limit_hits_total[5m]))

# Top 10 users hitting rate limits
topk(10, sum by (user_ip) (nginx_rate_limit_hits_total))

# Rate limit hits by route
sum by (route) (nginx_rate_limit_hits_total)

# Rate limit hits by HTTP method
sum by (http_method) (nginx_rate_limit_hits_total)
```

#### Filtered Queries

```promql
# Rate limit hits for a specific user
nginx_rate_limit_hits_total{user_ip="192.168.1.100"}

# Rate limit hits for a specific route
nginx_rate_limit_hits_total{route="/server1"}

# Rate limit hits for POST requests
nginx_rate_limit_hits_total{http_method="POST"}

# Rate limit hit rate for a specific user (hits per second)
sum(rate(nginx_rate_limit_hits_total{user_ip="192.168.1.100"}[5m]))
```

---

### `nginx_rate_limit_hits_global_total`

**Type:** Counter  
**Description:** Total number of rate limit hits (429 status codes) - global aggregated  
**Labels:** `route`, `http_method`

#### Basic Queries

```promql
# Total global rate limit hits
sum(nginx_rate_limit_hits_global_total)

# Global rate limit hits per second
sum(rate(nginx_rate_limit_hits_global_total[5m]))

# Global rate limit hits by route
sum by (route) (nginx_rate_limit_hits_global_total)

# Global rate limit hits by HTTP method
sum by (http_method) (nginx_rate_limit_hits_global_total)

# Global rate limit hit rate by route (hits per second)
sum by (route) (rate(nginx_rate_limit_hits_global_total[5m]))
```

#### Filtered Queries

```promql
# Global rate limit hits for a specific route
nginx_rate_limit_hits_global_total{route="/server1"}

# Global rate limit hits for GET requests
nginx_rate_limit_hits_global_total{http_method="GET"}

# Global rate limit hit rate for a specific route
sum(rate(nginx_rate_limit_hits_global_total{route="/server1"}[5m]))
```

---

## Timeout Metrics

### `nginx_timeout_events_total`

**Type:** Counter  
**Description:** Total number of timeout events (504, 408, or response time > 600s) per user  
**Labels:** `user_ip`, `route`, `timeout_type`, `http_method`  
**Timeout Types:** `gateway_timeout`, `request_timeout`, `response_timeout`

#### Basic Queries

```promql
# Total timeout events per user
sum by (user_ip) (nginx_timeout_events_total)

# Timeout events per user per second
sum by (user_ip) (rate(nginx_timeout_events_total[5m]))

# Top 10 users experiencing timeouts
topk(10, sum by (user_ip) (nginx_timeout_events_total))

# Timeout events by type
sum by (timeout_type) (nginx_timeout_events_total)

# Timeout events by route
sum by (route) (nginx_timeout_events_total)
```

#### Filtered Queries

```promql
# Timeout events for a specific user
nginx_timeout_events_total{user_ip="192.168.1.100"}

# Gateway timeout events (504 status)
nginx_timeout_events_total{timeout_type="gateway_timeout"}

# Request timeout events (408 status)
nginx_timeout_events_total{timeout_type="request_timeout"}

# Response timeout events (response time > 600s)
nginx_timeout_events_total{timeout_type="response_timeout"}

# Timeout events for a specific route
nginx_timeout_events_total{route="/server1"}

# Timeout rate for a specific user (timeouts per second)
sum(rate(nginx_timeout_events_total{user_ip="192.168.1.100"}[5m]))
```

---

### `nginx_timeout_events_global_total`

**Type:** Counter  
**Description:** Total number of timeout events (504, 408, or response time > 600s) - global aggregated  
**Labels:** `route`, `timeout_type`, `http_method`

#### Basic Queries

```promql
# Total global timeout events
sum(nginx_timeout_events_global_total)

# Global timeout events per second
sum(rate(nginx_timeout_events_global_total[5m]))

# Global timeout events by type
sum by (timeout_type) (nginx_timeout_events_global_total)

# Global timeout events by route
sum by (route) (nginx_timeout_events_global_total)

# Global timeout events by HTTP method
sum by (http_method) (nginx_timeout_events_global_total)
```

#### Filtered Queries

```promql
# Global gateway timeout events
nginx_timeout_events_global_total{timeout_type="gateway_timeout"}

# Global timeout events for a specific route
nginx_timeout_events_global_total{route="/server1"}

# Global timeout rate by route (timeouts per second)
sum by (route) (rate(nginx_timeout_events_global_total[5m]))

# Global timeout rate by type (timeouts per second)
sum by (timeout_type) (rate(nginx_timeout_events_global_total[5m]))
```

---

## Common Query Patterns

### User Activity Summary

```promql
# Complete user activity summary (requests, bandwidth, active connections)
sum by (user_ip) (
  nginx_user_requests_total
) or
sum by (user_ip) (
  nginx_user_bytes_total
) or
nginx_user_active_connections
```

### Error Rate Calculation

```promql
# Error rate percentage (4xx and 5xx)
(
  sum(rate(nginx_user_requests_total{status=~"[45].."}[5m])) /
  sum(rate(nginx_user_requests_total[5m]))
) * 100
```

### Request Success Rate

```promql
# Success rate percentage (2xx)
(
  sum(rate(nginx_user_requests_total{status=~"2.."}[5m])) /
  sum(rate(nginx_user_requests_total[5m]))
) * 100
```

### Average Response Time Across All Users

```promql
# Global average response time
sum(rate(nginx_user_request_duration_seconds_sum[5m])) / 
sum(rate(nginx_user_request_duration_seconds_count[5m]))
```

### Rate Limit Hit Percentage

```promql
# Percentage of requests that hit rate limits
(
  sum(rate(nginx_rate_limit_hits_global_total[5m])) /
  sum(rate(nginx_user_requests_total[5m]))
) * 100
```

### Timeout Event Percentage

```promql
# Percentage of requests that resulted in timeouts
(
  sum(rate(nginx_timeout_events_global_total[5m])) /
  sum(rate(nginx_user_requests_total[5m]))
) * 100
```

### Top Users by Multiple Metrics

```promql
# Top 5 users by request count, bandwidth, and active connections
topk(5, sum by (user_ip) (nginx_user_requests_total)) or
topk(5, sum by (user_ip) (nginx_user_bytes_total)) or
topk(5, nginx_user_active_connections)
```

### User Health Score

```promql
# Users with high error rates (> 10%)
(
  sum by (user_ip) (rate(nginx_user_requests_total{status=~"[45].."}[5m])) /
  sum by (user_ip) (rate(nginx_user_requests_total[5m]))
) > 0.10
```

### Inactive Users

```promql
# Users who haven't made a request in the last 10 minutes
(time() - nginx_user_last_request_time) > 600
```

### High Bandwidth Users

```promql
# Users using more than 1 MB/s
sum by (user_ip) (rate(nginx_user_bytes_total[5m])) > 1048576
```

---

## Grafana Dashboard Queries

### Panel: Total Requests Over Time

```promql
sum(rate(nginx_user_requests_total[5m]))
```

### Panel: Requests by Status Code

```promql
sum by (status) (rate(nginx_user_requests_total[5m]))
```

### Panel: Top 10 Users by Requests

```promql
topk(10, sum by (user_ip) (rate(nginx_user_requests_total[5m])))
```

### Panel: Average Response Time

```promql
sum(rate(nginx_user_request_duration_seconds_sum[5m])) / 
sum(rate(nginx_user_request_duration_seconds_count[5m]))
```

### Panel: 95th Percentile Response Time

```promql
histogram_quantile(0.95, sum by (le) (rate(nginx_user_request_duration_seconds_bucket[5m])))
```

### Panel: Bandwidth Usage

```promql
sum(rate(nginx_user_bytes_total[5m])) / 1024 / 1024
```

### Panel: Rate Limit Hits

```promql
sum(rate(nginx_rate_limit_hits_global_total[5m]))
```

### Panel: Timeout Events

```promql
sum by (timeout_type) (rate(nginx_timeout_events_global_total[5m]))
```

---

## Notes

- All rate queries use a 5-minute window `[5m]`. Adjust based on your scrape interval and needs.
- Histogram quantiles require aggregating by `le` (less than or equal) label.
- Counters should always be used with `rate()` or `increase()` functions in Prometheus.
- Gauges can be queried directly without rate functions.
- Use `sum()` to aggregate across labels, and `sum by (label)` to group by specific labels.

