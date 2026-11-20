#!/usr/bin/env bash
# offload-cache.sh —— 把可再生的重缓存迁移到大容量磁盘，并在原位置留下软链。
#
# 用法：
#   ./offload-cache.sh --data-dir /mnt/data            # 迁移默认列表
#   ./offload-cache.sh --data-dir /mnt/data --only gradle,google-chrome
#   ./offload-cache.sh --restore                       # 迁回原位置
#
# 迁移后各缓存仍以原路径访问（软链），应用无需改配置。
set -euo pipefail

DATA_DIR=""
RESTORE=0
ONLY=""
FORCE=0

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --data-dir) DATA_DIR="${2:-}"; shift 2 ;;
    --only)     ONLY="${2:-}"; shift 2 ;;
    --restore)  RESTORE=1; shift ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  usage 0 ;;
    *) echo "未知参数：$1" >&2; usage 1 ;;
  esac
done

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/disk-cleanup"
CONFIG="$CONFIG_DIR/config"
CACHE_ROOT="${DATA_DIR:+$DATA_DIR/disk-cleanup-cache}"

# name|源路径|运行中则跳过的进程名（空格分隔）
ENTRIES=(
  "gradle|$HOME/.gradle|GradleDaemon"
  "google-chrome|$HOME/.cache/google-chrome|chrome google-chrome"
  "chromium|$HOME/.cache/chromium|chromium"
  "microsoft-edge|$HOME/.cache/microsoft-edge|msedge microsoft-edge"
  "mozilla|$HOME/.cache/mozilla|firefox-bin firefox"
  "vivaldi|$HOME/.cache/vivaldi|vivaldi-bin vivaldi"
  "thumbnails|$HOME/.cache/thumbnails|"
)

selected() {
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; esac
  return 1
}

running() {
  local n
  for n in $1; do
    pgrep -x "$n" >/dev/null 2>&1 && return 0
  done
  return 1
}

# 目标文件系统大小写不敏感时，同目录下仅大小写不同的文件会互相覆盖
is_case_insensitive() {
  local probe="$1/.caseprobe.$$"
  mkdir -p "$probe" || return 1
  : >"$probe/a"
  local r=1
  [ -e "$probe/A" ] && r=0
  rm -rf "$probe"
  return $r
}

case_collisions() {
  local dir="$1"
  ( cd "$dir" && find . -type d -print0 2>/dev/null |
    while IFS= read -r -d '' d; do
      ls -1A -- "$d" 2>/dev/null | tr 'A-Z' 'a-z' | sort | uniq -d | sed "s|^|$d/|"
    done )
}

if [ "$RESTORE" = 1 ]; then
  # shellcheck disable=SC1090
  [ -r "$CONFIG" ] && . "$CONFIG"
  CACHE_ROOT="${CACHE_ROOT:-}"
  [ -n "$CACHE_ROOT" ] || { echo "未找到 $CONFIG，无法确定迁回位置" >&2; exit 1; }
  for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r name src _ <<<"$entry"
    selected "$name" || continue
    target="$CACHE_ROOT/$name"
    if [ -L "$src" ]; then
      rm -f "$src"
      if [ -d "$target" ]; then
        mkdir -p "$(dirname "$src")"
        echo "迁回 $target -> $src"
        mv "$target" "$src"
      fi
    fi
  done
  rm -f "$CONFIG"
  echo "已恢复。"
  exit 0
fi

[ -n "$DATA_DIR" ] || usage 1
[ -d "$DATA_DIR" ] || { echo "数据目录不存在：$DATA_DIR" >&2; exit 1; }
if [ "$FORCE" != 1 ] && ! mountpoint -q "$DATA_DIR" 2>/dev/null; then
  echo "错误：$DATA_DIR 不是挂载点（防止数据盘未挂载时写到系统盘）。" >&2
  echo "      确认无误可加 --force。" >&2
  exit 1
fi
[ -w "$DATA_DIR" ] || { echo "数据目录不可写：$DATA_DIR" >&2; exit 1; }
mkdir -p "$CACHE_ROOT"

if is_case_insensitive "$DATA_DIR"; then
  echo "提示：$DATA_DIR 大小写不敏感，迁移前会检查文件名冲突。"
fi

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r name src procs <<<"$entry"
  selected "$name" || continue
  target="$CACHE_ROOT/$name"

  if [ -L "$src" ]; then
    if [ "$(readlink "$src")" = "$target" ]; then
      echo "跳过 $name：已指向 $target"
    else
      echo "跳过 $name：已是指向 $(readlink "$src") 的软链" >&2
    fi
    continue
  fi

  if [ ! -e "$src" ]; then
    mkdir -p "$target"
    ln -s "$target" "$src"
    echo "创建 $name：$src -> $target（原目录不存在）"
    continue
  fi

  if [ -n "$procs" ] && running "$procs" && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
    echo "跳过 $name：相关程序正在运行（$procs），请关闭后重试" >&2
    continue
  fi

  if is_case_insensitive "$DATA_DIR"; then
    collisions=$(case_collisions "$src" | head -5)
    if [ -n "$collisions" ]; then
      echo "跳过 $name：目标文件系统大小写不敏感，存在同名冲突：" >&2
      printf '  %s\n' "$collisions" >&2
      continue
    fi
  fi

  src_count=$(find "$src" -type f 2>/dev/null | wc -l)
  mkdir -p "$target"
  cp -a "$src/." "$target/"
  dst_count=$(find "$target" -type f 2>/dev/null | wc -l)
  if [ "$src_count" != "$dst_count" ]; then
    echo "错误：$name 复制文件数不一致（$src_count != $dst_count），已保留原目录" >&2
    exit 1
  fi
  rm -rf "$src"
  ln -s "$target" "$src"
  echo "已迁移 $name：$src -> $target（$dst_count 个文件）"
done

mkdir -p "$CONFIG_DIR"
{
  echo "# 由 offload-cache.sh 生成，供 disk-cleanup 使用"
  printf 'DATA_MOUNT="%s"\n' "$DATA_DIR"
  printf 'CACHE_ROOT="%s"\n' "$CACHE_ROOT"
} >"$CONFIG"
echo "配置已写入 $CONFIG"
df -h /home "$DATA_DIR" 2>/dev/null | tail -3 || true
