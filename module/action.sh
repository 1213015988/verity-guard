#!/system/bin/sh
# action.sh —— 模块列表「执行」按钮：音量键控制面板
# 不用 WebUI 也能完成全部操作（检查 / 基线 / 备份 / 回写 / 导出）
# 音量上、音量下移动光标，电源键确认
M=/data/adb/modules/vgd
. "$M/lib.sh"
. "$M/parts.sh"
. "$M/keymenu.sh"
BASE=$G/baseline.txt
P=$CH/pending-restore
KM_LOG=$CH/ui.log
: > "$KM_LOG" 2>/dev/null
ulog "=== action.sh 开始 域=$(cat /proc/self/attr/current 2>/dev/null) PATH=$PATH"

mkdir -p "$CH" "$G/backup" "$G/exports" 2>/dev/null
detect_parts

# 有待回写的（WebUI 之外的兜底通道）先做掉
if [ -f "$P" ]; then
  part=$(sed -n 1p "$P")
  img=$(sed -n 2p "$P")
  case "$part" in
    ""|*/*|*..*) echo "分区名非法：$part" > "$CH/restore.log"; echo 2 > "$CH/restore.rc"; rm -f "$P"; exit 2 ;;
  esac
  case "$img" in
    "$G"/backup/*.img) ;;
    *) echo "镜像路径非法：$img" > "$CH/restore.log"; echo 3 > "$CH/restore.rc"; rm -f "$P"; exit 3 ;;
  esac
  prog "回写 $part：开始"
  sh "$M/dev.sh" restore "$part" "$img" > "$CH/restore.log" 2>&1
  rc=$?
  echo $rc > "$CH/restore.rc"
  rm -f "$P"
  if [ $rc -eq 0 ]; then prog "回写完成：$part"; else prog "回写失败：$part（rc=$rc）"; fi
  exit $rc
fi

# 守护进程挂了就顺手拉起来
if [ "$G" = "$VG_DEF" ]; then
  if [ ! -f "$CH/alive" ] || [ $(( $(date +%s) - $(cat "$CH/alive" 2>/dev/null || echo 0) )) -gt 60 ]; then
    spawn "$M/vgd.sh"
  fi
fi

# 注意：Android 的 mksh 用 32 位整数，按字节算会溢出（45GB 变成 306MB），一律用 MB
space_info() {
  NEED_MB=0
  for p in $PARTS; do
    s=$(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)
    [ -n "$s" ] && NEED_MB=$((NEED_MB + s / 1048576))
  done
  HAVE_MB=0
  for f in "$G"/backup/*.img; do
    [ -f "$f" ] || continue
    s=$(stat -c %s "$f" 2>/dev/null)
    HAVE_MB=$((HAVE_MB + ${s:-0} / 1048576))
  done
  ak=$(df -k "$G" 2>/dev/null | awk 'END{print $4}')
  case "$ak" in ''|*[!0-9]*) ak=0 ;; esac
  AVAIL_MB=$((ak / 1024 + HAVE_MB))
}

nb=0
[ -s "$BASE" ] && nb=$(wc -l < "$BASE" 2>/dev/null | tr -d ' ')
last=$(sed -n 's/.*"desc":"\([^"]*\)".*/\1/p' "$CH/status.json" 2>/dev/null | head -n 1)
[ -n "$last" ] || last="还没检查过"
space_info

if [ "$nb" = "0" ]; then
  echo "⚠️  还没有基线：请先选 1 建立基线，然后 2 备份"
fi
echo "================================"
echo " verity-guard 控制台"
echo " 分区 $NP 个 ｜ 基线 ${nb} 个"
echo " 上次：$last"
echo " 备份需要 $NEED_MB MB，可用 $AVAIL_MB MB"
echo "================================"

if [ -z "$KM_KEYS" ]; then
  if ! km_ready; then
    ulog "km_ready 失败"
    echo "读不到音量键，退回直接检查模式"
    sh "$M/wd.sh" 2>&1 | tee "$CH/action.log"
    exit $?
  fi
  ulog "km_ready ok devs=<$KM_DEVS>"
fi

do_check() {
  echo ""
  echo ">> 开始检查"
  sh "$M/wd.sh" 2>&1 | tee "$CH/action.log"
}

do_init() {
  echo ""
  if [ "$nb" != "0" ]; then
    echo "已经有 $nb 个分区的基线。"
    km_confirm "覆盖现有基线？只有换机、刷固件之后才需要覆盖" || return
    force=--force
  else
    echo "建立基线会读取 $NP 个分区并记下哈希，只读，不写分区。"
    echo "前提：这些分区现在必须是没有被改过的原厂状态。"
    echo "刷过 boot / init_boot / vbmeta 的，先刷回原厂再建基线，否则会把坏状态当成正常。"
    km_confirm "确认现在 $NP 个分区都是原厂状态，开始建立基线？" || return
    force=""
  fi
  echo ""
  echo ">> 建立基线"
  sh "$M/init.sh" --yes $force 2>&1 | tee -a "$CH/action.log"
  nb=0
  [ -s "$BASE" ] && nb=$(wc -l < "$BASE" 2>/dev/null | tr -d ' ')
}

do_backup() {
  echo ""
  space_info
  if [ "$AVAIL_MB" -lt "$NEED_MB" ]; then
    echo "空间不够：需要 $NEED_MB MB，可用 $AVAIL_MB MB"
    echo "清一点空间再试（旧副本会被覆盖，不算额外占用）"
    return
  fi
  echo "备份 $NP 个分区，约 $NEED_MB MB。"
  echo "备份前会先校验分区与基线一致，不一致直接拒绝。"
  km_confirm "开始备份？" || return
  echo ""
  echo ">> 备份中"
  VG_ECHO=1 sh "$M/backup.sh" --yes 2>&1 | tee -a "$CH/backup.log"
}

do_restore() {
  echo ""
  set --
  KM_SEL=1
  for p in $PARTS; do
    f=$G/backup/$p.img
    [ -f "$f" ] || continue
    h=$(cat "$f.sha256" 2>/dev/null | cut -c1-64)
    w=$(awk -v k="$p" '$1==k{print $2}' "$BASE" 2>/dev/null)
    if [ -n "$h" ] && [ -n "$w" ] && [ "$h" = "$w" ]; then
      set -- "$@" "$p ✔"
    else
      set -- "$@" "$p ✘副本异常"
    fi
  done
  if [ $# -eq 0 ]; then
    echo "还没有备份，先做一次备份"
    return
  fi
  set -- "$@" "取消"
  km_menu "选择要回写的分区" "$@" || return
  cur=$(eval "printf '%s' \"\${$KM_SEL}\"")
  part=${cur%% *}
  [ "$part" = "取消" ] && return
  echo ""
  echo "回写 = 把备份原样写进 /dev/block/by-name/$part。"
  echo "写完会复核哈希；中途断电有风险，确认电量充足。"
  km_confirm "确认回写 $part？" || return
  echo ""
  echo ">> 回写 $part"
  VG_ECHO=1 sh "$M/restore.sh" "$part" --yes 2>&1 | tee -a "$CH/restore.log"
}

do_export() {
  echo ""
  echo ">> 导出排障包"
  VG_ECHO=1 sh "$M/export.sh" 2>&1 | tee -a "$CH/export.log"
  echo "包在 $G/exports/"
}

do_help() {
  echo ""
  echo "怎么用（就按这个顺序）："
  echo "  1 建立基线   第一次必须做。只读，记下 $NP 个分区现在的指纹"
  echo "               没基线就不知道拿什么比，备份也会被拒绝"
  echo "  2 备份       校验分区没被改过，再 dd 出副本；出事才有东西回写"
  echo "  3 立即检查   日常看这个：模块脚本 + 分区哈希"
  echo "  4 回写       把副本写回分区，写完复核哈希"
  echo "  5 导出       日志打包，排障用"
  echo ""
  echo "  ✅ 绿色 = 与基线一致；❌ = 变了，先别重启"
  echo ""
  echo "按键：音量上/下短按移动光标，长按约 1 秒确认；电源键直接确认"
  echo "     （只有音量键也能全程操作；vgkey 跑不起来的机器用电源键确认）"
  echo ""
  echo "  WebUI（KernelSU / APatch）：模块列表里点模块打开"
  echo "  Magisk：没有「执行」按钮，用终端跑 sh $M/action.sh"
  echo ""
  echo "按任意键（音量）返回"
  km_wait "$KM_TIMEOUT" >/dev/null 2>&1
}

KM_SEL=1
firstmenu=1
acts=0
while :; do
  ulog "画菜单 sel=$KM_SEL"
  t0=$(date +%s)
  if [ "$nb" = "0" ]; then
    lb1="建立基线（第一次用，先做这个）"
  else
    lb1="建立基线（只读）"
  fi
  km_menu "verity-guard 控制台（音量键操作）" \
    "$lb1" \
    "备份关键分区" \
    "立即检查" \
    "回写分区" \
    "导出排障包" \
    "使用说明" \
    "退出" || {
      el=$(( $(date +%s) - t0 ))
      ulog "菜单退出，用时 ${el}s"
      # 第一次就秒退：说明这个环境下读不到键，别让人对着空面板
      if [ "$firstmenu" = "1" ] && [ "$el" -lt 3 ]; then
        echo "读键没生效（${el}s 就返回了），改成直接检查。"
        echo "细节在 $KM_LOG"
        sh "$M/wd.sh" 2>&1 | tee "$CH/action.log"
      fi
      break
    }
  firstmenu=0
  ulog "选中 $KM_SEL"
  sel=$KM_SEL
  acts=$((acts + 1))
  if [ "$acts" -gt 12 ]; then
    echo "这一轮已经操作 $acts 次，退出面板（防止按键连发把菜单刷爆）"
    break
  fi
  case "$sel" in
    1) do_init ;;
    2) do_backup ;;
    3) do_check ;;
    4) save=$KM_SEL; do_restore; KM_SEL=$save ;;
    5) do_export ;;
    6) do_help ;;
    7) echo ""; echo "已退出面板"; break ;;
  esac
  space_info
done
