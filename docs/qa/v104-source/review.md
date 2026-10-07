# v104 天赋操作预览静态审核

审核基线：`181216b77b4f19078e5e33f6fd1b108afea828ca`。

范围：`scripts/canonical_game_state.gd` 的共享候选计划与预览接口，以及 `scripts/ui/canonical_passive_panel.gd` 的最终 deferred 刷新补丁。沿调用链检查原有 store、全量规则、源树和物品元数据缓存；仅静态阅读与文本比较，未启动 Godot、未重跑测试、未修改运行源码。本审核不替代其他 QA 文件中的运行结果。

## 结论

当前审核版本未发现需阻断的后端契约变化。原 allocate/refund 的前置检查、错误顺序、候选构造、提交结果与保存先于内存更新的顺序均保留。预览使用同一候选构造和完整最终状态校验，不承诺保存成功；实际命令仍重新构造候选并独立提交校验。

初版 UI 会在 `changed` 的 `_busy=true` 窗口同步生成 `busy` 预览，再把 `_refresh_dirty` 清掉，导致提交返回后的 `_report().refresh()` 跳过刷新。最终版本的单队列 deferred 刷新已在现有调用路径内消除此问题，见下文。未发现其他实质缺陷；重复快照及派生缓存替换属于已识别、未实测耗时的额外成本。

审核源码 SHA-256：

- `scripts/canonical_game_state.gd`：`18353b0ebcdf1fb6aa1b0e935c784bd8c91114c8a9ae2ce70e3bcf3baccbd309`
- `scripts/ui/canonical_passive_panel.gd`：`ad4454a3be5721f8cfe1ac644ec295c7e1b9dbad61103c4fe49dc2a603af9b8e`

## 1. 共享 helper 与原方法一致

用基线 `git show` 取得原方法，以函数正文去掉最后一行 `return _commit(candidate,path)`，分别对比当前 `_plan_passive_allocation`、`_plan_passive_refund` 去掉最后一行 `return {"ok": true, "candidate": candidate}` 后的正文。两组正文逐字相等，强于仅忽略空白后的 token 相等。

- allocate 正文 SHA-256：`762900cc8f08ee890859799b82df02655543de8cef75a500bfa09ed76b0c9f26`
- refund 正文 SHA-256：`4afa932f953678db699e8c15965d0d6bbf6c12ebe67733d8327eeb204475934b`

因此分配仍按 `busy → stale_revision → unknown_node → already_allocated → no_points → invalid_mastery` 及原条件短路，之后才进行候选最终校验。退还仍按 `busy → stale_revision → not_allocated` 短路，再进行最终校验。职业起点、连接依赖、珠宝孔占用、精通要求等没有被新增 UI 规则替代，继续由完整最终状态校验决定。

当前公开命令在计划失败时原样返回 `_failure` 产生的字典；成功计划只在内部传递候选，公开命令返回原 `_commit` 的结果。因此没有把内部计划成功字典泄露为事务成功返回，也没有改变失败的 `revision: -1` 或成功的已提交 revision。

证据：`canonical_game_state.gd:272–310`；`canonical_build_store.gd:488–503,559–560`。以下依赖文件与基线逐字节相等：

- `scripts/save/canonical_build_store.gd`
- `scripts/save/canonical_build_rules.gd`
- `scripts/passives/source_tree_runtime.gd`
- `scripts/passives/source_tree_data.gd`
- `scripts/passives/source_tree_allocation_rules.gd`

`_prepare_candidate`、`_ensure_cache`、`cache_diagnostics` 也与基线原正文相等。

## 2. 完整校验与独立提交

预览的成功计划进入 `_prepare_candidate(plan.candidate)`，再调用 `Rules.reason(candidate, _talent_validator, _socket_ids)`，与 `_commit` 的准备及第一道最终状态校验一致。`Rules.reason` 先执行当前版本原生全量 `_reason`，涵盖 envelope、journey、修订、物品、位置、技能组、辅助兼容、成长、记账与源天赋；额外 validator 只能在原生规则通过后追加限制。

实际分配/退还不接受预览结果、缓存候选或预览 revision 作为提交凭证。每次调用重新执行同一 planner，再进入原 `_commit`；`_persist` 自身仍保留原来的再次校验、保存阻断、磁盘收据/冲突和真实写入检查。只有保存成功才 `_accept_memory` 并发送 `changed`。

预览返回的只有顶层当前 revision，以及两项 `{allowed, error_code, reason}`。合法预览不返回 `ok`、保存成功标记、磁盘保证或候选引用。`allowed=true` 表示该时刻构筑状态允许，后续仍可能因修订变化、磁盘冲突、保存阻断或写入失败被拒绝。UI 的允许文案只说明动作与点数，不宣称已保存。

证据：`canonical_game_state.gd:252–269`；`canonical_build_rules.gd:331–334,551–623`；`canonical_build_store.gd:488–545`；`canonical_passive_panel.gd:307–318`。

## 3. 候选隔离及只读边界

`snapshot()` 使用 `_current.duplicate(true)`。两个 planner 只改该快照中的天赋分配、精通、点数和候选 revision；预览调用的 `_prepare_candidate` 只往此候选的 `skill_groups` 补齐容量，未触及 `_current`。

`_prepare_candidate` 调用静态 `_stats_for(candidate)`，该函数从 `Legacy.BASE_STATS.duplicate(true)` 开始计算派生数值，不调用实例 `get_stats()`、`_ensure_cache()`、技能编译或 combat snapshot。因此不会更新 live stats cache、`_content_epoch`、build/view token、`stats_builds`、`skill_compiles` 或 `cast_entries`。预览没有 `_commit`、`_persist`、`_accept_memory`、signal emit、保存计数/错误状态赋值或 RNG 调用路径。

源数据加载的细节：`SourceTreeData.ready()` 在冷启动确实包含资源文件读取，不能概括成所有源树调用永远无 IO。但正常 `CanonicalGameState` 实例的父类 `_init()` 第一项就取得 `standard_socket_ids()`，并完成合法默认快照迁移，已经加载该固定资源。预览在已初始化实例中只读已加载源数据，没有存档 IO，也未添加资源读取入口。

这些静态结论针对仓库当前实现和正常初始化实例；私有 `_talent_validator` 默认为空，仓库未发现赋值安装有副作用回调。任意外部脚本改写私有字段或替换方法不属于这里证明的正常使用契约。

证据：`canonical_build_store.gd:61,68–103,106–111`；`canonical_game_state.gd:88–92,195–240,326–343`；`source_tree_data.gd:11–15,61–62`。

## 4. 静态派生缓存不会泄露候选状态

- `SourceTreeRuntime._contexts` 缓存固定源图；`_context` 只浅拷贝外层以替换 budget。共享的 nodes/adjacency 只供内部只读分配算法使用，算法输出为新建连接/来源容器，预览不返回 context。
- `_line_cache`、`_node_effect_cache` 只缓存源文本、节点、精通和执行版本对应的派生效果；缓存命中返回深拷贝，首次计算也先深拷贝入缓存再返回独立结果。
- `_analysis_key` 包含 talents、真实 socket rules、budget、policy；仅缓存合法分析，并深拷贝保存和返回。预览的合法候选可以替换这个单槽缓存，但之后分析 `_current` 会按其内容 key 命中或重算，不会把候选视作当前分配。结果中也不含候选的可变对象引用。
- 全量校验还会触及 `Items._metadata_cache`。该缓存以完整实例值、当前词汇版本和辅助定义存在性为 key，仅缓存验证通过的派生 metadata；保存和命中均隔离容器。它不改变物品实例或公开模型计数。

因此“只读”是权威状态、外部副作用、live cache 和公开诊断不变；不是要求已有内部派生缓存的字节绝对不变。未发现预览暴露或污染这些缓存的路径。

证据：`source_tree_runtime.gd:59–78,85–115,142–172`；`source_tree_allocation_rules.gd:22–155`；`unified_item_catalog.gd:104–123`。

## 5. 最终 UI 刷新路径

`_on_model_changed` 现在仅标记 dirty，并在可见时通过 `_model_refresh_queued` 合并安排一次 `_refresh_after_model_commit`。deferred 执行前事务已返回，`_busy` 恢复 false。

- 面板自身动作：`_report` 在 `allocate_passive/refund_passive/move_item` 返回后刷新，消费仍保留的 dirty；已排队 deferred 随后发现 clean 而跳过，不重复生成预览。
- 其他来源的模型变化：deferred 读取最新状态后刷新；连续变化由单队列合并。
- 隐藏面板：保留 dirty；若 deferred 到达时仍隐藏则不消费 dirty，之后 `visibility_changed` 再刷新。
- 现有 HUD 路径：`main._on_build_changed` 先于面板 setup 连接到模型信号；其同步 `hud.refresh_build()` 不会在面板稍后重新标 dirty 之后把这次 dirty 永久消费掉。即便有上次尚未刷新 dirty，面板自己的信号处理仍会重新标 dirty，deferred 能恢复最终按钮状态。

这保留了模型原有“signal 内可读但禁止重入写”的保护，没有为 UI 修改后端 busy 合法条件。证据：`canonical_passive_panel.gd:33,170–208,384–386`；`main.gd:192,254–271,303`；`game_hud.gd:360–367,1082–1093`。

## 6. 成本与验证限制

两种计划都会被询问，但同一正常节点的 allocate/refund 至多一种计划能到达完整候选校验，因此不是无条件做两次完整校验。分配已存在的标准节点时，allocation helper 仍按基线先 `snapshot()` 后报 `already_allocated`，随后 refund helper 再建一次快照；这是一份额外深拷贝，保留它维持了原正文和错误顺序。

合法预览会替换 SourceTree 的单槽 analysis cache，随后的 `_refresh_overlay()` 对当前构筑分析可能需要再算一次。完整预览还会按原准备路径计算候选 stats，按全量规则检查整个候选。这些成本局限在选择、精通选择或实际 dirty 刷新；本次没有新增逐帧预览、全图逐节点完整验证或新持久缓存。未测量毫秒耗时，故不作性能通过或性能退化的量化结论。

本审核没有运行测试。运行层面的只读快照、实际 UI 交叉流程与 deferred 时序证据应以本轮负责测试的 QA 记录为准。
