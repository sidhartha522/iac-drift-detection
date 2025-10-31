#!/bin/bash
# Continuous Drift Detection Monitor
# This script runs drift detection continuously at specified intervals

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/drift-detection.json"
DRIFT_DETECTOR="${SCRIPT_DIR}/drift-detector.py"
LOG_FILE="${SCRIPT_DIR}/../../logs/drift-monitor.log"
PID_FILE="${SCRIPT_DIR}/../../logs/drift-monitor.pid"

# Default values
DEFAULT_INTERVAL=300  # 5 minutes
DEFAULT_MAX_FAILURES=5

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [MONITOR] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Function to cleanup on exit
cleanup() {
    log "Drift monitor stopping..."
    rm -f "$PID_FILE"
    exit 0
}

# Function to check if monitor is already running
check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Drift monitor is already running (PID: $pid)"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi
}

# Function to read configuration
read_config() {
    local interval
    local config_interval
    
    if [[ -f "$CONFIG_FILE" ]]; then
        config_interval=$(python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE') as f:
        config = json.load(f)
    print(config.get('monitoring', {}).get('check_interval', $DEFAULT_INTERVAL))
except:
    print($DEFAULT_INTERVAL)
" 2>/dev/null || echo "$DEFAULT_INTERVAL")
        interval=$config_interval
    else
        interval=$DEFAULT_INTERVAL
    fi
    
    echo "$interval"
}

# Function to run single drift detection
run_drift_check() {
    local start_time
    local end_time
    local duration
    local exit_code
    
    start_time=$(date +%s)
    
    log "Starting drift detection check..."
    
    # Run drift detector
    if python3 "$DRIFT_DETECTOR" --config "$CONFIG_FILE" --quiet; then
        exit_code=0
        log "Drift check completed successfully - No drift detected"
    else
        exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
            log "Drift check completed - Drift detected!"
        else
            error "Drift check failed with exit code: $exit_code"
        fi
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "Drift check took ${duration} seconds"
    
    return $exit_code
}

# Function to start continuous monitoring
start_monitor() {
    local interval
    local failure_count=0
    local max_failures=$DEFAULT_MAX_FAILURES
    local last_success=$(date +%s)
    
    # Setup signal handlers
    trap cleanup SIGTERM SIGINT
    
    # Check if already running
    check_running
    
    # Create necessary directories
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$PID_FILE")"
    
    # Save PID
    echo $$ > "$PID_FILE"
    
    # Read configuration
    interval=$(read_config)
    
    log "Starting drift detection monitor"
    log "Check interval: ${interval} seconds"
    log "Max consecutive failures: $max_failures"
    log "PID: $$"
    
    while true; do
        if run_drift_check; then
            failure_count=0
            last_success=$(date +%s)
        else
            failure_count=$((failure_count + 1))
            error "Drift check failed ($failure_count/$max_failures)"
            
            if [[ $failure_count -ge $max_failures ]]; then
                error "Maximum consecutive failures reached. Stopping monitor."
                break
            fi
        fi
        
        # Check if we should send a heartbeat notification
        local current_time
        current_time=$(date +%s)
        local time_since_success=$((current_time - last_success))
        
        # Send heartbeat every hour if configured
        if [[ $((time_since_success % 3600)) -eq 0 && $time_since_success -gt 0 ]]; then
            log "Heartbeat: Monitor running for $(( time_since_success / 60 )) minutes"
        fi
        
        log "Waiting ${interval} seconds until next check..."
        sleep "$interval"
    done
    
    cleanup
}

# Function to stop monitor
stop_monitor() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            log "Stopping drift monitor (PID: $pid)"
            kill "$pid"
            
            # Wait for process to stop
            local count=0
            while kill -0 "$pid" 2>/dev/null && [[ $count -lt 30 ]]; do
                sleep 1
                count=$((count + 1))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                log "Force killing drift monitor"
                kill -9 "$pid"
            fi
            
            rm -f "$PID_FILE"
            log "Drift monitor stopped"
        else
            log "Drift monitor is not running"
            rm -f "$PID_FILE"
        fi
    else
        log "No PID file found, drift monitor is not running"
    fi
}

# Function to show status
show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            echo "Drift monitor is running (PID: $pid)"
            
            # Show recent log entries
            if [[ -f "$LOG_FILE" ]]; then
                echo "Recent log entries:"
                tail -10 "$LOG_FILE"
            fi
        else
            echo "Drift monitor PID file exists but process is not running"
            rm -f "$PID_FILE"
        fi
    else
        echo "Drift monitor is not running"
    fi
}

# Function to run once
run_once() {
    log "Running single drift detection check..."
    
    if run_drift_check; then
        echo "✅ No drift detected"
        exit 0
    else
        exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
            echo "⚠️  Drift detected!"
            exit 1
        else
            echo "❌ Drift check failed"
            exit $exit_code
        fi
    fi
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    start       Start continuous drift monitoring (default)
    stop        Stop drift monitoring
    restart     Restart drift monitoring
    status      Show monitor status
    once        Run drift detection once and exit

Options:
    -h, --help  Show this help message

Configuration is read from: $CONFIG_FILE
Logs are written to: $LOG_FILE
EOF
}

# Main script logic
case "${1:-start}" in
    start)
        start_monitor
        ;;
    stop)
        stop_monitor
        ;;
    restart)
        stop_monitor
        sleep 2
        start_monitor
        ;;
    status)
        show_status
        ;;
    once)
        run_once
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac