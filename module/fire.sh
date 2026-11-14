#!/system/bin/sh
# fire.sh —— 把耗时任务丢到后台立刻返回，避免 WebView 主线程被阻塞
M=/data/adb/modules/vgd
. "$M/lib.sh"

case "$1" in
  init)
    prog "准备开始：即将建立基线"
    if [ "$2" = "--force" ]; then
      spawn "$M/init.sh" --yes --force
    else
      spawn "$M/init.sh" --yes
    fi
    ;;
  check)
    prog "准备开始：即将检测"
    # 守护进程没起（刚装完还没重启）就顺手拉起来
    if [ "$G" = "$VG_DEF" ]; then
      if [ ! -f "$CH/alive" ] || [ $(( $(date +%s) - $(cat "$CH/alive" 2>/dev/null || echo 0) )) -gt 60 ]; then
        spawn "$M/vgd.sh"
      fi
    fi
    spawn "$M/wd.sh"
    ;;
  backup)
    prog "准备开始：即将备份"
    spawn "$M/backup.sh" --yes
    ;;
  restore)
    part=$2
    case "$part" in
      ""|*/*|*..*) prog "回写失败：分区名非法"; exit 2 ;;
    esac
    prog "准备开始：即将回写 $part"
    spawn "$M/restore.sh" "$part" --yes
    ;;
  export)
    prog "准备开始：即将导出日志包"
    spawn "$M/export.sh"
    ;;
  *)
    echo "usage: fire.sh init|check|backup|restore <part>|export"
    exit 2
    ;;
esac
sleep 0.2
exit 0
