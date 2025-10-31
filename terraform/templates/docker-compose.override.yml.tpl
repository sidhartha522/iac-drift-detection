version: '3.8'

services:
  web:
    image: ${web_container_image}
    restart: unless-stopped
    environment:
      - ENVIRONMENT=${environment}
    deploy:
      replicas: ${web_container_count}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.web.rule=Host(`localhost`)"
      - "traefik.http.services.web.loadbalancer.server.port=80"

  database:
    image: postgres:13-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_DB=${database_name}
      - POSTGRES_USER=${database_user}
      - POSTGRES_PASSWORD=${database_password}
    volumes:
      - db_data:/var/lib/postgresql/data
      - db_backups:/backups

  load_balancer:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "${load_balancer_port}:80"
    depends_on:
      - web

volumes:
  db_data:
  db_backups:

networks:
  default:
    driver: bridge