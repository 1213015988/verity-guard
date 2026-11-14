# AI 生成声明

**这个项目完全由 AI 编写，包括代码、注释和文档。**

## 具体说明

| 内容 | 作者 |
|---|---|
| 全部 shell 脚本（`action.sh`、`wd.sh`、`backup.sh`、`restore.sh`、`rollback.sh`、`init.sh`、`vgd.sh`、`keymenu.sh`、`lib.sh`、`parts.sh`、`export.sh`、`service.sh`、`customize.sh`、`fire.sh`、`uninstall.sh`、`vg`、`dev.sh`） | AI |
| `vgkey.c` 及其 static aarch64 二进制 | AI |
| Web 界面 `webroot/index.html`（HTML / CSS / JavaScript） | AI |
| 代码里的中文注释、日志文案、面板菜单文字 | AI |
| `README.md`、`module/README.md`、`CHANGELOG.md`、issue 模板、`build.sh` | AI |
| 需求、真机测试、是否发布的决定 | 人类 |

这些文件从第一行到最后一个标点都由 AI 生成；人类没有逐行重写，只做了审阅、测试和少量措辞调整。

## 为什么写在这里

写清楚了，用的人才知道自己面对的是什么：

- 代码可能有不严谨的地方，也可能有 AI 自己没意识到的边界问题
- 出问题之前请自己读一遍脚本，尤其是 `restore.sh` 和 `rollback.sh`——它们会 `dd` 裸写分区
- 项目采用 MIT 许可，你可以随意审查、修改、再分发，无需署名

## 怎么验证这句话

不用信，直接看：

- 所有脚本都在 `module/` 下，都是纯文本
- `git log` 里能看到提交节奏
- 每个脚本开头的注释风格高度一致，因为出自同一个模型

## 给 AI 使用者的建议

如果你也打算让 AI 写这类会写分区的工具，至少做三件事：

1. 让它在真机上跑通每一条路径，不要只看它说「已完成」
2. 自己审一遍涉及 `dd`、`blockdev`、`EVIOCGRAB` 的代码
3. 留一条人类可读的状态输出（这个项目的 `状态.txt` 就是为此加的）
