# Monitoring Module - Prometheus, Grafana, and cAdvisor
# This module sets up monitoring stack for drift detection

resource "docker_image" "prometheus" {
  name         = "prom/prometheus:latest"
  keep_locally = false
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = false
}

resource "docker_image" "cadvisor" {
  name         = "gcr.io/cadvisor/cadvisor:latest"
  keep_locally = false
}

# Prometheus configuration
resource "local_file" "prometheus_config" {
  content = templatefile("${path.module}/templates/prometheus.yml.tpl", {
    environment = var.environment
  })
  filename = "${path.module}/../../config/prometheus.yml"
}

# Prometheus container
resource "docker_container" "prometheus" {
  name  = "${var.labels.project}-prometheus-${var.environment}"
  image = docker_image.prometheus.image_id
  
  restart = "unless-stopped"
  
  networks_advanced {
    name = var.network_id
  }

  ports {
    internal = 9090
    external = 9090
  }

  volumes {
    host_path      = abspath(local_file.prometheus_config.filename)
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  volumes {
    host_path      = abspath("${path.module}/../../data/prometheus")
    container_path = "/prometheus"
  }

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--web.console.libraries=/etc/prometheus/console_libraries",
    "--web.console.templates=/etc/prometheus/consoles",
    "--storage.tsdb.retention.time=200h",
    "--web.enable-lifecycle"
  ]

  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  labels {
    label = "service"
    value = "prometheus"
  }
}

# Grafana container
resource "docker_container" "grafana" {
  name  = "${var.labels.project}-grafana-${var.environment}"
  image = docker_image.grafana.image_id
  
  restart = "unless-stopped"
  
  networks_advanced {
    name = var.network_id
  }

  ports {
    internal = 3000
    external = 3000
  }

  env = [
    "GF_SECURITY_ADMIN_USER=admin",
    "GF_SECURITY_ADMIN_PASSWORD=admin123",
    "GF_USERS_ALLOW_SIGN_UP=false"
  ]

  volumes {
    host_path      = abspath("${path.module}/../../data/grafana")
    container_path = "/var/lib/grafana"
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
    value = "grafana"
  }
}

# cAdvisor container for container metrics
resource "docker_container" "cadvisor" {
  name  = "${var.labels.project}-cadvisor-${var.environment}"
  image = docker_image.cadvisor.image_id
  
  restart = "unless-stopped"
  
  networks_advanced {
    name = var.network_id
  }

  ports {
    internal = 8080
    external = 8081
  }

  volumes {
    host_path      = "/"
    container_path = "/rootfs"
    read_only      = true
  }

  volumes {
    host_path      = "/var/run"
    container_path = "/var/run"
    read_only      = true
  }

  volumes {
    host_path      = "/sys"
    container_path = "/sys"
    read_only      = true
  }

  volumes {
    host_path      = "/var/lib/docker/"
    container_path = "/var/lib/docker"
    read_only      = true
  }

  volumes {
    host_path      = "/dev/disk/"
    container_path = "/dev/disk"
    read_only      = true
  }

  privileged = true

  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  labels {
    label = "service"
    value = "cadvisor"
  }
}

# Create necessary directories
resource "null_resource" "create_monitoring_dirs" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/../../data/prometheus
      mkdir -p ${path.module}/../../data/grafana
      mkdir -p ${path.module}/../../config
    EOT
  }
}