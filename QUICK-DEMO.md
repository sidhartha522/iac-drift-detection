# 📋 DEMO CHEAT SHEET - Quick Reference

## 🎯 **1-Minute Setup**
```bash
cd /Users/sidhartha/devops/terraform
terraform apply -auto-approve
```

## 🎬 **Demo Flow (5 commands)**
```bash
# 1. Show infrastructure
docker ps

# 2. Stop container (create drift)  
docker stop iac-drift-detection-web-1-dev

# 3. Detect drift
cd ../scripts/drift-detection
python3 drift-detector.py --config ../../config/drift-detection.json

# 4. Fix drift
cd ../../terraform
terraform apply -auto-approve

# 5. Verify fix
docker ps
```

## 💬 **What to Say:**
- **Setup:** "Creating infrastructure with Terraform"
- **Break:** "Simulating manual change outside of code"  
- **Detect:** "System finds the drift automatically"
- **Fix:** "Auto-remediation restores desired state"
- **Success:** "Infrastructure is healthy again"

## 🌐 **Show These URLs:**
- Load Balancer: http://localhost:8081
- Grafana: http://localhost:3000 (admin/admin123)  
- Prometheus: http://localhost:9090

## 🎯 **Key Message:**
"Automatic drift detection and remediation prevents infrastructure problems before they impact users."