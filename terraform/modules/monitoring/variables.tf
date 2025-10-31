# Monitoring Module Variables

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_id" {
  description = "Docker network ID"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}