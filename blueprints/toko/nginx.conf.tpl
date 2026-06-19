server {
    listen 80;
    server_name {{DOMAIN}};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type "text/plain";
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 127.0.0.1:4443 ssl;
    listen 127.0.0.1:4443 quic;
    http2 on;

    server_name {{DOMAIN}};

    ssl_certificate     /etc/nginx/certs/{{DOMAIN}}_cert.pem;
    ssl_certificate_key /etc/nginx/certs/{{DOMAIN}}_key.pem;

    location = /shop {
        proxy_pass http://127.0.0.1:{{STOREFRONT_PORT}}/shop;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 100m;
    }

    location ^~ /shop/ {
        proxy_pass http://127.0.0.1:{{STOREFRONT_PORT}};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 100m;
    }

    location ^~ /_next/ {
        proxy_pass http://127.0.0.1:{{STOREFRONT_PORT}};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ^~ /shop-api/ {
        proxy_pass http://127.0.0.1:{{BACKEND_PORT}}/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50m;
    }

    location ^~ /shop-uploads/ {
        alias {{PROJECT_DIR}}/uploads/;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location / {
        proxy_pass http://127.0.0.1:8085;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 100m;
    }
}
