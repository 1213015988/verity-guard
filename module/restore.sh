#!/system/bin/sh
# restore.sh <分区> --yes —— 校验副本与基线一致后回写，并复验
. /data/adb/modules/vgd/lib.sh
. /data/adb/modules/vgd/parts.sh
B=$G/backup
BASE=$G/baseline.txt
part=$1

fail() { prog "回写失败：$1"; echo "ERR $2"; exit "$3"; }

case "$part" in
  ""|*/*|*..*) fail "分区名非法" bad_part 1 ;;
esac
[ "$2" = "--yes" ] || fail "未确认" need_confirm 9

img=$B/$part.img
[ -f "$img" ] || fail "没有 $part 的备份" no_backup 1

p=$BYNAME/$part
[ -e "$p" ] || fail "分区 $part 不存在" no_partition 1

psz=$(blockdev --getsize64 "$p" 2>/dev/null)
fsz=$(wc -c < "$img" 2>/dev/null)
[ -n "$psz" ] && [ "$psz" = "$fsz" ] || fail "尺寸不匹配" "size part=$psz img=$fsz" 2

want=$(awk -v k="$part" '$1==k{print $2}' "$BASE" 2>/dev/null)
[ -n "$want" ] || fail "基线里没有 $part" no_baseline 3

prog "回写 $part：校验副本"
got=$(sha256sum "$img" 2>/dev/null | cut -c1-64)
[ "$got" = "$want" ] || fail "副本与基线不符" backup_mismatch 4

prog "回写 $part：写入中"
dd if="$img" of="$p" bs=1M 2>/dev/null || fail "写入出错" dd 5
blockdev --flushbufs "$p" 2>/dev/null

prog "回写 $part：复核哈希"
new=$(sha256sum "$p" 2>/dev/null | cut -c1-64)
if [ "$new" = "$want" ]; then
  echo "RESTORED $part $new"
  prog "回写完成：$part 已恢复并通过校验"
  exit 0
fi
fail "复核不一致" "verify want=$want got=$new" 6
