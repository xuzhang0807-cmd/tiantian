upstream {{NAME}}_backend {
    server 127.0.0.1:{{WEB_PORT}};
}

server {
    listen 80;
    server_name {{DOMAIN}};
    location ^~ /.well-known/acme-challenge/ { root /var/www/letsencrypt; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 127.0.0.1:4443 ssl;
    listen 127.0.0.1:4443 quic;
    http2 on;
    server_name {{DOMAIN}};
    ssl_certificate /etc/nginx/certs/{{DOMAIN}}_cert.pem;
    ssl_certificate_key /etc/nginx/certs/{{DOMAIN}}_key.pem;
    location / {
        proxy_pass http://{{NAME}}_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
