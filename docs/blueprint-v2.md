# TianTian Ops v2 Blueprint

## Mission

Turn `tt` into a repeatable personal infrastructure installer: a new server can run one bootstrap command, select a project, fill required values, and receive a verified deployment with nginx, SSL, Docker services, local secrets, backups, and health checks.

## Layers

```text
core/      detection, logging, state, input validation, presets, port pool, backup registry
gateway/   /home/web nginx, stream/SNI, ACME webroot, cert sync and reload
network/   Xray-core, Sing-box, Reality/VLESS/Trojan/WS templates and share output
blueprints/ project manifests, compose templates, nginx templates, health checks
github/    secret scanning, template linting, safe push workflow
```

## Runtime Paths

```text
/opt/tiantian/                  tt source and local runtime state
/home/web/                      nginx gateway stack
/home/docker/<project>/          normal project runtime
/home/network/<project>/         network-core runtime when not using Docker
/home/tt-backups/<project>/      local backup archives
/home/tt-secrets/<project>/      generated local secrets, never committed
/home/tt-cache/                  temporary downloads and probes
```

## Lifecycle

Every project follows:

1. `detect`: inspect OS, Docker, nginx, DNS, ports, disk, memory.
2. `preset`: load project defaults for type, path, port group, domain template, HTTPS, nginx, and backup policy.
3. `plan`: show the generated deployment plan; user can accept defaults or override type/domain/port.
4. `backup`: back up existing project/config before mutation or removal.
5. `render`: generate compose, env, nginx, stream, and service configs.
6. `deploy`: start containers or systemd units.
7. `verify`: check local endpoint, nginx syntax, HTTPS, service logs, and project health.
8. `register`: write project and port state only after successful deploy.
9. `export`: produce sanitized blueprint updates only.

## Secret Policy

Commit only templates and examples. Generate or collect secrets on the destination server:

- database passwords
- admin passwords
- JWT/session secrets
- Xray/Sing-box UUIDs, private keys, shortIds, share links
- TLS private keys and certificates
- Telegram/API tokens

## Port Pool

Use centrally managed contiguous ranges. Databases and Redis stay on Docker-internal networks unless explicitly requested.

```text
8445-8449  wordpress
8450-8459  toko
8460-8469  sub2api
8470-8479  komari
8480-8499  xray/singbox local APIs and management
8500+      future projects
```

## Project Blueprints

Each blueprint eventually contains:

```text
manifest.yaml
compose.yml.tpl
env.example
nginx.conf.tpl
stream.conf.tpl        optional
health.sh
backup.sh
restore.sh
README.md
```

## Network Core Requirements

Xray/Sing-box must support an interactive protocol menu:

- VLESS + Reality
- VLESS + WS + TLS
- Trojan + TLS
- Shadowsocks
- future: Hysteria2/TUIC

Reality camouflage selection should prefer TLS handshake latency over ping because many stable domains block ICMP. The probe should pick 10 candidates appropriate to the server region, test TCP/443 and TLS SNI, then select the best stable domain.

Deployment output must include copy-ready v2rayN/v2rayNG links and optional Clash/Sing-box outbound snippets. These outputs are local-only and never committed.

## Error Handling

- Invalid input: re-prompt the same field without discarding previous answers.
- Render failure: delete generated temp files and leave old config untouched.
- Docker failure: keep project directory and logs for debugging.
- nginx test failure: restore the previous config and do not reload.
- Certificate failure: keep local deployment and mark HTTPS incomplete.
- Remove failure: keep the backup and report the failed phase.

## Removal Policy

Project removal always backs up first. Users can delete old backups manually from `/home/tt-backups/<project>/` or via a future backup cleanup command.
