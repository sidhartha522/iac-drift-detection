# Web Application Module - Nginx/Apache Containers
# This module creates multiple web application containers with load balancing

resource "docker_image" "web" {
  name         = var.image
  keep_locally = false
}

# Web application containers
resource "docker_container" "web" {
  count = var.container_count
  name  = "${var.labels.project}-web-${count.index + 1}-${var.environment}"
  image = docker_image.web.image_id
  
  restart = "unless-stopped"
  
  networks_advanced {
    name = var.network_id
  }

  ports {
    internal = var.internal_port
    # External ports are managed by load balancer
  }

  env = [
    "ENVIRONMENT=${var.environment}",
    "CONTAINER_ID=${count.index + 1}",
    "DATABASE_HOST=${var.database_host}",
    "WEB_ROOT=/usr/share/nginx/html"
  ]

  volumes {
    host_path      = abspath("${path.module}/../../web-content")
    container_path = "/usr/share/nginx/html"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:${var.internal_port}/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "60s"
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
    value = "web"
  }

  labels {
    label = "container.number"
    value = tostring(count.index + 1)
  }

  labels {
    label = "loadbalancer.target"
    value = "true"
  }
}

# Create web content directory and files
resource "local_file" "index_html" {
  content = templatefile("${path.module}/templates/index.html.tpl", {
    environment = var.environment
    project     = var.labels.project
    timestamp   = timestamp()
  })
  filename = "${path.module}/../../web-content/index.html"
}

resource "local_file" "health_html" {
  content = jsonencode({
    status      = "healthy"
    environment = var.environment
    timestamp   = timestamp()
    service     = "web"
  })
  filename = "${path.module}/../../web-content/health"
}

resource "local_file" "nginx_conf" {
  content = templatefile("${path.module}/templates/nginx.conf.tpl", {
    port = var.internal_port
  })
  filename = "${path.module}/../../web-content/nginx.conf"
}