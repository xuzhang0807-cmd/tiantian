services:
  postgres:
    image: postgres:15-alpine
    container_name: sub2-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DATABASE_DBNAME:-sub2api}
      POSTGRES_USER: ${DATABASE_USER:-sub2api}
      POSTGRES_PASSWORD: ${DATABASE_PASSWORD:?set DATABASE_PASSWORD}
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER:-sub2api} -d $${POSTGRES_DB:-sub2api}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: sub2-redis
    restart: unless-stopped
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD:?set REDIS_PASSWORD}"]
    volumes:
      - redis_data:/data

  sub2api:
    image: weishaw/sub2api:latest
    container_name: sub2api
    restart: unless-stopped
    ports:
      - "127.0.0.1:{{API_PORT}}:8080"
    env_file:
      - ./.env
    volumes:
      - sub2api_data:/app/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

volumes:
  pg_data:
  redis_data:
  sub2api_data:
