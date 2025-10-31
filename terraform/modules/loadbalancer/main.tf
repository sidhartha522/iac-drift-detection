# Load Balancer Module - Nginx Reverse Proxy
# This module creates an Nginx load balancer container

resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = false
}

# Generate nginx configuration for load balancing
resource "local_file" "nginx_config" {
  content = templatefile("${path.module}/templates/nginx-lb.conf.tpl", {
    upstream_containers = var.upstream_containers
    environment        = var.environment
  })
  filename = "${path.module}/../../config/nginx-lb.conf"
}

resource "docker_container" "load_balancer" {
  name  = "${var.labels.project}-load-balancer-${var.environment}"
  image = docker_image.nginx.image_id
  
  restart = "unless-stopped"
  
  networks_advanced {
    name = var.network_id
  }

  ports {
    internal = 80
    external = var.external_port
  }

  volumes {
    host_path      = abspath(local_file.nginx_config.filename)
    container_path = "/etc/nginx/nginx.conf"
    read_only      = true
  }

  volumes {
    host_path      = abspath("${path.module}/../../logs")
    container_path = "/var/log/nginx"
  }

  env = [
    "ENVIRONMENT=${var.environment}"
  ]

  healthcheck {
    test         = ["CMD", "nginx", "-t"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "10s"
  }

  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  labels {
    label = "service"
    value = "load-balancer"
  }

  labels {
    label = "external.port"
    value = tostring(var.external_port)
  }
}

# Create logs directory if it doesn't exist
resource "null_resource" "create_logs_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../../logs"
  }
}