#!/usr/bin/env python3
"""
IaC Rollback System
Handles rollback operations for failed remediations
"""

import os
import sys
import json
import subprocess
import argparse
import logging
from datetime import datetime
from pathlib import Path
import shutil

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('../logs/rollback.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class RollbackManager:
    def __init__(self, config_file='../config/drift-detection.json'):
        self.config_file = config_file
        self.config = self.load_config()
        self.terraform_dir = '../terraform'
        self.backup_dir = '../backups'
        
    def load_config(self):
        """Load configuration"""
        try:
            with open(self.config_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.error(f"Configuration file not found: {self.config_file}")
            return {}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in config file: {e}")
            return {}
    
    def list_backups(self):
        """List available backups"""
        if not os.path.exists(self.backup_dir):
            logger.info("No backup directory found")
            return []
        
        backups = []
        for item in os.listdir(self.backup_dir):
            backup_path = os.path.join(self.backup_dir, item)
            if os.path.isdir(backup_path) and item.startswith('backup_'):
                try:
                    # Get backup metadata
                    timestamp = item.replace('backup_', '')
                    created_at = datetime.strptime(timestamp, '%Y%m%d_%H%M%S')
                    
                    # Check what's in the backup
                    contents = os.listdir(backup_path)
                    
                    backup_info = {
                        'id': item,
                        'path': backup_path,
                        'created_at': created_at.isoformat(),
                        'timestamp': timestamp,
                        'contents': contents,
                        'has_terraform_state': 'terraform.tfstate' in contents,
                        'has_infrastructure_state': 'infrastructure_state.json' in contents,
                        'volume_backups': [f for f in contents if f.endswith('.tar.gz')]
                    }
                    
                    backups.append(backup_info)
                    
                except ValueError:
                    logger.warning(f"Invalid backup directory name: {item}")
        
        # Sort by creation time (newest first)
        backups.sort(key=lambda x: x['created_at'], reverse=True)
        return backups
    
    def show_backup_details(self, backup_id):
        """Show detailed information about a backup"""
        backups = self.list_backups()
        backup = next((b for b in backups if b['id'] == backup_id), None)
        
        if not backup:
            logger.error(f"Backup not found: {backup_id}")
            return None
        
        logger.info(f"Backup Details: {backup_id}")
        logger.info(f"Created: {backup['created_at']}")
        logger.info(f"Path: {backup['path']}")
        
        # Show infrastructure state if available
        if backup['has_infrastructure_state']:
            state_file = os.path.join(backup['path'], 'infrastructure_state.json')
            try:
                with open(state_file, 'r') as f:
                    state = json.load(f)
                
                logger.info("Infrastructure State at Backup:")
                logger.info(f"  - Containers: {state.get('containers', {}).get('count', 0)}")
                logger.info(f"  - Networks: {state.get('networks', {}).get('count', 0)}")
                logger.info(f"  - Volumes: {state.get('volumes', {}).get('count', 0)}")
                logger.info(f"  - Docker Status: {state.get('docker_status', 'unknown')}")
                
            except Exception as e:
                logger.warning(f"Could not read infrastructure state: {e}")
        
        # Show Terraform state info
        if backup['has_terraform_state']:
            logger.info("Terraform State: Available")
        else:
            logger.info("Terraform State: Not available")
        
        # Show volume backups
        if backup['volume_backups']:
            logger.info(f"Volume Backups ({len(backup['volume_backups'])}):")
            for volume in backup['volume_backups']:
                volume_name = volume.replace('.tar.gz', '')
                logger.info(f"  - {volume_name}")
        
        return backup
    
    def create_rollback_plan(self, backup_id):
        """Create a rollback plan for the specified backup"""
        backup = self.show_backup_details(backup_id)
        if not backup:
            return None
        
        plan = {
            'backup_id': backup_id,
            'backup_path': backup['path'],
            'created_at': datetime.utcnow().isoformat(),
            'steps': []
        }
        
        # Step 1: Stop current containers
        plan['steps'].append({
            'order': 1,
            'action': 'stop_containers',
            'description': 'Stop current running containers',
            'command': ['docker', 'stop', '$(docker ps -q --filter label=environment=' + 
                       self.config.get('environment', 'dev') + ')']
        })
        
        # Step 2: Restore Terraform state
        if backup['has_terraform_state']:
            plan['steps'].append({
                'order': 2,
                'action': 'restore_terraform_state',
                'description': 'Restore Terraform state file',
                'source': os.path.join(backup['path'], 'terraform.tfstate'),
                'destination': os.path.join(self.terraform_dir, 'terraform.tfstate')
            })
        
        # Step 3: Restore Docker volumes
        if backup['volume_backups']:
            for volume_backup in backup['volume_backups']:
                volume_name = volume_backup.replace('.tar.gz', '')
                plan['steps'].append({
                    'order': 3,
                    'action': 'restore_volume',
                    'description': f'Restore Docker volume: {volume_name}',
                    'volume_name': volume_name,
                    'backup_file': os.path.join(backup['path'], volume_backup)
                })
        
        # Step 4: Apply Terraform configuration
        if backup['has_terraform_state']:
            plan['steps'].append({
                'order': 4,
                'action': 'terraform_apply',
                'description': 'Apply restored Terraform configuration',
                'command': ['terraform', 'apply', '-auto-approve']
            })
        
        # Step 5: Verify rollback
        plan['steps'].append({
            'order': 5,
            'action': 'verify_rollback',
            'description': 'Verify rollback was successful',
            'command': ['python3', '../scripts/drift-detection/drift-detector.py', '--config', self.config_file]
        })
        
        return plan
    
    def execute_rollback_plan(self, plan, dry_run=False):
        """Execute the rollback plan"""
        if dry_run:
            logger.info("DRY RUN MODE - Showing what would be done:")
            for step in sorted(plan['steps'], key=lambda x: x['order']):
                logger.info(f"Step {step['order']}: {step['description']}")
                if 'command' in step:
                    logger.info(f"  Command: {' '.join(step['command'])}")
            return True
        
        logger.info(f"Executing rollback plan for backup: {plan['backup_id']}")
        
        rollback_log = []
        
        try:
            for step in sorted(plan['steps'], key=lambda x: x['order']):
                logger.info(f"Step {step['order']}: {step['description']}")
                
                if step['action'] == 'stop_containers':
                    success = self._stop_containers()
                elif step['action'] == 'restore_terraform_state':
                    success = self._restore_terraform_state(step['source'], step['destination'])
                elif step['action'] == 'restore_volume':
                    success = self._restore_volume(step['volume_name'], step['backup_file'])
                elif step['action'] == 'terraform_apply':
                    success = self._terraform_apply()
                elif step['action'] == 'verify_rollback':
                    success = self._verify_rollback()
                else:
                    logger.warning(f"Unknown action: {step['action']}")
                    success = False
                
                rollback_log.append({
                    'step': step['order'],
                    'action': step['action'],
                    'success': success,
                    'timestamp': datetime.utcnow().isoformat()
                })
                
                if not success:
                    logger.error(f"Step {step['order']} failed: {step['description']}")
                    return False
                
                logger.info(f"Step {step['order']} completed successfully")
            
            logger.info("Rollback completed successfully")
            self._save_rollback_log(plan['backup_id'], rollback_log)
            return True
            
        except Exception as e:
            logger.error(f"Rollback failed with exception: {e}")
            self._save_rollback_log(plan['backup_id'], rollback_log, str(e))
            return False
    
    def _stop_containers(self):
        """Stop current containers"""
        try:
            environment = self.config.get('environment', 'dev')
            
            # Get containers for this environment
            result = subprocess.run([
                'docker', 'ps', '-q', '--filter', f'label=environment={environment}'
            ], capture_output=True, text=True, check=True)
            
            container_ids = result.stdout.strip().split('\n')
            container_ids = [cid for cid in container_ids if cid.strip()]
            
            if container_ids:
                logger.info(f"Stopping {len(container_ids)} containers")
                subprocess.run(['docker', 'stop'] + container_ids, check=True)
            else:
                logger.info("No containers to stop")
            
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to stop containers: {e}")
            return False
    
    def _restore_terraform_state(self, source, destination):
        """Restore Terraform state file"""
        try:
            logger.info(f"Restoring Terraform state: {source} -> {destination}")
            
            # Backup current state first
            if os.path.exists(destination):
                backup_current = f"{destination}.rollback-backup"
                shutil.copy2(destination, backup_current)
                logger.info(f"Current state backed up to: {backup_current}")
            
            # Copy restored state
            shutil.copy2(source, destination)
            logger.info("Terraform state restored successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to restore Terraform state: {e}")
            return False
    
    def _restore_volume(self, volume_name, backup_file):
        """Restore Docker volume from backup"""
        try:
            logger.info(f"Restoring volume: {volume_name}")
            
            # Create volume if it doesn't exist
            subprocess.run(['docker', 'volume', 'create', volume_name], 
                         capture_output=True)
            
            # Restore volume data
            subprocess.run([
                'docker', 'run', '--rm',
                '-v', f'{volume_name}:/target',
                '-v', f'{os.path.dirname(backup_file)}:/backup:ro',
                'alpine', 'sh', '-c', 
                f'cd /target && rm -rf * && tar xzf /backup/{os.path.basename(backup_file)}'
            ], check=True)
            
            logger.info(f"Volume {volume_name} restored successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to restore volume {volume_name}: {e}")
            return False
    
    def _terraform_apply(self):
        """Apply Terraform configuration"""
        try:
            logger.info("Applying Terraform configuration")
            os.chdir(self.terraform_dir)
            
            result = subprocess.run([
                'terraform', 'apply', '-auto-approve'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("Terraform apply completed successfully")
                return True
            else:
                logger.error(f"Terraform apply failed: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Terraform apply error: {e}")
            return False
        finally:
            os.chdir('..')
    
    def _verify_rollback(self):
        """Verify rollback was successful"""
        try:
            logger.info("Verifying rollback...")
            
            # Wait for services to start
            import time
            time.sleep(30)
            
            # Run drift detection to verify
            result = subprocess.run([
                'python3', '../scripts/drift-detection/drift-detector.py',
                '--config', self.config_file
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("Rollback verification successful - no drift detected")
                return True
            else:
                logger.warning("Rollback verification shows drift still exists")
                return False
                
        except Exception as e:
            logger.error(f"Rollback verification error: {e}")
            return False
    
    def _save_rollback_log(self, backup_id, rollback_log, error=None):
        """Save rollback execution log"""
        log_entry = {
            'backup_id': backup_id,
            'rollback_timestamp': datetime.utcnow().isoformat(),
            'steps': rollback_log,
            'success': error is None,
            'error': error
        }
        
        log_file = f"../logs/rollback-{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        try:
            os.makedirs(os.path.dirname(log_file), exist_ok=True)
            with open(log_file, 'w') as f:
                json.dump(log_entry, f, indent=2)
            logger.info(f"Rollback log saved to: {log_file}")
        except Exception as e:
            logger.error(f"Failed to save rollback log: {e}")
    
    def quick_rollback(self, backup_id=None):
        """Quick rollback to latest or specified backup"""
        if backup_id is None:
            # Get latest backup
            backups = self.list_backups()
            if not backups:
                logger.error("No backups available for rollback")
                return False
            
            backup = backups[0]  # Latest backup
            backup_id = backup['id']
            logger.info(f"Rolling back to latest backup: {backup_id}")
        else:
            backup = next((b for b in self.list_backups() if b['id'] == backup_id), None)
            if not backup:
                logger.error(f"Backup not found: {backup_id}")
                return False
        
        # Create and execute rollback plan
        plan = self.create_rollback_plan(backup_id)
        if not plan:
            return False
        
        return self.execute_rollback_plan(plan)

def main():
    parser = argparse.ArgumentParser(description='IaC Rollback Management Tool')
    parser.add_argument('--config', default='../config/drift-detection.json',
                       help='Path to configuration file')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # List backups
    list_parser = subparsers.add_parser('list', help='List available backups')
    
    # Show backup details
    show_parser = subparsers.add_parser('show', help='Show backup details')
    show_parser.add_argument('backup_id', help='Backup ID to show details for')
    
    # Create rollback plan
    plan_parser = subparsers.add_parser('plan', help='Create rollback plan')
    plan_parser.add_argument('backup_id', help='Backup ID to create plan for')
    plan_parser.add_argument('--dry-run', action='store_true', help='Show plan without executing')
    
    # Execute rollback
    rollback_parser = subparsers.add_parser('rollback', help='Execute rollback')
    rollback_parser.add_argument('--backup-id', help='Backup ID to rollback to (latest if not specified)')
    rollback_parser.add_argument('--dry-run', action='store_true', help='Show what would be done')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    manager = RollbackManager(args.config)
    
    if args.command == 'list':
        backups = manager.list_backups()
        if backups:
            print("Available Backups:")
            print("==================")
            for backup in backups:
                print(f"ID: {backup['id']}")
                print(f"Created: {backup['created_at']}")
                print(f"Terraform State: {'✓' if backup['has_terraform_state'] else '✗'}")
                print(f"Volume Backups: {len(backup['volume_backups'])}")
                print("-" * 40)
        else:
            print("No backups available")
    
    elif args.command == 'show':
        manager.show_backup_details(args.backup_id)
    
    elif args.command == 'plan':
        plan = manager.create_rollback_plan(args.backup_id)
        if plan:
            manager.execute_rollback_plan(plan, dry_run=True)
    
    elif args.command == 'rollback':
        success = manager.quick_rollback(args.backup_id)
        sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()