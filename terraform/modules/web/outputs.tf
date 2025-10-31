# Web Module Outputs

output "container_ids" {
  description = "IDs of the web containers"
  value       = docker_container.web[*].id
}

output "container_names" {
  description = "Names of the web containers"
  value       = docker_container.web[*].name
}

output "container_ips" {
  description = "IP addresses of the web containers"
  value       = [for container in docker_container.web : container.network_data[0].ip_address]
}

output "internal_port" {
  description = "Internal port of web containers"
  value       = var.internal_port
}

output "web_content_path" {
  description = "Path to web content directory"
  value       = "${path.module}/../../web-content"
}