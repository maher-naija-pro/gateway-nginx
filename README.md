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
- **Nginx Metrics**: http://localhost:9113/metrics

### Metrics Collection

- Nginx metrics are exposed via `stub_status` on port 8080 (internal)
- Nginx Prometheus Exporter scrapes metrics and converts them to Prometheus format
- Prometheus scrapes metrics from:
  - Nginx Exporter (nginx metrics)
  - Prometheus itself
  - Tempo
  - Grafana

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
