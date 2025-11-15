# Gateway Nginx

A Docker Compose setup with an nginx reverse proxy serving two separate nginx "Hello World" services, each with HTTP and HTTPS support and separate configuration files.

## Architecture

- **nginx-proxy**: Reverse proxy container handling HTTP (port 80) and HTTPS (port 443) with path-based routing
- **nginx-service1**: First backend service accessible via `/server1` route
- **nginx-service2**: Second backend service accessible via `/server2` route

Each service has its own nginx configuration file and serves a "Hello World" HTML page.

## Project Structure

```
gateway-nginx/
├── docker-compose.yml
├── generate-ssl.sh
├── nginx-proxy/
│   ├── nginx.conf              # Main proxy configuration
│   ├── conf.d/
│   │   └── default.conf        # Path-based routing config (/server1, /server2)
│   └── ssl/                    # SSL certificates (generated)
├── nginx-service1/
│   ├── nginx.conf              # Service1 nginx configuration
│   └── html/
│       └── index.html          # Service1 hello world page
└── nginx-service2/
    ├── nginx.conf              # Service2 nginx configuration
    └── html/
        └── index.html          # Service2 hello world page
```

## Setup Instructions

### 1. Generate SSL Certificates

First, generate self-signed SSL certificates for development:

```bash
chmod +x generate-ssl.sh
./generate-ssl.sh
```

This will create SSL certificates in `nginx-proxy/ssl/`:
- `service1.crt` and `service1.key`
- `service2.crt` and `service2.key`

### 2. Access via IP address

No need to modify `/etc/hosts` file. Services are accessed via path-based routing:
- `/server1` for the first service
- `/server2` for the second service

### 3. Start the Services

```bash
docker-compose up -d
```

### 4. Access the Services

The proxy is bound to IP address **80.247.0.31** on ports 80 (HTTP) and 443 (HTTPS).

**Path-based routing:**
- **Service 1**: `/server1` route
- **Service 2**: `/server2` route

#### Service 1
- **HTTP**: http://80.247.0.31/server1
- **HTTPS**: https://80.247.0.31/server1

#### Service 2
- **HTTP**: http://80.247.0.31/server2
- **HTTPS**: https://80.247.0.31/server2

**Note**: Since these are self-signed certificates, your browser will show a security warning. Click "Advanced" and "Proceed to site" to continue.

## Configuration Details

### Proxy Configuration

The nginx proxy (`nginx-proxy/nginx.conf`) includes:
- HTTP server on port 80
- HTTPS server on port 443
- SSL/TLS configuration
- Proxy pass to backend services
- Proper header forwarding

### Service Configurations

Each service has its own nginx configuration:
- `nginx-service1/nginx.conf` - Configuration for service1
- `nginx-service2/nginx.conf` - Configuration for service2

### Path-Based Routing

The proxy uses path-based routing in a single configuration file:
- `nginx-proxy/conf.d/default.conf` - Routes `/server1` to first service and `/server2` to second service

## Useful Commands

```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# View logs for specific service
docker-compose logs -f nginx-proxy
docker-compose logs -f nginx-service1
docker-compose logs -f nginx-service2

# Stop services
docker-compose down

# Restart services
docker-compose restart

# Rebuild and restart
docker-compose up -d --build
```

## Testing

Test the services using curl:

```bash
# Test Service 1 via HTTP
curl http://80.247.0.31/server1

# Test Service 1 via HTTPS
curl -k https://80.247.0.31/server1

# Test Service 2 via HTTP
curl http://80.247.0.31/server2

# Test Service 2 via HTTPS
curl -k https://80.247.0.31/server2

# Test with full path
curl http://80.247.0.31/server1/
curl http://80.247.0.31/server2/
```

## Monitoring Stack

The setup includes a complete observability stack with Prometheus, Tempo, and Grafana:

### Services

- **Prometheus** (port 9090): Metrics collection and storage
- **Grafana** (port 3000): Visualization and dashboards
- **Tempo** (port 3200): Distributed tracing backend
- **Nginx Exporter** (port 9113): Exports nginx metrics to Prometheus

### Access

- **Prometheus UI**: http://localhost:9090
- **Grafana UI**: http://localhost:3000
  - Username: `admin`
  - Password: `admin`
- **Tempo UI**: http://localhost:3200
- **Nginx Exporter Metrics**: http://localhost:9113/metrics
- **User Stats Exporter Metrics**: http://localhost:9114/metrics
- **OpenTelemetry Collector Metrics**: http://localhost:8889/metrics

### Metrics Collection

- Nginx metrics are exposed via `stub_status` on port 8080 (internal)
- Nginx Prometheus Exporter scrapes metrics and converts them to Prometheus format
- Prometheus scrapes metrics from:
  - Nginx Exporter (nginx metrics) - port 9113
  - User Stats Exporter (per-user metrics) - port 9114
  - OpenTelemetry Collector (rate limiting and timeout metrics) - port 8889
  - Prometheus itself - port 9090
  - Tempo - port 3200
  - Grafana - port 3000

### Prometheus Metrics

The following metrics are available in Prometheus:

#### Nginx Standard Metrics (from nginx-prometheus-exporter)

- `nginx_http_requests_total` - Total number of HTTP requests (labels: `status`)
- `nginx_connections_active` - Number of active connections
- `nginx_connections_accepted` - Total number of accepted connections
- `nginx_connections_handled` - Total number of handled connections
- `nginx_connections_reading` - Number of connections reading request headers
- `nginx_connections_writing` - Number of connections writing response
- `nginx_connections_waiting` - Number of idle connections waiting for requests

#### Per-User Metrics (from user-stats-exporter)

- `nginx_user_requests_total` - Total requests per user (labels: `user_ip`, `status`, `method`, `route`)
- `nginx_user_bytes_total` - Total bytes transferred per user (labels: `user_ip`, `direction`)
- `nginx_user_request_duration_seconds` - Request duration histogram per user (labels: `user_ip`, `route`)
- `nginx_user_active_connections` - Active connections per user (labels: `user_ip`)
- `nginx_user_requests_per_second` - Requests per second per user (labels: `user_ip`)
- `nginx_user_last_request_time` - Unix timestamp of last request per user (labels: `user_ip`)

#### Rate Limiting Metrics

- `nginx_rate_limit_hits_total` - Rate limit hits per user (labels: `user_ip`, `route`, `http_method`)
- `nginx_rate_limit_hits_global_total` - Global rate limit hits aggregated (labels: `route`, `http_method`)

#### Timeout Metrics

- `nginx_timeout_events_total` - Timeout events per user (labels: `user_ip`, `route`, `timeout_type`, `http_method`)
- `nginx_timeout_events_global_total` - Global timeout events aggregated (labels: `route`, `timeout_type`, `http_method`)

### Prometheus Query Examples

Query metrics in Prometheus UI (http://localhost:9090) using PromQL:

```promql
# Total requests per second (all status codes)
rate(nginx_http_requests_total[1m])

# Requests per second by status code
rate(nginx_http_requests_total[1m]) by (status)

# Active connections
nginx_connections_active

# Total requests per user
sum(nginx_user_requests_total) by (user_ip)

# Requests per second per user
sum(rate(nginx_user_requests_total[1m])) by (user_ip)

# Rate limit hits per user
sum(nginx_rate_limit_hits_total) by (user_ip)

# Rate limit hits by route
sum(nginx_rate_limit_hits_global_total) by (route)

# Timeout events by type
sum(nginx_timeout_events_global_total) by (timeout_type)

# Request duration percentiles per user (p95)
histogram_quantile(0.95, sum(rate(nginx_user_request_duration_seconds_bucket[5m])) by (user_ip, le))

# Top 10 users by request count
topk(10, sum(nginx_user_requests_total) by (user_ip))

# Error rate (4xx and 5xx status codes)
sum(rate(nginx_http_requests_total{status=~"4..|5.."}[1m]))

# Rate limit hit rate
rate(nginx_rate_limit_hits_global_total[1m])
```

### Checking Metrics with curl

You can query Prometheus metrics directly using curl:

```bash
# List all available metrics
curl -s "http://localhost:9090/api/v1/label/__name__/values" | jq '.data[]' | grep nginx_

# Query a specific metric (example: total requests)
curl -s -G --data-urlencode "query=nginx_http_requests_total" \
  "http://localhost:9090/api/v1/query" | jq '.'

# Query requests per second
curl -s -G --data-urlencode "query=rate(nginx_http_requests_total[1m])" \
  "http://localhost:9090/api/v1/query" | jq '.'

# Query per-user requests
curl -s -G --data-urlencode "query=sum(nginx_user_requests_total) by (user_ip)" \
  "http://localhost:9090/api/v1/query" | jq '.'

# Check Prometheus targets status
curl -s "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

**Quick check script**: Use the provided script for easier metric checking:

```bash
# Check all metrics
./check-prometheus-metrics.sh

# Check specific metric types
./check-prometheus-metrics.sh nginx      # Nginx standard metrics
./check-prometheus-metrics.sh user       # Per-user metrics
./check-prometheus-metrics.sh rate-limit # Rate limiting metrics
./check-prometheus-metrics.sh timeout    # Timeout metrics
./check-prometheus-metrics.sh list       # List all available metrics
./check-prometheus-metrics.sh targets    # Check target status
```

### Grafana Dashboards

- Pre-configured datasources for Prometheus and Tempo
- Nginx Gateway Monitoring dashboard (auto-provisioned)
- Custom dashboards can be added in `monitoring/grafana/dashboards/`

### Distributed Tracing

- Tempo is configured to receive traces via OTLP (OpenTelemetry Protocol)
- HTTP receiver on port 4318
- gRPC receiver on port 4317
- Traces can be queried in Grafana using the Tempo datasource

## Production Considerations

For production use:
1. Replace self-signed certificates with certificates from a trusted CA (Let's Encrypt, etc.)
2. Update server names in configuration files
3. Configure proper firewall rules
4. Enable additional security headers
5. Set up proper logging and monitoring (already configured)
6. Configure rate limiting and DDoS protection (already configured)
7. Change default Grafana admin password
8. Configure authentication for monitoring endpoints
9. Set up alerting rules in Prometheus
10. Configure backup for Prometheus and Grafana data volumes
