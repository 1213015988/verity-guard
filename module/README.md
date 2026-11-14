# verity-guard 分区守卫

盯着两件事：**模块里有没有会写分区的危险脚本**，**关键分区还是不是原来那个**。
被改了会提前报出来，别等你重启才发现开不了机。

## 它不做的事

- 不提供 root，也不修改系统
- 不改 system，不写分区（除非你自己点「回写」）
- 不守 `super` / `userdata`，只管 boot 链和 vbmeta

## 装前确认

1. 手机已经 root（KernelSU / APatch 有面板；Magisk 只有命令行，见下）
2. 有一个能跑的模块管理器，能装 zip
3. 留够备份空间，大约等于这些分区加起来的大小（面板「备份总量」会显示）

## 装完先做这一步

打开模块面板（模块列表里点这个模块），会看到 **⚪ 未建立基线**，下面有「建立基线」按钮。

点它。它只**读取**分区、算 sha256，记下当前的样子。

基线 = 健康时的样子。没有基线，面板不知道拿什么比，备份也会被拒绝。

## 音量键面板（没有 WebUI 也能用）

KernelSU / APatch：模块列表里点这个模块的「执行」按钮。
Magisk：打开终端（Termux、adb shell）跑

```sh
sh /data/adb/modules/vgd/action.sh
```

面板里 **音量上 / 音量下 短按移动光标，长按约 1 秒确认**（电源键也能直接确认），
2 分钟不按键自动退出：

```
── verity-guard 控制台（音量键操作）──
  ▶ 1. 建立基线（只读）
    2. 备份关键分区
    3. 立即检查
    4. 回写分区
    5. 导出排障包
    6. 使用说明
    7. 退出
  音量上/下：短按移动，长按约 1 秒确认（电源键也可确认）
```

按顺序用就是：**1 建立基线 → 2 备份 → 3 检测**。WebUI（KernelSU / APatch 里点模块打开的
那个页面）按钮也是这个顺序：建立基线 / 备份 / 检查。还没建基线时，面板顶部会提示
「⚠️ 还没有基线：请先选 1」，第 1 项也会变成「建立基线（第一次用，先做这个）」。

- 建基线、备份、回写都要再按一次电源键确认；确认菜单默认停在**取消**，手滑不会直接执行
- 回写前会列出每个副本是 ✔ 还是 ✘（副本哈希是否等于基线）
- **按电源键不会息屏**：面板自带的 `vgkey` 把输入设备抓过来，系统收不到这几个键，
  所以屏幕不灭、音量也不会被改。面板关掉后立刻恢复正常
- 面板开着时电源键被占用（不能锁屏），这是故意的不然就会息屏
- **只有音量键也能全程操作**：短按移动、长按 1 秒确认。
  只有 `vgkey` 跑不起来的机器（非 arm64 或系统限制执行）才只能用电源键确认

## 日常怎么看

| 面板 | 意思 |
|---|---|
| ✅ 一切正常 | 模块干净、分区与基线一致 |
| ⚠️ 有模块需留意 | 模块脚本里出现了 `avbctl`、`setenforce 0` 这类字样，看一眼 |
| ⛔ 有危险模块 | 有脚本会 `dd of=/dev/block/...`、`remount rw`，**先别重启** |
| ❌ 分区被修改 | 哈希变了，禁用可疑模块后点「回写」 |
| ⚪ 未建立基线 | 还没建基线，见上一步 |

装了新模块以后，守护进程 10 秒内会自动复查一次，不用手动点。

## 备份 / 回写

- 备份前会先把所有分区和基线校验一遍，**不一致直接拒绝**——把已经坏掉的数据存档没有意义
- 回写前校验副本哈希必须等于基线，写完再复核一遍
- 两个动作在面板上都要再确认一次

## 换手机 / 刷了固件之后

必须重建基线。旧基线在新机上会全红（那是正常的，不是坏了）。

面板里点「建立基线」，或执行：

```sh
sh /data/adb/modules/vgd/init.sh --yes --force
```

## 关于 vgkey

`vgkey` 是随模块带的一个几十 KB 静态程序（源码 `vgkey.c` 也在模块目录），只做一件事：
用 `EVIOCGRAB` 抓住音量键和电源键对应的输入设备，读出按键、不让系统响应；
顺便分辨**短按**（松开时算一次移动）和**长按**（按住约 1 秒直接算确认）。

- 它是 arm64 的；老架构跑不起来时自动退回 `getevent` 读键，功能一样能用，
  但那种情况下按电源键还是会息屏
- 抓取只在一个按键等待期间生效，进程退出（包括被杀）时内核自动释放，
  不会出现「电源键永久失灵」

## Magisk 用户（没有面板、没有「执行」按钮）

功能一样全，用命令行。装完就有一个短命令 `vg`：

```sh
sh /data/adb/vg init              # 第一次：建立基线（只读）
sh /data/adb/vg backup            # 第二次：备份
sh /data/adb/vg check             # 平时：查一次
sh /data/adb/vg status            # 看上次检查的结果
sh /data/adb/vg rollback --yes    # 出事了：把被改的分区按基线写回去
sh /data/adb/vg restore boot_b --yes   # 只写回一个分区
sh /data/adb/vg export            # 导出排障包
sh /data/adb/vg panel             # 音量键面板（短按移动、长按确认）
```

不想用终端也行：每次检查的结果会写成纯文本

```
/sdcard/Download/DSH-Go/guard/状态.txt
```

用文件管理器打开就能看，内容包括结论、哪些分区不对、哪个模块可疑、下一步该跑什么命令。
开机后守护进程自动跑，模块有增减改动的 10 秒内会自动复查一次。

## Magisk 用户（旧说明）

Magisk 没有 WebUI 面板，也没有「执行」按钮，只有 `service.sh` 在后台跑。全部功能用命令：

```sh
sh /data/adb/modules/vgd/init.sh --yes      # 建立基线
sh /data/adb/modules/vgd/wd.sh              # 检查一次
sh /data/adb/modules/vgd/backup.sh --yes    # 备份
sh /data/adb/modules/vgd/restore.sh boot_b --yes
sh /data/adb/modules/vgd/export.sh          # 导出排障包
```

结果都写在 `/sdcard/Download/DSH-Go/guard/chan/status.json`。

## 目录

```
/sdcard/Download/DSH-Go/guard/
├── baseline.txt / baseline.json   基线
├── backup/                        分区副本 + 每个的 .sha256
├── chan/                          status.json、日志、progress.txt
└── exports/                       排障包 tar.gz
```

## 分区是现场探测的

不写死机型。启动时按 `/dev/block/by-name` 里实际存在的 `vbmeta*`、`boot`、`init_boot`、`vendor_boot`、`dtbo` 自动识别单槽 / 双槽。

想多守几个分区，改 `/data/adb/modules/vgd/parts.sh` 里的 `BASES`（比如加 `recovery`、`persist`），然后重建基线。

## 风险

- 回写是 `dd` 裸写分区，脚本会校验大小和哈希，但别自己去改分区名
- 已经解锁 BL 的手机（verifiedbootstate=orange），基线记录的是**当前**状态，它只能保证「之后不再变」
- 这套东西防的是「模块乱写分区」，防不了你手动 fastboot 刷错东西

## 声明

本模块的代码、注释和文档全部由 AI 生成，人类只负责提需求、真机测试和发布决定。
详情见仓库里的 `AI-GENERATED.md`。
