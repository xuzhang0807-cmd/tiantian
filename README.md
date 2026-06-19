# TianTian Ops

TianTian Ops (`tt`) is a personal server deployment toolkit for reproducing the owner's Docker/nginx/SSL/project deployment habits on new hosts.

## Goals

- Install and verify server dependencies automatically.
- Keep the `/home/web` nginx gateway model with SNI/stream and internal `127.0.0.1:4443` HTTPS sites.
- Deploy selectable project blueprints under `/home/docker/<project>`.
- Generate local secrets on the target server instead of storing them in Git.
- Back up projects before removal and keep backups under `/home/tt-backups`.

## Safety Rules

GitHub stores only scripts, templates, schemas, and non-sensitive examples.

Never commit:

- `.env` files
- certificates or private keys
- databases, dumps, uploads, backups
- generated Reality/Xray/Sing-box secrets or share links
- local runtime state from `logs/` or `state/*.local.json`

## Current Commands

```bash
tt health        # system health check
tt detect        # server detection
tt profile       # server profile
tt deploy --plan toko      # preview preset deployment plan
tt configure toko /home/docker/shop  # generate local-only .env files interactively
tt deploy toko             # deploy after local config exists
tt deploy toko toko none 8450  # override type/domain/port
tt remove        # backup then remove a project
tt backup        # create project backup
tt ports         # show managed port pool
tt help          # command help
```

Chinese pinyin aliases are available for common operations, for example `tt jc`, `tt bs`, `tt bf`, `tt sc`, `tt rq`, `tt zs`, and `tt wg`.

## Preset Deploy Flow

Deployments are plan-first. TianTian suggests defaults, shows them clearly, and only mutates the server after confirmation.

Default rules:

- project path: blueprint `defaults.project_dir`, falling back to `/home/docker/<project>`
- domain: blueprint `defaults.domain`, falling back to `<project>.kazerush.xyz`, or `none` to skip
- port: blueprint default port first, then first free port from the project preset range
- local config: `tt configure <blueprint> [dir]` renders `.example` files into real local `.env` files; placeholders can be typed manually or auto-generated
- HTTPS/nginx: enabled when a domain is present, skipped when domain is `none`
- state: project metadata and port allocation are written only after successful deploy

## Standard Paths

```text
/opt/tiantian/             script repository
/home/web/                 nginx gateway
/home/docker/<project>/    project runtime directory
/home/tt-backups/<project>/ project backup archive directory
/home/tt-secrets/<project>/ local secrets directory
```

See `docs/blueprint-v2.md` for the v2 architecture plan.
