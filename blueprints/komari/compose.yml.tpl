services:
  komari:
    image: ghcr.io/komari-monitor/komari:latest
    container_name: komari
    restart: unless-stopped
    ports:
      - "127.0.0.1:{{WEB_PORT}}:25774"
    volumes:
      - {{DATA_DIR}}:/app/data
