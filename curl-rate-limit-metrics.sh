#!/bin/bash
# Quick curl commands for rate limit metrics
# Simple script with curl commands to query rate limit metrics

# Configuration
USER_STATS_EXPORTER="${USER_STATS_EXPORTER:-localhost:9114}"
PROMETHEUS="${PROMETHEUS:-localhost:9090}"

echo "=== Rate Limit Metrics - Quick Curl Commands ==="
echo ""

echo "1. Get all rate limit metrics from User Stats Exporter:"
echo "curl http://${USER_STATS_EXPORTER}/metrics | grep rate_limit"
echo ""

echo "2. Query rate limit hits per user from Prometheus:"
echo "curl 'http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_total'"
echo ""

echo "3. Query global rate limit hits from Prometheus:"
echo "curl 'http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_global_total'"
echo ""

echo "4. Query rate limit hits by route:"
echo "curl 'http://${PROMETHEUS}/api/v1/query?query=sum(nginx_rate_limit_hits_global_total)%20by%20(route)'"
echo ""

echo "5. Query rate limit hit rate (per minute):"
echo "curl 'http://${PROMETHEUS}/api/v1/query?query=rate(nginx_rate_limit_hits_global_total[1m])'"
echo ""

echo "6. Query rate limit hits per user IP:"
echo "curl 'http://${PROMETHEUS}/api/v1/query?query=sum(nginx_rate_limit_hits_total)%20by%20(user_ip)'"
echo ""

echo "=== Executing queries now ==="
echo ""

echo "--- User Stats Exporter Metrics ---"
curl -s "http://${USER_STATS_EXPORTER}/metrics" | grep -E "nginx_rate_limit_hits" || echo "No rate limit metrics found"
echo ""

echo "--- Prometheus: Rate Limit Hits Per User ---"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_total"
echo ""
echo ""

echo "--- Prometheus: Global Rate Limit Hits ---"
curl -s "http://${PROMETHEUS}/api/v1/query?query=nginx_rate_limit_hits_global_total"
echo ""
echo ""

echo "--- Prometheus: Rate Limit Hits by Route ---"
curl -s "http://${PROMETHEUS}/api/v1/query?query=sum(nginx_rate_limit_hits_global_total)%20by%20(route)"
echo ""
echo ""

echo "--- Prometheus: Rate Limit Hit Rate ---"
curl -s "http://${PROMETHEUS}/api/v1/query?query=rate(nginx_rate_limit_hits_global_total[1m])"
echo ""

