#!/system/bin/sh
# verity-guard 设备端助手 —— 只做读写块设备与取指纹，不含策略
BYNAME=/dev/block/by-name
op=${1:-}
[ $# -gt 0 ] && shift

hash_one() {
  p=$1
  [ -e "$BYNAME/$p" ] || { echo "MISSING $p"; return 0; }
  sz=$(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)
  h=$(sha256sum "$BYNAME/$p" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$sz" ] || [ -z "$h" ]; then echo "ERR hash $p"; return 0; fi
  echo "H $p $sz $h"
}

case "$op" in
  snapshot)
    echo "P ts=$(date +%s)"
    echo "P slot=$(getprop ro.boot.slot_suffix)"
    echo "P vbs=$(getprop ro.boot.verifiedbootstate)"
    echo "P locked=$(getprop ro.boot.flash.locked)"
    echo "P model=$(getprop ro.product.model)"
    echo "P build=$(getprop ro.build.display.id)"
    echo "P fp=$(getprop ro.build.fingerprint)"
    echo "P enforce=$(getenforce 2>&1)"
    for d in /sys/block/dm-*/dm/name; do
      [ -r "$d" ] && echo "V $(cat "$d" 2>/dev/null)"
    done
    for p in "$@"; do hash_one "$p"; done
    ;;
  backup)
    dest=$1; shift
    mkdir -p "$dest"
    for p in "$@"; do
      [ -e "$BYNAME/$p" ] || { echo "MISSING $p"; continue; }
      dd if="$BYNAME/$p" of="$dest/$p.img" bs=1M 2>/dev/null || { echo "ERR dd $p"; continue; }
      echo "D $p $(blockdev --getsize64 "$BYNAME/$p")"
    done
    ;;
  restore)
    p=$1; src=$2
    [ -e "$BYNAME/$p" ] || { echo "ERR no_part $p"; exit 1; }
    [ -f "$src" ]    || { echo "ERR no_src $src"; exit 1; }
    psz=$(blockdev --getsize64 "$BYNAME/$p")
    fsz=$(wc -c < "$src")
    [ "$psz" = "$fsz" ] || { echo "ERR size part=$psz img=$fsz"; exit 1; }
    dd if="$src" of="$BYNAME/$p" bs=1M 2>/dev/null || { echo "ERR dd"; exit 1; }
    blockdev --flushbufs "$BYNAME/$p" 2>/dev/null
    echo "WROTE $p $fsz"
    hash_one "$p"
    ;;
  list)
    for p in "$@"; do echo "S $p $(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)"; done
    ;;
  *)
    echo "usage: dev.sh {snapshot|backup|restore|list} ARGS"
    exit 2
    ;;
esac
