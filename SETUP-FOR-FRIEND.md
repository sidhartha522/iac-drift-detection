# 🚀 Quick Setup Guide for Your Friend

## Before You Start
**Prerequisites (install these first):**
- Docker Desktop: https://www.docker.com/products/docker-desktop
- Terraform: `brew install terraform`
- Python 3.8+ (usually pre-installed on Mac)

## 5-Minute Setup

```bash
# 1. Clone this repository  
git clone <REPO-URL>
cd <PROJECT-NAME>

# 2. Install Python packages
pip3 install -r requirements.txt

# 3. Start Docker Desktop
open -a Docker
# ⏰ Wait 30 seconds for Docker to fully start

# 4. Deploy infrastructure
cd terraform
terraform init
terraform apply -auto-approve

# 5. Start monitoring
cd ../monitoring
./setup-monitoring.sh start

# 6. RUN THE DEMO! 🎬
cd ..
./demo-script.sh
```

## Access URLs (after setup)
- **Load Balancer:** http://localhost:8081
- **Grafana:** http://localhost:3000 (admin/admin123)  
- **Prometheus:** http://localhost:9090

## Quick Demo Commands
```bash
# Show infrastructure
docker ps

# Break something (create drift)
docker stop $(docker ps --format "{{.Names}}" | grep web | head -1)

# Detect drift
cd scripts/drift-detection  
python3 drift-detector.py --config ../../config/drift-detection.json

# Fix automatically
cd ../../terraform
terraform apply -auto-approve

# Show it's fixed
docker ps
```

## Troubleshooting
- **Docker not running:** `open -a Docker` and wait
- **Port conflicts:** `docker system prune -f`
- **Terraform errors:** `terraform destroy -auto-approve` then `terraform apply -auto-approve`

## Demo Tips 🎯
1. **Always start with Docker Desktop running**
2. **Use `./demo-script.sh` - it's foolproof!**
3. **Show the monitoring dashboards - they're impressive**
4. **Explain the problem this solves - unauthorized infrastructure changes**

**Total time: 5 min setup + 8 min demo = 13 minutes to wow everyone! 🚀**