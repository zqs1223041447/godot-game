# dot 环境迁移核验

日期：2026-10-11（北京时间）。

## 已到位的源码

从 GitHub 克隆主分支 `fd072824d10def4b39402a5934b68de92b3303d1`，8322 个跟踪文件。迁移时跟踪文件无差异。当前 dot 环境可调用 Godot 4.6.3。

原云环境本地提交 `304ccfdb5f5e8ddad9dce9ba3ba1aba99812f870` 未上传，因此不在本次迁移范围内。2026-10-11 07:33（北京时间），用户明确放弃取回原云环境未提交内容，需要的功能在 dot 环境重新开发。未删除原环境文件，不再把取回该提交作为阻塞。后续开发只在 dot 环境进行。

## 有限验证

- 主场景无界面启动成功，输出 `playable arena ready`，退出码 0；不代表图形效果或性能验收。
- `tests/aim_overlap_test.gd` 在独立存档目录执行：122 检查、0 失败。`AIM_PHASE=dot-migration`，报告见 `aim-report.json`。
- 初次调用该测试时隔离路径不符合测试前置条件，未运行检查；初次空日志不计成功。更正为 `/tmp/godot-m1-aim-overlap-dot-migration` 后重新执行并记录检查计数。
- 初次资源导入发现编辑器配置目录不可写，后续调用已设置独立 `XDG_CONFIG_HOME`、`XDG_CACHE_HOME`、`XDG_DATA_HOME`。
- 另有两份历史 QA 截图扩展名为 PNG、实际字节为 JPEG，Godot 导入时报错：`docs/qa/v116-ruins-garden-entry/native-entry.png` 与 `docs/qa/v118-ground-dressing/native-map.png`。不是运行时美术资源，本次保留原文件，未声称全量导入无错误。
- 导入生成的未跟踪 `.uid` / `.import` 文件不作为开发成果提交。

## 尚未完成

用户已授权在 dot 环境发起 GitHub CLI 登录。设备流程轮询 GitHub API 时被网络策略拒绝；随后获批准的执行通道发生沙箱启动错误。普通本地 `gh auth status` 确认尚未登录，未把账号问题作为已证实原因。没有保存任何登录码或凭据于仓库。未推送新代码，未导出 Windows 程序，未作整体性能通过结论。
