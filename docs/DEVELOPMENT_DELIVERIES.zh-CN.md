# 开发成果与待集成清单

核验时间：**2026-10-02 17:41:16 UTC**。只读核对远端 `codex/*`、`feat/*`、`main` 与 `v0.14.0`，供后续 owner 持续维护。

发布源码基线：`main` = `v0.14.0` = [`2b8604c740495a810ddcec2431dbb0717427da2c`](https://github.com/zqs1223041447/godot-game/commit/2b8604c740495a810ddcec2431dbb0717427da2c)；共同分叉基线为 `v0.13.0`（`a4a306a6d8c14320fce383dccf6ad7ca40836757`）。这里的“已进入”仅指 tag 的源码树已有对应内容，不代表 Windows 成品运行或所有验收通过。Release 元数据本次 API 读取被拒，prerelease/资产状态待直接复核。

核验依据：远端 HEAD、`merge-base`、`rev-list`、`ls-tree`、实际 Git diff、脚本接口与引用；字体 cmap 另作静态读取。**本次未运行游戏或测试、未触发 CI、未合并代码。** 表中测试表示脚本存在；引用的 QA 数字/结论是历史提交记录，未重新验证其外部原始日志。分支名、文档中的“通过”及退出码不能单独作为实跑证据。

## 分支快照

HEAD 链接含完整 SHA。差异列是 `v0.14.0...分支` 的“发布基线独有 / 分支独有”提交数；这些分支 HEAD 均不在 tag 的祖先链上，但部分内容已由汇总提交进入 tag，不能凭提交数判断是否已集成。

| 远端分支 | HEAD | 差异 | 状态 |
| --- | --- | --- | --- |
| `codex/crafting-controls-v013-desktop-fbrtnr7` | [`c2e711bdccca`](https://github.com/zqs1223041447/godot-game/commit/c2e711bdcccaefbbfdcc7bb9e8dd41db5010287f) | 1 / 2 | 待集成：操作行 |
| `codex/crafting-controls-visual-20261002` | [`114266b662ff`](https://github.com/zqs1223041447/godot-game/commit/114266b662ff3f5c1ead696b47bbd1d2fb997d0c) | 1 / 8 | 待修复：视觉 QA 记录失败 |
| `codex/crafting-rules-v013` | [`f23dcc4d9267`](https://github.com/zqs1223041447/godot-game/commit/f23dcc4d9267a098301b07574390d5077b95867b) | 1 / 1 | 待集成：纯规则 |
| `codex/crafting-transactions-v013` | [`5d5bba0baeb6`](https://github.com/zqs1223041447/godot-game/commit/5d5bba0baeb680cf56e0244e7c0b53490e290757) | 1 / 2 | 待集成：候选事务规划器 |
| `codex/encounter-controls-20261002` | [`48b929b528b5`](https://github.com/zqs1223041447/godot-game/commit/48b929b528b5879c779712ab82814c535993b9a1) | 1 / 3 | 待集成；采用后续 review 测试 |
| `codex/encounter-controls-review-20261002` | [`e4beb7ebedd2`](https://github.com/zqs1223041447/godot-game/commit/e4beb7ebedd294efbc4821c6a62d06420fc2e6b1) | 1 / 4 | 待集成：最新控件复核 |
| `codex/encounter-modifiers-v013` | [`9f553d68277b`](https://github.com/zqs1223041447/godot-game/commit/9f553d68277b88b1bde18e5b4fc2d3333a17bde1) | 1 / 2 | 待集成；controls/review 已包含 |
| `codex/encounter-monster-composition-v013` | [`7fd23f21c555`](https://github.com/zqs1223041447/godot-game/commit/7fd23f21c5555ec3c348fd8488ebe7ecb53ed595) | 1 / 3 | 待集成：补充组合测试 |
| `codex/font-coverage-v014-20261002` | [`e841cca43f75`](https://github.com/zqs1223041447/godot-game/commit/e841cca43f75e027d87da69c26b8c4923d187ab6) | 1 / 5 | 890 已进入；最新 9 字增量未进入 |
| `codex/telegraph-audit-20261002` | [`574519abb0d2`](https://github.com/zqs1223041447/godot-game/commit/574519abb0d2969e9b05f473a2867144256a6eeb) | 1 / 4 | 待集成：最新 renderer 边界修正 |
| `codex/telegraph-renderer` | [`60743b6452ce`](https://github.com/zqs1223041447/godot-game/commit/60743b6452ced85531de903d9b08d0074dacc447) | 1 / 3 | 待集成；采用后续 audit 修正 |
| `codex/telegraphed-area-runtime` | [`6bf5cf3b8d5e`](https://github.com/zqs1223041447/godot-game/commit/6bf5cf3b8d5e2d02bc4e6d5dc716f6cc928e7c79) | 1 / 2 | 待集成；后续 renderer/audit 已包含 |
| `codex/v013-validation-parallel` | [`4051ee54495a`](https://github.com/zqs1223041447/godot-game/commit/4051ee54495a7332d3855d32dca66a51b6ef33fd) | 1 / 1 | 待集成；已有后续 v014 runner |
| `codex/v014-pierce-acceptance` | [`f1993306d45d`](https://github.com/zqs1223041447/godot-game/commit/f1993306d45d314a3bb1c07bf2f398dae5cca780) | 1 / 2 | 主体已进入；这是较早验收版本 |
| `codex/v014-pierce-integration` | [`fdff527230cb`](https://github.com/zqs1223041447/godot-game/commit/fdff527230cbab1b2e17f035a94f55efbd7d75c5) | 1 / 4 | 核心已进入；main 另含后续验收 |
| `codex/v014-validation-parallel` | [`1b75c6a36848`](https://github.com/zqs1223041447/godot-game/commit/1b75c6a368486c6768bcb1f6532d9cbaa6ac3f4f) | 1 / 4 | 待集成：新增 v014 计划审计 |
| `codex/windows-certificate-diagnosis-20261002` | [`e06ed4852be8`](https://github.com/zqs1223041447/godot-game/commit/e06ed4852be8317ce960a445f82a312e40d185a6) | 1 / 1 | 待集成：独立诊断脚本 |
| `codex/windows-export-smoke-20261002` | [`b616578e9d7c`](https://github.com/zqs1223041447/godot-game/commit/b616578e9d7ca6bdcf9e454df43c14b6429174bd) | 1 / 6 | 待集成：工具/夹具；成品运行待核 |
| `codex/windows-release-verifier-20261002` | [`e3a0881dd73e`](https://github.com/zqs1223041447/godot-game/commit/e3a0881dd73ef7db9aa0394934ca0865964582e0) | 1 / 1 | 待集成：只读 ZIP 核验 |
| `codex/windows-save-path-identity-fix-20261002` | [`fed036e05c29`](https://github.com/zqs1223041447/godot-game/commit/fed036e05c2972f456d6ccf6110f3086f411ace3) | 1 / 2 | 路径身份修复与测试已进入 |
| `codex/windows-save-validation-20261002` | [`fdcf31857583`](https://github.com/zqs1223041447/godot-game/commit/fdcf3185758320ab2ccf66a0b416fa2d8fbf20c8) | 1 / 1 | 工具/夹具已进入；别名测试有后续更新 |
| `codex/windows-v014-acceptance-20261002` | [`3d732edec8c0`](https://github.com/zqs1223041447/godot-game/commit/3d732edec8c0b4510d0f35e74a48492540ef51cc) | 1 / 5 | v014_* 脚本与验收说明已进入 |
| `feat/projectile-pierce-support` | [`5a93e90a027f`](https://github.com/zqs1223041447/godot-game/commit/5a93e90a027f430aaec410cad5cb64eae53dda01) | 1 / 2 | 可执行规则/测试已进入；说明已更新 |

## 已进入 v0.14 的实际路径

- 穿透支持：`scripts/combat/projectile_support_rules.gd`、`support_registry.gd`、`skill_compiler.gd`，以及 `main.gd`、`skill_support_panel.gd`、`build_state.gd` 的接线和 schema10；`tests/projectile_support_rules_test.gd`、`pierce_integration_test.gd`、`pierce_ui_test.gd` 已存在。相对 feat HEAD，规则文件只有状态注释更新，测试文件一致；不能再将穿透列为未接入。
- 存档路径：`build_state.gd` 的路径身份/保护/迁移备份实现已纳入；与 identity-fix 分支的差异是穿透和 schema10 接入，身份相关 helper 无差异。`tools/validate_windows.ps1`、`validate_save_paths_linux.py`、`tests/windows/save_*` 及历史存档夹具已存在。
- Windows v0.14 验收：`tests/windows/v014_*` 与 `docs/windows-qa/V014_ACCEPTANCE.zh-CN.md` 和 acceptance HEAD 一致。该记录为核心功能 19,643 项、最终字体 5,103 项检查通过，**严格日志未通过**；不是本次实跑，也不是导出成品 GUI 验收。
- 字体基础：`assets/fonts/arena_sans.otf` 静态读取为 337,516 字节 / 890 个 cmap 字符；覆盖 manifest、`tools/check_font_coverage.py`、`tests/test_font_coverage.py` 与生成入口已存在。包含制作/规划器文字不意味着制作代码已接入。

## 独立成果与主流程缺口

| 成果 | 实际模块、测试或工具 | 后续接点 / 限制 |
| --- | --- | --- |
| Craft rules / transactions | `scripts/items/crafting_rules.gd` 的报价/seed 校准；`crafting_transaction_planner.gd` 的 `quote/plan`；对应两个 `tests/*_test.gd`。transactions 包含 rules 基线。 | 需从权威 BuildState 构造上下文，在统一事务内重算并验证完整候选；接材料/revision schema10 后续迁移、seed、一次提交/刷新/保存、失败恢复和重放保护。规划器只返回候选，尚无实际钱包或提交。 |
| Craft controls / visual QA | `scripts/ui/crafting_controls.gd`、`tests/crafting_controls_test.gd`；视觉分支增补 `tests/crafting_controls_visual_test.gd`、28 张 PNG 和 [QA 记录](https://github.com/zqs1223041447/godot-game/blob/114266b662ff3f5c1ead696b47bbd1d2fb997d0c/docs/qa/CRAFTING_CONTROLS_VISUAL.zh-CN.md)。 | 需挂载 InventoryPanel 并连接 `craft_requested` 至权威事务；历史 Linux 实绘记录 **2604 检查 / 16 失败**（焦点浅色文字、长 tooltip 越界），待修复。不是 Windows 渲染验收；视觉分支也携带旧穿透/字体输入，勿整支覆盖新版主线。 |
| Telegraph runtime / renderer / latest audit | `scripts/combat/telegraphed_area_runtime.gd`、`scripts/monsters/telegraph_profiles.gd`、`scripts/visuals/telegraph_renderer.gd`；`tests/telegraphed_area_test.gd`、`telegraph_renderer_test.gd`。audit 包含 runtime 与 renderer。 | 最新 audit 修改 renderer：`age + epsilon >= windup_seconds` 时拒绝 windup 快照，并补测试；runtime 未改。需明确怪物技能分配，在主更新中 `start/advance/cancel/reset`，处理一次 `circle_attack` 的真实范围/防御结算，将世界坐标快照传入 ArenaVisuals 绘制，并处理暂停、死亡、重置。 |
| Encounter compiler / controls / latest review | `scripts/encounters/encounter_catalog.gd`、`encounter_compiler.gd` 的 `compile/apply_to_enemy`，`scripts/ui/encounter_controls.gd`；compiler/controls 专项测试。review 包含 controls，最新只增补键盘激活/上下文刷新测试和说明，未修改控件实现。 | 需挂载挑战入口、接 `encounter_requested`，由主流程持有经过验证的 profile，在根怪和死亡子怪生成后各应用一次，维持 admission、谱系/队列预算和资源比例。目录的风险是参数描述，奖励仍为 disabled metadata；挑战存档/奖励/图鉴尚未接线。 |
| Encounter × monster composition | `tests/encounter_monster_composition_test.gd` 与 [组合 QA 说明](https://github.com/zqs1223041447/godot-game/blob/7fd23f21c5555ec3c348fd8488ebe7ecb53ed595/docs/qa/ENCOUNTER_MONSTER_COMPOSITION.zh-CN.md)；仅补测试/说明，包含 compiler 基线。 | 覆盖真实目录/runtime/共享机制、稀有度、死亡后代和预算组合；不是自然挑战主流程已开放的证明。需将这份增量与 controls review 的测试共同保留。 |
| Windows ZIP verifier / certificate diagnosis | `tools/windows/verify_release.ps1`、`tests/windows/release_verifier_test.ps1`；`tests/windows/certificate_diagnosis.ps1`、`certificate_probe.gd`、`certificate_store_probe.ps1`。 | 以上文件均不在 tag。ZIP 静态容器/哈希/资源核验不证明游戏可运行；诊断是独立复现/定位工具，不是证书修复，也不能豁免严格日志门槛。 |
| Windows exported smoke | `tools/windows/smoke_export.ps1`、`tests/windows/export_smoke_fixture.cs`、`export_smoke_test.ps1`。 | 以上文件均不在 tag。工具要求指定成品 SHA 和官方模板，通过实际 userdata 隔离门禁再启动；最新历史说明仍记 `product_executed=false`、`godot_isolation_runtime_proved=false`。夹具检查和 Release 元数据不等于真实成品通过；成品字节/隔离与原生运行待核。 |
| Parallel validation | `tools/validate_parallel.py`、`tests/test_validation_runner.py`、`docs/VALIDATION_RUNNER.zh-CN.md` 均未进入 tag；最新 `codex/v014-validation-parallel` 增补 v014 60 步计划（v013 为 54 步）。 | 最新 runner 审计来源为集成 `0db7a1bd`；`validate.sh`、Linux 路径工具与 `project.godot` 已静态确认和 main 一致。历史记录区分伪引擎 60 步与真实 7 步专项，**未跑真实 v014 全量**；需按当前 main 保留隔离/串行屏障并接维护入口，不能以此宣称发布门槛通过。 |
| Font latest increment | 最新分支字体静态读取为 342,836 字节 / 899 cmap；相对 tag 仅增加 `健参层评遇遭险难集` 九字，旧 890 字符未删除；manifest、覆盖测试/报告与字体检查亦有后续增量。 | 最新九字尚未进入 tag，需配合 encounter 动态标签一起接入，按路径带入增量并重核旧字形/度量；不能整支回灌旧存档/发布脚本。`⌁`、`◈` 的既有系统回退限制仍保留；静态 cmap 不证明所有目标平台绘制通过。 |

`main` 的 `scripts/`、`scenes/` 和 `tools/validate.sh` 中未发现上述 crafting、telegraph、encounter 模块路径引用，其模块文件也不在 tag 树中。缺口判断同时来自文件存在性与引用/diff，不只依据分支说明。

维护时先更新远端 HEAD 和 tag 内容比对，再按上表拆取增量；保留 audit/review 与组合 QA 的补充，不重复导入已进入的穿透、路径保护及旧字体。未直接核验的历史运行、成品/Release 状态继续标待核，由 owner 在实际集成后更新。
