#!/system/bin/sh
# keymenu.sh —— 音量键菜单（电源键确认），给「执行」面板用
# 读键靠 getevent；KM_KEYS 是给自动化测试的假按键（如 KM_KEYS="down,ok"）
KM_TMP=${KM_TMP:-/data/local/tmp/vg.key}
KM_TIMEOUT=${KM_TIMEOUT:-120}
KM_KEYBIN=${KM_KEYBIN:-/data/adb/modules/vgd/vgkey}
KM_KEY=""
KM_SEL=1
KM_N=0

ulog() {
  [ -n "$KM_LOG" ] && echo "$(date +%T) $*" >> "$KM_LOG" 2>/dev/null
  return 0
}

# 只从物理按键设备读：排除 uinput（系统注入，比如息屏时会伪造 KEY_POWER）和触摸屏
km_devs() {
  KM_DEVS=""
  tf=$KM_TMP.dev
  pf=$KM_TMP.p
  : > "$tf" 2>/dev/null
  getevent -p 2>/dev/null > "$pf" || return 0
  cur=""
  while read -r l; do
    case "$l" in
      "add device"*)
        cur=${l##*: }
        ;;
      *"name:"*)
        nm=${l#*name:}
        case "$nm" in
          *uinput*|*goodix*|*Touch*|*touch*|*ts*|*jack*|*Jack*) ;;
          *) [ -n "$cur" ] && echo "$cur" >> "$tf" 2>/dev/null ;;
        esac
        cur=""
        ;;
    esac
  done < "$pf" 2>/dev/null
  KM_DEVS=$(tr '\n' ' ' < "$tf" 2>/dev/null)
  rm -f "$tf" "$pf" 2>/dev/null
}

# vgkey 能跑吗（能跑就别用 getevent，它能抓住设备，按电源不会息屏）
km_keybin() {
  [ -n "$KM_KEYBIN_OK" ] && return 0
  [ -x "$KM_KEYBIN" ] || return 1
  timeout 5 "$KM_KEYBIN" --no-grab --timeout 1 $KM_DEVS >/dev/null 2>&1
  [ "$?" = "3" ] || return 1
  KM_KEYBIN_OK=1
  return 0
}

km_ready() {
  command -v getevent >/dev/null 2>&1 || return 1
  : > "$KM_TMP" 2>/dev/null || KM_TMP=/data/local/tmp/vg.key
  # 试一秒：读不到设备就是 SELinux 拦了
  err=$(timeout 1 getevent -l -q 2>&1 >/dev/null | head -n 1)
  ulog "km_ready err=<$err>"
  case "$err" in
    ""|*"add device"*) return 0 ;;
    *) echo "读键不可用：$err"; return 1 ;;
  esac
}

# 等一个键：设置 KM_KEY=up|down|ok；到期还没按键就返回 1
km_wait() {
  t=${1:-$KM_TIMEOUT}
  KM_KEY=""
  if [ -n "$KM_KEYS" ]; then
    KM_KEY=${KM_KEYS%%,*}
    case "$KM_KEYS" in
      *,*) KM_KEYS=${KM_KEYS#*,} ;;
      *)   KM_KEYS="" ;;
    esac
    return 0
  fi
  [ -n "$KM_DEVS" ] || km_devs
  ulog "wait 开始 ${t}s devs=<$KM_DEVS>"
  if km_keybin; then
    out=$(timeout $((t + 5)) "$KM_KEYBIN" --timeout "$t" $KM_DEVS 2>/dev/null)
    rc=$?
    if [ -n "$out" ]; then
      KM_KEY=$out
      ulog "vgkey 读到 <$out>"
      return 0
    fi
    ulog "vgkey 没读到键 rc=$rc"
    return 1
  fi
  end=$(( $(date +%s) + t ))
  tries=0
  while :; do
    now=$(date +%s)
    left=$(( end - now ))
    [ "$left" -le 0 ] && break
    tries=$((tries + 1))
    # 注意：Android 的 getevent 只收一个设备参数，给多个会直接退出，
    # 所以这里读全部设备，再按设备路径过滤——只认物理按键，丢掉 uinput 注入
    rm -f "$KM_TMP" 2>/dev/null
    s0=$(date +%s)
    timeout "$left" getevent -l -q 2>/dev/null | {
      while read -r l; do
        case "$l" in
          *EV_KEY*) ;;
          *) continue ;;
        esac
        dev=${l%%:*}
        if [ -n "$KM_DEVS" ]; then
          case " $KM_DEVS " in
            *" $dev "*) ;;
            *) continue ;;
          esac
        fi
        case "$l" in
          *KEY_VOLUMEUP*DOWN*|*KEY_VOLUMEDOWN*DOWN*|*KEY_POWER*DOWN*)
            echo "$l" >> "${KM_LOG:-/dev/null}" 2>/dev/null ;;
        esac
        case "$l" in
          *KEY_VOLUMEUP*DOWN*)   printf up   > "$KM_TMP"; exit 0 ;;
          *KEY_VOLUMEDOWN*DOWN*) printf down > "$KM_TMP"; exit 0 ;;
          *KEY_POWER*DOWN*)      printf ok   > "$KM_TMP"; exit 0 ;;
        esac
      done
    }
    KM_KEY=$(cat "$KM_TMP" 2>/dev/null)
    s1=$(date +%s)
    ulog "wait 第 ${tries} 次：耗时 $((s1 - s0))s 剩余 ${left}s key=<$KM_KEY>"
    rm -f "$KM_TMP" 2>/dev/null
    [ -n "$KM_KEY" ] || { [ $((s1 - s0)) -ge 2 ] || sleep 2; continue; }
    # 电源键确认后等它松开（最多 1 秒），长按不连点，免得连续确认
    if [ "$KM_KEY" = "ok" ]; then
      timeout 1 getevent -l -q 2>/dev/null | {
        while read -r l; do
          case "$l" in
            *KEY_POWER*UP*|*KEY_VOLUMEUP*UP*|*KEY_VOLUMEDOWN*UP*) exit 0 ;;
          esac
        done
      }
    fi
    return 0
  done
  ulog "wait 到期，没有按键"
  return 1
}

# 画一个菜单并等选择；成功返回 0，选中项在 KM_SEL
km_menu() {
  KM_TITLE=$1
  shift
  KM_N=$#
  [ "$KM_SEL" -gt "$KM_N" ] && KM_SEL=1
  [ "$KM_SEL" -lt 1 ] && KM_SEL=1
  first=1
  while :; do
    if [ "$first" = "1" ]; then
      echo ""
      echo "── $KM_TITLE ──"
      i=0
      for it in "$@"; do
        i=$((i+1))
        if [ "$i" = "$KM_SEL" ]; then
          echo "  ▶ $i. $it"
        else
          echo "    $i. $it"
        fi
      done
      if [ "$KM_TIMEOUT" -ge 60 ]; then
      tl="$((KM_TIMEOUT / 60)) 分钟"
    else
      tl="$KM_TIMEOUT 秒"
    fi
    echo "  音量上/下：短按移动，长按约 1 秒确认（电源键也可确认）"
      first=0
    else
      # 之后每次只打一行光标位置，别把对话框刷满
      cur=$(eval "printf '%s' \"\${$KM_SEL}\"")
      echo "  ▶ $KM_SEL. $cur"
    fi
    if ! km_wait "$KM_TIMEOUT"; then
      echo "  没等到按键，退出面板"
      return 1
    fi
    case "$KM_KEY" in
      up)   KM_SEL=$((KM_SEL - 1)); [ "$KM_SEL" -lt 1 ] && KM_SEL=$KM_N ;;
      down) KM_SEL=$((KM_SEL + 1)); [ "$KM_SEL" -gt "$KM_N" ] && KM_SEL=1 ;;
      ok)   echo "  选中：$KM_SEL"
           return 0 ;;
    esac
  done
}

# 需要二次确认：确认返回 0
km_confirm() {
  KM_SEL=2   # 默认停在「取消」，手滑按到电源不会直接执行
  km_menu "⚠️  $1" "确认" "取消" || return 1
  [ "$KM_SEL" = "1" ]
}
