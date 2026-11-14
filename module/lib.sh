#!/system/bin/sh
# lib.sh —— 公共部分：进度上报 / 后台起进程
# 所有脚本都从这里拿 G，避免各写一份路径
VG_DEF=/sdcard/Download/DSH-Go/guard
VG_G=${VG_G:-$VG_DEF}
G=$VG_G
CH=$G/chan
SELFDIR=/data/adb/modules/vgd

prog() {
  if [ -n "$VG_QUIET" ]; then echo "$*"; return; fi
  printf '%s\n' "$*" > "$CH/progress.txt.tmp" 2>/dev/null \
    && mv -f "$CH/progress.txt.tmp" "$CH/progress.txt" 2>/dev/null
  # 只有在默认目录上跑才更新面板，测试用的临时目录不许污染 WebUI
  [ "$G" = "$VG_DEF" ] && cp -f "$CH/progress.txt" "$SELFDIR/webroot/progress.txt" 2>/dev/null
  echo "$*"
}

# 后台起一个脚本，立刻返回；老设备没有 setsid 就退回 nohup
spawn() {
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$@" >/dev/null 2>&1 &
  else
    nohup sh "$@" >/dev/null 2>&1 &
  fi
}
