#!/bin/bash

set -e

# 1. Initialize Terraform
echo "Initializing Terraform..."
terraform -chdir=terraform init

# 2. Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform -chdir=terraform apply -auto-approve

# 3. Introduce a drift
echo "Introducing a drift..."
echo "This is a drift" > terraform/hello.txt

# 4. Detect the drift
echo "Detecting the drift..."
terraform -chdir=terraform plan

# 5. Remediate the drift
echo "Remediating the drift..."
terraform -chdir=terraform apply -auto-approve
