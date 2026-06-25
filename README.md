# TianTian Kejilion Nginx Patch

独立补丁包：只接管 kejilion 脚本的 nginx 覆盖生成逻辑，不换皮、不改 k 入口、不迁移其他功能。

## Commands

- `kp`：对当前 `/usr/local/bin/k` 和 `/root/kejilion.sh` 打 TT nginx 补丁
- `kp update`：检查 kejilion 上游更新，下载新版，打补丁，验证，失败回滚
- `kp check`：只检查上游是否变化和当前补丁状态
- `kp rollback`：回滚到最近一次补丁前备份
- `kp status`：查看补丁状态

## Protected nginx model

- 公网 `443` 由 `/home/web/stream.d/reality-relay.conf` 负责 SNI 分流
- HTTPS 站点监听 `127.0.0.1:4443 ssl/quic`
- `/home/web/nginx.conf`、`default.conf`、`map.conf`、`docker-compose.yml`、`reality-relay.conf` 使用本目录模板覆盖

## Backups

- 补丁前脚本备份：`/opt/tiantian/backups/`
- 旧 TT 项目完整备份：`/root/backups/tiantian-reset/`
