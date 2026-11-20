#!/usr/bin/env bash
# 卸载 disk-cleanup。
#   ./scripts/uninstall.sh            # 仅移除脚本与定时器
#   ./scripts/uninstall.sh --restore  # 同时把软链缓存迁回 /home
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RESTORE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --restore) RESTORE=1; shift ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
done

[ "$RESTORE" = 1 ] && "$ROOT/scripts/offload-cache.sh" --restore

systemctl --user disable --now disk-cleanup.timer 2>/dev/null || true
rm -f "$HOME/.local/bin/disk-cleanup"
rm -f "$HOME/.config/systemd/user/disk-cleanup.service"
rm -f "$HOME/.config/systemd/user/disk-cleanup.timer"
systemctl --user daemon-reload
echo "已卸载。日志保留在 ${XDG_STATE_HOME:-$HOME/.local/state}/disk-cleanup.log"
