global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['iac-drift-detection-cadvisor-${environment}:8080']

  - job_name: 'nginx'
    static_configs:
      - targets: ['iac-drift-detection-load-balancer-${environment}:80']
    metrics_path: /nginx-status
    
  - job_name: 'web-health'
    static_configs:
      - targets: ['iac-drift-detection-load-balancer-${environment}:80']
    metrics_path: /health
    scrape_interval: 30s