# Load Balancer Module Variables

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_id" {
  description = "Docker network ID"
  type        = string
}

variable "external_port" {
  description = "External port for load balancer"
  type        = number
}

variable "upstream_containers" {
  description = "List of upstream container names"
  type        = list(string)
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}