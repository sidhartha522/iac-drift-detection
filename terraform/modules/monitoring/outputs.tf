# Monitoring Module Outputs

output "container_info" {
  description = "Information about monitoring containers"
  value = {
    prometheus = {
      id   = docker_container.prometheus.id
      name = docker_container.prometheus.name
      port = 9090
      url  = "http://localhost:9090"
    }
    grafana = {
      id   = docker_container.grafana.id
      name = docker_container.grafana.name
      port = 3000
      url  = "http://localhost:3000"
      credentials = {
        username = "admin"
        password = "admin123"
      }
    }
    cadvisor = {
      id   = docker_container.cadvisor.id
      name = docker_container.cadvisor.name
      port = 8081
      url  = "http://localhost:8081"
    }
  }
}