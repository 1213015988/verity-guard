#!/system/bin/sh
# 开机 / 模块更新时拉起 vgd（加锁防并发，避免多实例互相踩）
P=/data/adb/modules/vgd
G=/sdcard/Download/DSH-Go/guard
L=/data/adb/vgd.lock

[ -f "$P/disable" ] && exit 0

mkdir -p "$G/chan" "$G/backup" "$G/exports" 2>/dev/null

i=0
while ! mkdir "$L" 2>/dev/null; do
  i=$((i+1))
  [ $i -gt 50 ] && break
  sleep 0.2
done
for pid in $(ps -A -o PID,ARGS 2>/dev/null | grep "[v]gd\.sh$" | awk '{print $1}'); do
  kill -9 "$pid" 2>/dev/null
done
sleep 0.3
if command -v setsid >/dev/null 2>&1; then
  setsid sh "$P/vgd.sh" >/dev/null 2>&1 &
else
  nohup sh "$P/vgd.sh" >/dev/null 2>&1 &
fi
sleep 1
rmdir "$L" 2>/dev/null
