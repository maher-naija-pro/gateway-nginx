#!/bin/sh
# Startup script for nginx that splits stdout to named pipe and stdout
# This allows both docker logs and exporters to read nginx access logs

# Create named pipe for access logs (shared with exporters)
mkfifo -m 0666 /var/log/nginx/access.log 2>/dev/null || true

# Start nginx and filter its output
# Access logs (lines starting with IP addresses) go to both pipe and stdout via tee
# Error logs go to stderr only
nginx -g 'daemon off;' 2>&1 | while IFS= read -r line; do
    # Check if line looks like an access log entry (starts with IP address)
    if echo "$line" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        # Write to both named pipe and stdout using tee
        # Note: This may block if no readers on the pipe, but exporters will start reading
        echo "$line" | tee /var/log/nginx/access.log
    else
        # Output error logs and other messages to stderr
        echo "$line" >&2
    fi
done

