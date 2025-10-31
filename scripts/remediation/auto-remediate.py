#!/usr/bin/env python3
"""
IaC Drift Remediation System
This script automatically remediates detected infrastructure drift
"""

import os
import sys
import json
import subprocess
import argparse
import logging
from datetime import datetime
from pathlib import Path
import time
import shlex

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('../logs/remediation.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class RemediationEngine:
    def __init__(self, config_file='../config/drift-detection.json'):
        self.config_file = config_file
        self.config = self.load_config()
        self.terraform_dir = '../terraform'
        self.max_retries = 3
        self.retry_delay = 10  # seconds
        
    def load_config(self):
        """Load remediation configuration"""
        try:
            with open(self.config_file, 'r') as f:
                config = json.load(f)
            return config
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {self.config_file}")
            return {}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in config file: {e}")
            return {}
    
    def create_backup(self):
        """Create backup before remediation"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_dir = f'../backups/backup_{timestamp}'
        
        try:
            os.makedirs(backup_dir, exist_ok=True)
            
            # Backup Terraform state
            if os.path.exists(f'{self.terraform_dir}/terraform.tfstate'):
                subprocess.run([
                    'cp', f'{self.terraform_dir}/terraform.tfstate', 
                    f'{backup_dir}/terraform.tfstate'
                ], check=True)
            
            # Backup Docker volumes (if any)
            self.backup_docker_volumes(backup_dir)
            
            # Save current infrastructure state
            state_result = subprocess.run([
                'bash', '../scripts/drift-detection/get-current-state.sh', 
                self.config.get('environment', 'dev')
            ], capture_output=True, text=True)
            
            if state_result.returncode == 0:
                with open(f'{backup_dir}/infrastructure_state.json', 'w') as f:
                    f.write(state_result.stdout)
            
            logger.info(f"Backup created at {backup_dir}")
            return backup_dir
            
        except Exception as e:
            logger.error(f"Failed to create backup: {e}")
            return None
    
    def backup_docker_volumes(self, backup_dir):
        """Backup Docker volumes"""
        try:
            environment = self.config.get('environment', 'dev')
            
            # Get volumes for this environment
            volumes_result = subprocess.run([
                'docker', 'volume', 'ls', '--format', '{{.Name}}',
                '--filter', f'label=environment={environment}'
            ], capture_output=True, text=True, check=True)
            
            volumes = volumes_result.stdout.strip().split('\n')
            
            for volume in volumes:
                if volume.strip():
                    logger.info(f"Backing up volume: {volume}")
                    
                    # Create backup of volume using temporary container
                    subprocess.run([
                        'docker', 'run', '--rm', 
                        '-v', f'{volume}:/source:ro',
                        '-v', f'{os.path.abspath(backup_dir)}:/backup',
                        'alpine', 'tar', 'czf', f'/backup/{volume}.tar.gz', '-C', '/source', '.'
                    ], check=True)
                    
        except subprocess.CalledProcessError as e:
            logger.warning(f"Volume backup failed: {e}")
        except Exception as e:
            logger.warning(f"Volume backup error: {e}")
    
    def remediate_terraform_drift(self, drift_report):
        """Remediate Terraform-detected drift"""
        logger.info("Remediating Terraform drift...")
        
        try:
            os.chdir(self.terraform_dir)
            
            # Run terraform apply to fix drift
            apply_result = subprocess.run([
                'terraform', 'apply', '-auto-approve'
            ], capture_output=True, text=True)
            
            if apply_result.returncode == 0:
                logger.info("Terraform apply completed successfully")
                return True
            else:
                logger.error(f"Terraform apply failed: {apply_result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Terraform remediation error: {e}")
            return False
        finally:
            os.chdir('..')
    
    def remediate_container_drift(self, drift_details):
        """Remediate container-specific drift"""
        success = True
        
        for detail in drift_details:
            if detail.get('type') == 'container_count_drift':
                if not self.fix_container_count(detail):
                    success = False
            elif detail.get('type') == 'health_drift':
                if not self.fix_container_health(detail):
                    success = False
        
        return success
    
    def fix_container_count(self, drift_detail):
        """Fix container count mismatch"""
        service = drift_detail.get('service')
        expected_count = drift_detail.get('expected')
        actual_count = drift_detail.get('actual')
        
        logger.info(f"Fixing container count for {service}: {actual_count} -> {expected_count}")
        
        try:
            environment = self.config.get('environment', 'dev')
            
            if expected_count > actual_count:
                # Need to scale up - trigger Terraform apply
                return self.scale_containers_via_terraform(service, expected_count)
            else:
                # Need to scale down - remove extra containers
                return self.remove_excess_containers(service, expected_count, environment)
                
        except Exception as e:
            logger.error(f"Failed to fix container count for {service}: {e}")
            return False
    
    def scale_containers_via_terraform(self, service, target_count):
        """Scale containers by updating Terraform configuration"""
        try:
            # Update terraform variables
            tfvars_file = f'{self.terraform_dir}/terraform.tfvars'
            
            # Read existing tfvars or create new
            tfvars = {}
            if os.path.exists(tfvars_file):
                with open(tfvars_file, 'r') as f:
                    for line in f:
                        if '=' in line and not line.strip().startswith('#'):
                            key, value = line.strip().split('=', 1)
                            tfvars[key.strip()] = value.strip().strip('"')
            
            # Update container count
            if service == 'web':
                tfvars['web_container_count'] = str(target_count)
            
            # Write updated tfvars
            with open(tfvars_file, 'w') as f:
                for key, value in tfvars.items():
                    f.write(f'{key} = "{value}"\n')
            
            # Apply changes
            os.chdir(self.terraform_dir)
            result = subprocess.run([
                'terraform', 'apply', '-auto-approve'
            ], capture_output=True, text=True)
            
            return result.returncode == 0
            
        except Exception as e:
            logger.error(f"Failed to scale containers via Terraform: {e}")
            return False
        finally:
            os.chdir('..')
    
    def remove_excess_containers(self, service, target_count, environment):
        """Remove excess containers"""
        try:
            # Get containers for this service
            containers_result = subprocess.run([
                'docker', 'ps', '--format', '{{.Names}}',
                '--filter', f'label=environment={environment}',
                '--filter', f'label=service={service}'
            ], capture_output=True, text=True, check=True)
            
            containers = [c.strip() for c in containers_result.stdout.strip().split('\n') if c.strip()]
            
            if len(containers) > target_count:
                containers_to_remove = containers[target_count:]
                
                for container in containers_to_remove:
                    logger.info(f"Removing excess container: {container}")
                    subprocess.run(['docker', 'stop', container], check=True)
                    subprocess.run(['docker', 'rm', container], check=True)
            
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to remove excess containers: {e}")
            return False
    
    def fix_container_health(self, drift_detail):
        """Fix unhealthy container"""
        container_name = drift_detail.get('container')
        
        logger.info(f"Attempting to fix unhealthy container: {container_name}")
        
        try:
            # Try restarting the container first
            logger.info(f"Restarting container: {container_name}")
            subprocess.run(['docker', 'restart', container_name], check=True)
            
            # Wait for container to start
            time.sleep(10)
            
            # Check if it's healthy now
            health_result = subprocess.run([
                'docker', 'inspect', '--format', '{{.State.Health.Status}}', container_name
            ], capture_output=True, text=True)
            
            health_status = health_result.stdout.strip()
            
            if health_status == 'healthy':
                logger.info(f"Container {container_name} is now healthy")
                return True
            else:
                logger.warning(f"Container {container_name} still unhealthy after restart")
                
                # Try recreating the container via Terraform
                return self.recreate_container_via_terraform()
                
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to fix container health: {e}")
            return False
    
    def recreate_container_via_terraform(self):
        """Recreate containers via Terraform taint and apply"""
        try:
            os.chdir(self.terraform_dir)
            
            # Taint web containers to force recreation
            subprocess.run([
                'terraform', 'taint', 'module.web_app.docker_container.web[0]'
            ], capture_output=True, text=True)
            
            # Apply to recreate
            result = subprocess.run([
                'terraform', 'apply', '-auto-approve'
            ], capture_output=True, text=True)
            
            return result.returncode == 0
            
        except Exception as e:
            logger.error(f"Failed to recreate containers: {e}")
            return False
        finally:
            os.chdir('..')
    
    def verify_remediation(self, original_drift_report):
        """Verify that remediation was successful"""
        logger.info("Verifying remediation...")
        
        # Wait a bit for services to stabilize
        time.sleep(30)
        
        # Run drift detection again
        try:
            # Run drift detector script directly
            result = subprocess.run([
                'python3', '../drift-detection/drift-detector.py', 
                '--config', self.config_file, '--quiet'
            ], capture_output=True, text=True, cwd='../scripts')
            
            if result.returncode == 0:
                new_report = {'drift_detected': False, 'drift_details': []}
            else:
                # Try to get the latest drift report
                log_dir = '../logs'
                if os.path.exists(log_dir):
                    reports = [f for f in os.listdir(log_dir) if f.startswith('drift-report-')]
                    if reports:
                        latest_report = sorted(reports)[-1]
                        with open(f'{log_dir}/{latest_report}', 'r') as f:
                            new_report = json.load(f)
                    else:
                        new_report = {'drift_detected': True, 'drift_details': []}
                else:
                    new_report = {'drift_detected': True, 'drift_details': []}
            
            # Compare results
            if not new_report['drift_detected']:
                logger.info("Remediation successful - no drift detected")
                return True, new_report
            else:
                remaining_issues = len(new_report['drift_details'])
                original_issues = len(original_drift_report['drift_details'])
                
                if remaining_issues < original_issues:
                    logger.info(f"Partial remediation success: {original_issues - remaining_issues} issues fixed")
                    return False, new_report
                else:
                    logger.warning("Remediation failed - same or more issues remain")
                    return False, new_report
                    
        except Exception as e:
            logger.error(f"Failed to verify remediation: {e}")
            return False, None
    
    def rollback_changes(self, backup_dir):
        """Rollback changes if remediation fails"""
        if not backup_dir or not os.path.exists(backup_dir):
            logger.error("No valid backup directory for rollback")
            return False
        
        logger.info(f"Rolling back changes from backup: {backup_dir}")
        
        try:
            # Restore Terraform state
            state_backup = f'{backup_dir}/terraform.tfstate'
            if os.path.exists(state_backup):
                subprocess.run([
                    'cp', state_backup, f'{self.terraform_dir}/terraform.tfstate'
                ], check=True)
                
                # Apply the restored state
                os.chdir(self.terraform_dir)
                subprocess.run([
                    'terraform', 'apply', '-auto-approve'
                ], check=True)
                os.chdir('..')
            
            # Restore Docker volumes
            self.restore_docker_volumes(backup_dir)
            
            logger.info("Rollback completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Rollback failed: {e}")
            return False
    
    def restore_docker_volumes(self, backup_dir):
        """Restore Docker volumes from backup"""
        try:
            backup_files = [f for f in os.listdir(backup_dir) if f.endswith('.tar.gz')]
            
            for backup_file in backup_files:
                volume_name = backup_file.replace('.tar.gz', '')
                logger.info(f"Restoring volume: {volume_name}")
                
                # Stop containers using the volume
                subprocess.run([
                    'docker', 'ps', '-q', '--filter', f'volume={volume_name}'
                ], capture_output=True, text=True)
                
                # Restore volume data
                subprocess.run([
                    'docker', 'run', '--rm',
                    '-v', f'{volume_name}:/target',
                    '-v', f'{os.path.abspath(backup_dir)}:/backup:ro',
                    'alpine', 'sh', '-c', f'cd /target && tar xzf /backup/{backup_file}'
                ], check=True)
                
        except Exception as e:
            logger.warning(f"Volume restore failed: {e}")
    
    def send_remediation_notification(self, success, drift_report, remediation_summary):
        """Send notification about remediation results"""
        webhook_url = self.config.get('monitoring', {}).get('webhook_url')
        
        if not webhook_url:
            return
        
        try:
            import requests
            
            if success:
                message = f"✅ *Remediation Successful* - {self.config.get('environment', 'dev').upper()}\n\n"
                message += f"All {len(drift_report['drift_details'])} issues have been resolved.\n"
            else:
                message = f"❌ *Remediation Failed* - {self.config.get('environment', 'dev').upper()}\n\n"
                message += f"Failed to resolve drift issues.\n"
            
            message += f"\n**Remediation Summary:**\n{remediation_summary}\n"
            message += f"\nTimestamp: {datetime.utcnow().isoformat()}"
            
            payload = {
                'text': message,
                'username': 'IaC Remediation Engine',
                'icon_emoji': ':robot_face:'
            }
            
            requests.post(webhook_url, json=payload, timeout=10)
            
        except Exception as e:
            logger.error(f"Failed to send remediation notification: {e}")
    
    def run_remediation(self, drift_report_file=None, auto_approve=False):
        """Main remediation workflow"""
        logger.info("Starting automatic remediation...")
        
        # Load drift report
        if drift_report_file and os.path.exists(drift_report_file):
            with open(drift_report_file, 'r') as f:
                drift_report = json.load(f)
        else:
            # Run drift detection first
            try:
                logger.info("Running drift detection...")
                result = subprocess.run([
                    'python3', '../drift-detection/drift-detector.py', 
                    '--config', self.config_file
                ], capture_output=True, text=True, cwd='../scripts')
                
                # Get the latest drift report
                log_dir = '../logs'
                if os.path.exists(log_dir):
                    reports = [f for f in os.listdir(log_dir) if f.startswith('drift-report-')]
                    if reports:
                        latest_report = sorted(reports)[-1]
                        with open(f'{log_dir}/{latest_report}', 'r') as f:
                            drift_report = json.load(f)
                    else:
                        logger.error("No drift reports found")
                        return False
                else:
                    logger.error("Logs directory not found")
                    return False
                    
            except Exception as e:
                logger.error(f"Cannot run drift detection: {e}")
                return False
        
        if not drift_report.get('drift_detected'):
            logger.info("No drift detected, remediation not needed")
            return True
        
        logger.info(f"Drift detected with {len(drift_report['drift_details'])} issues")
        
        # Create backup before remediation
        backup_dir = self.create_backup()
        
        remediation_summary = []
        success = True
        
        try:
            # Check for terraform drift
            terraform_drift = any(
                d.get('type') == 'terraform_drift' 
                for d in drift_report['drift_details']
            )
            
            if terraform_drift:
                if auto_approve or self.get_user_approval("Apply Terraform changes?"):
                    if self.remediate_terraform_drift(drift_report):
                        remediation_summary.append("✅ Terraform drift remediated")
                    else:
                        remediation_summary.append("❌ Terraform remediation failed")
                        success = False
                else:
                    remediation_summary.append("⏭️ Terraform remediation skipped (not approved)")
            
            # Check for container drift
            container_drifts = [
                d for d in drift_report['drift_details'] 
                if d.get('type') in ['container_count_drift', 'health_drift']
            ]
            
            if container_drifts:
                if auto_approve or self.get_user_approval("Fix container issues?"):
                    if self.remediate_container_drift(container_drifts):
                        remediation_summary.append("✅ Container drift remediated")
                    else:
                        remediation_summary.append("❌ Container remediation failed")
                        success = False
                else:
                    remediation_summary.append("⏭️ Container remediation skipped (not approved)")
            
            # Verify remediation
            if success:
                verification_success, new_report = self.verify_remediation(drift_report)
                if verification_success:
                    remediation_summary.append("✅ Remediation verified successful")
                else:
                    success = False
                    remediation_summary.append("❌ Remediation verification failed")
            
            # Send notification
            summary_text = '\n'.join(remediation_summary)
            self.send_remediation_notification(success, drift_report, summary_text)
            
            return success
            
        except Exception as e:
            logger.error(f"Remediation failed with exception: {e}")
            
            # Attempt rollback
            if backup_dir and not auto_approve:
                if self.get_user_approval("Rollback changes?"):
                    self.rollback_changes(backup_dir)
            
            return False
    
    def get_user_approval(self, message):
        """Get user approval for remediation actions"""
        try:
            response = input(f"{message} (y/N): ").lower().strip()
            return response in ['y', 'yes']
        except (EOFError, KeyboardInterrupt):
            return False

def main():
    parser = argparse.ArgumentParser(description='IaC Drift Remediation Tool')
    parser.add_argument('--config', default='../config/drift-detection.json',
                       help='Path to configuration file')
    parser.add_argument('--drift-report', help='Path to drift report file')
    parser.add_argument('--auto-approve', action='store_true',
                       help='Automatically approve all remediation actions')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be done without making changes')
    
    args = parser.parse_args()
    
    if args.dry_run:
        logger.info("DRY RUN MODE - No changes will be made")
        # TODO: Implement dry run logic
        return
    
    engine = RemediationEngine(args.config)
    success = engine.run_remediation(args.drift_report, args.auto_approve)
    
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()