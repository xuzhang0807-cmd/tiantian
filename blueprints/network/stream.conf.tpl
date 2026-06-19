upstream nginx_local {
    server 127.0.0.1:4443;
}

upstream v2bx_reality {
    server 127.0.0.1:{{VLESS_REALITY_PORT}};
}

upstream vless_reality {
    server 127.0.0.1:{{VLESS_WS_DIRECT_PORT}};
}

map $ssl_preread_server_name $target {
    {{REALITY_SNI}} v2bx_reality;
    {{WS_SNI}} vless_reality;
    default nginx_local;
}

server {
    listen 443 reuseport;
    listen [::]:443 reuseport;
    ssl_preread on;
    proxy_pass $target;
    proxy_protocol off;
}
