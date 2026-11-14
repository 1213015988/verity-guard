#!/system/bin/sh
# customize.sh —— 安装时执行（Magisk / KernelSU / APatch 通用）
# 只做权限修正、目录准备、装前提醒，不改任何分区

chmod 755 "$MODPATH"/*.sh "$MODPATH/vgkey" 2>/dev/null
if [ -d "$MODPATH/webroot" ]; then
  chmod 755 "$MODPATH/webroot" 2>/dev/null
  chmod 644 "$MODPATH/webroot/index.html" 2>/dev/null
fi
chmod 644 "$MODPATH/module.prop" 2>/dev/null
chmod 755 "$MODPATH/vg" "$MODPATH/rollback.sh" 2>/dev/null

# 给个短命令入口：sh /data/adb/vg check
ln -sf /data/adb/modules/vgd/vg /data/adb/vg 2>/dev/null

G=/sdcard/Download/DSH-Go/guard
mkdir -p "$G/chan" "$G/backup" "$G/exports" 2>/dev/null

# 估一下备份要多少空间
. "$MODPATH/parts.sh" 2>/dev/null
detect_parts 2>/dev/null
need=0
for p in $PARTS; do
  s=$(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)
  [ -n "$s" ] && need=$((need + s))
done
need_mb=$((need / 1048576))
ak=$(df -k "$G" 2>/dev/null | awk 'END{print $4}')
[ -n "$ak" ] || ak=0
avail_mb=$((ak / 1024))

say() {
  if command -v ui_print >/dev/null 2>&1; then ui_print "$1"; else echo "$1"; fi
}

say " "
say "- verity-guard 已安装：守护 $NP 个关键分区（$PARTS）"
say "- 备份需要约 ${need_mb} MB 空间，当前可用 ${avail_mb} MB"
if [ "$ak" -lt "$need" ]; then
  say "- ⚠️ 空间不够备份！先清出至少 $((need_mb - avail_mb)) MB"
fi
say " "
say "- 重要：建档（建立基线）之前，请确认这些分区现在是原厂状态。"
say "  刷过 boot / init_boot / vbmeta / dtbo 的，先刷回原厂，否则基线"
say "  会把已经被改过的内容当成正常，之后就不会再报警。"
say " "
if [ -d "$MODPATH/webroot" ]; then
  say "- 用法 A（KernelSU / APatch）：点模块打开面板，或用「执行」按钮；"
  say "  执行面板里用 音量上/下 移动、电源键 确认，网络不通也能操作。"
fi
say "- 用法 B（Magisk / 终端 / adb，没有面板时用这个）："
say "    sh /data/adb/vg init       建立基线（第一次）"
say "    sh /data/adb/vg backup     备份"
say "    sh /data/adb/vg check      检查一次"
say "    sh /data/adb/vg panel      音量键面板（短按移动、长按确认）"
say "- 懒得用终端也行：检查结果会写到"
say "    /sdcard/Download/DSH-Go/guard/状态.txt"
say "    用文件管理器打开就能看"
say " "
say "- 第一步永远是「建立基线」，第二步「备份」，之后才会报警"
