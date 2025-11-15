#!/usr/bin/env python3
"""
Tests for per-user metrics to ensure they are properly incremented.
"""

import user_stats_exporter
import pytest
import time
from unittest.mock import Mock, patch, MagicMock
from collections import defaultdict
import sys
import os

# Add the current directory to the path to import the module
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import the module to test


class TestPerUserMetrics:
    """Test suite for per-user metrics incrementation."""

    def setup_method(self):
        """Reset metrics before each test."""
        # Reset all metrics
        user_stats_exporter.user_requests_total._metrics.clear()
        user_stats_exporter.user_bytes_total._metrics.clear()
        user_stats_exporter.rate_limit_hits_total._metrics.clear()
        user_stats_exporter.timeout_events_total._metrics.clear()
        user_stats_exporter.user_last_request_time._metrics.clear()
        user_stats_exporter.active_users.clear()
        user_stats_exporter.user_last_seen.clear()

    def test_user_requests_total_increments_per_user(self):
        """Test that request counts are tracked separately per user."""
        # Create log lines for two different users
        log_line_user1 = '192.168.1.1 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_user2 = '192.168.1.2 - - [25/Dec/2023:10:00:01 +0000] "GET /server2 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_user1)
        user_stats_exporter.process_log_line(
            log_line_user1)  # User1 makes another request
        user_stats_exporter.process_log_line(log_line_user2)

        # Check that user1 has 2 requests
        user1_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.1',
            status='200',
            method='GET',
            route='/server1'
        )
        assert user1_metric._value.get() == 2.0, "User1 should have 2 requests"

        # Check that user2 has 1 request
        user2_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.2',
            status='200',
            method='GET',
            route='/server2'
        )
        assert user2_metric._value.get() == 1.0, "User2 should have 1 request"

    def test_user_bytes_total_increments_per_user(self):
        """Test that bytes transferred are tracked separately per user."""
        # Create log lines with different byte counts for different users
        log_line_user1_1 = '192.168.1.10 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1000 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_user1_2 = '192.168.1.10 - - [25/Dec/2023:10:00:01 +0000] "GET /server1 HTTP/1.1" 200 2000 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_user2 = '192.168.1.20 - - [25/Dec/2023:10:00:02 +0000] "GET /server2 HTTP/1.1" 200 5000 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_user1_1)
        user_stats_exporter.process_log_line(log_line_user1_2)
        user_stats_exporter.process_log_line(log_line_user2)

        # Check that user1 has 3000 bytes (1000 + 2000)
        user1_bytes = user_stats_exporter.user_bytes_total.labels(
            user_ip='192.168.1.10',
            direction='sent'
        )
        assert user1_bytes._value.get() == 3000.0, "User1 should have 3000 bytes total"

        # Check that user2 has 5000 bytes
        user2_bytes = user_stats_exporter.user_bytes_total.labels(
            user_ip='192.168.1.20',
            direction='sent'
        )
        assert user2_bytes._value.get() == 5000.0, "User2 should have 5000 bytes total"

    def test_rate_limit_hits_increment_per_user(self):
        """Test that rate limit hits are tracked separately per user."""
        # Create log lines with 429 status codes for different users
        log_line_user1_rate_limit = '192.168.1.100 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 429 0 "referer" "user-agent" "x-forwarded-for" rt=0.01 uct="0.005" uht="0.008" urt="0.01"'
        log_line_user1_rate_limit2 = '192.168.1.100 - - [25/Dec/2023:10:00:01 +0000] "POST /server1 HTTP/1.1" 429 0 "referer" "user-agent" "x-forwarded-for" rt=0.01 uct="0.005" uht="0.008" urt="0.01"'
        log_line_user2_rate_limit = '192.168.1.200 - - [25/Dec/2023:10:00:02 +0000] "GET /server2 HTTP/1.1" 429 0 "referer" "user-agent" "x-forwarded-for" rt=0.01 uct="0.005" uht="0.008" urt="0.01"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_user1_rate_limit)
        user_stats_exporter.process_log_line(log_line_user1_rate_limit2)
        user_stats_exporter.process_log_line(log_line_user2_rate_limit)

        # Check that user1 has 2 rate limit hits (GET and POST)
        user1_get_rate_limit = user_stats_exporter.rate_limit_hits_total.labels(
            user_ip='192.168.1.100',
            route='/server1',
            http_method='GET'
        )
        assert user1_get_rate_limit._value.get(
        ) == 1.0, "User1 should have 1 GET rate limit hit"

        user1_post_rate_limit = user_stats_exporter.rate_limit_hits_total.labels(
            user_ip='192.168.1.100',
            route='/server1',
            http_method='POST'
        )
        assert user1_post_rate_limit._value.get(
        ) == 1.0, "User1 should have 1 POST rate limit hit"

        # Check that user2 has 1 rate limit hit
        user2_rate_limit = user_stats_exporter.rate_limit_hits_total.labels(
            user_ip='192.168.1.200',
            route='/server2',
            http_method='GET'
        )
        assert user2_rate_limit._value.get() == 1.0, "User2 should have 1 rate limit hit"

    def test_timeout_events_increment_per_user(self):
        """Test that timeout events are tracked separately per user."""
        # Create log lines with timeout status codes for different users
        log_line_user1_504 = '192.168.1.50 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 504 0 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_user1_408 = '192.168.1.50 - - [25/Dec/2023:10:00:01 +0000] "POST /server1 HTTP/1.1" 408 0 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_user2_504 = '192.168.1.60 - - [25/Dec/2023:10:00:02 +0000] "GET /server2 HTTP/1.1" 504 0 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_user1_504)
        user_stats_exporter.process_log_line(log_line_user1_408)
        user_stats_exporter.process_log_line(log_line_user2_504)

        # Check that user1 has timeout events
        user1_504_timeout = user_stats_exporter.timeout_events_total.labels(
            user_ip='192.168.1.50',
            route='/server1',
            timeout_type='gateway_timeout',
            http_method='GET'
        )
        assert user1_504_timeout._value.get(
        ) == 1.0, "User1 should have 1 gateway_timeout event"

        user1_408_timeout = user_stats_exporter.timeout_events_total.labels(
            user_ip='192.168.1.50',
            route='/server1',
            timeout_type='request_timeout',
            http_method='POST'
        )
        assert user1_408_timeout._value.get(
        ) == 1.0, "User1 should have 1 request_timeout event"

        # Check that user2 has timeout events
        user2_timeout = user_stats_exporter.timeout_events_total.labels(
            user_ip='192.168.1.60',
            route='/server2',
            timeout_type='gateway_timeout',
            http_method='GET'
        )
        assert user2_timeout._value.get() == 1.0, "User2 should have 1 timeout event"

    def test_multiple_users_separate_metrics(self):
        """Test that multiple users have completely separate metrics."""
        # Create log lines for 5 different users
        users = ['192.168.1.1', '192.168.1.2',
                 '192.168.1.3', '192.168.1.4', '192.168.1.5']

        for i, user_ip in enumerate(users):
            log_line = f'{user_ip} - - [25/Dec/2023:10:00:0{i} +0000] "GET /server1 HTTP/1.1" 200 {1000 + i * 100} "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
            user_stats_exporter.process_log_line(log_line)

        # Verify each user has their own metrics
        for i, user_ip in enumerate(users):
            # Check request count
            request_metric = user_stats_exporter.user_requests_total.labels(
                user_ip=user_ip,
                status='200',
                method='GET',
                route='/server1'
            )
            assert request_metric._value.get(
            ) == 1.0, f"User {user_ip} should have 1 request"

            # Check bytes
            bytes_metric = user_stats_exporter.user_bytes_total.labels(
                user_ip=user_ip,
                direction='sent'
            )
            expected_bytes = 1000 + i * 100
            assert bytes_metric._value.get() == float(
                expected_bytes), f"User {user_ip} should have {expected_bytes} bytes"

    def test_user_last_request_time_updates_per_user(self):
        """Test that last request time is tracked separately per user."""
        # Create log lines for two users with time gap
        log_line_user1 = '192.168.1.30 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'

        time1 = time.time()
        user_stats_exporter.process_log_line(log_line_user1)

        # Wait a bit
        time.sleep(0.1)

        log_line_user2 = '192.168.1.40 - - [25/Dec/2023:10:00:01 +0000] "GET /server2 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'
        time2 = time.time()
        user_stats_exporter.process_log_line(log_line_user2)

        # Check that each user has their own last request time
        user1_time = user_stats_exporter.user_last_request_time.labels(
            user_ip='192.168.1.30'
        )
        user2_time = user_stats_exporter.user_last_request_time.labels(
            user_ip='192.168.1.40'
        )

        assert user1_time._value.get() < user2_time._value.get(
        ), "User2's last request time should be later than User1's"
        assert user1_time._value.get() >= time1, "User1's last request time should be set"
        assert user2_time._value.get() >= time2, "User2's last request time should be set"

    def test_active_users_tracking_per_user(self):
        """Test that active users are tracked separately."""
        # Create log lines for multiple users
        log_line_user1_1 = '192.168.1.70 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_user1_2 = '192.168.1.70 - - [25/Dec/2023:10:00:01 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_user2 = '192.168.1.80 - - [25/Dec/2023:10:00:02 +0000] "GET /server2 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_user1_1)
        user_stats_exporter.process_log_line(log_line_user1_2)
        user_stats_exporter.process_log_line(log_line_user2)

        # Check that active_users dictionary tracks each user separately
        assert user_stats_exporter.active_users['192.168.1.70'] == 2, "User1 should have 2 requests tracked"
        assert user_stats_exporter.active_users['192.168.1.80'] == 1, "User2 should have 1 request tracked"
        assert len(
            user_stats_exporter.active_users) == 2, "Should have 2 active users"

    def test_different_routes_per_user(self):
        """Test that the same user can have metrics for different routes."""
        # Create log lines for same user accessing different routes
        log_line_server1 = '192.168.1.90 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_server2 = '192.168.1.90 - - [25/Dec/2023:10:00:01 +0000] "GET /server2 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'
        log_line_root = '192.168.1.90 - - [25/Dec/2023:10:00:02 +0000] "GET / HTTP/1.1" 200 512 "referer" "user-agent" "x-forwarded-for" rt=0.05 uct="0.02" uht="0.03" urt="0.05"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_server1)
        user_stats_exporter.process_log_line(log_line_server2)
        user_stats_exporter.process_log_line(log_line_root)

        # Check that the same user has separate metrics for each route
        server1_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.90',
            status='200',
            method='GET',
            route='/server1'
        )
        assert server1_metric._value.get() == 1.0, "User should have 1 request to /server1"

        server2_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.90',
            status='200',
            method='GET',
            route='/server2'
        )
        assert server2_metric._value.get() == 1.0, "User should have 1 request to /server2"

        root_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.90',
            status='200',
            method='GET',
            route='/'
        )
        assert root_metric._value.get() == 1.0, "User should have 1 request to /"

    def test_different_status_codes_per_user(self):
        """Test that the same user can have metrics for different status codes."""
        # Create log lines for same user with different status codes
        log_line_200 = '192.168.1.95 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'
        log_line_404 = '192.168.1.95 - - [25/Dec/2023:10:00:01 +0000] "GET /server1/notfound HTTP/1.1" 404 256 "referer" "user-agent" "x-forwarded-for" rt=0.05 uct="0.02" uht="0.03" urt="0.05"'
        log_line_500 = '192.168.1.95 - - [25/Dec/2023:10:00:02 +0000] "GET /server1 HTTP/1.1" 500 512 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_200)
        user_stats_exporter.process_log_line(log_line_404)
        user_stats_exporter.process_log_line(log_line_500)

        # Check that the same user has separate metrics for each status code
        status_200_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.95',
            status='200',
            method='GET',
            route='/server1'
        )
        assert status_200_metric._value.get(
        ) == 1.0, "User should have 1 request with status 200"

        status_404_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.95',
            status='404',
            method='GET',
            route='/server1'
        )
        assert status_404_metric._value.get(
        ) == 1.0, "User should have 1 request with status 404"

        status_500_metric = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.95',
            status='500',
            method='GET',
            route='/server1'
        )
        assert status_500_metric._value.get(
        ) == 1.0, "User should have 1 request with status 500"

    def test_response_time_timeout_detection_per_user(self):
        """Test that response time timeouts (>600s) are detected and tracked per user."""
        # Create log lines with response time > 600s (timeout threshold)
        log_line_user1_timeout = '192.168.1.110 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=650.5 uct="0.05" uht="0.08" urt="650.5"'
        log_line_user2_timeout = '192.168.1.120 - - [25/Dec/2023:10:00:01 +0000] "POST /server2 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=700.0 uct="0.1" uht="0.15" urt="700.0"'
        log_line_user1_normal = '192.168.1.110 - - [25/Dec/2023:10:00:02 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"'

        # Process log lines
        user_stats_exporter.process_log_line(log_line_user1_timeout)
        user_stats_exporter.process_log_line(log_line_user2_timeout)
        user_stats_exporter.process_log_line(log_line_user1_normal)

        # Check that user1 has 1 response_timeout event
        user1_timeout = user_stats_exporter.timeout_events_total.labels(
            user_ip='192.168.1.110',
            route='/server1',
            timeout_type='response_timeout',
            http_method='GET'
        )
        assert user1_timeout._value.get() == 1.0, "User1 should have 1 response_timeout event"

        # Check that user2 has 1 response_timeout event
        user2_timeout = user_stats_exporter.timeout_events_total.labels(
            user_ip='192.168.1.120',
            route='/server2',
            timeout_type='response_timeout',
            http_method='POST'
        )
        assert user2_timeout._value.get() == 1.0, "User2 should have 1 response_timeout event"

        # Check that normal request doesn't create timeout event
        # User1 should still have only 1 timeout event (not 2)
        assert user1_timeout._value.get() == 1.0, "User1 should still have only 1 timeout event"

    def test_comprehensive_per_user_metrics_integration(self):
        """Comprehensive integration test for all per-user metrics."""
        # Simulate realistic scenario with multiple users making various requests
        user1_logs = [
            '192.168.1.200 - - [25/Dec/2023:10:00:00 +0000] "GET /server1 HTTP/1.1" 200 1024 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"',
            '192.168.1.200 - - [25/Dec/2023:10:00:01 +0000] "GET /server1 HTTP/1.1" 200 2048 "referer" "user-agent" "x-forwarded-for" rt=0.15 uct="0.08" uht="0.12" urt="0.15"',
            '192.168.1.200 - - [25/Dec/2023:10:00:02 +0000] "POST /server1 HTTP/1.1" 429 0 "referer" "user-agent" "x-forwarded-for" rt=0.01 uct="0.005" uht="0.008" urt="0.01"',
            '192.168.1.200 - - [25/Dec/2023:10:00:03 +0000] "GET /server2 HTTP/1.1" 200 512 "referer" "user-agent" "x-forwarded-for" rt=0.05 uct="0.02" uht="0.03" urt="0.05"',
        ]

        user2_logs = [
            '192.168.1.201 - - [25/Dec/2023:10:00:10 +0000] "GET /server2 HTTP/1.1" 200 4096 "referer" "user-agent" "x-forwarded-for" rt=0.2 uct="0.1" uht="0.15" urt="0.2"',
            '192.168.1.201 - - [25/Dec/2023:10:00:11 +0000] "GET /server2 HTTP/1.1" 504 0 "referer" "user-agent" "x-forwarded-for" rt=0.1 uct="0.05" uht="0.08" urt="0.1"',
            '192.168.1.201 - - [25/Dec/2023:10:00:12 +0000] "GET /server2 HTTP/1.1" 200 8192 "referer" "user-agent" "x-forwarded-for" rt=0.25 uct="0.12" uht="0.18" urt="0.25"',
        ]

        # Process all log lines
        for log_line in user1_logs + user2_logs:
            user_stats_exporter.process_log_line(log_line)

        # Verify User1 metrics
        # Total requests: 4 (2 GET /server1, 1 POST /server1, 1 GET /server2)
        user1_get_server1_200 = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.200',
            status='200',
            method='GET',
            route='/server1'
        )
        assert user1_get_server1_200._value.get(
        ) == 2.0, "User1 should have 2 GET requests to /server1 with status 200"

        user1_post_server1_429 = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.200',
            status='429',
            method='POST',
            route='/server1'
        )
        assert user1_post_server1_429._value.get(
        ) == 1.0, "User1 should have 1 POST request to /server1 with status 429"

        user1_get_server2_200 = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.200',
            status='200',
            method='GET',
            route='/server2'
        )
        assert user1_get_server2_200._value.get(
        ) == 1.0, "User1 should have 1 GET request to /server2 with status 200"

        # User1 bytes: 1024 + 2048 + 0 + 512 = 3584
        user1_bytes = user_stats_exporter.user_bytes_total.labels(
            user_ip='192.168.1.200',
            direction='sent'
        )
        assert user1_bytes._value.get() == 3584.0, "User1 should have 3584 bytes total"

        # User1 rate limit hits: 1
        user1_rate_limit = user_stats_exporter.rate_limit_hits_total.labels(
            user_ip='192.168.1.200',
            route='/server1',
            http_method='POST'
        )
        assert user1_rate_limit._value.get() == 1.0, "User1 should have 1 rate limit hit"

        # Verify User2 metrics
        # Total requests: 3 (2 GET /server2 with 200, 1 GET /server2 with 504)
        user2_get_server2_200 = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.201',
            status='200',
            method='GET',
            route='/server2'
        )
        assert user2_get_server2_200._value.get(
        ) == 2.0, "User2 should have 2 GET requests to /server2 with status 200"

        user2_get_server2_504 = user_stats_exporter.user_requests_total.labels(
            user_ip='192.168.1.201',
            status='504',
            method='GET',
            route='/server2'
        )
        assert user2_get_server2_504._value.get(
        ) == 1.0, "User2 should have 1 GET request to /server2 with status 504"

        # User2 bytes: 4096 + 0 + 8192 = 12288
        user2_bytes = user_stats_exporter.user_bytes_total.labels(
            user_ip='192.168.1.201',
            direction='sent'
        )
        assert user2_bytes._value.get() == 12288.0, "User2 should have 12288 bytes total"

        # User2 timeout events: 1 (504 status)
        user2_timeout = user_stats_exporter.timeout_events_total.labels(
            user_ip='192.168.1.201',
            route='/server2',
            timeout_type='gateway_timeout',
            http_method='GET'
        )
        assert user2_timeout._value.get() == 1.0, "User2 should have 1 gateway_timeout event"

        # Verify active users tracking
        assert user_stats_exporter.active_users['192.168.1.200'] == 4, "User1 should have 4 requests tracked"
        assert user_stats_exporter.active_users['192.168.1.201'] == 3, "User2 should have 3 requests tracked"
        assert len(
            user_stats_exporter.active_users) == 2, "Should have 2 active users"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
