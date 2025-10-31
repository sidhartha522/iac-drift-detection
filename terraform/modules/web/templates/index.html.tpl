<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IaC Drift Detection - ${project}</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header {
            text-align: center;
            color: #333;
            margin-bottom: 30px;
        }
        .status {
            background: #e8f5e8;
            border: 1px solid #4caf50;
            color: #2e7d32;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .info-card {
            background: #f9f9f9;
            padding: 15px;
            border-radius: 5px;
            border-left: 4px solid #2196f3;
        }
        .footer {
            text-align: center;
            color: #666;
            margin-top: 30px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 IaC Drift Detection & Remediation</h1>
            <h2>Infrastructure as Code GitOps Platform</h2>
        </div>
        
        <div class="status">
            ✅ Infrastructure Status: Healthy and Running
        </div>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>🌍 Environment</h3>
                <p><strong>${environment}</strong></p>
            </div>
            <div class="info-card">
                <h3>📊 Project</h3>
                <p><strong>${project}</strong></p>
            </div>
            <div class="info-card">
                <h3>⏰ Deployed At</h3>
                <p>${timestamp}</p>
            </div>
            <div class="info-card">
                <h3>🔧 Managed By</h3>
                <p>Terraform + GitOps</p>
            </div>
        </div>
        
        <div class="info-card">
            <h3>🎯 Features</h3>
            <ul>
                <li>🔍 Automated drift detection</li>
                <li>🤖 Self-healing infrastructure</li>
                <li>📈 Real-time monitoring</li>
                <li>🔔 Instant notifications</li>
                <li>📋 Compliance tracking</li>
                <li>🔒 Security scanning</li>
            </ul>
        </div>
        
        <div class="footer">
            <p>Powered by Docker, Terraform, and GitOps principles</p>
            <p>Visit <a href="/health">/health</a> for API status</p>
        </div>
    </div>
</body>
</html>