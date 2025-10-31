# Simplified outputs for demo
output "network_name" {
  description = "Name of the created Docker network"
  value       = docker_network.app_network.name
}

output "network_id" {
  description = "ID of the created Docker network"  
  value       = docker_network.app_network.id
}

output "web_container_names" {
  description = "Names of the web containers"
  value       = docker_container.web[*].name
}

output "web_container_ports" {
  description = "External ports of the web containers"
  value       = [for container in docker_container.web : container.ports[0].external]
}

output "database_container_name" {
  description = "Name of the database container"
  value       = docker_container.database.name
}

output "database_container_port" {
  description = "External port of the database"
  value       = docker_container.database.ports[0].external
}

output "load_balancer_container_name" {
  description = "Name of the load balancer container"
  value       = docker_container.load_balancer.name
}

output "load_balancer_port" {
  description = "External port of the load balancer"
  value       = docker_container.load_balancer.ports[0].external
}

output "infrastructure_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    environment    = var.environment
    web_containers = length(docker_container.web)
    database_name  = var.database_name
    network_subnet = var.network_subnet
  }
}