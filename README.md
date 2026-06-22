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
tt deps doctor   # check required/recommended dependencies
tt deps install  # install missing recommended dependencies
tt deps versions # show installed dependency versions
tt update        # pull latest TT scripts and project blueprints
tt tools         # terminal system toolbox menu
tt tools resource # CPU/memory/disk overview
tt tools ports   # listening ports
tt tools clean   # clean package/log cache after confirmation
tt firewall status # read-only firewall/rules/listening-port report
tt firewall backup # snapshot current ufw/firewalld/nft/iptables state
tt firewall apply allow 443 tcp # write firewall rule after confirmation, with rollback path
tt firewall restore <backup_dir> # restore from a TT firewall backup
tt bench all     # lightweight IP/DNS/ping/HTTP tests
tt bench ip      # public IP and ipinfo summary
tt bench speed   # download speed test (Cloudflare/Hetzner ~100MB)
tt bench streaming # streaming region unlock check (Netflix/YouTube/Disney+/etc)
tt bench hardware # CPU/memory/disk/OpenSSL quick benchmark
tt ops ssh       # read-only SSH security/listener/auth-key summary
tt ssh harden-plan 22 # preview SSH hardening drop-in without writing
tt ssh backup    # backup sshd_config and sshd_config.d
tt ssh harden-write 22 --yes # write SSH hardening drop-in after explicit confirmation
tt ssh restore <backup_dir> # restore SSH config from backup
tt users list    # system user/sudo/lock overview
tt users create-plan deploy sudo # preview creating a sudo-capable user
tt users create deploy sudo --yes # create user after backup and explicit confirmation
tt users delete-plan deploy # preview destructive user removal
tt hosts list    # view /etc/hosts with line numbers
tt hosts add-plan 127.0.0.1 local.test # preview adding a hosts record
tt hosts add 127.0.0.1 local.test --yes # add hosts record after backup
tt hosts delete-plan local.test # preview deleting matching hosts records
tt ops dns       # DNS resolver and name-resolution diagnostics
tt ops cron      # crontab and systemd timer overview
tt ops bbr       # TCP congestion / BBR status
tt ops process   # process, load, CPU/memory top, zombie check
tt ops disk      # filesystem, inode, large-dir and large-log overview
tt ops services  # systemd service active/enabled/failed overview
tt ops tmux      # tmux/background workspace status
tt swap 2048     # create/replace 2GB swap after confirmation
tt selftest      # safe read-only/low-risk smoke test
tt upstream sync # download kejilion.sh as read-only reference
tt upstream guard # verify TT stream/SNI gateway protection
tt profile       # server profile
tt deploy --plan toko      # preview preset deployment plan
tt apps list               # list personal blueprint app catalog
tt apps show toko          # show app details from blueprint manifest/readme
tt apps plan toko          # preview app deploy plan without writing files
tt firewall plan allow 443 tcp # print backup steps and candidate firewall commands only
tt cluster add jp root@1.2.3.4 22 ~/.ssh/key # add remote node
tt cluster run jp 'hostname && uptime' # execute command on remote node
tt cluster tt-selftest jp # upload temporary TT copy and run selftest remotely
tt tasks list    # list rsync sync jobs
tt tasks add backup_www push /home/web root@1.2.3.4:/backup/web 22 ~/.ssh/key # add rsync job
tt tasks plan backup_www # preview rsync command without copying data
tt tasks schedule backup_www daily # add TT-managed crontab entry
tt security status # fail2ban/ClamAV/SSH security overview
tt security fail2ban-plan # show install/enable plan without changing system
tt security clamav-plan /home # show containerized ClamAV read-only scan plan
tt disk overview # disk, partition, filesystem and inode overview
tt disk mounts # mount table and /etc/fstab overview
tt disk candidates # unmounted partition candidates, read-only
tt disk mount-plan /dev/vdb1 /data ext4 # print mount/fstab plan without writing
tt disk format-plan /dev/vdb1 ext4 data # print destructive format plan without executing
tt disk format-write /dev/vdb1 ext4 data --yes # real mkfs; destructive
tt disk mount-write /dev/vdb1 /data ext4 --yes # real mount and append fstab
tt disk unmount-write /data --yes # real umount and remove matching fstab entry
tt configure toko /home/docker/shop  # generate local-only .env files interactively
tt deploy toko             # deploy after local config exists
tt deploy toko toko none 8450  # override type/domain/port
tt docker overview # Docker engine/container/image/storage resource overview
tt docker containers # list all containers
tt docker images # list images
tt docker storage # list volumes and networks
tt docker check [project] # validate compose config without starting containers
tt docker daemon # read-only Docker daemon/mirror/IPv6 config inspection
tt docker audit # read-only Docker safety audit for low-memory hosts
tt docker prune-plan safe # preview stopped-container/dangling-image/build-cache cleanup
tt docker prune-run safe --yes # run safe Docker cleanup after saving a pre-clean snapshot
tt docker prune-plan all # preview aggressive system prune including unused volumes
tt cluster status # read-only cluster/node reachability scaffold
tt coverage      # Kejilion-inspired feature coverage matrix
tt restore plan <backup.tar.gz> # inspect restore plan without touching production
tt restore stage <backup.tar.gz> [dir] # extract backup to staging only
tt restore verify <backup.tar.gz> [dir] # run restore drill into staging, no production overwrite
tt remove        # backup then remove a project
tt backup        # create project backup
tt ports         # show managed port pool
tt help          # command help
```

English commands are the primary interface. Short aliases are also available for frequent operations, for example `tt jc`, `tt bs`, `tt bf`, `tt sc`, `tt rq`, `tt zs`, `tt wg`, `tt yl`, `tt gj`, and `tt cs`.

## Preset Deploy Flow

Recommended new-server flow:

```bash
tt deps doctor
# If required/recommended dependencies are missing:
tt deps install
tt detect
tt nginx test
tt deploy --plan <project>
tt configure <project> [target_dir]
tt deploy <project>
tt health
```

`tt update` refreshes the TT scripts and bundled project blueprints from Git. Use it before deploying on long-lived servers so nginx/Docker/certbot handling and packaged projects stay current.

## Upstream Reference Flow

TT may use `kejilion.sh` as a read-only reference for mature menu/tool ideas, but TT does not execute kejilion project deployment functions because they can overwrite the nginx gateway model.

```bash
tt upstream sync
tt upstream guard
tt selftest
```

Rules:

- borrow menu style, system tools, Docker panels, and test-script ideas
- translate projects into TT blueprints instead of calling kejilion deployment functions
- keep public `443` owned by TT stream/SNI routing
- keep websites on internal `127.0.0.1:4443` HTTPS listeners
- run `tt upstream guard` and `tt selftest` after any upstream-inspired change

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
