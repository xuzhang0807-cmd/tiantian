{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": {{VLESS_REALITY_PORT}},
      "users": [{"uuid": "{{VLESS_UUID}}", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "{{REALITY_SNI}}",
        "reality": {
          "enabled": true,
          "handshake": {"server": "{{REALITY_HANDSHAKE_SERVER}}", "server_port": 443},
          "private_key": "{{REALITY_PRIVATE_KEY}}",
          "short_id": ["{{REALITY_SHORT_ID}}"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": {{HYSTERIA2_UDP_PORT}},
      "users": [{"password": "{{HYSTERIA2_PASSWORD}}"}]
    },
    {
      "type": "vless",
      "tag": "vless-ws-in-direct",
      "listen": "127.0.0.1",
      "listen_port": {{VLESS_WS_DIRECT_PORT}},
      "users": [{"uuid": "{{VLESS_WS_UUID}}"}]
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
