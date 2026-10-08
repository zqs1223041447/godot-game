# 地图门槛挑战强度文案

基线：`071e8e24e5b0ecd7f3482b5fae20ca5dfd4b29a1`，已正常 fast-forward 发布到 main 并读回确认。独立修复分支：`codex/map-gate-strength-wording`，供父任务审查，未将本修复推 main。

运行源码仅 `scripts/ui/town_service_panel.gd` 四行字符串变化：

- 特殊词缀按钮：`需要波次` → `最低强度`。
- 提示：`需要波次 / 当前波次` → `最低强度 / 当前挑战强度`。
- 已选失效说明：`需要波次` → `最低强度`。
- 状态栏：`当前挑战波次` → `当前挑战强度`。

四处仍读取原 `entry.minimum_wave` / `preview.wave` 数值。未改内部字段、编译器、收费、解锁、奖励或任何地图行为；未合入原 WIP 的药剂实现或整提交。`map_modifier_preflight_test.gd` 同步原文字断言，原低档检查额外核对提示中的最低/当前强度。费用预览测试源码未改。

有限验证：Godot 4.6.3，两个独立全新 Linux XDG 目录，复用既有入口，每进程 45 秒限时。

- `tools/validate_map_modifier_preflight.sh`：**200 项 / 0 失败**。实际 Main/面板/信号、全部原门槛预览与编译器边界、失效选择保留/阻止/取消、地图/档位刷新、正式和独立测试路由、原生地形准备取消、纯预览不改构筑/存档/草案/RNG，以及四处新文案。[结果](preflight.json) · [日志](preflight.log.txt)。
- `tools/validate_map_cost_preview.sh`：**59 项 / 0 失败**。真实费用/全清结算/余额预览，失效选择清理旧费用，预览与准备不收费，正常/测试档隔离、过期启动拒绝、一次合法入图只扣四碎片一次。[结果](cost-preview.json) · [日志](cost-preview.log.txt)。使用原可信有限 UI 夹具，不作为战斗收益或经济平衡证据。
- 报告源 SHA256 与当前文件匹配。按四行替换恢复比对后，完整 UI 文件与基线一致；其他运行源码逐字节未改。[范围核验](scope.json)。`git diff --check` 通过。

本次为 headless 有限检查，未追加原生截图、药剂事务、全仓/长期检测、Windows 导出、封包、release/tag 或模型工作。历史 F8 卡片与其生成数据保持已发布版本，未扩大静态图鉴或其他历史文案范围。
