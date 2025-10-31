# Load Balancer Module Outputs

output "container_id" {
  description = "ID of the load balancer container"
  value       = docker_container.load_balancer.id
}

output "container_name" {
  description = "Name of the load balancer container"
  value       = docker_container.load_balancer.name
}

output "external_port" {
  description = "External port of the load balancer"
  value       = var.external_port
}

output "nginx_config_path" {
  description = "Path to nginx configuration file"
  value       = local_file.nginx_config.filename
}