# TianTian TT Kejilion Nginx Patch Panel

TT 是一个给 kejilion 脚本使用的窄补丁层：不替换 kejilion 主入口，只接管 nginx 覆盖/生成逻辑，保护 `/home/web` 的 SNI/127.0.0.1:4443 架构。

## 安装

```bash
git clone <repo-url> tiantian
cd tiantian
bash install.sh
```

安装后使用：

```bash
tt
```

首次运行如果检测到 kejilion 已安装但补丁未安装，会询问：

- `y/yes`：立即安装补丁
- `n/no`：进入面板

## 面板

```text
1. 补丁安装
2. 补丁状态
3. 备份恢复
0. 退出
```

## 报告格式

成功报告只保留三项：

```text
状态: ...
检测: ...
备份: ...
```

失败报告按阶段提示：检测 / 备份 / 执行 / 验收。若原因无法精确判断，会提示查看上方真实命令输出，不编造原因。

## 备份策略

- `/opt/tiantian/backups/latest`：最近一次操作前备份，重复执行会覆盖。
- `/opt/tiantian/backups/original`：首次原始备份，只创建一次。

## 常用命令

普通使用只需要：

```bash
tt
```

维护命令：

```bash
kp install
kp status
kp restore
kp update
```

## 验证

```bash
bash -n /opt/tiantian/bin/kp
bash -n /opt/tiantian/tiantian.sh
bash -n /usr/local/bin/k
bash -n /root/kejilion.sh
docker exec nginx nginx -t  # nginx 容器存在时
kp status
```
