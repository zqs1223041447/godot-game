# v0.82 冰霜异常持续时间 F8 窄更新

基线 `a57a9c0`。新增 [冰霜异常持续时间规则卡](../../reference/index.html#rules-cold_ailment_duration)；当前运行版本为 0.82.0、存档和源政策为 49、装备词汇仍为 46。原图鉴缓存的 0.78 数值与旧章节保留历史身份，不全量重导出。

## 输入与导出范围

使用 [实际 Main 报告](../v082-gameplay/main-result.json) 中无失败的 `compiled_and_preview` 部分，以及六份完整合法构筑：`before/after-plain-frost`、`before/after-lingering-frost`、`before/after-frost-lock`。构筑通过 `tests/fixtures/v082/cold_ailment_duration_fixture.gd` 的 4 级、8 点女巫路线准备，真实分配 14209，并以真实所有权事务装配技能组；F8 不另造装备。

[唯一短片段入口](export-fragment.gd)在父任务统一 import 后运行。逐份严格解码和校验原构筑，只读重建 `Model`，实际调用 `get_group_cast` 与 `DamagePreview.details`，整份 cast、stats、preview 必须与 Main 的 `compiled-preview.json` 精确相等。读取前后校验 fixture SHA，要求零保存尝试。输出只含 F8 所需的配方、策略、时长、预览和来源身份。

同一进程读取源节点 14209 的当前执行和中文动态实装状态、五个既有当前源绑定机制，以及 `SourceCoverage.build_report()` 的完整覆盖。覆盖必须只改变 14209 的执行记录和对应统计、可达前沿；其他节点、mastery、原始源树拓扑和来源身份严格不变。

## 字节保全与政策 metadata

[窄合并脚本](merge-fragment.py)只读取得精确 Git 基线，再替换有依据的 JSON span。旧 catalog 不进入 Godot，不重序列化历史数字、typed 结构或示例。新片段以外仅允许当前版本标签、14209 的动态执行/中文标记及五个当前源定义的三类 metadata：`source_policy`、`source_save_version` 的 48 → 49，`policy_version` 的 `policy:48` → `policy:49`，共 15 项。旧 actor 快照及其源 metadata 原样保留。

[HTML 构建器](../../../tools/build_reference.py)新增规则卡和 14209 的链接；霜锁、三元素及已存在的四个历史提示明确标注当前存档/源政策49并指向本章。旧例子不会据此改算。原支持卡的全局运行版本标签与装备规则的当前存档标签随当前版本变化；其他未涉及卡逐字节比较。

[聚焦检查](check-reference.py)校对六份实际 Main 来源、权威 HTML 数值路径与显示、全部旧锚点、本地链接、PNG 原字节、原始数据、15 项明确 metadata 变化及全部未涉及卡。20% 单句开放不放宽 21460 的 50% 词句或其他混合节点。没有全量 catalog 导出、历史大套件、额外 Main、浏览器或桌面 UI、图片生成、打包、提交、tag 或 Release。

[完整规则说明](../../COLD_AILMENT_DURATION.zh-CN.md) · [Main 运行收据](../v082-gameplay/main-run.json)

## 验证结果

唯一 [Godot 窄片段导出](cold-duration-fragment-result.json) 6.611 秒通过，六份真实 Main cast、stats 和 preview 精确相等，零保存尝试，无错误且运行时输入 SHA 不变。覆盖只有 14209 的执行记录变化；七职业非起点可达数均从 707 到 708，不代表可在同一预算全部分配。

[原始 tokens 保全](catalog-format-preservation.json)只拼接 28 处允许差异，77 个历史顶层片段原字节保留；五源绑定的 15 项溯源 metadata 单独列出。23 个旧机制和全部历史 actor 数值/metadata 不变。HTML 保留 3761 张旧卡原字节，23 张卡只有精确版本标签变化；保留 3842 个旧锚点，只新增本章锚点。239 个受保护文件和 135 张旧 PNG 原字节保持，无新增图片；本批源本地化文件由源接线单独维护，不冒充未修改。

[HTML 构建](build-result.json)和[确定性核对](build-check-result.json)通过；[聚焦检查](focused-reference-result.json) 6.325 秒通过，校对 24 个权威 HTML 数值及显示文本、全部旧锚点和本地链接。完整结果见 [preservation.json](preservation.json)。

所有阶段首次通过；输入 SHA 和完整 stdout/stderr 同目录保存，没有重跑 Godot、覆盖失败收据或放松相等检查。
