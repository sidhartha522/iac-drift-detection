#!/usr/bin/env python3
"""
IaC Drift Detection Script
This script detects configuration drift between desired and actual infrastructure state
"""

import os
import sys
import json
import subprocess
import argparse
import logging
from datetime import datetime
from pathlib import Path
import yaml

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('../../logs/drift-detection.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DriftDetector:
    def __init__(self, config_file='../config/drift-detection.json'):
        self.config_file = config_file
        self.config = self.load_config()
        self.terraform_dir = self.config.get('terraform', {}).get('config_dir', '../terraform')
        
    def load_config(self):
        """Load drift detection configuration"""
        try:
            with open(self.config_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {self.config_file}")
            return {}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in config file: {e}")
            return {}
    
    def get_terraform_state(self):
        """Get current Terraform state"""
        try:
            os.chdir(self.terraform_dir)
            result = subprocess.run(
                ['terraform', 'show', '-json'],
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to get Terraform state: {e.stderr}")
            return None
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse Terraform state JSON: {e}")
            return None
        finally:
            os.chdir('..')
    
    def get_terraform_plan(self):
        """Generate and analyze Terraform plan for drift detection"""
        try:
            os.chdir(self.terraform_dir)
            
            # Generate plan
            plan_result = subprocess.run(
                ['terraform', 'plan', '-detailed-exitcode', '-out=drift-plan.tfplan'],
                capture_output=True,
                text=True
            )
            
            # Convert plan to JSON
            json_result = subprocess.run(
                ['terraform', 'show', '-json', 'drift-plan.tfplan'],
                capture_output=True,
                text=True,
                check=True
            )
            
            plan_data = json.loads(json_result.stdout)
            
            # Clean up plan file
            if os.path.exists('drift-plan.tfplan'):
                os.remove('drift-plan.tfplan')
            
            return {
                'exit_code': plan_result.returncode,
                'stdout': plan_result.stdout,
                'stderr': plan_result.stderr,
                'plan_data': plan_data
            }
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to generate Terraform plan: {e}")
            return None
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse plan JSON: {e}")
            return None
        finally:
            os.chdir('..')
    
    def get_docker_state(self):
        """Get current Docker infrastructure state"""
        try:
            environment = self.config.get('environment', 'dev')
            
            # Get containers
            containers_result = subprocess.run(
                ['docker', 'ps', '--format', 'json', '--filter', f'label=environment={environment}'],
                capture_output=True,
                text=True,
                check=True
            )
            
            containers = []
            if containers_result.stdout.strip():
                for line in containers_result.stdout.strip().split('\n'):
                    if line.strip():
                        containers.append(json.loads(line))
            
            # Get networks
            networks_result = subprocess.run(
                ['docker', 'network', 'ls', '--format', 'json', '--filter', f'label=environment={environment}'],
                capture_output=True,
                text=True,
                check=True
            )
            
            networks = []
            if networks_result.stdout.strip():
                for line in networks_result.stdout.strip().split('\n'):
                    if line.strip():
                        networks.append(json.loads(line))
            
            # Get volumes
            volumes_result = subprocess.run(
                ['docker', 'volume', 'ls', '--format', 'json', '--filter', f'label=environment={environment}'],
                capture_output=True,
                text=True,
                check=True
            )
            
            volumes = []
            if volumes_result.stdout.strip():
                for line in volumes_result.stdout.strip().split('\n'):
                    if line.strip():
                        volumes.append(json.loads(line))
            
            return {
                'containers': containers,
                'networks': networks,
                'volumes': volumes,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to get Docker state: {e}")
            return None
    
    def analyze_drift(self, terraform_plan, docker_state):
        """Analyze drift between desired and actual state"""
        drift_detected = False
        drift_details = []
        
        if not terraform_plan:
            logger.error("No Terraform plan available for analysis")
            return False, []
        
        # Check Terraform plan exit code
        # 0 = no changes, 1 = error, 2 = changes detected
        if terraform_plan['exit_code'] == 2:
            drift_detected = True
            drift_details.append({
                'type': 'terraform_drift',
                'severity': 'high',
                'message': 'Terraform plan shows infrastructure changes needed',
                'details': terraform_plan['stdout']
            })
        
        # Analyze expected vs actual container counts
        expected_containers = self.config.get('infrastructure', {}).get('containers', {})
        actual_containers = docker_state.get('containers', []) if docker_state else []
        
        for service, expected in expected_containers.items():
            if 'count' in expected:
                expected_count = expected['count']
                actual_count = len([c for c in actual_containers if service in c.get('Names', '')])
                
                if expected_count != actual_count:
                    drift_detected = True
                    drift_details.append({
                        'type': 'container_count_drift',
                        'severity': 'medium',
                        'service': service,
                        'expected': expected_count,
                        'actual': actual_count,
                        'message': f'{service} container count mismatch'
                    })
        
        # Check for unhealthy containers
        for container in actual_containers:
            # Get container health status
            try:
                health_result = subprocess.run(
                    ['docker', 'inspect', '--format', '{{.State.Health.Status}}', container['Names']],
                    capture_output=True,
                    text=True
                )
                health_status = health_result.stdout.strip()
                
                if health_status and health_status != 'healthy':
                    drift_detected = True
                    drift_details.append({
                        'type': 'health_drift',
                        'severity': 'high',
                        'container': container['Names'],
                        'status': health_status,
                        'message': f'Container {container["Names"]} is unhealthy'
                    })
            except subprocess.CalledProcessError:
                pass  # Container might not have health checks
        
        return drift_detected, drift_details
    
    def generate_drift_report(self, drift_detected, drift_details, terraform_plan, docker_state):
        """Generate comprehensive drift report"""
        report = {
            'timestamp': datetime.utcnow().isoformat(),
            'environment': self.config.get('environment', 'dev'),
            'drift_detected': drift_detected,
            'summary': {
                'total_issues': len(drift_details),
                'high_severity': len([d for d in drift_details if d.get('severity') == 'high']),
                'medium_severity': len([d for d in drift_details if d.get('severity') == 'medium']),
                'low_severity': len([d for d in drift_details if d.get('severity') == 'low'])
            },
            'drift_details': drift_details,
            'infrastructure_state': {
                'terraform': {
                    'plan_exit_code': terraform_plan['exit_code'] if terraform_plan else None,
                    'changes_detected': terraform_plan['exit_code'] == 2 if terraform_plan else False
                },
                'docker': {
                    'containers_running': len(docker_state.get('containers', [])) if docker_state else 0,
                    'networks': len(docker_state.get('networks', [])) if docker_state else 0,
                    'volumes': len(docker_state.get('volumes', [])) if docker_state else 0
                }
            }
        }
        
        return report
    
    def save_report(self, report):
        """Save drift report to file"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        report_file = f'../logs/drift-report-{timestamp}.json'
        
        try:
            os.makedirs('../logs', exist_ok=True)
            with open(report_file, 'w') as f:
                json.dump(report, f, indent=2)
            logger.info(f"Drift report saved to {report_file}")
            return report_file
        except Exception as e:
            logger.error(f"Failed to save report: {e}")
            return None
    
    def send_notification(self, report):
        """Send drift notification if configured"""
        webhook_url = self.config.get('monitoring', {}).get('webhook_url')
        
        if not webhook_url:
            logger.info("No webhook URL configured, skipping notification")
            return
        
        message = self.format_notification_message(report)
        
        try:
            import requests
            
            payload = {
                'text': message,
                'username': 'IaC Drift Detector',
                'icon_emoji': ':warning:' if report['drift_detected'] else ':white_check_mark:'
            }
            
            response = requests.post(webhook_url, json=payload, timeout=10)
            response.raise_for_status()
            
            logger.info("Notification sent successfully")
            
        except ImportError:
            logger.warning("requests library not available, cannot send webhook notification")
        except Exception as e:
            logger.error(f"Failed to send notification: {e}")
    
    def format_notification_message(self, report):
        """Format notification message"""
        if report['drift_detected']:
            message = f"🚨 *IaC Drift Detected* - {report['environment'].upper()}\n\n"
            message += f"**Summary:**\n"
            message += f"• Total Issues: {report['summary']['total_issues']}\n"
            message += f"• High Severity: {report['summary']['high_severity']}\n"
            message += f"• Medium Severity: {report['summary']['medium_severity']}\n\n"
            
            for detail in report['drift_details'][:5]:  # Show first 5 issues
                severity_emoji = {'high': '🔴', 'medium': '🟡', 'low': '🟢'}.get(detail.get('severity', 'low'), '⚪')
                message += f"{severity_emoji} {detail.get('message', 'Unknown issue')}\n"
            
            if len(report['drift_details']) > 5:
                message += f"... and {len(report['drift_details']) - 5} more issues\n"
                
        else:
            message = f"✅ *No Drift Detected* - {report['environment'].upper()}\n\n"
            message += "Infrastructure is in sync with desired state."
        
        message += f"\nTimestamp: {report['timestamp']}"
        return message
    
    def run_drift_detection(self):
        """Main drift detection workflow"""
        logger.info("Starting drift detection...")
        
        # Get current states
        logger.info("Getting Terraform plan...")
        terraform_plan = self.get_terraform_plan()
        
        logger.info("Getting Docker state...")
        docker_state = self.get_docker_state()
        
        # Analyze drift
        logger.info("Analyzing drift...")
        drift_detected, drift_details = self.analyze_drift(terraform_plan, docker_state)
        
        # Generate report
        report = self.generate_drift_report(drift_detected, drift_details, terraform_plan, docker_state)
        
        # Save report
        report_file = self.save_report(report)
        
        # Send notification
        if drift_detected or self.config.get('monitoring', {}).get('always_notify', False):
            self.send_notification(report)
        
        # Print summary
        if drift_detected:
            logger.warning(f"Drift detected! {len(drift_details)} issues found.")
            for detail in drift_details:
                logger.warning(f"  - {detail.get('message', 'Unknown issue')}")
        else:
            logger.info("No drift detected. Infrastructure is in sync.")
        
        return report

def main():
    parser = argparse.ArgumentParser(description='IaC Drift Detection Tool')
    parser.add_argument('--config', default='../config/drift-detection.json',
                       help='Path to configuration file')
    parser.add_argument('--output', help='Output file for drift report')
    parser.add_argument('--quiet', action='store_true', help='Suppress console output')
    
    args = parser.parse_args()
    
    if args.quiet:
        logging.getLogger().setLevel(logging.WARNING)
    
    detector = DriftDetector(args.config)
    report = detector.run_drift_detection()
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"Report saved to {args.output}")
    
    # Exit with appropriate code
    sys.exit(1 if report['drift_detected'] else 0)

if __name__ == '__main__':
    main()