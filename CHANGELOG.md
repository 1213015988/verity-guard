# 更新记录

## 1.5.0

第一个对外版本。

- 模块脚本静态扫描：`dd of=/dev/block`、`blockdev --setrw`、`remount rw`、`avbctl`、
  `flash_erase`、`setenforce 0` 等危险写法
- 关键分区 sha256 基线比对，分区列表现场探测（单槽/双槽、有无 `init_boot` 自动识别）
- 备份：先校验分区与基线一致、检查剩余空间，再 `dd` 出副本并记 `.sha256`
- 回写：校验副本哈希等于基线，写入后复核
- 一键回退：`vg rollback` 只写和基线不一致的分区
- 三种入口：WebUI、音量键面板（短按移动 / 长按确认）、命令行 `vg`
- 音量键面板用 `vgkey` 抓住输入设备，按电源键不会熄屏
- 排障包：`vg export` 打包 logcat / dmesg / 各脚本原始日志 / 环境信息
- 人类可读状态文件 `状态.txt`，不开终端也能看结果
- KernelSU 模块描述动态显示当前结论
