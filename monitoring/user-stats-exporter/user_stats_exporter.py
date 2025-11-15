#!/usr/bin/env python3
"""
Nginx Per-User Stats Exporter
Reads nginx access logs and exports per-user metrics in Prometheus format.
"""

import re
import time
import os
import sys
from collections import defaultdict
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

# Prometheus metrics
# Per-user request counter by status code, method, and route
user_requests_total = Counter(
    'nginx_user_requests_total',
    'Total number of requests per user',
    ['user_ip', 'status', 'method', 'route']
)

# Per-user bytes transferred
user_bytes_total = Counter(
    'nginx_user_bytes_total',
    'Total bytes transferred per user',
    ['user_ip', 'direction']
)

# Per-user request duration histogram
user_request_duration_seconds = Histogram(
    'nginx_user_request_duration_seconds',
    'Request duration per user',
    ['user_ip', 'route'],
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05,
             0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
)

# Per-user active connections (gauge)
user_active_connections = Gauge(
    'nginx_user_active_connections',
    'Number of active connections per user',
    ['user_ip']
)

# Per-user requests per second (gauge)
user_requests_per_second = Gauge(
    'nginx_user_requests_per_second',
    'Requests per second per user',
    ['user_ip']
)

# Per-user last request time
user_last_request_time = Gauge(
    'nginx_user_last_request_time',
    'Unix timestamp of last request per user',
    ['user_ip']
)

# Rate limiting metrics - per-user
rate_limit_hits_total = Counter(
    'nginx_rate_limit_hits_total',
    'Total number of rate limit hits (429 status codes) per user',
    ['user_ip', 'route', 'http_method']
)

# Rate limiting metrics - global (aggregated)
rate_limit_hits_global_total = Counter(
    'nginx_rate_limit_hits_global_total',
    'Total number of rate limit hits (429 status codes) - global aggregated',
    ['route', 'http_method']
)

# Timeout metrics - per-user
timeout_events_total = Counter(
    'nginx_timeout_events_total',
    'Total number of timeout events (504, 408, or response time > 600s) per user',
    ['user_ip', 'route', 'timeout_type', 'http_method']
)

# Timeout metrics - global (aggregated)
timeout_events_global_total = Counter(
    'nginx_timeout_events_global_total',
    'Total number of timeout events (504, 408, or response time > 600s) - global aggregated',
    ['route', 'timeout_type', 'http_method']
)

# Track active users and their request counts
active_users = defaultdict(int)
user_last_seen = {}
# Read from stdin instead of log file
read_from_stdin = True


def parse_log_line(line):
    """
    Parse a line from nginx access log.
    Format: $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent ... rt=$request_time ...
    Supports both old format (without timing) and new format (with timing information)
    """
    try:
        line = line.strip()

        # Try enhanced format first (with timing information)
        # Format: IP - user [timestamp] "METHOD URI HTTP/VERSION" status bytes "referer" "user-agent" "x-forwarded-for" rt=time uct="..." uht="..." urt="..."
        enhanced_pattern = r'^(\S+) - (\S+) \[([^\]]+)\] "(\S+) (\S+) ([^"]+)" (\d+) (\d+) "([^"]*)" "([^"]*)" "([^"]*)" rt=([\d.]+) uct="([^"]*)" uht="([^"]*)" urt="([^"]*)"'
        match = re.match(enhanced_pattern, line)

        request_time = None
        if match:
            # Enhanced format with timing
            remote_addr = match.group(1)
            time_local = match.group(3)
            method = match.group(4)
            uri = match.group(5)
            status = match.group(7)
            bytes_sent = int(match.group(8)) if match.group(8) else 0
            request_time = float(match.group(12)) if match.group(12) else None
        else:
            # Fallback to basic format (without timing)
            pattern = r'^(\S+) - (\S+) \[([^\]]+)\] "(\S+) (\S+) ([^"]+)" (\d+) (\d+) "([^"]*)" "([^"]*)" "([^"]*)"'
            match = re.match(pattern, line)
            if not match:
                return None

            remote_addr = match.group(1)
            time_local = match.group(3)
            method = match.group(4)
            uri = match.group(5)
            status = match.group(7)
            bytes_sent = int(match.group(8)) if match.group(8) else 0

        # Extract route from URI
        route = '/'
        if uri.startswith('/server1'):
            route = '/server1'
        elif uri.startswith('/server2'):
            route = '/server2'

        # Detect rate limiting (429 status code)
        rate_limit_hit = (status == '429')

        # Detect timeout events
        timeout_hit = False
        timeout_type = ''
        if status == '504':
            timeout_hit = True
            timeout_type = 'gateway_timeout'
        elif status == '408':
            timeout_hit = True
            timeout_type = 'request_timeout'
        elif request_time and request_time > 600.0:  # proxy_read_timeout is 600s
            timeout_hit = True
            timeout_type = 'response_timeout'

        return {
            'user_ip': remote_addr,
            'time': time_local,
            'method': method,
            'uri': uri,
            'route': route,
            'status': status,
            'bytes_sent': bytes_sent,
            'request_time': request_time,
            'rate_limit_hit': rate_limit_hit,
            'timeout_hit': timeout_hit,
            'timeout_type': timeout_type,
        }
    except (ValueError, AttributeError, IndexError) as e:
        return None


def process_log_line(line):
    """Process a single log line and update metrics."""
    current_time = time.time()
    
    log_entry = parse_log_line(line)
    if not log_entry:
        return
    
    user_ip = log_entry['user_ip']
    route = log_entry['route']
    method = log_entry['method']

    # Update basic metrics
    user_requests_total.labels(
        user_ip=user_ip,
        status=log_entry['status'],
        method=method,
        route=route
    ).inc()

    user_bytes_total.labels(
        user_ip=user_ip,
        direction='sent'
    ).inc(log_entry['bytes_sent'])

    # Update rate limiting metrics (per-user and global)
    if log_entry.get('rate_limit_hit', False):
        rate_limit_hits_total.labels(
            user_ip=user_ip,
            route=route,
            http_method=method
        ).inc()

        rate_limit_hits_global_total.labels(
            route=route,
            http_method=method
        ).inc()

    # Update timeout metrics (per-user and global)
    if log_entry.get('timeout_hit', False):
        timeout_type = log_entry.get('timeout_type', 'unknown')
        timeout_events_total.labels(
            user_ip=user_ip,
            route=route,
            timeout_type=timeout_type,
            http_method=method
        ).inc()

        timeout_events_global_total.labels(
            route=route,
            timeout_type=timeout_type,
            http_method=method
        ).inc()

    # Track active users
    active_users[user_ip] += 1
    user_last_seen[user_ip] = current_time
    user_last_request_time.labels(
        user_ip=user_ip).set(current_time)


def update_active_connections():
    """Update active connections gauge based on recent activity."""
    current_time = time.time()
    active_threshold = 60

    for user_ip, last_seen in list(user_last_seen.items()):
        if current_time - last_seen < active_threshold:
            recent_requests = active_users.get(user_ip, 0)
            user_active_connections.labels(
                user_ip=user_ip).set(min(recent_requests, 10))
        else:
            user_active_connections.labels(user_ip=user_ip).set(0)
            active_users[user_ip] = 0


def calculate_requests_per_second():
    """Calculate and update requests per second for each user."""
    current_time = time.time()
    window_seconds = 60

    for user_ip in list(user_last_seen.keys()):
        if user_ip in active_users:
            rps = active_users[user_ip] / \
                window_seconds if active_users[user_ip] > 0 else 0
            user_requests_per_second.labels(user_ip=user_ip).set(rps)


def metrics_updater_loop():
    """Periodically update active connections and RPS metrics."""
    while True:
        try:
            time.sleep(5)
            update_active_connections()
            calculate_requests_per_second()
        except Exception as e:
            print(f"Error in metrics updater loop: {e}", file=sys.stderr)
            time.sleep(5)


def log_processor_loop():
    """Main loop for processing logs from stdin."""
    if read_from_stdin:
        # Read from stdin line by line
        try:
            for line in sys.stdin:
                line = line.strip()
                if line:
                    process_log_line(line)
        except Exception as e:
            print(f"Error reading from stdin: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Fallback: process log file (for backward compatibility)
        while True:
            try:
                # This would need the old process_log_file() function
                # Keeping for backward compatibility if needed
                time.sleep(5)
            except Exception as e:
                print(f"Error in log processor loop: {e}", file=sys.stderr)
                time.sleep(5)


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus metrics endpoint."""

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', CONTENT_TYPE_LATEST)
            self.end_headers()
            self.wfile.write(generate_latest())
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def main():
    """Main entry point."""
    # Start log processor thread (reads from stdin)
    processor_thread = Thread(target=log_processor_loop, daemon=True)
    processor_thread.start()
    
    # Start metrics updater thread (updates active connections and RPS periodically)
    metrics_thread = Thread(target=metrics_updater_loop, daemon=True)
    metrics_thread.start()

    port = int(os.environ.get('EXPORTER_PORT', '9114'))
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    print(f"Starting user stats exporter on port {port}", file=sys.stderr)
    if read_from_stdin:
        print("Reading logs from stdin", file=sys.stderr)
    else:
        print(f"Monitoring log file: {log_file_path}", file=sys.stderr)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
