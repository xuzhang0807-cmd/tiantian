# Current Deployment vs Blueprints Audit

## Scope

This audit compares the live server deployment with TianTian Ops blueprints. It is read-only for live services and excludes real secrets, certificates, databases, uploads, and generated client links from Git.

## Live Projects Covered

- `toko`: `/home/docker/shop`, storefront `127.0.0.1:3000`, backend `127.0.0.1:3001`, PostgreSQL, Redis, uploads, nginx routes `/shop`, `/shop-api/`, `/shop-uploads/`.
- `wordpress`: `/home/docker/wordpress`, WordPress `127.0.0.1:8085`, MariaDB data bind mount.
- `sub2api`: `/opt/sub2api`, API `127.0.0.1:8080`, PostgreSQL/Redis/app Docker volumes, nginx domain `sub2.kazerush.xyz`.
- `komari`: container `komari`, `127.0.0.1:8083 -> 25774`, data bind `/home/komari/data`, nginx domain `komari.kazerush.xyz`.
- `network`: nginx stream SNI relay on public `443`, sing-box TCP `8443/8444` and UDP `30888`.

## Blueprint Coverage

- `blueprints/toko`: compose/nginx/env examples/health/backup/restore.
- `blueprints/wordpress`: compose/env example/health/backup/restore.
- `blueprints/sub2api`: compose/nginx/env example/health/backup/restore note.
- `blueprints/komari`: compose/nginx/env example/health/backup/restore.
- `blueprints/network`: stream config template, sing-box config template, health check, secret-only placeholders.

## Safety Rules Confirmed

- Real `.env` files are not copied into blueprints.
- Databases, uploads, Redis data, backups, and Docker volumes are not copied into blueprints.
- Certificates/private keys and sing-box private keys are not copied into blueprints.
- Network client links, UUIDs, short IDs, and generated share data remain local-only.
- Runtime TianTian state files are ignored by Git.

## Live Comparison Result

The automated comparison confirmed:

- Toko storefront port: expected `3000`, live `3000`.
- Toko backend port: expected `3001`, live `3001`.
- WordPress web port: expected `8085`, live `8085`.
- Sub2API port: expected `8080`, live `8080`.
- Komari port: expected `8083`, live `8083`.
- Komari data mount: expected `/home/komari/data`, live `/home/komari/data`.
- WordPress DB/data mounts match live bind paths.
- Toko uploads mount matches `/home/docker/shop/uploads`.
- nginx domains exist for Toko, Sub2API, and Komari.
- Local health checks returned HTTP `200` for Toko, WordPress, Sub2API, and Komari.
- External HTTPS smoke checks returned HTTP `200` for Toko, Sub2API, and Komari.
- nginx syntax test passed.

## Known Compatibility Notes

- Live Toko nginx config filename and cert references have historical mixed case: `toko.Kazerush.xyz`. Blueprints normalize domain placeholders to lowercase; deployment logic should keep compatibility for existing cert file names or create lowercase cert symlinks before switching.
- Current live Sub2API uses `/opt/sub2api`; blueprint target defaults to `/home/docker/sub2api` for future consistency. Migration must copy or render into the chosen target path explicitly.
- The network blueprint is template-only. Secrets must be generated per host and never pushed to Git.

## Next Safe Step

Before commit/push, run the final audit commands in `docs/project-packaging-plan.md` and review `git diff --stat` plus `git status --ignored` to confirm only scripts, templates, examples, and docs are tracked.
