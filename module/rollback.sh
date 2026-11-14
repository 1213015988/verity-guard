#!/system/bin/sh
# rollback.sh --yes —— 把和基线不一致的分区，逐个从备份写回去
# 只写「本来有备份、备份哈希等于基线」的分区，其余拒绝
. /data/adb/modules/vgd/lib.sh
. /data/adb/modules/vgd/parts.sh
M=/data/adb/modules/vgd
BASE=$G/baseline.txt

if [ "$1" != "--yes" ]; then
  echo "ERR need_confirm"
  prog "回退被取消：没有确认"
  exit 9
fi
if [ ! -s "$BASE" ]; then
  echo "REFUSED no_baseline"
  prog "回退被拒绝：还没有基线"
  exit 8
fi

detect_parts
bad=""
for p in $PARTS; do
  want=$(awk -v k="$p" '$1==k{print $2}' "$BASE" 2>/dev/null)
  [ -n "$want" ] || continue
  got=$(sha256sum "$BYNAME/$p" 2>/dev/null | cut -c1-64)
  [ "$got" = "$want" ] || bad="$bad $p"
done

if [ -z "$bad" ]; then
  prog "回退：所有分区都和基线一致，不用回写"
  echo "OK nothing"
  exit 0
fi

n=$(printf '%s' "$bad" | wc -w | tr -d ' ')
echo "需要回写：$bad"
prog "开始回退 $n 个分区：$bad"

okn=0
failn=0
for p in $bad; do
  prog "回退 $p…"
  sh "$M/restore.sh" "$p" --yes > "$G/chan/rollback-${p}.log" 2>&1
  rc=$?
  if [ $rc -eq 0 ]; then
    okn=$((okn + 1))
    echo "OK $p"
  else
    failn=$((failn + 1))
    echo "FAIL $p rc=$rc（日志 chan/rollback-${p}.log）"
  fi
done

prog "回退结束：成功 $okn 个，失败 $failn 个"
VG_QUIET=1 sh "$M/wd.sh" >/dev/null 2>&1
if [ "$failn" -eq 0 ]; then
  echo "ROLLBACK ok $okn"
  exit 0
fi
echo "ROLLBACK fail $failn"
exit 1
