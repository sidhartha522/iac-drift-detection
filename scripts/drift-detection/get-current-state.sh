#!/bin/bash
# Get Current Infrastructure State Script
# This script captures the current state of Docker infrastructure

set -euo pipefail

ENVIRONMENT="${1:-dev}"
CONFIG_FILE="${2:-../config/drift-detection.json}"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" >&2
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
}

# Initialize output
output_json="{}"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    error "Docker is not running or not accessible"
    output_json='{"error": "Docker not accessible", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    echo "$output_json"
    exit 1
fi

log "Capturing current infrastructure state for environment: $ENVIRONMENT"

# Get Docker containers
containers=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" --filter "label=environment=$ENVIRONMENT" 2>/dev/null || echo "")

# Get Docker networks
networks=$(docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" --filter "label=environment=$ENVIRONMENT" 2>/dev/null || echo "")

# Get Docker volumes
volumes=$(docker volume ls --format "table {{.Name}}\t{{.Driver}}" --filter "label=environment=$ENVIRONMENT" 2>/dev/null || echo "")

# Get container health status
container_health=()
while IFS= read -r container_name; do
    if [[ -n "$container_name" && "$container_name" != "NAMES" ]]; then
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown")
        container_health+=("{\"name\": \"$container_name\", \"health\": \"$health\"}")
    fi
done <<< "$(docker ps --format "{{.Names}}" --filter "label=environment=$ENVIRONMENT" 2>/dev/null || echo "")"

# Build JSON output
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
container_count=$(docker ps -q --filter "label=environment=$ENVIRONMENT" | wc -l | tr -d ' ')
network_count=$(docker network ls -q --filter "label=environment=$ENVIRONMENT" | wc -l | tr -d ' ')
volume_count=$(docker volume ls -q --filter "label=environment=$ENVIRONMENT" | wc -l | tr -d ' ')

output_json=$(cat <<EOF
{
    "timestamp": "$timestamp",
    "environment": "$ENVIRONMENT", 
    "docker_status": "running",
    "containers": {
        "count": $container_count,
        "health": [$(IFS=,; echo "${container_health[*]}")],
        "list": "$(echo "$containers" | base64 -w 0)"
    },
    "networks": {
        "count": $network_count,
        "list": "$(echo "$networks" | base64 -w 0)"
    },
    "volumes": {
        "count": $volume_count, 
        "list": "$(echo "$volumes" | base64 -w 0)"
    }
}
EOF
)

echo "$output_json"
log "Infrastructure state captured successfully"