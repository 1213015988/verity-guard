#!/system/bin/sh
# wd.sh —— 一次完整体检：模块脚本 + 关键分区哈希 + 备份完整性
# 没有基线时明确报「未建立基线」，不谎报正常
M=/data/adb/modules/vgd
. "$M/lib.sh"
. "$M/parts.sh"
MODS=${VG_MODS:-/data/adb/modules}
UPD=${VG_UPD:-/data/adb/modules_update}
BASE=$G/baseline.txt
B=$G/backup
SELF=vgd

BLOCK_PAT='dd .*of=/dev/block|blockdev --setrw|remount[^|]*[, ]rw|flash_erase|nandwrite|write_raw_image'
WARN_PAT='avbctl|--disable-verity|fastboot (flash|erase)|mke2fs|mkfs\.|setenforce 0|(curl|wget).*\|[ ]*(sh|bash)'

mkdir -p "$CH" "$B" 2>/dev/null
detect_parts

hasbase=0
[ -s "$BASE" ] && hasbase=1

lint_one() {
  d=$1
  n=${d##*/}
  hit=$(find "$d" -name '*.sh' -exec grep -El "$BLOCK_PAT" {} \; 2>/dev/null | head -n 1)
  if [ -n "$hit" ]; then printf 'BLOCK %s %s\n' "$n" "${hit#$d/}"; return; fi
  hit=$(find "$d" -name '*.sh' -exec grep -El "$WARN_PAT" {} \; 2>/dev/null | head -n 1)
  if [ -n "$hit" ]; then printf 'WARN %s %s\n' "$n" "${hit#$d/}"; return; fi
  printf 'OK %s -\n' "$n"
}

# 要校验的清单 = 现场探测到的 + 基线里有但现在没了的
checklist=$PARTS
mo=$(baseline_only "$BASE")
[ -n "$mo" ] && checklist="$checklist $mo"
NC=$(printf '%s' "$checklist" | wc -w | tr -d ' ')

now=$(date +%H:%M)
nowsec=$(date +%H:%M:%S)
parts=""
modules=""
changed=""
miss=""
blk=0
wrn=0
cnt=0
modtxt=""
allok=$hasbase

total=0
for d in "$MODS"/* "$UPD"/*; do
  [ -d "$d" ] || continue
  n0=${d##*/}
  [ "$n0" = "$SELF" ] && continue
  [ -f "$d/module.prop" ] || continue
  [ -f "$d/disable" ] && continue
  total=$((total+1))
done

prog "开始检测：$total 个模块、$NC 个分区"

for d in "$MODS"/* "$UPD"/*; do
  [ -d "$d" ] || continue
  n0=${d##*/}
  [ "$n0" = "$SELF" ] && continue
  [ -f "$d/module.prop" ] || continue
  [ -f "$d/disable" ] && continue
  cnt=$((cnt+1))
  prog "扫描模块 $cnt/$total：$n0"
  line=$(lint_one "$d")
  lvl=${line%% *}
  rest=${line#* }
  name=$(printf '%s' "${rest%% *}" | tr -cd 'A-Za-z0-9_.-')
  det=$(printf '%s' "${rest#* }" | tr -cd 'A-Za-z0-9_.-/')
  case "$lvl" in
    BLOCK) blk=$((blk+1)); modtxt="$modtxt⛔ $name ${det:-脚本可疑}\n" ;;
    WARN)  wrn=$((wrn+1)); modtxt="$modtxt⚠️ $name ${det:-脚本可疑}\n" ;;
  esac
  modules="${modules}{\"name\":\"$name\",\"level\":\"$lvl\",\"detail\":\"$det\"},"
done
modules=$(printf '%s' "$modules" | sed 's/,$//')

i=0
for p in $checklist; do
  i=$((i+1))
  want=$(awk -v k="$p" '$1==k{print $2}' "$BASE" 2>/dev/null)
  if [ "$hasbase" = "0" ] || [ -z "$want" ]; then
    sz=$(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)
    [ -n "$sz" ] || sz=0
    parts="${parts}{\"n\":\"$p\",\"ok\":-1,\"sz\":$sz},"
    continue
  fi
  prog "校验分区 $i/$NC：$p"
  if [ ! -e "$BYNAME/$p" ]; then
    allok=0
    miss="$miss $p"
    parts="${parts}{\"n\":\"$p\",\"ok\":0,\"sz\":0},"
    continue
  fi
  sz=$(blockdev --getsize64 "$BYNAME/$p" 2>/dev/null)
  [ -n "$sz" ] || sz=0
  got=$(sha256sum "$BYNAME/$p" 2>/dev/null | cut -c1-64)
  if [ -z "$got" ] || [ "$got" != "$want" ]; then
    allok=0
    changed="$changed $p"
    parts="${parts}{\"n\":\"$p\",\"ok\":0,\"sz\":$sz},"
  else
    parts="${parts}{\"n\":\"$p\",\"ok\":1,\"sz\":$sz},"
  fi
done
parts=$(printf '%s' "$parts" | sed 's/,$//')
changed=$(printf '%s' "$changed" | tr -d '\n' | sed 's/^ *//;s/ *$//')
miss=$(printf '%s' "$miss" | tr -d '\n' | sed 's/^ *//;s/ *$//')

bcount=0
bsize=0
bk=""
for f in "$B"/*.img; do
  [ -f "$f" ] || continue
  bcount=$((bcount+1))
  s=$(stat -c %s "$f" 2>/dev/null)
  [ -n "$s" ] || s=0
  bsize=$((bsize + s))
  nm=${f##*/}
  nm=${nm%.img}
  h=$(cat "$f.sha256" 2>/dev/null | cut -c1-64)
  w=$(awk -v k="$nm" '$1==k{print $2}' "$BASE" 2>/dev/null)
  if [ -n "$h" ] && [ -n "$w" ] && [ "$h" = "$w" ]; then okb=1; else okb=0; fi
  bk="${bk}{\"n\":\"$nm\",\"sz\":$s,\"ok\":$okb},"
done
bk=$(printf '%s' "$bk" | sed 's/,$//')
# 基线时间优先读 baseline.json 里记的（sdcard 上 stat 的 mtime 有时会回旧值）
bts=$(sed -n 's/.*"created_str": *"\([^"]*\)".*/\1/p' "$G/baseline.json" 2>/dev/null | head -n 1)
[ -n "$bts" ] || bts=$(stat -c %y "$BASE" 2>/dev/null | cut -c1-16)

if [ "$hasbase" = "0" ]; then
  verdict=nobase
  desc="⚪ 未建立基线，先点「建立基线」（$now）"
elif [ -n "$changed" ] || [ -n "$miss" ]; then
  verdict=changed
  if [ -n "$changed" ] && [ -n "$miss" ]; then
    desc="❌ 分区异常：改 $changed；缺 $miss（$now）"
  elif [ -n "$changed" ]; then
    desc="❌ 分区被改：$changed，先别重启（$now）"
  else
    desc="❌ 分区缺失：$miss，先别重启（$now）"
  fi
elif [ "$blk" -gt 0 ]; then
  verdict=block
  desc="⛔ $blk 个模块含危险脚本，别重启（$now）"
elif [ "$wrn" -gt 0 ]; then
  verdict=warn
  desc="⚠️ $wrn 个模块需留意（$now）"
else
  verdict=ok
  desc="✅ $cnt 个模块 / $NC 分区正常（$now）"
fi

printf '{"ts":"%s","verdict":"%s","base":%s,"np":%s,"parts_ok":%s,"changed":"%s","miss":"%s","parts":[%s],"modules":[%s],"backup":{"n":%s,"sz":%s,"baseline":"%s","list":[%s]},"desc":"%s"}\n' \
  "$nowsec" "$verdict" "$hasbase" "$NC" "$allok" "$changed" "$miss" "$parts" "$modules" "$bcount" "$bsize" "$bts" "$bk" "$desc" > "$CH/status.json.tmp"
mv -f "$CH/status.json.tmp" "$CH/status.json" 2>/dev/null
if [ "$G" = "$VG_DEF" ]; then
  cp -f "$CH/status.json" "$SELFDIR/webroot/status.json" 2>/dev/null
  f=$SELFDIR/module.prop
  [ -f "$f" ] && sed -i "s#^description=.*#description=$desc#" "$f" 2>/dev/null
fi

# 日志导出
logarr() {
  f=$1
  [ -f "$f" ] || return
  tail -n 40 "$f" 2>/dev/null \
    | awk '{gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\r/,""); printf "\"%s\",", $0}' \
    | sed 's/,$//'
}
logs="{\"vgd\":[$(logarr "$CH/vgd.log")],\"action\":[$(logarr "$CH/action.log")],\"restore\":[$(logarr "$CH/restore.log")],\"backup\":[$(logarr "$CH/backup.log")],\"export\":[$(logarr "$CH/export.log")]}"
printf '%s\n' "$logs" > "$CH/logs.json.tmp" 2>/dev/null && mv -f "$CH/logs.json.tmp" "$CH/logs.json" 2>/dev/null
[ "$G" = "$VG_DEF" ] && cp -f "$CH/logs.json" "$SELFDIR/webroot/logs.json" 2>/dev/null

# 人类可读状态：没 WebUI 的人（Magisk）直接看这个文件
write_state() {
  st=${VG_STATE:-$G/状态.txt}
  {
    echo "verity-guard 分区守卫"
    echo "时间：$(date '+%Y-%m-%d %H:%M:%S')"
    echo "结论：$desc"
    echo
    if [ "$hasbase" = "0" ]; then
      echo "分区：还没有基线，没法比对"
      echo "     下一步：sh /data/adb/vg init"
    elif [ -z "$changed" ] && [ -z "$miss" ]; then
      echo "分区（$NC 个）：✅ 全部与基线一致"
    else
      echo "分区（$NC 个）："
      [ -n "$changed" ] && echo "  ❌ 被改过：$changed"
      [ -n "$miss" ] && echo "  ❌ 不存在：$miss"
      echo "  下一步：先别重启，跑 sh /data/adb/vg rollback --yes"
    fi
    echo
    if [ -z "$modtxt" ]; then
      echo "模块（$cnt 个）：✅ 没有会写分区的脚本"
    else
      echo "模块（$cnt 个）："
      printf "%b" "$modtxt"
      echo "  处理：在模块管理器里禁用可疑模块，再跑 vg check"
    fi
    echo
    echo "备份：$bcount 个文件，$((bsize / 1048576)) MB"
    echo "基线：$bts"
    echo
    echo "命令（终端 / adb / Termux 都行）："
    echo "  sh /data/adb/vg check        检查一次"
    echo "  sh /data/adb/vg init         建立基线（第一次）"
    echo "  sh /data/adb/vg backup       备份"
    echo "  sh /data/adb/vg rollback --yes   把被改的分区写回去"
    echo "  sh /data/adb/vg export       导出排障包"
    echo "  sh /data/adb/vg panel        音量键面板"
  } > "$st.tmp" 2>/dev/null && mv -f "$st.tmp" "$st"
  cp -f "$st" "$G/status.txt" 2>/dev/null
}
if [ "$G" = "$VG_DEF" ] || [ -n "$VG_STATE" ]; then
  write_state
fi

prog "检测完成：$desc"
