services:
  shop-postgres:
    image: postgres:15-alpine
    container_name: {{NAME}}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-shop}
      POSTGRES_USER: ${POSTGRES_USER:-shop}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    networks:
      - {{NAME}}-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER:-shop} -d $${POSTGRES_DB:-shop}"]
      interval: 10s
      timeout: 5s
      retries: 5

  shop-redis:
    image: redis:7-alpine
    container_name: {{NAME}}-redis
    restart: unless-stopped
    volumes:
      - ./redis-data:/data
    networks:
      - {{NAME}}-net

  shop-backend:
    build:
      context: ./backend-v2
    container_name: {{NAME}}-backend
    restart: unless-stopped
    depends_on:
      shop-postgres:
        condition: service_healthy
      shop-redis:
        condition: service_started
    env_file:
      - ./backend-v2/.env
    ports:
      - "127.0.0.1:{{BACKEND_PORT}}:3001"
    volumes:
      - ./uploads:/app/uploads
    networks:
      - {{NAME}}-net

  shop-storefront:
    build:
      context: ./storefront
    container_name: {{NAME}}-storefront
    restart: unless-stopped
    depends_on:
      - shop-backend
    ports:
      - "127.0.0.1:{{STOREFRONT_PORT}}:3000"
    networks:
      - {{NAME}}-net

networks:
  {{NAME}}-net:
    driver: bridge
