---
name: 问题反馈
about: 面板打不开、检测报错、备份/回写失败等
labels: bug
---

## 环境

- 手机型号：
- Android 版本 / 系统：
- Root 管理器（KernelSU / APatch / Magisk）及版本：
- verity-guard 版本（看 module.prop 里的 `version`）：

## 现象

<!-- 具体哪一步、看到什么、期望是什么 -->

## 已经试过的

```sh
sh /data/adb/vg status
sh /data/adb/vg check
```

<!-- 把上面两条的输出贴这里 -->

## 排障包（强烈建议）

```sh
sh /data/adb/vg export
```

生成的包在 `/sdcard/Download/DSH-Go/guard/exports/`。

**发之前请检查一下**：包里有 logcat、dmesg、脚本和状态，可能有你的设备信息，
不需要的部分自己删掉再贴。
