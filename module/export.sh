#!/system/bin/sh
# export.sh —— 打包排障包：原始日志 + 状态 + 环境 + 脚本；采集失败也记进日志
. /data/adb/modules/vgd/lib.sh
. /data/adb/modules/vgd/parts.sh
M=/data/adb/modules/vgd
E=$G/exports
LOG=$CH/export.log
mkdir -p "$E" "$CH" 2>/dev/null
if [ -z "$VG_ECHO" ]; then
  : > "$LOG"
  exec >> "$LOG" 2>&1
fi

ts=$(date +%Y%m%d-%H%M%S)
out=$E/vg-report-$ts.tar.gz
tmp=/data/local/tmp/vg-exp-$$
rm -rf "$tmp"; mkdir -p "$tmp/scripts" 2>/dev/null
: > "$tmp/collect.log"

echo "--- export $(date '+%F %T') ---"

# 采集一项：成功记 OK，失败记 FAIL（不计入包内文件）
collect() {
  name=$1
  shift
  timeout 25 "$@" > "$tmp/$name" 2> "$tmp/$name.err"
  rc=$?
  sz=$(wc -c < "$tmp/$name" 2>/dev/null)
  [ -n "$sz" ] || sz=0
  if [ $rc -eq 0 ] && [ "$sz" -gt 0 ]; then
    echo "OK   $name ${sz}B" | tee -a "$tmp/collect.log"
  else
    echo "FAIL $name rc=$rc size=${sz}B（无法导出，已跳过）" | tee -a "$tmp/collect.log"
    rm -f "$tmp/$name"
  fi
}

prog "导出：收集原始日志"
collect logcat logcat -d -v threadtime -t 3000
collect dmesg dmesg
collect last_kmsg cat /proc/last_kmsg

echo "== 其他日志文件 ==" | tee -a "$tmp/collect.log"
for f in "$CH"/vgd.log "$CH"/action.log "$CH"/restore.log "$CH"/backup.log; do
  [ -f "$f" ] || continue
  b=${f##*/}
  cp -f "$f" "$tmp/$b" 2>/dev/null
  s=$(wc -c < "$f" 2>/dev/null)
  [ -n "$s" ] || s=0
  echo "OK   $b ${s}B（原始文件）" | tee -a "$tmp/collect.log"
done

prog "导出：收集状态与脚本"
cp -f "$G/chan/status.json" "$G/chan/logs.json" "$G/chan/progress.txt" "$tmp/" 2>/dev/null
cp -f "$G/baseline.txt" "$G/baseline.json" "$G/README.md" "$tmp/" 2>/dev/null
cp -f "$M"/module.prop "$M"/*.sh "$M/webroot/index.html" "$tmp/scripts/" 2>/dev/null

detect_parts
{
  echo "== 时间 =="; date
  echo "== 机型 =="; getprop ro.product.model; getprop ro.build.display.id; getprop ro.build.fingerprint
  echo "== 启动状态 =="; getprop ro.boot.verifiedbootstate; getprop ro.boot.flash.locked; getprop ro.boot.slot_suffix
  echo "== SELinux =="; getenforce
  echo "== 内核 =="; uname -a
  echo "== 探测到的分区 =="; echo "$PARTS（$NP 个）"
  echo "== 模块列表 =="
  for d in /data/adb/modules/*; do
    [ -d "$d" ] || continue
    n=${d##*/}
    [ -f "$d/module.prop" ] || continue
    id=$(grep '^id=' "$d/module.prop" | cut -d= -f2)
    ver=$(grep '^version=' "$d/module.prop" | cut -d= -f2)
    au=$(grep '^author=' "$d/module.prop" | cut -d= -f2)
    dis=no; [ -f "$d/disable" ] && dis=yes
    echo "$n | id=$id | ver=$ver | author=$au | disabled=$dis"
  done
  echo "== 分区大小 =="
  for p in $PARTS; do
    echo "$p $(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)"
  done
} > "$tmp/meta.txt" 2>&1

for f in "$tmp"/*.err; do
  [ -e "$f" ] || continue
  [ -s "$f" ] || rm -f "$f"
done
prog "导出：打包"
tar -czf "$out" -C "$tmp" . 2>/dev/null
rm -rf "$tmp"

if [ -f "$out" ]; then
  sz=$(wc -c < "$out")
  echo "EXPORTED $out $sz"
  prog "导出完成：$out（$(($sz / 1024)) KB）"
else
  echo "ERR export"
  prog "导出失败：无法写入 $E"
  exit 1
fi
