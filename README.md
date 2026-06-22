# TianTian Ops

TianTian Ops (`tt`) is a personal, terminal-first server deployment toolkit for reproducing the owner's Docker/nginx/SSL/project deployment habits on new hosts.

## Goals

- One script entry: run `tt` to open a Chinese numeric menu, or use short commands directly.
- Keep the `/home/web` nginx stream/SNI gateway model with internal HTTPS sites on `127.0.0.1:4443`.
- Deploy selectable project blueprints under `/home/docker/<project>`.
- Generate local secrets on the target server instead of storing secrets in Git.
- Back up before destructive or configuration-writing actions.
- Keep README command details complete enough for fast future testing.

## Safety Rules

GitHub stores only scripts, templates, schemas, and non-sensitive examples.

Never commit:

- `.env` files
- certificates or private keys
- databases, dumps, uploads, backups
- generated Reality/Xray/Sing-box secrets or share links
- local runtime state from `logs/` or `state/*.local.json`

Write-action conventions:

- Commands ending in `plan` or `*-plan` are preview-only.
- Commands that modify config/data require `--yes` where supported.
- SSH, firewall, hosts, disk, user, and system-setting writes create backups first.
- High-risk kernel/reinstall actions are intentionally not automated by default.

## Quick Start

```bash
tt                  # open interactive menu
tt help             # command reference
tt selftest         # safe read-only/low-risk smoke test
tt coverage         # Kejilion-inspired feature coverage matrix
tt update           # pull latest TT scripts and blueprints
tt version          # show TT version
```

Recommended new-server flow:

```bash
tt deps doctor
tt deps install
tt detect
tt profile
tt nginx test
tt deploy --plan <project>
tt configure <project> [target_dir]
tt deploy <project>
tt health
tt selftest
```

## Short Aliases

English commands are the primary documented interface. Short aliases are convenience shortcuts:

- `jc`: detection, same as `tt detect`
- `zt`: health/status, same as `tt health`
- `bs`: deploy, same as `tt deploy`
- `sc`: remove, same as `tt remove`
- `bf`: backup, same as `tt backup`
- `hf`: restore, same as `tt restore`
- `xm`: project list, same as `tt list`
- `rq`: Docker menu, same as `tt docker`
- `rj`: logs, same as `tt logs`
- `zs`: certificate status, same as `tt cert`
- `wg`: nginx, same as `tt nginx`
- `dk`: ports, same as `tt ports`
- `yl`: dependencies, same as `tt deps`
- `gj`: tools, same as `tt tools`
- `yw`: ops checks, same as `tt ops`
- `fh`: firewall, same as `tt firewall`
- `jq`: cluster, same as `tt cluster`
- `rw`: rsync tasks, same as `tt tasks`
- `aq`: security, same as `tt security`
- `cp`: disk, same as `tt disk`
- `sshgl`: SSH management, same as `tt ssh`
- `yh`: user management, same as `tt users`
- `jx`: hosts management, same as `tt hosts`
- `xt`: system settings, same as `tt system`
- `yy`: app catalog, same as `tt apps`
- `fg`: coverage, same as `tt coverage`
- `cs`: selftest, same as `tt selftest`
- `cesu`: benchmark/network tests, same as `tt bench`

## Main Menu Map

Run `tt` without arguments to enter the menu:

1. System detection: `tt detect`
2. Server profile: `tt profile`
3. Project management: deploy/list/remove/logs
4. nginx management: list/test/reload/add/remove
5. Certificates: certbot status/obtain/sync/renew/hook
6. Docker management: compose operations and Docker audits
7. Health check: `tt health`
8. Backup/restore notes
9. System tools: resources, ports, cleanup, swap
10. Firewall: status, plan, backup, apply, restore
11. Bench tests: IP/DNS/ping/HTTP/speed/streaming/hardware
12. Common ops: SSH/DNS/cron/BBR/process/disk/services/tmux checks
13. Cluster: remote node inventory and SSH actions
14. Apps: personal blueprint catalog
15. Tasks: rsync task and cron management
16. Security: fail2ban/ClamAV plans and status
17. Disk: overview, mount plans, format/mount writes
18. SSH: status, hardening plan/write/restore
19. Users: list/create/lock/delete with backups
20. hosts: list/add/delete/restore with backups
21. System settings: timezone, hostname, IPv4 preference
22. Advanced: certbot hook, TT update, logs, dependencies

## Health, Detection, and Profile

```bash
tt health            # system health check
tt detect            # OS, CPU, memory, disk, network, Docker/nginx/cert status
tt profile           # classify host capacity and deployment recommendations
tt doctor            # broader diagnostic checks where available
```

Use these first on a new server to understand capacity and missing dependencies.

## Dependencies

```bash
tt deps doctor       # check required/recommended dependencies
tt deps install      # install recommended dependency set
tt deps install required
tt deps install all
tt deps versions     # show installed versions
```

Supported package managers include common Debian/Ubuntu, RHEL-family, and Alpine style systems where commands are available.

## System Tools

```bash
tt tools             # system toolbox menu
tt tools resource    # CPU, memory, disk overview
tt tools ports       # listening ports
tt tools network     # IP, routes, DNS basics
tt tools logs [N]    # recent system logs
tt tools clean       # clean package/log cache after confirmation
tt tools update      # run package manager update/upgrade flow
tt tools install     # install common tools menu
tt tools swap status # show swap status
tt tools swap add 2048
tt swap 2048         # shortcut for setting 2GB swap after confirmation
```

`clean`, `update`, and swap writes change system state; use them intentionally.

## Common Ops Checks

```bash
tt ops menu          # common ops menu
tt ops ssh           # SSH listener/root/password/auth-key summary
tt ops dns           # resolvers and name-resolution diagnostics
tt ops cron          # crontab and systemd timer overview
tt ops bbr           # TCP congestion and qdisc status
tt ops process       # process/load/top/zombie summary
tt ops disk          # filesystem, inode, large directory/log overview
tt ops services      # active/enabled/failed service overview
tt ops tmux          # tmux/background workspace status
```

These are read-only checks and safe for routine inspection.

## System Settings

Inspired by Kejilion's timezone, hostname, and IPv4/IPv6 preference helpers, implemented with TT backups and explicit writes.

```bash
tt system status                         # hostname, timezone, IPv4-preference state
tt system backup                         # backup /etc/hostname, /etc/hosts, /etc/timezone, /etc/localtime, /etc/gai.conf
tt system timezone-plan Asia/Shanghai    # preview timezone change
tt system timezone-set Asia/Shanghai --yes
tt system hostname-plan my-server        # preview hostname change
tt system hostname-set my-server --yes
tt system ip-prefer-status               # show /etc/gai.conf address-family preference
tt system ip-prefer-plan ipv4            # preview IPv4 priority
tt system ip-prefer-set ipv4 --yes       # write IPv4 preference to /etc/gai.conf
tt system ip-prefer-plan default         # preview removing TT IPv4 preference
tt system ip-prefer-set default --yes
tt system restore <backup_dir> --yes     # restore files from a TT system backup
tt system menu
```

Backups default to `/home/tt-backups/system/<timestamp>`, or `TT_SYSTEM_BACKUP_ROOT` when set.

## nginx Gateway

```bash
tt nginx list                    # list configured sites
tt nginx test                    # nginx config test
tt nginx reload                  # reload nginx
tt nginx add <domain> <port>     # render TT site config for internal app port
tt nginx remove <domain>         # remove site config then reload
```

TT preserves the owner's gateway model:

- Public `443` belongs to nginx `stream` with SNI routing.
- Web apps terminate HTTPS internally on `127.0.0.1:4443` where applicable.
- New website configs should not directly steal public `443` from the stream gateway.

## Certificates

```bash
tt cert status
tt cert obtain <domain> [email]
tt cert sync <domain>
tt cert renew
tt cert hook
tt cert install
```

Preferred certificate flow uses webroot `/home/letsencrypt` and avoids stopping nginx.

## Project and Blueprint Deployment

```bash
tt list                              # list deployed TT projects
tt deploy --plan <name>              # preview preset deployment plan
tt configure <blueprint> [dir]       # generate local-only .env files interactively
tt deploy <name>                     # deploy using defaults
tt deploy <name> <type> <domain|none> [port]
tt remove <name>                     # backup then remove project
tt logs <name> [lines]               # show project logs
```

Default rules:

- project path: blueprint `defaults.project_dir`, fallback `/home/docker/<project>`
- domain: blueprint default, fallback `<project>.kazerush.xyz`, or `none` to skip HTTPS
- port: blueprint default first, then managed preset range
- local config: `.example` files render into local `.env` files on the target server
- state: project metadata and port allocations are written only after successful deploy

## App Catalog

```bash
tt apps list
tt apps show <name>
tt apps plan <name> [domain|none] [port]
tt apps menu
```

The app catalog reads TT blueprints and creates personal deployment plans without writing runtime files.

## Docker

```bash
tt docker menu
tt docker ps                         # TT project compose list
tt docker up <project>
tt docker down <project>
tt docker restart <project>
tt docker logs <project> [lines]
tt docker overview                   # Docker engine/container/image/storage overview
tt docker containers                 # all containers
tt docker images                     # images
tt docker storage                    # volumes and networks
tt docker check [project]            # compose config validation
tt docker daemon                     # daemon.json, mirrors, IPv6 inspection
tt docker audit                      # low-memory and safety audit
tt docker prune-plan safe            # preview stopped/dangling/build-cache cleanup
tt docker prune-run safe --yes       # run safe cleanup after pre-clean snapshot
tt docker prune-plan all             # preview aggressive prune including volumes
tt docker prune-run all --yes
```

Use `prune-plan` before `prune-run`; `all` can remove unused volumes and should be treated as destructive.

## Backup and Restore

```bash
tt backup create <project>
tt backup list [project]
tt backup root
tt restore plan <backup.tar.gz>
tt restore stage <backup.tar.gz> [target_dir]
tt restore verify <backup.tar.gz> [target_dir]
```

Restore commands stage or verify backups without overwriting production by default.

## Ports

```bash
tt ports list
tt ports alloc <project> [group] [key]
tt ports release <project>
tt ports
```

Ports are managed as TT state to avoid collisions between project blueprints.

## Firewall

```bash
tt firewall status
tt firewall ports
tt firewall plan allow 443 tcp [source_cidr]
tt firewall plan deny 22 tcp [source_cidr]
tt firewall backup
tt firewall apply allow 443 tcp [source_cidr]
tt firewall apply delete 443 tcp [source_cidr]
tt firewall restore <backup_dir>
tt firewall menu
```

Supported backends include `ufw`, `firewalld`, `nft`, and `iptables` where available. Writes create a backup first.

## Bench and Network Tests

```bash
tt bench menu
tt bench all
tt bench ip
tt bench dns
tt bench ping
tt bench http
tt bench speed
tt bench streaming
tt bench hardware
```

`all` runs lightweight IP/DNS/ping/HTTP tests. Speed and streaming checks may use external network services.

## SSH Management

```bash
tt ssh status
tt ssh harden-plan [port]
tt ssh backup
tt ssh harden-write [port] --yes
tt ssh restore <backup_dir>
tt ssh menu
```

Hardening uses a preview-first model and backs up `sshd_config` and `sshd_config.d` before writing.

## User Management

```bash
tt users list
tt users create-plan <user> [normal|sudo]
tt users create <user> [normal|sudo] --yes
tt users lock-plan <user>
tt users lock <user> --yes
tt users delete-plan <user>
tt users delete <user> --yes
tt users backup
tt users menu
```

User writes back up account-related files first and require explicit confirmation.

## hosts Management

```bash
tt hosts list
tt hosts backup
tt hosts add-plan 127.0.0.1 local.test
tt hosts add 127.0.0.1 local.test --yes
tt hosts delete-plan local.test
tt hosts delete local.test --yes
tt hosts restore <backup_file_or_dir> --yes
tt hosts menu
```

Backups default to `/home/tt-backups/hosts` or `TT_HOSTS_BACKUP_ROOT` when set.

## Disk and Mounts

```bash
tt disk overview
tt disk mounts
tt disk candidates
tt disk health
tt disk mount-plan <device> <mountpoint> [ext4|xfs]
tt disk format-plan <device> [ext4|xfs] [label]
tt disk format-write <device> [ext4|xfs] [label] --yes
tt disk mount-write <device> <mountpoint> [ext4|xfs] --yes
tt disk unmount-write <device|mountpoint> --yes
tt disk menu
```

Formatting is destructive. Mount/unmount writes touch `/etc/fstab`; inspect plans first.

## Security Tools

```bash
tt security status
tt security fail2ban-plan
tt security fail2ban-install
tt security clamav-plan [dir]
tt security clamav-scan [dir]
tt security menu
```

Fail2ban installation changes packages/services. ClamAV scan plans are preview-first and can use containerized scanning where implemented.

## Cluster Nodes

```bash
tt cluster status
tt cluster list
tt cluster add <name> <user@host> [port] [key]
tt cluster remove <name>
tt cluster run <name> <cmd>
tt cluster copy <name> <local> <remote>
tt cluster tt-selftest <name>
tt cluster menu
```

Cluster state is local inventory-backed. `tt-selftest` uploads a temporary TT copy to the remote node and runs safe checks there.

## Rsync Tasks

```bash
tt tasks list
tt tasks add <name> <push|pull> <local> <user@host:/path> [port] [key] [opts]
tt tasks plan <name>
tt tasks run <name>
tt tasks schedule <name> [hourly|daily|weekly|cron]
tt tasks unschedule <name>
tt tasks remove <name>
tt tasks crontab
tt tasks menu
```

Use `plan` before `run`; scheduled tasks are TT-managed crontab entries.

## Upstream Reference Flow

TT may use `kejilion.sh` as a read-only reference for mature menu/tool ideas, but TT does not execute kejilion project deployment functions because they can overwrite the nginx gateway model.

```bash
tt upstream sync
tt upstream report
tt upstream guard
tt selftest
```

Rules:

- borrow menu style, system tools, Docker panels, and test-script ideas
- translate projects into TT blueprints instead of calling kejilion deployment functions
- keep public `443` owned by TT stream/SNI routing
- keep websites on internal `127.0.0.1:4443` HTTPS listeners
- run `tt upstream guard` and `tt selftest` after upstream-inspired changes

## Coverage and Selftest

```bash
tt coverage
tt selftest
```

`selftest` runs safe read-only/low-risk commands only. It intentionally skips real project deployment and destructive system updates unless a dedicated test target is provided.

## Standard Paths

```text
/opt/tiantian/                    script repository
/home/web/                        nginx gateway
/home/docker/<project>/           project runtime directory
/home/tt-backups/<project>/       project backup archive directory
/home/tt-backups/system/          TT system-setting backups
/home/tt-secrets/<project>/       local secrets directory
/home/tt-cache/                   cache/runtime helper directory
```

See `docs/blueprint-v2.md` for the v2 architecture plan.
