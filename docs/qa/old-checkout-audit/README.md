# 旧检出有限只读盘点

2026-10-10，以主线 `d67a1221ec38a290a8b981ccf596acebf4e7df97` 为核对基准。旧目录操作均设置 `GIT_OPTIONAL_LOCKS=0`；未 checkout、add、commit、reset、删除文件或修复 Git 配置。没有读取凭据内容，也未扫描忽略的缓存/配置目录。此结论限于 Git 可见源码工作区及现有提交引用。

| 旧检出 | 当前分支 / 提交 | 工作区 |
|---|---|---|
| `/workspace/godot-game` | `work` / `205fda514d58b00370033df32c9a42a3a85994eb` | 已跟踪差异、非忽略未跟踪文件、stash 均为空 |
| `/workspace/godot-flask-recovery` | `main` / `fabeeb3af1f8336ead5b49eac4bd40c1f216d37c` | 已跟踪差异、非忽略未跟踪文件、stash 均为空 |

恢复目录仍引用不存在的 `/tmp/godot-recovery-audit.git/objects`，产生警告。只通过环境变量借用当前独立检出的对象库读取，没有改写旧目录的 alternates。

当前检出原为 11 提交浅克隆，首次祖先检查缺少旧对象；在**当前独立检出**补取 64 代主线历史及明确远端引用后重新核对。不要把对象缺失误认作未合入。最终两个旧目录全部本地分支提交都是基准主线的祖先，并且每个提交仍有至少一个同 SHA 的远端分支副本；完整精确 refs 在 `audit.json`。

需继续保留的独立历史 WIP：

- `refs/heads/codex/normal-flask-purchase-wip` → `967733eb8170e997838ecfa43ed7b8ae1477c8b7`，远端读取确认。它有一个未直接进入主线的快照提交，包含药剂购买模块、Main、城镇商人及两个相关测试的修改。
- 对应正式恢复 `refs/heads/codex/normal-flask-purchase-recovery` → `9b5d618ad7a88e4aed69b1aae37e37ddd2c3bff6` 已在主线。恢复版保留这条购买路径并补充校验、事务/UI 测试和取证；不把旧 WIP 再次套入当前实现。
- 旧 `work` 提交也由远端 `refs/heads/codex/equipment-purchase-reference` 保存，且已在主线。

没有发现尚未备份的独有 Git 可见 WIP，因此没有建立重复备份分支，也没有把 WIP 合入生产 main。旧目录及现有备份分支全部原样保留；此记录和后续开发成果位于 `/workspace/godot-cues-scan`。
