# verity-guard 分区守卫

一个 Android 模块：盯着两件事——**模块里有没有脚本会写分区**，**关键分区还是不是原来的样子**。
被改了提前报警，别等重启才发现开不了机。

- 不自带 root，也不修改系统
- 检测只读；备份、回写都要手动确认
- 分区列表现场探测，不写死机型

## 它管什么

有些机器出问题后没有 fastboot 可救，一旦 boot 链分区被写坏就只能找售后。
这个模块在「被写坏」和「你重启」之间加一道提示：

- 每次模块有增减改动，10 秒内自动复查一次
- 静态扫描模块脚本里的危险写法（`dd of=/dev/block`、`blockdev --setrw`、`remount rw`、
  `avbctl`、`flash_erase` 等）
- 对 boot 链关键分区做 sha256 比对，和建立基线时不一致就报警
- 报警之后可以一键把不一致的分区按基线写回去

## 支持范围

| Root 管理器 | 刷入 | WebUI | 「执行」面板 | 命令行 |
|---|---|---|---|---|
| KernelSU（官方） | ✅ | ✅ | ✅ | ✅ |
| KernelSU Next / SukiSU Ultra | ✅ | ✅ | ✅ | ✅ |
| APatch | ✅ | ✅ | 视版本 | ✅ |
| Magisk / Delta / Alpha | ✅ | ❌ | ❌ | ✅ |

> 目前只在 KernelSU 上实测过。其它管理器按各自的模块规范写了入口，但没有真机验证；
> Magisk 没有 WebUI 和「执行」按钮，用命令行。

## 安装

1. 在模块管理器里刷 `verity-guard-v1.5.0.zip`
2. 重启（Magisk 需要；KernelSU 一般刷完就能用）
3. 打开模块：
   - KernelSU / APatch：点模块打开面板
   - Magisk：终端 `/data/adb/vg init`、`/data/adb/vg backup`

**顺序永远是：1 建立基线 → 2 备份 → 3 检测。**
基线没建立之前，面板和 WebUI 都会提示，备份会被拒绝。

## 三种入口

### WebUI（KernelSU / APatch）

模块列表里点模块打开，三个按钮：建立基线 / 备份 / 检查。
分区、模块、备份、日志都在同一页。

### 音量键面板

KernelSU / APatch 点「执行」按钮，或终端 `sh /data/adb/vg panel`：

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

- 音量上/下**短按**移动光标，**长按约 1 秒**确认；电源键也能直接确认
- 按电源键不会息屏：面板自带的 `vgkey` 会在等待按键时抓住输入设备，系统收不到这几个键
- 2 分钟不按键自动退出

### 命令行

```sh
sh /data/adb/vg init              # 建立基线（只读）
sh /data/adb/vg backup            # 备份
sh /data/adb/vg check             # 检查一次
sh /data/adb/vg status            # 看上次结果
sh /data/adb/vg rollback --yes    # 把被改的分区按基线写回去
sh /data/adb/vg restore boot_b --yes  # 只写回一个分区
sh /data/adb/vg export            # 导出排障包
```

不想开终端也行：每次检查会写 `/sdcard/Download/DSH-Go/guard/状态.txt`，
文件管理器打开就能看结论、异常分区、可疑模块和下一步该跑什么。

## 目录

```
/sdcard/Download/DSH-Go/guard/
├── baseline.txt / baseline.json  基线（分区哈希）
├── backup/                       分区副本 + 每个的 .sha256
├── chan/                         status.json、日志、progress.txt
├── exports/                      排障包
└── 状态.txt                      人类可读的状态
```

## 风险与免责

- 回写是 `dd` 裸写分区。脚本会校验大小和哈希，写入后还会复核，但**写回过程中断电有风险**
- 只守 boot 链（`vbmeta*`、`boot`、`init_boot`、`vendor_boot`、`dtbo`），不管 `super` 和 `userdata`
- **不是救砖工具**：分区已经坏了的时候，它能告诉你坏了，但救不回来
- 已经解锁 BL 的手机（`verifiedbootstate=orange`），基线记录的是当前状态，只能保证「之后不再变」
- 在分区已经被改过的状态下建立基线，等于把坏状态记成正常——装之前务必确认分区是健康的

## 构建

```sh
./build.sh          # 产出 dist/verity-guard-<version>.zip
```

需要 `python3`。`vgkey` 的源码在 `module/vgkey.c`：

```sh
musl-gcc -static -Os -s -o vgkey vgkey.c
```

## 许可

MIT，见 [LICENSE](LICENSE)。
