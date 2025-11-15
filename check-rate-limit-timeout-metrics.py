#!/usr/bin/env python3
"""
Check rate limiting and timeout metrics from Prometheus and OpenTelemetry Collector
Supports both global and per-user metrics
"""

import requests
import json
import sys
from datetime import datetime
from typing import Dict, List, Optional

PROMETHEUS_URL = "http://localhost:9090"
OTEL_COLLECTOR_URL = "http://localhost:8889"

def query_prometheus(query: str, description: str) -> Optional[Dict]:
    """Query Prometheus and return results"""
    try:
        response = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": query},
            timeout=10
        )
        if response.status_code == 200:
            data = response.json()
            if data.get("status") == "success":
                return data.get("data", {})
        print(f"✗ Error querying Prometheus: HTTP {response.status_code}")
        return None
    except requests.exceptions.ConnectionError:
        print(f"✗ Could not connect to Prometheus at {PROMETHEUS_URL}")
        return None
    except Exception as e:
        print(f"✗ Error: {e}")
        return None

def check_otel_collector_metrics():
    """Check metrics directly from OpenTelemetry Collector"""
    print("=" * 70)
    print("Checking OpenTelemetry Collector Metrics")
    print("=" * 70)
    try:
        response = requests.get(f"{OTEL_COLLECTOR_URL}/metrics", timeout=10)
        if response.status_code == 200:
            print(f"✓ Successfully connected to OpenTelemetry Collector")
            metrics = response.text
            
            # Check for per-user rate limit metrics
            rate_limit_per_user = [line for line in metrics.split('\n') 
                                  if 'nginx_rate_limit_hits_total{' in line and 'user_ip=' in line 
                                  and not line.startswith('#')]
            
            # Check for global rate limit metrics
            rate_limit_global = [line for line in metrics.split('\n') 
                                if 'nginx_rate_limit_hits_global_total{' in line 
                                and not line.startswith('#')]
            
            # Check for per-user timeout metrics
            timeout_per_user = [line for line in metrics.split('\n') 
                               if 'nginx_timeout_events_total{' in line and 'user_ip=' in line 
                               and not line.startswith('#')]
            
            # Check for global timeout metrics
            timeout_global = [line for line in metrics.split('\n') 
                             if 'nginx_timeout_events_global_total{' in line 
                             and not line.startswith('#')]
            
            print(f"\nPer-user rate limit metrics: {len(rate_limit_per_user)} entries")
            if rate_limit_per_user:
                print("  Sample entries:")
                for metric in rate_limit_per_user[:5]:
                    print(f"    {metric}")
                if len(rate_limit_per_user) > 5:
                    print(f"    ... and {len(rate_limit_per_user) - 5} more")
            
            print(f"\nGlobal rate limit metrics: {len(rate_limit_global)} entries")
            if rate_limit_global:
                print("  Sample entries:")
                for metric in rate_limit_global[:5]:
                    print(f"    {metric}")
                if len(rate_limit_global) > 5:
                    print(f"    ... and {len(rate_limit_global) - 5} more")
            
            print(f"\nPer-user timeout metrics: {len(timeout_per_user)} entries")
            if timeout_per_user:
                print("  Sample entries:")
                for metric in timeout_per_user[:5]:
                    print(f"    {metric}")
                if len(timeout_per_user) > 5:
                    print(f"    ... and {len(timeout_per_user) - 5} more")
            else:
                print("  (No timeout events yet - this is normal)")
            
            print(f"\nGlobal timeout metrics: {len(timeout_global)} entries")
            if timeout_global:
                print("  Sample entries:")
                for metric in timeout_global[:5]:
                    print(f"    {metric}")
                if len(timeout_global) > 5:
                    print(f"    ... and {len(timeout_global) - 5} more")
            else:
                print("  (No timeout events yet - this is normal)")
            
            return True
        else:
            print(f"✗ Error: HTTP {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print(f"✗ Could not connect to OpenTelemetry Collector at {OTEL_COLLECTOR_URL}")
        print("  Make sure the service is running: docker-compose up -d")
        return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

def display_per_user_rate_limits():
    """Display per-user rate limit statistics"""
    print("\n" + "=" * 70)
    print("Per-User Rate Limit Statistics")
    print("=" * 70)
    
    query = "sum(nginx_rate_limit_hits_total) by (user_ip, route, http_method)"
    data = query_prometheus(query, "Per-user rate limit hits")
    
    if data and data.get("result"):
        results = data["result"]
        if results:
            print(f"\nFound {len(results)} per-user rate limit entries:\n")
            for result in results:
                metric = result.get("metric", {})
                value = result.get("value", [None, "0"])[1]
                user_ip = metric.get("user_ip", "unknown")
                route = metric.get("route", "unknown")
                method = metric.get("http_method", "unknown")
                print(f"  User: {user_ip:15} Route: {route:10} Method: {method:6} Hits: {value}")
        else:
            print("\n⚠ No per-user rate limit data available yet")
            print("  Try running: ./test-rate-limit-timeout-metrics.sh")
    else:
        print("\n⚠ Could not fetch per-user rate limit data")

def display_global_rate_limits():
    """Display global rate limit statistics"""
    print("\n" + "=" * 70)
    print("Global Rate Limit Statistics")
    print("=" * 70)
    
    query = "sum(nginx_rate_limit_hits_global_total) by (route, http_method)"
    data = query_prometheus(query, "Global rate limit hits")
    
    if data and data.get("result"):
        results = data["result"]
        if results:
            print(f"\nFound {len(results)} global rate limit entries:\n")
            total = 0
            for result in results:
                metric = result.get("metric", {})
                value = float(result.get("value", [None, "0"])[1])
                route = metric.get("route", "unknown")
                method = metric.get("http_method", "unknown")
                total += value
                print(f"  Route: {route:10} Method: {method:6} Total Hits: {value:.0f}")
            print(f"\n  Grand Total: {total:.0f} rate limit hits across all users")
        else:
            print("\n⚠ No global rate limit data available yet")
            print("  Try running: ./test-rate-limit-timeout-metrics.sh")
    else:
        print("\n⚠ Could not fetch global rate limit data")

def display_per_user_timeouts():
    """Display per-user timeout statistics"""
    print("\n" + "=" * 70)
    print("Per-User Timeout Statistics")
    print("=" * 70)
    
    query = "sum(nginx_timeout_events_total) by (user_ip, route, timeout_type)"
    data = query_prometheus(query, "Per-user timeout events")
    
    if data and data.get("result"):
        results = data["result"]
        if results:
            print(f"\nFound {len(results)} per-user timeout entries:\n")
            for result in results:
                metric = result.get("metric", {})
                value = result.get("value", [None, "0"])[1]
                user_ip = metric.get("user_ip", "unknown")
                route = metric.get("route", "unknown")
                timeout_type = metric.get("timeout_type", "unknown")
                print(f"  User: {user_ip:15} Route: {route:10} Type: {timeout_type:20} Count: {value}")
        else:
            print("\n⚠ No per-user timeout data available yet")
            print("  (This is normal if no timeouts have occurred)")
    else:
        print("\n⚠ Could not fetch per-user timeout data")

def display_global_timeouts():
    """Display global timeout statistics"""
    print("\n" + "=" * 70)
    print("Global Timeout Statistics")
    print("=" * 70)
    
    query = "sum(nginx_timeout_events_global_total) by (route, timeout_type)"
    data = query_prometheus(query, "Global timeout events")
    
    if data and data.get("result"):
        results = data["result"]
        if results:
            print(f"\nFound {len(results)} global timeout entries:\n")
            total = 0
            for result in results:
                metric = result.get("metric", {})
                value = float(result.get("value", [None, "0"])[1])
                route = metric.get("route", "unknown")
                timeout_type = metric.get("timeout_type", "unknown")
                total += value
                print(f"  Route: {route:10} Type: {timeout_type:20} Total: {value:.0f}")
            print(f"\n  Grand Total: {total:.0f} timeout events across all users")
        else:
            print("\n⚠ No global timeout data available yet")
            print("  (This is normal if no timeouts have occurred)")
    else:
        print("\n⚠ Could not fetch global timeout data")

def check_prometheus_targets():
    """Check if Prometheus targets are configured correctly"""
    print("\n" + "=" * 70)
    print("Checking Prometheus Targets")
    print("=" * 70)
    try:
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/targets", timeout=10)
        if response.status_code == 200:
            data = response.json()
            if data.get("status") == "success":
                targets = data.get("data", {}).get("activeTargets", [])
                otel_target = [t for t in targets if "otel-collector" in t.get("labels", {}).get("job", "")]
                
                if otel_target:
                    target = otel_target[0]
                    health = target.get("health", "unknown")
                    if health == "up":
                        print(f"✓ OpenTelemetry Collector target is UP")
                        return True
                    else:
                        print(f"⚠ OpenTelemetry Collector target is {health.upper()}")
                        return False
                else:
                    print("⚠ OpenTelemetry Collector target not found in Prometheus")
                    return False
        return False
    except Exception as e:
        print(f"✗ Error checking targets: {e}")
        return False

def main():
    print(f"\nRate Limiting & Timeout Metrics Checker")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    # Check OpenTelemetry Collector
    otel_ok = check_otel_collector_metrics()
    
    # Check Prometheus targets
    targets_ok = check_prometheus_targets()
    
    # Display statistics
    if otel_ok or targets_ok:
        display_per_user_rate_limits()
        display_global_rate_limits()
        display_per_user_timeouts()
        display_global_timeouts()
    
    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)
    print(f"OpenTelemetry Collector: {'✓ OK' if otel_ok else '✗ Not accessible'}")
    print(f"Prometheus Targets: {'✓ OK' if targets_ok else '✗ Not accessible'}")
    print("\nAvailable Metrics:")
    print("  Per-user:")
    print("    - nginx_rate_limit_hits_total{user_ip, route, http_method}")
    print("    - nginx_timeout_events_total{user_ip, route, timeout_type}")
    print("  Global:")
    print("    - nginx_rate_limit_hits_global_total{route, http_method}")
    print("    - nginx_timeout_events_global_total{route, timeout_type}")
    print("\nTo generate test traffic, run:")
    print("  ./test-rate-limit-timeout-metrics.sh")
    print("\nTo view metrics in Prometheus:")
    print(f"  {PROMETHEUS_URL}")
    print("\nTo view metrics in Grafana:")
    print("  http://localhost:3000")
    print("\nTo view OTel Collector metrics directly:")
    print(f"  {OTEL_COLLECTOR_URL}/metrics")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        sys.exit(1)

