# Database Module Variables

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_id" {
  description = "Docker network ID"
  type        = string
}

variable "image" {
  description = "Docker image for the database"
  type        = string
}

variable "port" {
  description = "Database port"
  type        = number
}

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "database_user" {
  description = "Database user"
  type        = string
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}