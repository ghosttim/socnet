#!/bin/bash

echo "Starting monitoring stack..."

MONITORING_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$MONITORING_DIR"

docker compose -f docker-compose.yml down -v

docker compose -f docker-compose.yml up -d --build

echo "Waiting for Grafana and exporters..."

sleep 20

echo "Monitoring stack ready!"