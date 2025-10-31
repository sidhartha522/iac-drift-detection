# 🚀 IaC Drift Detection & Remediation - LIVE DEMO GUIDE

## 📋 Quick Demo Script (10 minutes)

### 🎯 **What to Tell Your Ma'am:**
*"This system automatically detects when infrastructure changes outside of our code (drift) and fixes it automatically. I'll show you how it works with a live demo."*

---

## 🔧 **PART 1: Setup & Infrastructure (2 minutes)**

### Check Prerequisites
```bash
# Show these are installed
docker --version
terraform -version
python3 --version
```

### Deploy Infrastructure with Terraform
```bash
cd /Users/sidhartha/devops/terraform
terraform apply -auto-approve
```

**What to Say:** *"Terraform creates our desired infrastructure - 2 web servers, 1 database, 1 load balancer, all in Docker containers."*

**Show the Output:** Point to the container names and ports created

---

## 🎯 **PART 2: Show What's Running (1 minute)**

### Check Current Infrastructure
```bash
# Show containers running as expected
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Show network created
docker network ls | grep iac-drift
```

**What to Say:** *"This is our baseline infrastructure. Terraform manages this state."*

---

## 🔍 **PART 3: Drift Detection Demo (3 minutes)**

### Run Drift Detection
```bash
cd /Users/sidhartha/devops/scripts/drift-detection
python3 drift-detector.py --config ../../config/drift-detection.json
```

**What to Say:** *"The drift detector compares what Terraform expects vs what's actually running. Right now, no drift detected."*

### Simulate Infrastructure Drift (The Key Demo!)
```bash
# Stop one web container (simulate manual change)
docker stop iac-drift-detection-web-1-dev

# Show the problem
docker ps | grep web
```

**What to Say:** *"Oops! Someone manually stopped a web server outside of our Terraform code. This is drift!"*

### Detect the Drift
```bash
python3 drift-detector.py --config ../../config/drift-detection.json
```

**What to Say:** *"Now the drift detector finds the problem - we're supposed to have 2 web containers but only have 1 running."*

---

## 🛠️ **PART 4: Automatic Remediation (2 minutes)**

### Show Remediation Options
```bash
cd /Users/sidhartha/devops/scripts/remediation
ls -la
```

**What to Say:** *"We have scripts for automatic remediation or approval-based workflows."*

### Fix the Drift Automatically
```bash
# Method 1: Terraform apply (safest)
cd ../../terraform
terraform apply -auto-approve

# OR Method 2: Direct container restart
docker start iac-drift-detection-web-1-dev
```

**What to Say:** *"The system automatically restores the infrastructure to the desired state."*

### Verify Fix
```bash
docker ps | grep web
```

**What to Say:** *"Perfect! Both web containers are running again. Infrastructure restored."*

---

## 📊 **PART 5: Show Monitoring (2 minutes)**

### Open Monitoring Dashboards
```bash
# Show monitoring URLs
echo "Grafana Dashboard: http://localhost:3000 (admin/admin123)"
echo "Prometheus Metrics: http://localhost:9090"
```

**Open in browser and show:**
- Grafana dashboard with infrastructure health
- Container status and metrics

### Generate Health Report
```bash
cd /Users/sidhartha/devops/monitoring
python3 health_monitor.py --report --config ../config/drift-detection.json
```

**What to Say:** *"The monitoring shows real-time health of our infrastructure and can alert us to problems."*

---

## 🎤 **TALKING POINTS FOR YOUR MA'AM:**

### 💡 **Problem This Solves:**
- *"Infrastructure changes made outside of code create security risks and inconsistencies"*
- *"Manual fixes are slow and error-prone"*
- *"This system automatically prevents configuration drift"*

### 🛡️ **Key Benefits:**
- *"Automatic detection of unauthorized changes"*
- *"Self-healing infrastructure"*  
- *"Full audit trail of all changes"*
- *"Reduces downtime and human errors"*

### 🔧 **Technical Highlights:**
- *"Uses Terraform for infrastructure as code"*
- *"Python scripts for intelligent drift detection"*  
- *"Docker containers for consistent environments"*
- *"Prometheus & Grafana for monitoring"*
- *"GitHub Actions for CI/CD automation"*

---

## 🎬 **BONUS: Show Additional Features**

### GitOps Workflow (if time permits)
```bash
# Show GitHub Actions
cd /Users/sidhartha/devops
ls .github/workflows/
cat .github/workflows/drift-detection.yml
```

### Show Configuration
```bash
# Show the configuration
cat config/drift-detection.json
```

### Show Logs
```bash
# Show what gets logged
ls logs/
tail logs/health-monitor.log
```

---

## 🎯 **KEY DEMO POINTS TO EMPHASIZE:**

1. **Before:** Manual infrastructure changes cause problems
2. **Detection:** System automatically finds drift 
3. **Remediation:** Automatically fixes the problem
4. **Monitoring:** Continuous oversight and alerting
5. **Prevention:** Stops problems before they impact users

---

## 🚨 **TROUBLESHOOTING (Just in Case):**

### If Docker isn't running:
```bash
open -a Docker
# Wait 30 seconds
```

### If containers fail to start:
```bash
docker system prune -f
terraform destroy -auto-approve
terraform apply -auto-approve  
```

### If monitoring isn't working:
```bash
cd monitoring
./setup-monitoring.sh restart
```

---

## 📝 **SUMMARY TO CLOSE WITH:**

*"This system provides automatic infrastructure drift detection and remediation using modern DevOps practices. It reduces manual work, prevents security issues, and ensures our infrastructure always matches what's defined in code. The monitoring gives us complete visibility and the automation means problems are fixed before users notice them."*

**Total Demo Time: 8-10 minutes**
**Preparation Time: 2 minutes**
**Wow Factor: Maximum! 🚀**