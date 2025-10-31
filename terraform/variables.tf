# Variables for IaC Drift Detection and Remediation Project
# Using Docker and local infrastructure

variable "docker_host" {
  description = "Docker daemon host"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "devops-team"
}

variable "network_name" {
  description = "Docker network name"
  type        = string
  default     = "iac-drift-network"
}

variable "network_subnet" {
  description = "Docker network subnet"
  type        = string
  default     = "172.20.0.0/16"
}

variable "web_container_count" {
  description = "Number of web containers to deploy"
  type        = number
  default     = 2
}

variable "web_container_image" {
  description = "Docker image for web containers"
  type        = string
  default     = "nginx:alpine"
}

variable "web_container_port" {
  description = "Internal port for web containers"
  type        = number
  default     = 80
}

variable "load_balancer_port" {
  description = "External port for load balancer"
  type        = number
  default     = 8081
}

variable "database_image" {
  description = "Docker image for database"
  type        = string
  default     = "postgres:13-alpine"
}

variable "database_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "database_user" {
  description = "Database user"
  type        = string
  default     = "appuser"
}

variable "database_password" {
  description = "Database password"
  type        = string
  default     = "changeme123"
  sensitive   = true
}

variable "enable_drift_detection" {
  description = "Enable drift detection monitoring"
  type        = bool
  default     = true
}

variable "drift_check_interval" {
  description = "Interval for drift detection in seconds"
  type        = number
  default     = 300  # 5 minutes
}

variable "notification_webhook_url" {
  description = "Webhook URL for notifications (Slack, Teams, etc.)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "monitoring_enabled" {
  description = "Enable monitoring containers"
  type        = bool
  default     = true
}

variable "load_balancer_image" {
  description = "Docker image for load balancer"
  type        = string
  default     = "nginx:alpine"
}