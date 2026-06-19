# Toko Blueprint

This blueprint models the current live Toko shop stack without committing runtime secrets or data.

## Live Shape

- Storefront: `127.0.0.1:3000`, routed at `/shop`.
- Backend API: `127.0.0.1:3001`, routed at `/shop-api/`.
- Uploads: `{{PROJECT_DIR}}/uploads`, routed at `/shop-uploads/`.
- Database: PostgreSQL bind data directory `./postgres-data`.
- Cache: Redis bind data directory `./redis-data`.
- Gateway: `/home/web` nginx host-network gateway, HTTPS internally on `127.0.0.1:4443`.

## Safe Migration Steps

1. Clone TianTian Ops on the target host.
2. Copy application source into `backend-v2/` and `storefront/`.
3. Copy `env.example`, `backend-v2.env.example`, and `storefront.env.example` to real `.env` files and fill values locally.
4. Render `compose.yml.tpl` with project name, domain, and ports.
5. Run `docker compose config` before starting containers.
6. Start services and run `health.sh`.
7. Render `nginx.conf.tpl`, run `nginx -t`, then reload nginx.
8. Register project state and ports only after health checks pass.

## Git Safety

Do not commit:

- `.env` files
- `postgres-data/`
- `redis-data/`
- `uploads/`
- `backups/`
- certificates or private keys
- Telegram bot token/chat ID

## Validation

```bash
bash -n blueprints/toko/health.sh blueprints/toko/backup.sh blueprints/toko/restore.sh
CHECK_EXTERNAL=false DOMAIN=toko.kazerush.xyz blueprints/toko/health.sh
```
