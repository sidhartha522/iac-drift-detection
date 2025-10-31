#!/usr/bin/env python3
"""
Notification Manager for IaC Drift Detection
Handles multiple notification channels: Slack, Email, Teams, Discord, etc.
"""

import os
import sys
import json
import smtplib
import logging
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Dict, List, Optional, Any
import requests
from jinja2 import Template

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NotificationManager:
    def __init__(self, config_file='../../config/drift-detection.json'):
        self.config_file = config_file
        self.config = self.load_config()
        self.notification_config = self.config.get('notifications', {})
        
    def load_config(self):
        """Load notification configuration"""
        try:
            with open(self.config_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {self.config_file}")
            return {}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in config file: {e}")
            return {}
    
    def send_notification(self, notification_type: str, data: Dict[str, Any], channels: Optional[List[str]] = None):
        """Send notification to specified channels"""
        if not channels:
            channels = self.notification_config.get('default_channels', ['slack'])
        
        success_count = 0
        total_channels = len(channels)
        
        for channel in channels:
            try:
                if channel == 'slack':
                    success = self.send_slack_notification(notification_type, data)
                elif channel == 'email':
                    success = self.send_email_notification(notification_type, data)
                elif channel == 'teams':
                    success = self.send_teams_notification(notification_type, data)
                elif channel == 'discord':
                    success = self.send_discord_notification(notification_type, data)
                elif channel == 'webhook':
                    success = self.send_webhook_notification(notification_type, data)
                else:
                    logger.warning(f"Unknown notification channel: {channel}")
                    success = False
                
                if success:
                    success_count += 1
                    logger.info(f"Successfully sent {notification_type} notification to {channel}")
                else:
                    logger.error(f"Failed to send {notification_type} notification to {channel}")
                    
            except Exception as e:
                logger.error(f"Error sending notification to {channel}: {e}")
        
        return success_count, total_channels
    
    def send_slack_notification(self, notification_type: str, data: Dict[str, Any]) -> bool:
        """Send Slack notification"""
        webhook_url = self.notification_config.get('slack', {}).get('webhook_url')
        if not webhook_url:
            logger.warning("Slack webhook URL not configured")
            return False
        
        message = self.format_slack_message(notification_type, data)
        
        try:
            response = requests.post(webhook_url, json=message, timeout=10)
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to send Slack notification: {e}")
            return False
    
    def send_email_notification(self, notification_type: str, data: Dict[str, Any]) -> bool:
        """Send email notification"""
        email_config = self.notification_config.get('email', {})
        
        if not all([
            email_config.get('smtp_server'),
            email_config.get('smtp_port'),
            email_config.get('username'),
            email_config.get('password'),
            email_config.get('recipients')
        ]):
            logger.warning("Email configuration incomplete")
            return False
        
        try:
            subject, body = self.format_email_message(notification_type, data)
            
            msg = MIMEMultipart()
            msg['From'] = email_config['username']
            msg['To'] = ', '.join(email_config['recipients'])
            msg['Subject'] = subject
            
            msg.attach(MIMEText(body, 'html'))
            
            with smtplib.SMTP(email_config['smtp_server'], email_config['smtp_port']) as server:
                server.starttls()
                server.login(email_config['username'], email_config['password'])
                server.send_message(msg)
            
            return True
        except Exception as e:
            logger.error(f"Failed to send email notification: {e}")
            return False
    
    def send_teams_notification(self, notification_type: str, data: Dict[str, Any]) -> bool:
        """Send Microsoft Teams notification"""
        webhook_url = self.notification_config.get('teams', {}).get('webhook_url')
        if not webhook_url:
            logger.warning("Teams webhook URL not configured")
            return False
        
        message = self.format_teams_message(notification_type, data)
        
        try:
            response = requests.post(webhook_url, json=message, timeout=10)
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to send Teams notification: {e}")
            return False
    
    def send_discord_notification(self, notification_type: str, data: Dict[str, Any]) -> bool:
        """Send Discord notification"""
        webhook_url = self.notification_config.get('discord', {}).get('webhook_url')
        if not webhook_url:
            logger.warning("Discord webhook URL not configured")
            return False
        
        message = self.format_discord_message(notification_type, data)
        
        try:
            response = requests.post(webhook_url, json=message, timeout=10)
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to send Discord notification: {e}")
            return False
    
    def send_webhook_notification(self, notification_type: str, data: Dict[str, Any]) -> bool:
        """Send generic webhook notification"""
        webhook_config = self.notification_config.get('webhook', {})
        webhook_url = webhook_config.get('url')
        
        if not webhook_url:
            logger.warning("Generic webhook URL not configured")
            return False
        
        payload = {
            'timestamp': datetime.utcnow().isoformat(),
            'notification_type': notification_type,
            'environment': self.config.get('environment', 'unknown'),
            'data': data
        }
        
        headers = webhook_config.get('headers', {})
        
        try:
            response = requests.post(webhook_url, json=payload, headers=headers, timeout=10)
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to send webhook notification: {e}")
            return False
    
    def format_slack_message(self, notification_type: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Format message for Slack"""
        color = self.get_notification_color(notification_type)
        icon = self.get_notification_icon(notification_type)
        
        if notification_type == 'drift_detected':
            return {
                "text": f"{icon} Infrastructure Drift Detected",
                "attachments": [{
                    "color": color,
                    "fields": [
                        {
                            "title": "Environment",
                            "value": data.get('environment', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Issues Found",
                            "value": str(data.get('issue_count', 0)),
                            "short": True
                        },
                        {
                            "title": "Severity",
                            "value": data.get('max_severity', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Timestamp",
                            "value": data.get('timestamp', 'unknown'),
                            "short": True
                        }
                    ],
                    "text": self.format_drift_summary(data.get('drift_details', [])),
                    "footer": "IaC Drift Detection System"
                }]
            }
        
        elif notification_type == 'remediation_started':
            return {
                "text": f"{icon} Automated Remediation Started",
                "attachments": [{
                    "color": color,
                    "fields": [
                        {
                            "title": "Environment",
                            "value": data.get('environment', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Remediation ID",
                            "value": data.get('remediation_id', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Actions Planned",
                            "value": str(len(data.get('planned_actions', []))),
                            "short": True
                        }
                    ],
                    "text": "Automated remediation process has been initiated.",
                    "footer": "IaC Remediation Engine"
                }]
            }
        
        elif notification_type == 'remediation_completed':
            success = data.get('success', False)
            return {
                "text": f"{icon} Remediation {'Completed Successfully' if success else 'Failed'}",
                "attachments": [{
                    "color": "good" if success else "danger",
                    "fields": [
                        {
                            "title": "Environment",
                            "value": data.get('environment', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Status",
                            "value": "Success" if success else "Failed",
                            "short": True
                        },
                        {
                            "title": "Duration",
                            "value": data.get('duration', 'unknown'),
                            "short": True
                        }
                    ],
                    "text": data.get('summary', 'No summary available'),
                    "footer": "IaC Remediation Engine"
                }]
            }
        
        elif notification_type == 'system_health':
            return {
                "text": f"{icon} System Health Report",
                "attachments": [{
                    "color": color,
                    "fields": [
                        {
                            "title": "Environment",
                            "value": data.get('environment', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Status",
                            "value": data.get('status', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Uptime",
                            "value": data.get('uptime', 'unknown'),
                            "short": True
                        },
                        {
                            "title": "Last Check",
                            "value": data.get('last_check', 'unknown'),
                            "short": True
                        }
                    ],
                    "footer": "IaC Health Monitor"
                }]
            }
        
        # Default message format
        return {
            "text": f"{icon} {notification_type.replace('_', ' ').title()}",
            "attachments": [{
                "color": color,
                "text": json.dumps(data, indent=2),
                "footer": "IaC Drift Detection System"
            }]
        }
    
    def format_teams_message(self, notification_type: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Format message for Microsoft Teams"""
        color = self.get_notification_color(notification_type)
        
        return {
            "@type": "MessageCard",
            "@context": "https://schema.org/extensions",
            "summary": f"IaC {notification_type.replace('_', ' ').title()}",
            "themeColor": color.replace('#', ''),
            "sections": [{
                "activityTitle": f"Infrastructure Alert: {notification_type.replace('_', ' ').title()}",
                "activitySubtitle": f"Environment: {data.get('environment', 'unknown')}",
                "facts": [
                    {"name": "Timestamp", "value": data.get('timestamp', 'unknown')},
                    {"name": "Status", "value": data.get('status', 'unknown')}
                ]
            }]
        }
    
    def format_discord_message(self, notification_type: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Format message for Discord"""
        color = int(self.get_notification_color(notification_type).replace('#', ''), 16)
        
        return {
            "embeds": [{
                "title": f"IaC {notification_type.replace('_', ' ').title()}",
                "description": f"Environment: {data.get('environment', 'unknown')}",
                "color": color,
                "timestamp": datetime.utcnow().isoformat(),
                "fields": [
                    {
                        "name": "Status",
                        "value": data.get('status', 'unknown'),
                        "inline": True
                    },
                    {
                        "name": "Timestamp",
                        "value": data.get('timestamp', 'unknown'),
                        "inline": True
                    }
                ]
            }]
        }
    
    def format_email_message(self, notification_type: str, data: Dict[str, Any]) -> tuple:
        """Format message for email"""
        subject = f"IaC Alert: {notification_type.replace('_', ' ').title()} - {data.get('environment', 'unknown')}"
        
        # HTML email template
        html_template = Template("""
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                .header { background-color: {{ color }}; color: white; padding: 15px; border-radius: 5px; }
                .content { padding: 20px; border: 1px solid #ddd; border-radius: 5px; margin-top: 10px; }
                .field { margin: 10px 0; }
                .label { font-weight: bold; }
                .footer { margin-top: 20px; font-size: 12px; color: #666; }
            </style>
        </head>
        <body>
            <div class="header">
                <h2>{{ title }}</h2>
            </div>
            <div class="content">
                <div class="field">
                    <span class="label">Environment:</span> {{ environment }}
                </div>
                <div class="field">
                    <span class="label">Timestamp:</span> {{ timestamp }}
                </div>
                {% for key, value in data.items() %}
                <div class="field">
                    <span class="label">{{ key.replace('_', ' ').title() }}:</span> {{ value }}
                </div>
                {% endfor %}
            </div>
            <div class="footer">
                This is an automated notification from the IaC Drift Detection System.
            </div>
        </body>
        </html>
        """)
        
        body = html_template.render(
            title=f"IaC {notification_type.replace('_', ' ').title()}",
            color=self.get_notification_color(notification_type),
            environment=data.get('environment', 'unknown'),
            timestamp=data.get('timestamp', datetime.utcnow().isoformat()),
            data=data
        )
        
        return subject, body
    
    def format_drift_summary(self, drift_details: List[Dict[str, Any]]) -> str:
        """Format drift details for display"""
        if not drift_details:
            return "No drift details available"
        
        summary_lines = []
        for detail in drift_details[:5]:  # Show first 5 items
            severity = detail.get('severity', 'unknown')
            message = detail.get('message', 'No message')
            summary_lines.append(f"• {severity.upper()}: {message}")
        
        if len(drift_details) > 5:
            summary_lines.append(f"... and {len(drift_details) - 5} more issues")
        
        return '\n'.join(summary_lines)
    
    def get_notification_color(self, notification_type: str) -> str:
        """Get color for notification type"""
        colors = {
            'drift_detected': '#FF6B6B',      # Red
            'remediation_started': '#4ECDC4',  # Teal
            'remediation_completed': '#45B7D1', # Blue
            'remediation_failed': '#FF6B6B',   # Red
            'system_health': '#96CEB4',        # Green
            'approval_required': '#FFEAA7',    # Yellow
            'backup_created': '#A29BFE',       # Purple
            'rollback_initiated': '#FD79A8'    # Pink
        }
        return colors.get(notification_type, '#74B9FF')  # Default blue
    
    def get_notification_icon(self, notification_type: str) -> str:
        """Get emoji icon for notification type"""
        icons = {
            'drift_detected': '🚨',
            'remediation_started': '🔧',
            'remediation_completed': '✅',
            'remediation_failed': '❌',
            'system_health': '💚',
            'approval_required': '⚠️',
            'backup_created': '💾',
            'rollback_initiated': '🔄'
        }
        return icons.get(notification_type, '📢')
    
    def send_test_notification(self, channels: Optional[List[str]] = None) -> bool:
        """Send a test notification to verify configuration"""
        test_data = {
            'environment': self.config.get('environment', 'test'),
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'test',
            'message': 'This is a test notification from the IaC Drift Detection System'
        }
        
        success_count, total_channels = self.send_notification('system_health', test_data, channels)
        
        logger.info(f"Test notification sent to {success_count}/{total_channels} channels")
        return success_count > 0

# CLI interface
def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='IaC Notification Manager')
    parser.add_argument('--config', default='../../config/drift-detection.json',
                       help='Path to configuration file')
    parser.add_argument('--type', required=True,
                       help='Notification type (drift_detected, remediation_started, etc.)')
    parser.add_argument('--data', type=json.loads, default='{}',
                       help='Notification data as JSON string')
    parser.add_argument('--channels', nargs='+',
                       help='Notification channels (slack, email, teams, discord)')
    parser.add_argument('--test', action='store_true',
                       help='Send test notification')
    
    args = parser.parse_args()
    
    manager = NotificationManager(args.config)
    
    if args.test:
        success = manager.send_test_notification(args.channels)
        sys.exit(0 if success else 1)
    else:
        success_count, total_channels = manager.send_notification(args.type, args.data, args.channels)
        sys.exit(0 if success_count > 0 else 1)

if __name__ == '__main__':
    main()