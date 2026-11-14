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

## AI 生成声明

**这个项目的全部代码、注释和文档都是 AI 写的。**

- 每一行 shell 脚本、`vgkey.c`、Web 界面、README、CHANGELOG，以及代码里的中文注释，均由 AI 生成
- 人类负责：提需求、在真机上测试、决定要不要发布
- 经过 AI 自测和一次真机验证，但**不代表没有 bug**；涉及写分区的部分，请自己看一遍再跑

详见 [AI-GENERATED.md](AI-GENERATED.md)。

## 支持范围

| Root 管理器 | 刷入 | WebUI | 「执行」面板 | 命令行 |
|---|---|---|---|---|
| KernelSU（官方） | ✅ | ✅ | ✅ | ✅ |
| KernelSU Next / SukiSU Ultra | ✅ | ✅ | ✅ | ✅ |
| APatch | ✅ | ✅ | 视版本 | ✅ |
| Magisk / Delta / Alpha | ✅ | ❌ | ❌ | ✅ |

> 目前只在 KernelSU 上实测过。其它管理器按各自的模块规范写了入口，但没有真机验证；
> Magisk 没有 WebUI 和「执行」按钮，用命令行；从开终端到回退的完整步骤见下面「安装 → Magisk 用户」。

## 安装

1. 刷 `verity-guard-v1.5.0.zip`
   - Magisk：模块 → 从本地安装
   - KernelSU / APatch：模块 → 安装
2. **重启一次**。Magisk 必须重启：模块装完先落在 `/data/adb/modules_update/vgd`，
   重启后才合并到 `/data/adb/modules/vgd`，不重启的话所有命令都找不到文件。
   KernelSU 一般刷完就能用。
3. 打开模块：
   - KernelSU / APatch：点模块打开面板（WebUI + 「执行」按钮）
   - Magisk：没有面板，全部用命令行，按下面「Magisk 用户」一节走

**顺序永远是：1 建立基线 → 2 备份 → 3 检测。**
基线没建立之前，面板和 WebUI 都会提示，备份会被拒绝。

### Magisk 用户：完整流程（从打开终端到回退）

Magisk 没有 WebUI，也没有「执行」按钮，所有操作都在终端里跑。
下面按顺序做一遍：在哪开终端、第一条命令是什么、日常怎么查、出问题怎么退。

#### 1. 准备一个终端

| 方案 | 怎么弄 | 备注 |
|---|---|---|
| A. Termux（推荐） | 装 Termux：F-Droid 版最稳；Google Play 版 2024 年才重新上架、只在 Android 11+ 提供，官方说仍在开发中 | 两者签名不同，**装了哪个就一直用哪个**，别互相覆盖 |
| B. adb shell | 电脑装 platform-tools，手机开「开发者选项 → USB 调试」，`adb devices` 能看到设备后 `adb shell` | 手机进不去系统时也能用 |
| C. 其他终端 App | 任意能执行 shell 的终端 App | 老 App 在新系统上不一定能跑 |

#### 2. 拿到 root

模块的命令都要 root（读 `/data/adb`、读分区、写回分区），普通用户跑会直接失败。

**Termux：**

```sh
su
```

第一次会弹 Magisk 授权框，点「允许」（可勾「记住选择」）。然后：

```sh
export PATH=/system/bin:/system/xbin:$PATH
id
```

第二行是把安卓自己的命令补进 PATH —— Termux 的 PATH 不含 `/system/bin`，
不补的话 `blockdev`、`getprop` 这些会 `not found`。
`id` 输出 `uid=0(root)` 就说明已经是 root 了。

**adb shell：**

```sh
adb shell
su
```

adb 的环境本来就是安卓的，不用补 PATH。

> `su: not found` 或 `Permission denied`：先在 Magisk App → 超级用户里确认已授权；
> 还不行就试绝对路径 `/system/bin/su` 或 `/debug_ramdisk/su`。

#### 3. 确认模块在位

```sh
ls /data/adb/modules/vgd
```

能看到 `module.prop`、`vg`、`init.sh` 就对了。
没有这个目录：模块没装成功，或者装了还没重启（见上面第 2 步）。

#### 4. 第一条命令：建立基线（只读）

```sh
sh /data/adb/vg init
```

- 只读：读分区、算 sha256、写基线文件，**不写任何分区**
- 第一次必须做。没有基线它不知道拿什么比，`backup` 会直接拒绝
- 成功会打印 `基线建立完成：N 个分区`
- 已经有基线时会拒绝（`ERR baseline_exists`），要覆盖就加 `--force`：
  `sh /data/adb/vg init --force`

> 建基线前，先确认这些分区现在是**原厂状态**。已经刷过 boot / init_boot / vbmeta / dtbo 的，
> 现在建基线等于把改过的状态记成「正常」，以后它就不会再报警了。

#### 5. 备份

```sh
df -h /sdcard            # 先看空间够不够
sh /data/adb/vg backup
```

备份前会把所有分区和基线核对一遍，不一致就拒绝——把已经坏掉的数据存档没有意义。
副本落在 `/sdcard/Download/DSH-Go/guard/backup/`，大小约等于 boot 链分区之和
（`vbmeta*` 很小，`boot` / `init_boot` / `vendor_boot` 各几十 MB）。

被拒绝时对照处理：

| 输出 | 意思 | 怎么办 |
|---|---|---|
| `REFUSED no_baseline` | 还没有基线 | 先做第 4 步 |
| `REFUSED partition_changed: boot_b` | 分区和基线不一致 | 先 `check` 看是谁改的，再决定回写还是重建基线 |
| `REFUSED no_space need=… avail=…` | 空间不够 | 照提示清出对应 MB 数 |

#### 6. 日常检查

```sh
sh /data/adb/vg check     # 检查一次（只读）
sh /data/adb/vg status    # 看人类可读的结论
```

结论同时写到 `/sdcard/Download/DSH-Go/guard/状态.txt`，用文件管理器打开就能看，
不开终端也行。开机后守护进程会自动复查，模块有增减 10 秒内再查一次。

#### 7. 装完新模块，重启之前先查一次

Magisk 装模块会先放进 `/data/adb/modules_update/<id>`，重启后才合并进 `/data/adb/modules`。
`check` 会把**这两个目录都扫一遍**，所以在 Magisk 上「装完先查、确认没问题再重启」是可行的：

```sh
sh /data/adb/vg check
```

- `✅ 一切正常` → 可以重启
- `⚠️ 有模块需留意` → 看报告里点了哪个模块的哪个脚本，确认无误再重启
- `⛔ 有危险模块` → 先别重启，把那个模块关掉再复查：

```sh
ls /data/adb/modules_update          # 还没重启的模块在这里，先看清 id
touch /data/adb/modules_update/<id>/disable
sh /data/adb/vg check                # 复查，确认变干净
```

已经生效的模块同理，路径换成 `/data/adb/modules/<id>/disable`。
也可以在 Magisk App 的模块列表里直接关掉开关。

#### 8. 出问题了怎么回退

按严重程度，从上往下选：

**a. 分区被改了 —— 用模块自己回退**

```sh
sh /data/adb/vg check                 # 先看是哪几个分区变了
sh /data/adb/vg rollback --yes        # 把变了的按基线写回去
sh /data/adb/vg check                 # 复核
```

`rollback` 只写「本来有备份、且备份哈希等于基线」的分区，其余一律拒绝。
只想写回一个分区：

```sh
sh /data/adb/vg restore boot_b --yes
```

日志在 `/sdcard/Download/DSH-Go/guard/chan/rollback-<分区>.log`。
**写回过程别断电、别拔线**——`dd` 是裸写，写到一半断电就是真坏。

**b. 想先让这个模块安静**

```sh
touch /data/adb/modules/vgd/disable   # 禁用：重启后模块不加载
rm /data/adb/modules/vgd/disable      # 恢复：删掉再重启
```

Magisk App 里关掉模块开关是同一件事。注意：本模块平时不写分区，禁用它只是让它闭嘴，
**不会**把已经改掉的分区改回去——分区要回去，用上面的 `rollback`。

**c. 开机进不去系统 —— 交给 Magisk 自己救**

- **自动**：连续两次没完成开机（`boot_completed`），Magisk 会在下一次开机自动进安全模式，
  给每个模块建 `disable` 文件、关掉 Zygisk，让你能进系统。
- **手动（有 adb）**：`adb shell` 后 `su -c 'magisk --remove-modules'`，
  删掉所有模块并自动重启。
- **手动（按键）**：开机动画**出现前几秒**按住音量下键，动画一开始就松开 = 只进 Magisk 安全模式
  （比网上教程写的时机要早，晚了只会进系统安全模式）；一直按到开机完成 = 两个安全模式都进。
- **能进系统的话**：Magisk App 首页右上角的重启菜单里可以直接切「安全模式」，再重启。

进系统后把可疑模块关掉，正常重启一次就恢复。
本模块不会在没人操作时写分区，所以「装了这个就开不了机」基本可以排除，真进不去多半是别的模块。

**d. 要给作者贴 issue**

```sh
sh /data/adb/vg export
```

排障包在 `/sdcard/Download/DSH-Go/guard/exports/`，里面有原始日志、状态、脚本副本，
还有 `collect.log` 记录每一项采集是成功还是失败（失败也写进去，不藏）。

#### 常用命令速查

```sh
su                                   # 提权（Termux 用）
sh /data/adb/vg init                 # 建立基线（第一次）
sh /data/adb/vg init --force         # 重建基线
sh /data/adb/vg backup               # 备份
sh /data/adb/vg check                # 检查一次
sh /data/adb/vg status               # 看上回结论
sh /data/adb/vg rollback --yes       # 按基线写回被改的分区
sh /data/adb/vg restore boot_b --yes # 只写回一个分区
sh /data/adb/vg export               # 导出排障包
sh /data/adb/vg panel                # 音量键面板
```

`/data/adb/vg` 是安装时建的软链；万一不存在，用全路径
`sh /data/adb/modules/vgd/vg <子命令>`。不想一直敲命令就用最后那条 `panel`（音量键操作，见下一节）。

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
sh /data/adb/vg --help            # 列出全部子命令
sh /data/adb/vg check             # 检查一次
sh /data/adb/vg status            # 看上次结果
```

每个子命令干什么、先跑哪个、Magisk 上怎么用，见上面「安装 → Magisk 用户」。

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
