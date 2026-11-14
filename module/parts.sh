#!/system/bin/sh
# parts.sh —— 现场探测要守护的分区，不写死机型
# 调用后可用：PARTS（空格分隔）、NP（个数）、BYNAME、SLOT
BYNAME=/dev/block/by-name
[ -d "$BYNAME" ] || BYNAME=/dev/block/bootdevice/by-name
[ -d "$BYNAME" ] || BYNAME=/dev/block/platform/soc/by-name
SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)

# 需要守护的分区基名。顺序就是面板顺序。
# 想多守一个，往这里加基名（如 recovery、persist），然后重建基线。
BASES="vbmeta vbmeta_system vbmeta_vendor boot init_boot vendor_boot dtbo"

detect_parts() {
  PARTS=""
  for b in $BASES; do
    if [ -n "$SLOT" ]; then
      for s in _a _b; do
        [ -e "$BYNAME/$b$s" ] && PARTS="$PARTS $b$s"
      done
    fi
    # 单槽设备，或该分区本身不分槽
    [ -e "$BYNAME/$b" ] && PARTS="$PARTS $b"
  done
  PARTS=$(printf '%s' "$PARTS" | sed 's/^ *//')
  NP=$(printf '%s' "$PARTS" | wc -w | tr -d ' ')
}

# 基线里出现、但现在探测不到的分区（固件升级后分区消失等）
baseline_only() {
  [ -s "$1" ] || return 0
  out=""
  for p in $(awk '{print $1}' "$1" 2>/dev/null); do
    case " $PARTS " in *" $p "*) ;; *) out="$out $p" ;; esac
  done
  printf '%s' "$out" | sed 's/^ *//'
}
