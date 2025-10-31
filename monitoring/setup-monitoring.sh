#!/bin/bash

# Comprehensive Monitoring Setup Script
# Sets up Prometheus, Grafana, and health monitoring for IaC drift detection system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/drift-detection.json"
MONITORING_DIR="$PROJECT_ROOT/monitoring"
LOGS_DIR="$PROJECT_ROOT/logs"

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log "Checking dependencies..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    # Check if required Python packages are available
    local required_packages=("psutil" "docker" "requests")
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" &> /dev/null; then
            warning "Python package '$package' is not installed. Installing..."
            pip3 install "$package" || {
                error "Failed to install $package. Please install manually."
                exit 1
            }
        fi
    done
    
    success "All dependencies are available"
}

create_directories() {
    log "Creating monitoring directories..."
    
    local directories=(
        "$LOGS_DIR"
        "$LOGS_DIR/metrics"
        "$LOGS_DIR/prometheus"
        "$LOGS_DIR/grafana"
        "$MONITORING_DIR/data/prometheus"
        "$MONITORING_DIR/data/grafana"
        "$PROJECT_ROOT/backups"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            success "Created directory: $dir"
        fi
    done
}

setup_prometheus() {
    log "Setting up Prometheus monitoring..."
    
    # Create Prometheus data directory
    local prometheus_data="$MONITORING_DIR/data/prometheus"
    mkdir -p "$prometheus_data"
    
    # Set proper permissions
    chmod 777 "$prometheus_data"
    
    # Create docker-compose for monitoring stack
    cat > "$MONITORING_DIR/docker-compose.monitoring.yml" << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: iac-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./alert_rules.yml:/etc/prometheus/alert_rules.yml:ro
      - ./data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
    networks:
      - iac-monitoring
    labels:
      - "project=iac-drift-detection"
      - "component=monitoring"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: iac-grafana
    ports:
      - "3000:3000"
    volumes:
      - ./data/grafana:/var/lib/grafana
      - ./grafana-dashboard.json:/var/lib/grafana/dashboards/iac-dashboard.json:ro
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/iac-dashboard.json
    networks:
      - iac-monitoring
    labels:
      - "project=iac-drift-detection"
      - "component=monitoring"
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: iac-node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - iac-monitoring
    labels:
      - "project=iac-drift-detection"
      - "component=monitoring"
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: iac-cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    privileged: true
    devices:
      - /dev/kmsg
    networks:
      - iac-monitoring
    labels:
      - "project=iac-drift-detection"
      - "component=monitoring"
    restart: unless-stopped

networks:
  iac-monitoring:
    driver: bridge
    name: iac-monitoring-network
EOF

    success "Prometheus monitoring stack configuration created"
}

start_monitoring_stack() {
    log "Starting monitoring stack..."
    
    cd "$MONITORING_DIR"
    
    # Stop any existing containers
    docker-compose -f docker-compose.monitoring.yml down --remove-orphans 2>/dev/null || true
    
    # Start monitoring stack
    docker-compose -f docker-compose.monitoring.yml up -d
    
    # Wait for services to start
    log "Waiting for services to start..."
    sleep 10
    
    # Check if services are running
    if docker-compose -f docker-compose.monitoring.yml ps | grep -q "Up"; then
        success "Monitoring stack started successfully"
        log "Prometheus: http://localhost:9090"
        log "Grafana: http://localhost:3000 (admin/admin123)"
        log "Node Exporter: http://localhost:9100"
        log "cAdvisor: http://localhost:8080"
    else
        error "Failed to start monitoring stack"
        docker-compose -f docker-compose.monitoring.yml logs
        exit 1
    fi
}

start_health_monitoring() {
    log "Starting health monitoring service..."
    
    cd "$MONITORING_DIR"
    
    # Install Python dependencies if not already installed
    local required_packages=("psutil" "docker" "requests" "prometheus_client")
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" &> /dev/null; then
            log "Installing Python package: $package"
            pip3 install "$package"
        fi
    done
    
    # Start health monitor in background
    nohup python3 health_monitor.py --monitor --config "$CONFIG_FILE" --interval 60 > "$LOGS_DIR/health-monitor.log" 2>&1 &
    
    local health_pid=$!
    echo $health_pid > "$LOGS_DIR/health-monitor.pid"
    
    # Wait a moment and check if it's still running
    sleep 3
    if kill -0 $health_pid 2>/dev/null; then
        success "Health monitoring service started (PID: $health_pid)"
    else
        error "Failed to start health monitoring service"
        cat "$LOGS_DIR/health-monitor.log"
        exit 1
    fi
}

setup_monitoring_cron() {
    log "Setting up monitoring cron jobs..."
    
    # Create cron job for health checks
    local cron_entry="*/5 * * * * cd $MONITORING_DIR && python3 health_monitor.py --report --config $CONFIG_FILE >> $LOGS_DIR/health-reports.log 2>&1"
    
    # Add to user's crontab if not already present
    if ! crontab -l 2>/dev/null | grep -q "health_monitor.py"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        success "Health monitoring cron job added"
    else
        log "Health monitoring cron job already exists"
    fi
}

show_monitoring_status() {
    log "Monitoring System Status:"
    echo
    
    # Check Docker containers
    echo "=== Docker Containers ==="
    docker ps --filter "label=project=iac-drift-detection" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    
    # Check health monitor process
    echo "=== Health Monitor Process ==="
    if [[ -f "$LOGS_DIR/health-monitor.pid" ]]; then
        local pid=$(cat "$LOGS_DIR/health-monitor.pid")
        if kill -0 $pid 2>/dev/null; then
            echo "Health monitor is running (PID: $pid)"
        else
            echo "Health monitor is not running"
        fi
    else
        echo "Health monitor PID file not found"
    fi
    echo
    
    # Check monitoring endpoints
    echo "=== Service Endpoints ==="
    local endpoints=(
        "Prometheus:http://localhost:9090"
        "Grafana:http://localhost:3000"
        "Node Exporter:http://localhost:9100"
        "cAdvisor:http://localhost:8080"
    )
    
    for endpoint in "${endpoints[@]}"; do
        local name="${endpoint%%:*}"
        local url="${endpoint#*:}"
        
        if curl -s --max-time 5 "$url" >/dev/null 2>&1; then
            echo -e "$name: ${GREEN}✓ Available${NC} ($url)"
        else
            echo -e "$name: ${RED}✗ Unavailable${NC} ($url)"
        fi
    done
    echo
    
    # Show recent logs
    echo "=== Recent Health Monitor Logs ==="
    if [[ -f "$LOGS_DIR/health-monitor.log" ]]; then
        tail -5 "$LOGS_DIR/health-monitor.log"
    else
        echo "No health monitor logs found"
    fi
}

stop_monitoring() {
    log "Stopping monitoring services..."
    
    cd "$MONITORING_DIR"
    
    # Stop Docker containers
    docker-compose -f docker-compose.monitoring.yml down --remove-orphans
    
    # Stop health monitor process
    if [[ -f "$LOGS_DIR/health-monitor.pid" ]]; then
        local pid=$(cat "$LOGS_DIR/health-monitor.pid")
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            rm "$LOGS_DIR/health-monitor.pid"
            success "Health monitor process stopped"
        fi
    fi
    
    success "All monitoring services stopped"
}

show_help() {
    echo "IaC Drift Detection - Monitoring Setup Script"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  start     Start all monitoring services"
    echo "  stop      Stop all monitoring services"
    echo "  restart   Restart all monitoring services"
    echo "  status    Show monitoring system status"
    echo "  setup     Initial setup (create directories, install dependencies)"
    echo "  help      Show this help message"
    echo
    echo "Examples:"
    echo "  $0 setup     # Initial setup"
    echo "  $0 start     # Start monitoring"
    echo "  $0 status    # Check status"
    echo
}

# Main execution
main() {
    local action="${1:-help}"
    
    case "$action" in
        "setup")
            log "Starting monitoring setup..."
            check_dependencies
            create_directories
            setup_prometheus
            success "Monitoring setup completed!"
            ;;
        "start")
            log "Starting monitoring services..."
            check_dependencies
            create_directories
            setup_prometheus
            start_monitoring_stack
            start_health_monitoring
            setup_monitoring_cron
            show_monitoring_status
            success "All monitoring services started!"
            ;;
        "stop")
            stop_monitoring
            ;;
        "restart")
            stop_monitoring
            sleep 2
            "$0" start
            ;;
        "status")
            show_monitoring_status
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Execute main function with all arguments
main "$@"