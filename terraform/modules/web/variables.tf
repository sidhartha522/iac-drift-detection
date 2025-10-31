# Web Module Variables

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "network_id" {
  description = "Docker network ID"
  type        = string
}

variable "container_count" {
  description = "Number of web containers"
  type        = number
  default     = 2
}

variable "image" {
  description = "Docker image for web containers"
  type        = string
}

variable "internal_port" {
  description = "Internal port for web containers"
  type        = number
}

variable "database_host" {
  description = "Database host name"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}