#!/bin/bash
# Remediation Workflow Manager
# Handles approval workflows and orchestrates remediation tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config/drift-detection.json"
APPROVALS_DIR="${SCRIPT_DIR}/../../config/approvals"
LOG_FILE="${SCRIPT_DIR}/../../logs/remediation-workflow.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WORKFLOW] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Create necessary directories
mkdir -p "$APPROVALS_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Function to create approval request
create_approval_request() {
    local drift_report="$1"
    local approval_id
    approval_id="approval_$(date +%s)"
    local approval_file="${APPROVALS_DIR}/${approval_id}.json"
    
    log "Creating approval request: $approval_id"
    
    # Extract drift summary from report
    local drift_summary
    drift_summary=$(python3 -c "
import json, sys
try:
    with open('$drift_report') as f:
        report = json.load(f)
    print(f\"{len(report.get('drift_details', []))} issues detected\")
    for detail in report.get('drift_details', [])[:5]:
        print(f\"- {detail.get('type', 'unknown')}: {detail.get('message', 'No message')}\")
except Exception as e:
    print(f\"Error reading report: {e}\")
" 2>/dev/null)
    
    # Create approval request
    cat > "$approval_file" << EOF
{
    "approval_id": "$approval_id",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "pending",
    "drift_report_file": "$drift_report",
    "summary": "$drift_summary",
    "requested_actions": [
        "terraform_apply",
        "container_remediation"
    ],
    "approvers": [],
    "expires_at": "$(date -u -d '+4 hours' +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Approval request created: $approval_file"
    echo "$approval_id"
}

# Function to send approval notification
send_approval_notification() {
    local approval_id="$1"
    local approval_file="${APPROVALS_DIR}/${approval_id}.json"
    
    if [[ ! -f "$approval_file" ]]; then
        error "Approval file not found: $approval_file"
        return 1
    fi
    
    # Read webhook URL from config
    local webhook_url
    webhook_url=$(python3 -c "
import json
try:
    with open('$CONFIG_FILE') as f:
        config = json.load(f)
    print(config.get('monitoring', {}).get('webhook_url', ''))
except:
    print('')
" 2>/dev/null)
    
    if [[ -z "$webhook_url" ]]; then
        log "No webhook URL configured, cannot send approval notification"
        return 0
    fi
    
    # Get approval details
    local summary
    summary=$(python3 -c "
import json
with open('$approval_file') as f:
    approval = json.load(f)
print(approval.get('summary', 'No summary available'))
" 2>/dev/null)
    
    # Send notification
    local message
    message="🔧 *Remediation Approval Required*

**Approval ID:** $approval_id
**Environment:** $(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('environment','dev'))" 2>/dev/null)

**Drift Summary:**
$summary

**Actions Required:**
• Terraform Apply
• Container Remediation

**To approve:** \`./remediation-workflow.sh approve $approval_id\`
**To reject:** \`./remediation-workflow.sh reject $approval_id\`

**Expires:** $(python3 -c "
import json
with open('$approval_file') as f:
    approval = json.load(f)
print(approval.get('expires_at', 'Unknown'))
" 2>/dev/null)"
    
    # Send via webhook
    python3 -c "
import requests, json
try:
    payload = {
        'text': '''$message''',
        'username': 'IaC Remediation Workflow',
        'icon_emoji': ':gear:'
    }
    response = requests.post('$webhook_url', json=payload, timeout=10)
    print('Notification sent successfully' if response.status_code == 200 else f'Failed: {response.status_code}')
except Exception as e:
    print(f'Failed to send notification: {e}')
" 2>/dev/null || log "Failed to send approval notification"
}

# Function to approve remediation
approve_remediation() {
    local approval_id="$1"
    local approver="${2:-system}"
    local approval_file="${APPROVALS_DIR}/${approval_id}.json"
    
    if [[ ! -f "$approval_file" ]]; then
        error "Approval request not found: $approval_id"
        return 1
    fi
    
    log "Approving remediation request: $approval_id by $approver"
    
    # Update approval status
    python3 -c "
import json
from datetime import datetime

with open('$approval_file') as f:
    approval = json.load(f)

approval['status'] = 'approved'
approval['approved_at'] = datetime.utcnow().isoformat() + 'Z'
approval['approved_by'] = '$approver'

with open('$approval_file', 'w') as f:
    json.dump(approval, f, indent=2)
"
    
    # Execute remediation
    local drift_report
    drift_report=$(python3 -c "
import json
with open('$approval_file') as f:
    approval = json.load(f)
print(approval.get('drift_report_file', ''))
" 2>/dev/null)
    
    if [[ -n "$drift_report" && -f "$drift_report" ]]; then
        log "Executing approved remediation..."
        python3 "${SCRIPT_DIR}/auto-remediate.py" \
            --config "$CONFIG_FILE" \
            --drift-report "$drift_report" \
            --auto-approve
    else
        error "Drift report not found: $drift_report"
        return 1
    fi
}

# Function to reject remediation
reject_remediation() {
    local approval_id="$1"
    local rejector="${2:-system}"
    local reason="${3:-No reason provided}"
    local approval_file="${APPROVALS_DIR}/${approval_id}.json"
    
    if [[ ! -f "$approval_file" ]]; then
        error "Approval request not found: $approval_id"
        return 1
    fi
    
    log "Rejecting remediation request: $approval_id by $rejector"
    
    # Update approval status
    python3 -c "
import json
from datetime import datetime

with open('$approval_file') as f:
    approval = json.load(f)

approval['status'] = 'rejected'
approval['rejected_at'] = datetime.utcnow().isoformat() + 'Z'
approval['rejected_by'] = '$rejector'
approval['rejection_reason'] = '$reason'

with open('$approval_file', 'w') as f:
    json.dump(approval, f, indent=2)
"
    
    log "Remediation request rejected: $reason"
}

# Function to check for expired approvals
cleanup_expired_approvals() {
    log "Checking for expired approval requests..."
    
    local current_time
    current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    for approval_file in "$APPROVALS_DIR"/*.json; do
        if [[ -f "$approval_file" ]]; then
            local status
            local expires_at
            local approval_id
            
            status=$(python3 -c "
import json
try:
    with open('$approval_file') as f:
        approval = json.load(f)
    print(approval.get('status', 'unknown'))
except:
    print('error')
" 2>/dev/null)
            
            expires_at=$(python3 -c "
import json
try:
    with open('$approval_file') as f:
        approval = json.load(f)
    print(approval.get('expires_at', ''))
except:
    print('')
" 2>/dev/null)
            
            approval_id=$(basename "$approval_file" .json)
            
            if [[ "$status" == "pending" && "$expires_at" < "$current_time" ]]; then
                log "Expiring approval request: $approval_id"
                reject_remediation "$approval_id" "system" "Approval request expired"
            fi
        fi
    done
}

# Function to list pending approvals
list_approvals() {
    local status="${1:-all}"
    
    echo "Remediation Approval Requests:"
    echo "=============================="
    
    for approval_file in "$APPROVALS_DIR"/*.json; do
        if [[ -f "$approval_file" ]]; then
            python3 -c "
import json
try:
    with open('$approval_file') as f:
        approval = json.load(f)
    
    if '$status' == 'all' or approval.get('status', '') == '$status':
        print(f\"ID: {approval.get('approval_id', 'unknown')}\")
        print(f\"Status: {approval.get('status', 'unknown')}\")
        print(f\"Created: {approval.get('created_at', 'unknown')}\")
        print(f\"Summary: {approval.get('summary', 'No summary')}\")
        print(f\"Expires: {approval.get('expires_at', 'unknown')}\")
        print('-' * 40)
except Exception as e:
    print(f'Error reading {approval_file}: {e}')
"
        fi
    done
}

# Function to run automated remediation workflow
run_automated_workflow() {
    log "Starting automated remediation workflow..."
    
    # Run drift detection
    log "Running drift detection..."
    if ! python3 "${SCRIPT_DIR}/../drift-detection/drift-detector.py" --config "$CONFIG_FILE"; then
        log "Drift detected, initiating approval workflow..."
        
        # Get latest drift report
        local latest_report
        latest_report=$(ls -t "${SCRIPT_DIR}/../../logs"/drift-report-*.json 2>/dev/null | head -1)
        
        if [[ -n "$latest_report" ]]; then
            # Create approval request
            local approval_id
            approval_id=$(create_approval_request "$latest_report")
            
            # Send notification
            send_approval_notification "$approval_id"
            
            log "Approval workflow initiated: $approval_id"
        else
            error "No drift report found"
            return 1
        fi
    else
        log "No drift detected, no remediation needed"
    fi
    
    # Clean up expired approvals
    cleanup_expired_approvals
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    run             Run automated workflow (detect -> approve -> remediate)
    approve ID      Approve remediation request
    reject ID       Reject remediation request  
    list [STATUS]   List approval requests (pending/approved/rejected/all)
    cleanup         Clean up expired approvals
    
Examples:
    $0 run                                    # Run full automated workflow
    $0 approve approval_1635789123           # Approve specific request
    $0 reject approval_1635789123            # Reject specific request
    $0 list pending                          # List pending approvals
EOF
}

# Main script logic
case "${1:-run}" in
    run)
        run_automated_workflow
        ;;
    approve)
        if [[ -z "${2:-}" ]]; then
            echo "Error: Approval ID required"
            usage
            exit 1
        fi
        approve_remediation "$2" "${3:-$(whoami)}"
        ;;
    reject)
        if [[ -z "${2:-}" ]]; then
            echo "Error: Approval ID required"
            usage
            exit 1
        fi
        reject_remediation "$2" "${3:-$(whoami)}" "${4:-Manual rejection}"
        ;;
    list)
        list_approvals "${2:-all}"
        ;;
    cleanup)
        cleanup_expired_approvals
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