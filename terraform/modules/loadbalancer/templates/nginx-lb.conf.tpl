events {
    worker_connections 1024;
}

http {
    upstream backend {
%{ for container in upstream_containers ~}
        server ${container}:80;
%{ endfor ~}
    }

    server {
        listen 80;
        
        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /health {
            access_log off;
            return 200 '{"status":"healthy","environment":"${environment}","timestamp":"$time_iso8601"}';
            add_header Content-Type application/json;
        }

        location /nginx-status {
            stub_status on;
            access_log off;
            allow 127.0.0.1;
            allow 172.20.0.0/16;
            deny all;
        }
    }

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}