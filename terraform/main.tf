# Simple IaC Drift Detection Demo - Docker Infrastructure
terraform {
  required_version = ">= 1.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
  
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "docker" {
  host = var.docker_host
}

# Local variables
locals {
  common_labels = {
    project     = "iac-drift-detection"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Docker network
resource "docker_network" "app_network" {
  name   = "${local.common_labels.project}-network-${var.environment}"
  driver = "bridge"
  
  ipam_config {
    subnet = var.network_subnet
  }
}

# Web Application Image
resource "docker_image" "web" {
  name         = var.web_container_image
  keep_locally = false
}

# Web containers (simulating our application)
resource "docker_container" "web" {
  count = var.web_container_count
  name  = "${local.common_labels.project}-web-${count.index + 1}-${var.environment}"
  image = docker_image.web.image_id
  
  restart = "unless-stopped"
  
  ports {
    internal = var.web_container_port
    external = var.web_container_port + count.index
  }

  networks_advanced {
    name = docker_network.app_network.name
  }

  env = [
    "ENVIRONMENT=${var.environment}",
    "CONTAINER_ID=${count.index + 1}"
  ]
}

# Database Image
resource "docker_image" "database" {
  name         = var.database_image
  keep_locally = false
}

# Database Volume
resource "docker_volume" "database_data" {
  name = "${local.common_labels.project}-db-data-${var.environment}"
}

# Database container
resource "docker_container" "database" {
  name  = "${local.common_labels.project}-database-${var.environment}"
  image = docker_image.database.image_id
  
  restart = "unless-stopped"
  
  ports {
    internal = var.database_port
    external = var.database_port
  }

  networks_advanced {
    name = docker_network.app_network.name
  }

  volumes {
    volume_name    = docker_volume.database_data.name
    container_path = "/var/lib/postgresql/data"
  }

  env = [
    "POSTGRES_DB=${var.database_name}",
    "POSTGRES_USER=${var.database_user}",
    "POSTGRES_PASSWORD=${var.database_password}"
  ]
}

# Load Balancer Image  
resource "docker_image" "load_balancer" {
  name         = var.load_balancer_image
  keep_locally = false
}

# Load Balancer container
resource "docker_container" "load_balancer" {
  name  = "${local.common_labels.project}-loadbalancer-${var.environment}"
  image = docker_image.load_balancer.image_id
  
  restart = "unless-stopped"
  
  ports {
    internal = 80
    external = var.load_balancer_port
  }

  networks_advanced {
    name = docker_network.app_network.name
  }

  env = [
    "ENVIRONMENT=${var.environment}"
  ]

  depends_on = [docker_container.web]
}