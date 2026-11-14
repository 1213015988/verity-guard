#!/system/bin/sh
# vgd —— root 通道（只读 snapshot/backup）+ 模块变化监听；体检逻辑在 wd.sh
MODS=/data/adb/modules
UPD=/data/adb/modules_update
G=${VG_G:-/sdcard/Download/DSH-Go/guard}
CH=$G/chan
Q=$CH/q
R=$CH/r
SELF=vgd
SELFDIR=$MODS/$SELF

# 开机时 /sdcard 可能还没挂上，等它（最多 60 秒）
w=0
while [ ! -d /sdcard/Download ] && [ "$w" -lt 60 ]; do sleep 1; w=$((w+1)); done
mkdir -p "$CH" "$Q" "$R" "$G/backup" "$G/exports" 2>/dev/null
rm -f "$Q"/*.run 2>/dev/null
: > "$CH/vgd.log" 2>/dev/null
exec >> "$CH/vgd.log" 2>&1
echo "--- start $(date) ---"

if [ -f "$CH/pid" ]; then
  old=$(cat "$CH/pid" 2>/dev/null)
  if [ -n "$old" ] && [ "$old" != "$$" ] && [ -r "/proc/$old/cmdline" ] \
     && grep -q "vgd\.sh" "/proc/$old/cmdline" 2>/dev/null; then
    echo "another instance ($old) alive, exit"
    exit 0
  fi
  echo "stale pid $old, ignore"
fi
# 全局只允许一个：别管用的是哪个目录，都不许起第二个
others=$(ps -A -o PID,ARGS 2>/dev/null | grep "[v]gd\.sh$" | awk -v me="$$" '$1 != me {print $1}')
if [ -n "$others" ]; then
  echo "还有别的 vgd.sh 在跑（$others），退出"
  exit 0
fi
echo $$ > "$CH/pid"

sig() {
  for d in "$MODS"/* "$UPD"/*; do
    [ -d "$d" ] || continue
    n=${d##*/}
    [ "$n" = "$SELF" ] && continue
    [ -f "$d/module.prop" ] || continue
    if [ -f "$d/disable" ]; then st=off; else st=on; fi
    t=$(stat -c %Y "$d/module.prop" 2>/dev/null)
    c=$(ls "$d"/*.sh 2>/dev/null | wc -l)
    printf '%s:%s:%s:%s\n' "$n" "$st" "$t" "$c"
  done | sort
}

lastsig=""
ticks=0
while :; do
  [ -d "$CH" ] || mkdir -p "$CH" "$G/backup" "$G/exports" 2>/dev/null
  date +%s > "$CH/alive.tmp" 2>/dev/null && mv -f "$CH/alive.tmp" "$CH/alive" 2>/dev/null

  for f in "$Q"/*.run; do
    [ -f "$f" ] || break
    id=${f##*/}
    id=${id%.run}
    op=$(head -n 1 "$f" 2>/dev/null)
    args=$(printf '%s\n' "$op" | cut -d' ' -f2-)
    op=${op%% *}
    case "$op" in
      snapshot|backup)
        if [ -f "$SELFDIR/dev.sh" ]; then
          sh "$SELFDIR/dev.sh" "$op" $args > "$R/$id.out" 2>&1
          echo $? > "$R/$id.rc.tmp" && mv -f "$R/$id.rc.tmp" "$R/$id.rc"
        else
          echo "DENIED no_cli" > "$R/$id.out"
          echo 13 > "$R/$id.rc.tmp" && mv -f "$R/$id.rc.tmp" "$R/$id.rc"
        fi
        ;;
      *)
        echo "DENIED $op" > "$R/$id.out"
        echo 13 > "$R/$id.rc.tmp" && mv -f "$R/$id.rc.tmp" "$R/$id.rc"
        ;;
    esac
    rm -f "$f"
  done

  ticks=$((ticks+1))
  if [ $ticks -ge 10 ]; then
    ticks=0
    cur=$(sig)
    if [ "$cur" != "$lastsig" ]; then
      [ -n "$lastsig" ] && sleep 2
      # 启动后也先跑一次，面板一打开就有状态可看
      sh "$SELFDIR/wd.sh" >/dev/null 2>&1
      lastsig=$cur
    fi
  fi
  sleep 1
done
