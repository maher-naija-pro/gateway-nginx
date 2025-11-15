#!/usr/bin/env python3
"""
Check per-user metrics from Prometheus
"""

import requests
import json
import sys
from datetime import datetime

PROMETHEUS_URL = "http://localhost:9090"
USER_STATS_EXPORTER_URL = "http://localhost:9114"

def check_user_stats_exporter_metrics():
    """Check metrics directly from User Stats Exporter"""
    print("=" * 60)
    print("Checking User Stats Exporter Metrics")
    print("=" * 60)
    try:
        response = requests.get(f"{USER_STATS_EXPORTER_URL}/metrics", timeout=5)
        if response.status_code == 200:
            print(f"✓ Successfully connected to User Stats Exporter")
            metrics = response.text
            
            # Find per-user metrics
            user_metrics = [line for line in metrics.split('\n') 
                          if 'nginx_user_requests_total' in line and not line.startswith('#')]
            
            if user_metrics:
                print(f"\nFound {len(user_metrics)} per-user metric entries:\n")
                for metric in user_metrics[:20]:  # Show first 20
                    print(f"  {metric}")
                if len(user_metrics) > 20:
                    print(f"  ... and {len(user_metrics) - 20} more")
            else:
                print("\n⚠ No nginx_user_requests_total metrics found yet")
                print("  This might be normal if no requests have been made")
            return True
        else:
            print(f"✗ Error: HTTP {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print(f"✗ Could not connect to User Stats Exporter at {USER_STATS_EXPORTER_URL}")
        print("  Make sure the service is running: docker-compose up -d")
        return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

def query_prometheus(query, description):
    """Query Prometheus and return results"""
    try:
        response = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": query},
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            if data.get("status") == "success":
                return data.get("data", {}).get("result", [])
            else:
                print(f"✗ Query error: {data.get('error', 'Unknown error')}")
                return None
        else:
            print(f"✗ HTTP Error: {response.status_code}")
            return None
    except requests.exceptions.ConnectionError:
        print(f"✗ Could not connect to Prometheus at {PROMETHEUS_URL}")
        print("  Make sure the service is running: docker-compose up -d")
        return None
    except Exception as e:
        print(f"✗ Error: {e}")
        return None

def check_prometheus_targets():
    """Check if Prometheus is scraping User Stats Exporter"""
    print("\n" + "=" * 60)
    print("Checking Prometheus Targets")
    print("=" * 60)
    try:
        response = requests.get(f"{PROMETHEUS_URL}/api/v1/targets", timeout=5)
        if response.status_code == 200:
            data = response.json()
            targets = data.get("data", {}).get("activeTargets", [])
            
            exporter_target = None
            for target in targets:
                if "user-stats-exporter" in target.get("labels", {}).get("job", ""):
                    exporter_target = target
                    break
            
            if exporter_target:
                health = exporter_target.get("health", "unknown")
                last_error = exporter_target.get("lastError", "")
                print(f"✓ Found User Stats Exporter target")
                print(f"  Health: {health}")
                if last_error:
                    print(f"  Last Error: {last_error}")
                return health == "up"
            else:
                print("⚠ User Stats Exporter target not found")
                return False
        else:
            print(f"✗ HTTP Error: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

def display_per_user_stats():
    """Display per-user statistics"""
    print("\n" + "=" * 60)
    print("Per-User Statistics")
    print("=" * 60)
    
    # Query total requests per user
    query = "sum(nginx_user_requests_total) by (user_ip)"
    results = query_prometheus(query, "Total requests per user")
    
    if results:
        print(f"\nTotal Requests per User:\n")
        print(f"{'User IP':<20} {'Total Requests':<15}")
        print("-" * 35)
        for result in sorted(results, key=lambda x: float(x.get("value", [0, "0"])[1]), reverse=True):
            user_ip = result.get("metric", {}).get("user_ip", "unknown")
            value = result.get("value", [0, "0"])[1]
            print(f"{user_ip:<20} {value:<15}")
    else:
        print("\n⚠ No data available yet")
        print("  Try generating some traffic first")

def display_detailed_stats():
    """Display detailed per-user statistics"""
    print("\n" + "=" * 60)
    print("Detailed Per-User Statistics")
    print("=" * 60)
    
    # Query requests by user, status, method, and route
    query = "sum(nginx_user_requests_total) by (user_ip, status, method, route)"
    results = query_prometheus(query, "Detailed per-user stats")
    
    if results:
        print(f"\nRequests by User, Status, Method, and Route:\n")
        print(f"{'User IP':<20} {'Status':<8} {'Method':<8} {'Route':<12} {'Count':<10}")
        print("-" * 70)
        for result in sorted(results, key=lambda x: (
            x.get("metric", {}).get("user_ip", ""),
            x.get("metric", {}).get("status", ""),
            x.get("metric", {}).get("method", ""),
            x.get("metric", {}).get("route", "")
        )):
            metric = result.get("metric", {})
            user_ip = metric.get("user_ip", "unknown")
            status = metric.get("status", "unknown")
            method = metric.get("method", "unknown")
            route = metric.get("route", "unknown")
            value = result.get("value", [0, "0"])[1]
            print(f"{user_ip:<20} {status:<8} {method:<8} {route:<12} {value:<10}")
    else:
        print("\n⚠ No detailed data available yet")

def main():
    print(f"\nPer-User Metrics Checker")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    # Check User Stats Exporter
    exporter_ok = check_user_stats_exporter_metrics()
    
    # Check Prometheus targets
    targets_ok = check_prometheus_targets()
    
    # Display statistics
    if exporter_ok or targets_ok:
        display_per_user_stats()
        display_detailed_stats()
    
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"User Stats Exporter: {'✓ OK' if exporter_ok else '✗ Not accessible'}")
    print(f"Prometheus Targets: {'✓ OK' if targets_ok else '✗ Not accessible'}")
    print("\nTo generate test traffic, run:")
    print("  ./test-user-metrics.sh")
    print("\nTo view metrics in Prometheus:")
    print(f"  {PROMETHEUS_URL}")
    print("\nTo view metrics in Grafana:")
    print("  http://localhost:3000")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)

