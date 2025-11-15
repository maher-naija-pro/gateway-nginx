#!/bin/bash

# Script to generate self-signed SSL certificates for development
# Includes IP address 80.247.0.31 in Subject Alternative Name (SAN)

SSL_DIR="./nginx-proxy/ssl"
mkdir -p "$SSL_DIR"

# Generate certificate for service1 with IP address in SAN
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/service1.key" \
    -out "$SSL_DIR/service1.crt" \
    -config "$SSL_DIR/openssl-service1.conf" \
    -extensions v3_req

# Generate certificate for service2 with IP address in SAN
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/service2.key" \
    -out "$SSL_DIR/service2.crt" \
    -config "$SSL_DIR/openssl-service2.conf" \
    -extensions v3_req

echo "SSL certificates generated successfully in $SSL_DIR"
echo "Certificates include IP address 80.247.0.31 in Subject Alternative Name"
echo "Note: These are self-signed certificates for development only"

