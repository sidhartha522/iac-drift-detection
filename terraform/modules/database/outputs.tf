# Database Module Outputs

output "container_id" {
  description = "ID of the database container"
  value       = docker_container.database.id
}

output "container_name" {
  description = "Name of the database container"
  value       = docker_container.database.name
}

output "container_ip" {
  description = "IP address of the database container"
  value       = docker_container.database.network_data[0].ip_address
}

output "port" {
  description = "Database port"
  value       = var.port
}

output "connection_string" {
  description = "Database connection string"
  value       = "postgresql://${var.database_user}:${var.database_password}@${docker_container.database.name}:${var.port}/${var.database_name}"
  sensitive   = true
}

output "volume_data_name" {
  description = "Name of the data volume"
  value       = docker_volume.database_data.name
}

output "volume_backups_name" {
  description = "Name of the backups volume"
  value       = docker_volume.database_backups.name
}