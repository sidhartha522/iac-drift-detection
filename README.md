# 🚀 IaC Drift Detection & Remediation System

An automated infrastructure drift detection and remediation system using GitOps principles, built with Terraform, Docker, and Python.

## 🎯 What This System Does

This project automatically:
- **Detects** infrastructure drift (unauthorized changes)
- **Alerts** teams about configuration mismatches  
- **Remediates** issues automatically or with approval
- **Monitors** infrastructure health in real-time
- **Prevents** problems before they impact users

## 🚀 Quick Start (5 minutes)

### Prerequisites
- **Docker Desktop** (https://www.docker.com/products/docker-desktop)
- **Terraform** (`brew install terraform`)  
- **Python 3.8+** (usually pre-installed)

### Setup & Run
```bash
# 1. Clone repository
git clone <YOUR-REPO-URL>
cd <PROJECT-NAME>

# 2. Install Python dependencies
pip3 install -r requirements.txt

# 3. Start Docker Desktop
open -a Docker
# Wait 30 seconds for Docker to fully start

# 4. Deploy infrastructure
cd terraform
terraform init
terraform apply -auto-approve

# 5. Start monitoring stack
cd ../monitoring  
./setup-monitoring.sh start

# 6. Run the demo!
cd ..
./demo-script.sh
```

## 🎬 Live Demo

Run the interactive demo to see drift detection and remediation in action:

```bash
./demo-script.sh
```

**Or follow the manual steps:**

```bash
# 1. Show current infrastructure
docker ps

# 2. Simulate drift (break something)
docker stop $(docker ps --format "{{.Names}}" | grep web | head -1)

# 3. Detect the drift
cd scripts/drift-detection
python3 drift-detector.py --config ../../config/drift-detection.json

# 4. Auto-remediate
cd ../../terraform
terraform apply -auto-approve

# 5. Verify fix
docker ps
```

## 🌐 Access Points

Once running, access these services:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Load Balancer** | http://localhost:8081 | - |
| **Grafana Dashboard** | http://localhost:3000 | admin/admin123 |
| **Prometheus Metrics** | http://localhost:9090 | - |
| **cAdvisor** | http://localhost:8080 | - |

## 🚨 Troubleshooting

### Common Issues

**Docker not running:**
```bash
open -a Docker
# Wait 30-60 seconds, then retry
```

**Port conflicts:**
```bash
docker-compose down
docker system prune -f
terraform destroy -auto-approve
terraform apply -auto-approve
```

**Terraform errors:**
```bash
cd terraform
terraform destroy -auto-approve
terraform init -reconfigure
terraform apply -auto-approve
```

## 🎯 Demo Points for Presentations

**Key talking points:**
- ✅ **Problem:** Manual infrastructure changes cause outages
- ✅ **Solution:** Automated detection and remediation
- ✅ **Benefits:** Zero downtime, reduced human error
- ✅ **Technology:** Modern DevOps practices (IaC, containerization, monitoring)
- ✅ **Results:** Self-healing infrastructure that prevents problems

**🎉 Ready to impress? Run `./demo-script.sh` and show off your automated infrastructure!**
