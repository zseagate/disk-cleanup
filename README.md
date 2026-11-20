# disk-cleanup

小容量 `/home` 的缓存清理与卸载工具：每周自动清掉可再生的缓存和旧日志，并可选把
Gradle、浏览器等重缓存迁到大容量数据盘（原路径保留软链），让系统盘不再被缓存撑满。

起源于一台 Linux Mint / macOS 双启动机器：`/home` 只有 7.6G，浏览器缓存和 Android
构建缓存反复把分区顶到 98%，所以把规则固化成脚本 + systemd 定时器。

## 清理内容

| 项目 | 规则 |
| --- | --- |
| OpenCode 桌面版待安装的 `.deb` | 超过 1 天删除（对应版本通常已安装） |
| pip 缓存 | 超过 30 天删除 |
| uv 缓存 | `uv cache prune`（只清未引用条目） |
| 缩略图 | 超过 14 天删除 |
| Mesa 着色器缓存 | 超过 30 天删除 |
| Chrome / Chromium / Edge / Vivaldi / Brave 磁盘缓存 | 浏览器未运行时清理；运行中跳过 |
| Firefox 磁盘缓存 | 同上 |
| 钉钉缓存与 7 天前日志 | 钉钉未运行时清理 |
| 微信旧日志 / crashinfo | 超过 7 天删除 |
| OpenCode 7 天前日志 | 删除 |

**不碰**：配置、书签、密码、聊天记录、项目文件、OpenCode session 数据库、下载目录。

## 安装

依赖：Linux、bash、systemd（用户实例）、`pgrep`、`find`、`df`。

```bash
git clone git@github.com:<you>/disk-cleanup.git
cd disk-cleanup
./scripts/install.sh
```

安装后：

- 脚本：`~/.local/bin/disk-cleanup`
- 定时器：`disk-cleanup.timer`，每周日 04:30 执行，开机 15 分钟后补跑一次
- 日志：`~/.local/state/disk-cleanup.log`

手动执行一次：

```bash
~/.local/bin/disk-cleanup
systemctl --user list-timers disk-cleanup.timer
```

## 把重缓存迁到数据盘（可选）

适合 `/home` 很小、另有数据盘的机器：

```bash
./scripts/install.sh --data-dir /mnt/data
# 或单独执行
./scripts/offload-cache.sh --data-dir /mnt/data
```

迁移列表：

- `~/.gradle`
- `~/.cache/google-chrome`、`chromium`、`microsoft-edge`、`vivaldi`
- `~/.cache/mozilla`（Firefox）
- `~/.cache/thumbnails`

原路径会变成指向 `<数据盘>/disk-cleanup-cache/<名称>` 的软链，应用无需改配置。
脚本会：

1. 拒绝非挂载点（防止数据盘未挂载时写入系统盘），确认可用 `--force`
2. 目标文件系统大小写不敏感时，检查同目录文件名冲突（exfat/NTFS）
3. 复制后校验文件数一致才删除原目录
4. 相关程序运行时跳过该目录（关闭浏览器后重跑即可）

只迁移其中几项：

```bash
./scripts/offload-cache.sh --data-dir /mnt/data --only gradle,microsoft-edge
```

迁回原位置：

```bash
./scripts/offload-cache.sh --restore
```

## 配置

`offload-cache.sh` 会生成 `~/.config/disk-cleanup/config`：

```bash
DATA_MOUNT="/mnt/data"
CACHE_ROOT="/mnt/data/disk-cleanup-cache"
```

- `DATA_MOUNT`：数据盘挂载点；未挂载时日志会告警
- `CACHE_ROOT`：软链目标必须位于此目录下，清理脚本才会清空，防止配置错误误删

也可以手动创建该文件，只设置其中一项。

## 卸载

```bash
./scripts/uninstall.sh            # 移除脚本与定时器
./scripts/uninstall.sh --restore  # 同时把软链缓存迁回
```

## 注意事项

- 浏览器运行中不会清理其缓存；缓存目录是软链时只清链接目标内容，保留软链。
- systemd 用户定时器在用户退出登录后是否继续运行取决于 `loginctl enable-linger`；
  桌面日常使用无需开启。
- exfat 等文件系统簇较大（如 128K），大量小文件（Gradle 缓存）实际占用会明显大于
  ext4，迁移前请确认数据盘空间充足。
- 本工具不处理需要 root 的清理项（journal、apt 缓存、旧内核），需要时手动执行：

  ```bash
  sudo journalctl --vacuum-size=200M
  sudo apt clean
  sudo apt autoremove --purge
  ```

## 目录结构

```
bin/disk-cleanup          清理脚本（systemd 定时器调用）
scripts/install.sh        安装脚本与定时器
scripts/uninstall.sh      卸载
scripts/offload-cache.sh  缓存迁移/迁回
systemd/                  systemd 用户单元
```

## License

[MIT](LICENSE)
