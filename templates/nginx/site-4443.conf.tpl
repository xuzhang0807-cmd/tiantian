# TianTian Ops - Nginx 4443 Site Template
# 不占用公网 443，通过内部 4443 端口反代

server {
    listen 127.0.0.1:4443 ssl;
    http2 on;
    server_name {{DOMAIN}};

    ssl_certificate     /etc/nginx/certs/{{DOMAIN}}_cert.pem;
    ssl_certificate_key /etc/nginx/certs/{{DOMAIN}}_key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90;
        proxy_connect_timeout 30;
        proxy_send_timeout 90;
        proxy_buffering off;
        client_max_body_size 100m;
    }
}
