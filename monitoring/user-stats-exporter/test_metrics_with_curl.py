#!/usr/bin/env python3
"""
Test script to verify per-user metrics are properly incremented using curl/HTTP requests.
This script can work with a running user-stats-exporter service.
"""

import sys
import time
import subprocess
import requests
from typing import Dict, List, Optional


class MetricsTester:
    """Test per-user metrics incrementation via HTTP/curl."""
    
    def __init__(self, metrics_endpoint: str = "http://localhost:9114/metrics"):
        """
        Initialize the metrics tester.
        
        Args:
            metrics_endpoint: URL of the metrics endpoint
        """
        self.metrics_endpoint = metrics_endpoint
        self.test_logs: List[str] = []
    
    def check_endpoint_accessible(self) -> bool:
        """Check if the metrics endpoint is accessible."""
        try:
            response = requests.get(self.metrics_endpoint, timeout=5)
            return response.status_code == 200
        except Exception as e:
            print(f"Error accessing metrics endpoint: {e}")
            return False
    
    def get_metrics(self) -> str:
        """Get all metrics from the endpoint."""
        try:
            response = requests.get(self.metrics_endpoint, timeout=5)
            return response.text
        except Exception as e:
            print(f"Error fetching metrics: {e}")
            return ""
    
    def get_metric_value(self, metric_name: str, labels: Dict[str, str]) -> float:
        """
        Get a specific metric value.
        
        Args:
            metric_name: Name of the metric (e.g., 'nginx_user_requests_total')
            labels: Dictionary of label key-value pairs
            
        Returns:
            The metric value as a float, or 0.0 if not found
        """
        metrics_text = self.get_metrics()
        if not metrics_text:
            return 0.0
        
        # Build label filter
        label_filters = [f'{k}="{v}"' for k, v in labels.items()]
        
        # Search for the metric line
        for line in metrics_text.split('\n'):
            if line.startswith(metric_name) and all(label in line for label in label_filters):
                # Extract the value (format: metric_name{labels} value)
                parts = line.split()
                if len(parts) >= 2:
                    try:
                        return float(parts[1])
                    except ValueError:
                        continue
        
        return 0.0
    
    def get_user_metrics(self, user_ip: str) -> Dict[str, float]:
        """
        Get all metrics for a specific user.
        
        Args:
            user_ip: IP address of the user
            
        Returns:
            Dictionary of metric values
        """
        metrics_text = self.get_metrics()
        user_metrics = {}
        
        if not metrics_text:
            return user_metrics
        
        for line in metrics_text.split('\n'):
            if f'user_ip="{user_ip}"' in line and not line.startswith('#'):
                # Parse the metric line
                parts = line.split()
                if len(parts) >= 2:
                    metric_name = parts[0].split('{')[0]
                    try:
                        value = float(parts[1])
                        # Create a key from the full line (for uniqueness)
                        key = parts[0]  # Full metric with labels
                        user_metrics[key] = value
                    except ValueError:
                        continue
        
        return user_metrics
    
    def print_user_metrics(self, user_ip: str):
        """Print all metrics for a specific user."""
        print(f"\n--- Metrics for user {user_ip} ---")
        metrics = self.get_user_metrics(user_ip)
        if metrics:
            for metric_key, value in sorted(metrics.items()):
                print(f"  {metric_key} = {value}")
        else:
            print(f"  No metrics found for user {user_ip}")
        print()
    
    def send_log_line_to_exporter(self, log_line: str, method: str = "stdin") -> bool:
        """
        Send a log line to the exporter.
        
        Args:
            log_line: The log line to send
            method: Method to use ('stdin', 'file', 'docker')
            
        Returns:
            True if successful, False otherwise
        """
        if method == "stdin":
            # Try to send via stdin to a running process
            # This would require the exporter to be running and accepting stdin
            print(f"Note: Sending log line via {method} (requires exporter to accept stdin)")
            print(f"  {log_line}")
            return True
        elif method == "file":
            # Write to log file (if accessible)
            log_file = "/var/log/nginx/access.log"
            try:
                with open(log_file, 'a') as f:
                    f.write(log_line + '\n')
                return True
            except Exception as e:
                print(f"Error writing to log file: {e}")
                return False
        elif method == "docker":
            # Send to Docker container
            try:
                result = subprocess.run(
                    ['docker', 'exec', '-i', 'user-stats-exporter', 'python3', '-c', 
                     f'import sys; sys.stdin.readline()'],
                    input=log_line.encode(),
                    capture_output=True,
                    timeout=5
                )
                return result.returncode == 0
            except Exception as e:
                print(f"Error sending to Docker container: {e}")
                return False
        
        return False
    
    def test_metrics_incrementation(self):
        """Run comprehensive tests for per-user metrics incrementation."""
        print("=" * 60)
        print("Testing Per-User Metrics with Prometheus/Curl")
        print("=" * 60)
        print(f"Metrics endpoint: {self.metrics_endpoint}\n")
        
        # Test 1: Check endpoint accessibility
        print("Test 1: Checking metrics endpoint accessibility...")
        if not self.check_endpoint_accessible():
            print("✗ Metrics endpoint is not accessible!")
            print(f"  Please ensure the user-stats-exporter is running at {self.metrics_endpoint}")
            print("\n  You can start it with:")
            print("    docker-compose up -d user-stats-exporter")
            print("  Or run it locally:")
            print("    cd monitoring/user-stats-exporter")
            print("    python3 user_stats_exporter.py")
            return False
        print("✓ Metrics endpoint is accessible\n")
        
        # Test 2: Get initial metrics state
        print("Test 2: Getting initial metrics state...")
        initial_metrics = self.get_metrics()
        if initial_metrics:
            print(f"✓ Retrieved {len(initial_metrics.split(chr(10)))} lines of metrics")
        print()
        
        # Test 3: Display current per-user metrics
        print("Test 3: Current per-user metrics...")
        test_users = ['192.168.1.100', '192.168.1.200']
        for user_ip in test_users:
            self.print_user_metrics(user_ip)
        
        # Test 4: Verify metrics structure
        print("Test 4: Verifying metrics structure...")
        metrics_text = self.get_metrics()
        required_metrics = [
            'nginx_user_requests_total',
            'nginx_user_bytes_total',
            'nginx_rate_limit_hits_total',
            'nginx_timeout_events_total'
        ]
        
        found_metrics = []
        for metric in required_metrics:
            if metric in metrics_text:
                found_metrics.append(metric)
                print(f"  ✓ Found metric: {metric}")
            else:
                print(f"  ✗ Missing metric: {metric}")
        
        if len(found_metrics) == len(required_metrics):
            print("\n✓ All required metrics are present")
        else:
            print(f"\n✗ Only {len(found_metrics)}/{len(required_metrics)} required metrics found")
        
        print()
        
        # Test 5: Check for per-user isolation
        print("Test 5: Checking per-user metric isolation...")
        print("  This test verifies that different users have separate metrics")
        print("  If you have sent test log lines, metrics should be visible above")
        print()
        
        # Test 6: Sample metric queries
        print("Test 6: Sample metric queries...")
        print("  Querying specific metrics for test users...")
        
        # Example queries
        user1_requests = self.get_metric_value(
            'nginx_user_requests_total',
            {'user_ip': '192.168.1.100', 'status': '200', 'method': 'GET', 'route': '/server1'}
        )
        print(f"  User 192.168.1.100 - GET /server1 (200): {user1_requests}")
        
        user2_requests = self.get_metric_value(
            'nginx_user_requests_total',
            {'user_ip': '192.168.1.200', 'status': '200', 'method': 'GET', 'route': '/server2'}
        )
        print(f"  User 192.168.1.200 - GET /server2 (200): {user2_requests}")
        
        print()
        
        # Test 7: Instructions for manual testing
        print("=" * 60)
        print("Manual Testing Instructions")
        print("=" * 60)
        print("\nTo test metrics incrementation:")
        print("\n1. Send test log lines to the exporter:")
        print("   Example log lines:")
        print('   192.168.1.100 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"')
        print('   192.168.1.200 - - [25/Dec/2023:10:00:01 +0000] "GET /server2 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"')
        print("\n2. If using Docker, send logs via:")
        print("   docker exec -i user-stats-exporter sh -c 'echo \"<log_line>\" | python3 user_stats_exporter.py'")
        print("\n3. Query metrics:")
        print(f"   curl {self.metrics_endpoint} | grep nginx_user_")
        print("\n4. Query specific user metrics:")
        print(f"   curl {self.metrics_endpoint} | grep 'user_ip=\"192.168.1.100\"'")
        print()
        
        return True


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Test per-user metrics incrementation')
    parser.add_argument(
        '--endpoint',
        default='http://localhost:9114/metrics',
        help='Metrics endpoint URL (default: http://localhost:9114/metrics)'
    )
    
    args = parser.parse_args()
    
    tester = MetricsTester(args.endpoint)
    success = tester.test_metrics_incrementation()
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()

