# v090 探索路线与六驻点的有限 F8 同步

基线图鉴为 `8944b8f`。仅替换当前 `exploration_maps` 的布局、描述、独立 Plan、实际入场记录与证据；修改四张地图卡和探索规则说明。`game_version=0.87.0`、schema50/source49/equipment46、费用、完成奖励、首领预算和所有旧伤害示例保留。

- `export-fragment.gd` 只调用四图 I 档、空词缀、seed 90001 的独立 Plan 与当前 Layout；不加载旧大 catalog、不实例化 Main、不构造角色装备、不运行战斗或重导入。
- `exploration-fragment.json` 提供同源几何和全部 25/37 个初始实体；每图六处驻点，旧庭 3/5 怪各三处，其余 4/8 怪各三处；原三个 camps 仅是来源编排。
- 四张 SVG 逐段使用实际 route_segments 端点与 72 路宽，绘制六处驻点牌、首领牌和全部初始点。路线和旗标只作平面说明，没有新 PNG。
- 复用 `../v090-routes/layout-result.json` 的 28,135 项、36 配置验证和 `../v090-routes/main-result.json` 的 185 项验证；逐文件核对 `tested-inputs.json`。没有在本步骤重跑这些测试。
- Main 的 `entries` 仅含残垣、晴泉、银杏。旧庭实际生成记录来自 `full_run.records`，ID 从其记录提取；报告未单列旧庭入口坐标，未凭空填入。
- `merge-fragment.py` 使用 Python raw-token splice；其余顶层段、四图旧经济和首领字段保留原 token。旧数值不经过 Godot JSON 往返。
- `check-reference.py` 只检查生成结果、结构、链接、同源 SVG 坐标、既有验收来源和保全。新 builder 配旧 catalog 必须逐字节生成旧 index；当前仅四图卡与探索规则卡有差异，页面数据索引和指纹同步改变。
- `frozen-inputs.json` 与 `preservation.json` 证明生产、根 README、探索合同未改；旧图鉴资产和 source coverage 字节及 mtime 均未改。

执行顺序：一次隔离用户目录的有限 Godot 导出 → Python splice → `tools/build_reference.py` → 窄静态验证。过程日志见 `export-result.json`、`export.*.log.txt`、`build-result.json` 和 `preservation.json`。

本步骤不声明自然战斗录像、原生 F8 视觉、600 秒稳定性、安装包或 Release 通过；不调用旧整库 `export_reference`，不全量重建资产。
