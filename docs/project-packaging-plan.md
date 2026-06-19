# TianTian Ops Project Packaging Plan

## Goal

Package the current server deployment habits into Git-safe TianTian Ops blueprints so a new host can clone the repository, preview a deployment plan, fill/confirm defaults, and recreate nginx, SSL, Docker project layout, ports, backups, and verification flow.

## Packaging Boundary

Commit to GitHub:

- scripts and libraries
- project blueprint manifests
- compose/nginx templates
- health-check scripts
- backup/restore scripts
- `.env.example` files with placeholders only
- documentation and migration notes

Never commit:

- `.env` files with real values
- certs/private keys
- databases, uploads, backups, runtime state
- generated proxy links, UUIDs, Reality keys, API tokens

## Blueprint Layout

```text
blueprints/<project>/
  manifest.yaml
  compose.yml.tpl
  env.example
  nginx.conf.tpl
  health.sh
  backup.sh
  restore.sh
  README.md
```

Optional network services may add:

```text
  stream.conf.tpl
  systemd.service.tpl
  share-output.example.txt
```

## Existing Server Projects To Model

Use the current infrastructure as the first preset set:

- `wordpress`: `/home/docker/wordpress`, default port range `8445-8449`, domain optional.
- `toko`: `/home/docker/toko`, default port range `8450-8459`, default domain `toko.kazerush.xyz`.
- `sub2api`: `/opt/sub2api` or future `/home/docker/sub2api`, default port range `8460-8469`, default domain `sub2.kazerush.xyz`.
- `komari`: `/home/komari/data` data mount, default port range `8470-8479`, default domain `komari.kazerush.xyz`.
- `network`: Xray/Sing-box style services, default local range `8480-8499`, generated secrets local-only.

## Conversion Method

For each project:

1. Read-only inventory: compose files, container image, mounts, exposed ports, nginx site, cert path, health URL, data directories.
2. Classify data: Git-safe templates vs local-only runtime data.
3. Create `blueprints/<project>/manifest.yaml` with defaults for type, port group, domain template, paths, health checks, and required secrets.
4. Convert compose/nginx into templates using placeholders such as `{{NAME}}`, `{{PORT}}`, `{{DOMAIN}}`, `{{DATA_DIR}}`.
5. Create `.env.example`; real `.env` is generated or prompted on target host.
6. Add `health.sh` that verifies container status, local port, nginx syntax, and external HTTPS when a domain exists.
7. Add `backup.sh` and `restore.sh` covering databases, uploads, compose, env, and nginx configs.
8. Test with `tt deploy --plan <project>` first, then deploy on a staging/new host.

## Deployment Flow Target

```text
tt deploy --plan toko
  -> show preset plan
  -> confirm/override type, domain, port, paths
  -> backup existing same-name project if present
  -> render templates into /home/docker/<project>
  -> start Docker services
  -> run health checks
  -> render nginx + cert flow
  -> register state and port only after success
```

## Retry And Interruption Policy

- Invalid project names/domains/ports fail before any mutation.
- `--plan` never writes project or port state.
- Deployment writes status `deploying` with the current phase.
- Failure or forced interruption marks status `failed` with `phase`.
- Re-running the same deploy command backs up existing managed files first, then retries from a clean rendered state.
- Existing non-TianTian directories are not overwritten automatically.

## Implemented Blueprints

- `blueprints/toko`: models the live Toko shop stack at `/home/docker/shop` with storefront, backend API, PostgreSQL, Redis, uploads, nginx path routing, health checks, and backup/restore scripts. Runtime `.env`, uploads, databases, certificates, and Telegram credentials stay local-only.
- `blueprints/wordpress`: models the live WordPress + MariaDB stack on `127.0.0.1:8085`, including data/log mounts and database backup script.
- `blueprints/sub2api`: models Sub2API with PostgreSQL, Redis, app data volumes, nginx domain `sub2.kazerush.xyz`, and API health checks.
- `blueprints/komari`: models Komari with persistent `/home/komari/data`, port `127.0.0.1:8083 -> 25774`, nginx domain `komari.kazerush.xyz`, and data backup/restore scripts.
- `blueprints/network`: models nginx stream SNI relay and sing-box structure with secret-only placeholders; real keys, UUIDs, and share links remain local-only.

## Recommended Implementation Order

1. Keep `blueprints/toko` as the first representative Docker + nginx app project.
2. Use `blueprints/wordpress` as the simple Docker + DB baseline.
3. Use `blueprints/sub2api` to validate Docker volume and API-style health checks.
4. Use `blueprints/komari` to validate data-mount-sensitive backup discipline.
5. Use `blueprints/network` as a template-only network skeleton; generate secrets on each target host.

## Audit Before Push

Run before committing or pushing:

```bash
bash -n tiantian.sh bootstrap.sh lib/*.sh
./tiantian.sh deploy --plan toko
./tiantian.sh deploy --plan demo static none 8555
./tiantian.sh jc
./tiantian.sh dk
git check-ignore -v logs/tt.log state/projects.json state/ports.json profiles/current.txt
```

Then scan tracked and untracked files for private keys, tokens, certs, `.env`, databases, dumps, and generated share links.
