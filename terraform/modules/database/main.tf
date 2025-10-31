# Database Module - PostgreSQL Container
# This module creates a PostgreSQL database container with proper configuration

resource "docker_image" "database" {
  name         = var.image
  keep_locally = false
}

resource "docker_volume" "database_data" {
  name = "${var.labels.project}-db-data-${var.environment}"
}

resource "docker_volume" "database_backups" {
  name = "${var.labels.project}-db-backups-${var.environment}"
}

resource "docker_container" "database" {
  name  = "${var.labels.project}-database-${var.environment}"
  image = docker_image.database.image_id
  
  restart = "unless-stopped"
  
  networks_advanced {
    name = var.network_id
  }

  ports {
    internal = var.port
    external = var.port
  }

  env = [
    "POSTGRES_DB=${var.database_name}",
    "POSTGRES_USER=${var.database_user}",
    "POSTGRES_PASSWORD=${var.database_password}",
    "PGDATA=/var/lib/postgresql/data/pgdata"
  ]

  volumes {
    volume_name    = docker_volume.database_data.name
    container_path = "/var/lib/postgresql/data"
  }

  volumes {
    volume_name    = docker_volume.database_backups.name
    container_path = "/backups"
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U ${var.database_user} -d ${var.database_name}"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "30s"
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
    value = "database"
  }

  labels {
    label = "backup.enabled"
    value = "true"
  }
}

# Database initialization script
resource "docker_container" "database_init" {
  name  = "${var.labels.project}-database-init-${var.environment}"
  image = docker_image.database.image_id
  
  must_run = false
  rm       = true

  networks_advanced {
    name = var.network_id
  }

  env = [
    "PGHOST=${docker_container.database.name}",
    "PGPORT=${var.port}",
    "PGUSER=${var.database_user}",
    "PGPASSWORD=${var.database_password}",
    "PGDATABASE=${var.database_name}"
  ]

  command = [
    "sh", "-c", <<-EOT
      echo 'Waiting for database to be ready...'
      while ! pg_isready -h $PGHOST -p $PGPORT -U $PGUSER; do
        sleep 2
      done
      echo 'Database is ready!'
      
      # Create tables and initial data if needed
      psql -c "CREATE TABLE IF NOT EXISTS app_health (
        id SERIAL PRIMARY KEY,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        status VARCHAR(20) NOT NULL,
        message TEXT
      );"
      
      psql -c "INSERT INTO app_health (status, message) VALUES ('healthy', 'Database initialized successfully');"
      
      echo 'Database initialization completed!'
    EOT
  ]

  depends_on = [docker_container.database]
}