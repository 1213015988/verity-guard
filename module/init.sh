#!/system/bin/sh
# init.sh --yes [--force] —— 建立基线：只读取分区、记录哈希，不写任何分区
# 换机型 / 刷了固件之后都要重建基线，否则守卫会按别人的口径报警
# baseline.txt 给 shell 用；baseline.json 与 guard.py 的格式兼容，两边可以互相接手
M=/data/adb/modules/vgd
. "$M/lib.sh"
. "$M/parts.sh"
BASE=$G/baseline.txt
BJSON=$G/baseline.json
B=$G/backup

yes=0
force=0
for a in "$@"; do
  [ "$a" = "--yes" ] && yes=1
  [ "$a" = "--force" ] && force=1
done

if [ "$yes" != "1" ]; then
  echo "ERR need_confirm"
  prog "建立基线被取消：没有确认"
  exit 9
fi

mkdir -p "$G/chan" "$B" "$G/exports" 2>/dev/null
detect_parts
if [ -z "$PARTS" ]; then
  echo "ERR no_partition"
  prog "建立基线失败：一个关键分区都没找到"
  exit 2
fi

if [ -f "$BASE" ] && [ "$force" != "1" ]; then
  old=$(wc -l < "$BASE" 2>/dev/null | tr -d ' ')
  echo "ERR baseline_exists"
  prog "建立基线被拒绝：已有基线（$old 个分区），要覆盖请加 --force"
  exit 8
fi

vb=$(getprop ro.boot.verifiedbootstate 2>/dev/null)
if [ "$vb" != "green" ]; then
  prog "提示：verifiedbootstate=$vb，基线记录的是当前实际内容"
fi

tmp=$BASE.tmp
raw=$G/tmp/base.$$
mkdir -p "$G/tmp" 2>/dev/null
: > "$tmp" && : > "$raw" || { prog "建立基线失败：$G 不可写"; echo "ERR not_writable"; exit 5; }

i=0
for p in $PARTS; do
  i=$((i+1))
  prog "建立基线 $i/$NP：$p"
  h=$(sha256sum "$BYNAME/$p" 2>/dev/null | cut -c1-64)
  if [ -z "$h" ]; then
    rm -f "$tmp" "$raw"
    echo "ERR hash $p"
    prog "建立基线失败：$p 读不出来"
    exit 3
  fi
  sz=$(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)
  [ -n "$sz" ] || sz=0
  echo "$p $h" >> "$tmp"
  echo "$p $h $sz" >> "$raw"
done
mv -f "$tmp" "$BASE" || { rm -f "$raw"; prog "建立基线失败：写不进 $BASE"; exit 5; }

# 机器可读的一份，字段与 guard.py 的 baseline.json 一致
model=$(getprop ro.product.model 2>/dev/null)
build=$(getprop ro.build.display.id 2>/dev/null)
fp=$(getprop ro.build.fingerprint 2>/dev/null)
locked=$(getprop ro.boot.flash.locked 2>/dev/null)
enf=$(getenforce 2>/dev/null)
{
  printf '{\n  "version": 1,\n  "created": %s,\n  "created_str": "%s",\n' "$(date +%s)" "$(date '+%F %T')"
  printf '  "props": {"model": "%s", "slot": "%s", "vbs": "%s", "locked": "%s", "enforce": "%s", "build": "%s", "fp": "%s"},\n' \
    "$model" "$SLOT" "$vb" "$locked" "$enf" "$build" "$fp"
  printf '  "parts": {\n'
  first=1
  while read -r n h sz; do
    [ -n "$n" ] || continue
    if [ "$first" = "1" ]; then first=0; else printf ',\n'; fi
    printf '    "%s": {"size": %s, "sha256": "%s"}' "$n" "$sz" "$h"
  done < "$raw"
  printf '\n  },\n  "deep": false\n}\n'
} > "$BJSON.tmp" 2>/dev/null
rm -f "$raw"
[ -s "$BJSON.tmp" ] && mv -f "$BJSON.tmp" "$BJSON"

prog "基线建立完成：$NP 个分区（$(date +%H:%M)）"
echo "BASELINE ok $NP"
