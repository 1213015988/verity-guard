#!/system/bin/sh
# backup.sh --yes —— 先校验全部分区与基线一致，再备份；没有基线直接拒绝
. /data/adb/modules/vgd/lib.sh
. /data/adb/modules/vgd/parts.sh
B=$G/backup
BASE=$G/baseline.txt
M=/data/adb/modules/vgd

if [ "$1" != "--yes" ]; then
  echo "ERR need_confirm"
  exit 9
fi

mkdir -p "$B" "$CH" "$G/exports" 2>/dev/null

detect_parts
[ -n "$PARTS" ] || { echo "ERR no_partition"; prog "备份失败：没找到可备份的分区"; exit 2; }
if [ ! -s "$BASE" ]; then
  echo "REFUSED no_baseline"
  prog "备份被拒绝：还没有基线，先建立基线"
  exit 8
fi

# 前置校验：分区必须与基线一致，否则备份等于把坏数据存档
bad=""
miss=""
i=0
for p in $PARTS; do
  i=$((i+1))
  prog "备份前校验 $i/$NP：$p"
  want=$(awk -v k="$p" '$1==k{print $2}' "$BASE" 2>/dev/null)
  if [ ! -e "$BYNAME/$p" ]; then
    miss="$miss $p"
    continue
  fi
  if [ -z "$want" ]; then
    bad="$bad $p"
    continue
  fi
  got=$(sha256sum "$BYNAME/$p" 2>/dev/null | cut -c1-64)
  if [ -z "$got" ] || [ "$got" != "$want" ]; then
    bad="$bad $p"
  fi
done
if [ -n "$bad" ] || [ -n "$miss" ]; then
  prog "备份被拒绝：分区与基线不一致$bad$miss"
  echo "REFUSED partition_changed:$bad$miss"
  echo "先重建基线或回写以下分区：$bad$miss"
  VG_QUIET=1 sh "$M/wd.sh" >/dev/null 2>&1
  exit 7
fi
# 空间检查：不够就别开始，免得写一半
# 注意：mksh 是 32 位算术，按字节算会溢出，统一用 MB
need_mb=0
for p in $PARTS; do
  s=$(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)
  [ -n "$s" ] && need_mb=$((need_mb + s / 1048576))
done
have_mb=0
for f in "$B"/*.img; do
  [ -f "$f" ] || continue
  s=$(stat -c %s "$f" 2>/dev/null)
  have_mb=$((have_mb + ${s:-0} / 1048576))
done
ak=$(df -k "$G" 2>/dev/null | awk 'END{print $4}')
[ -n "$ak" ] || ak=0
avail_mb=$((ak / 1024 + have_mb))
if [ "$avail_mb" -lt "$need_mb" ]; then
  prog "备份被拒绝：空间不够（需要 $need_mb MB，可用 $avail_mb MB）"
  echo "REFUSED no_space need=${need_mb}MB avail=${avail_mb}MB"
  exit 6
fi
echo "PREFLIGHT ok need=${need_mb}MB avail=${avail_mb}MB"
prog "校验通过（需 $need_mb MB，可用 $avail_mb MB），开始写入备份"

if [ -z "$VG_ECHO" ]; then
  : > "$CH/backup.log"
  exec >> "$CH/backup.log" 2>&1
fi
echo "--- backup $(date '+%F %T') ---"

n=0
fail=0
i=0
for p in $PARTS; do
  i=$((i+1))
  prog "备份 $i/$NP：$p"
  src=$BYNAME/$p
  if [ ! -e "$src" ]; then
    echo "MISSING $p"
    fail=$((fail+1))
    continue
  fi
  if dd if="$src" of="$B/$p.img" bs=1M 2>/dev/null; then
    sha256sum "$B/$p.img" 2>/dev/null | cut -c1-64 > "$B/$p.img.sha256"
    sz=$(wc -c < "$B/$p.img" 2>/dev/null)
    echo "OK $p $sz"
    n=$((n+1))
  else
    echo "ERR dd $p"
    fail=$((fail+1))
  fi
done

echo "BACKED_UP $n fail=$fail"
VG_QUIET=1 sh "$M/wd.sh" >/dev/null 2>&1
prog "备份完成：$n 个分区"
echo "DONE"
