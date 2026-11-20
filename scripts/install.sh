#!/usr/bin/env bash
# 安装 disk-cleanup 脚本与 systemd 用户定时器。
#   ./scripts/install.sh                      # 只安装清理任务
#   ./scripts/install.sh --data-dir /mnt/data # 同时把重缓存迁到数据盘
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DATA_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --data-dir) DATA_DIR="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
done

install -Dm755 "$ROOT/bin/disk-cleanup" "$HOME/.local/bin/disk-cleanup"
install -Dm644 "$ROOT/systemd/disk-cleanup.service" "$HOME/.config/systemd/user/disk-cleanup.service"
install -Dm644 "$ROOT/systemd/disk-cleanup.timer" "$HOME/.config/systemd/user/disk-cleanup.timer"

systemctl --user daemon-reload
systemctl --user enable --now disk-cleanup.timer

if [ -n "$DATA_DIR" ]; then
  "$ROOT/scripts/offload-cache.sh" --data-dir "$DATA_DIR"
fi

systemctl --user start disk-cleanup.service || true
echo
echo "安装完成。"
echo "  定时器：$(systemctl --user list-timers disk-cleanup.timer --no-pager | sed -n '2p')"
echo "  日志：  ${XDG_STATE_HOME:-$HOME/.local/state}/disk-cleanup.log"
