# 蚀影飞弹＋牵引：有限内容扩展

基线 `6dbf3f9`。读取当前 AGENTS.md，在 dot Linux checkout 使用 Godot 4.6.3 完成。只扩展一个原先明确拒绝的技能／辅助组合；不修改伤害系统、模型、schema61、宝石身份或获得方式。

## 规则和生产修改

蚀影飞弹成功主命中后，把原45向外冲量替换成朝施放时角色脚下位置的190初速。复用牵引原520/秒衰减、怪物移动、墙体与分离。基础魔力8→9.6，占一辅助槽；混沌伤害、附加分量、速度620、零基础穿透、650射程、1.7寿命和1.2冷却保持。牵引可能把敌人拉近，不声称通用强度或DPS提升。

仅四个生产文件变更：
- `inward_pull_support_rules.gd`：兼容白名单增加 shade_bolt，中文说明同步
- `main.gd`：既有冰霜条件加入蚀影，包括原点冻结、施放前固定策略验证、成功结算后的牵引以及防止45向外冲量覆盖
- `projectile_runtime.gd`：原命中事件携带已冻结原点；只影响选中牵引的蚀影
- `damage_preview.gd`：增加蚀影说明，不借用冰缓文字

Compiler、伤害解析器、技能配方、原面积／连锁／伏击消费者和存档格式不变。没有新载体或第二次命中判断。

## 有限证据

- `before.log`：在修改生产前实际运行，原蚀影合法，牵引组合以“技能不支持此辅助”拒绝；基本魔力8、速度620、穿透0、减速0。首个隔离环境未设缓存目录产生 Fontconfig 警告，探针正常退出0；后续均使用可写缓存
- `baseline.json`：从基线只读提取依赖到独立 `/tmp`，记录原文件与脱离命名空间后的哈希；未回退工作区
- `attempt-01`：406检查、0失败；`attempt-02`增加旧冰霜在途事件比较，409检查、0失败；`attempt-03`增加冷却原子拒绝，最终**413检查、0失败，exit0**。没有隐藏失败重跑
- **177次旧完整编译字节对照**：10技能全部原空链／单辅助，两种快照，另原蚀影多辅助和冰霜牵引组合；原配方、包、冷却、伤害分量保持。新组合增加一次1.20魔力；五槽顺序无关
- **15批旧投射载体／事件字节对照**：飞弹、冰霜、蚀影、龙卷无辅助路径，以及携带原点的旧冰霜牵引。未选中的蚀影不新增字段，旧命中和终止事件保持
- 正式 Main 加载已提交 `aim-overlap/owned-after.json`，保留原蚀影主石 `item_000010`、第10组。实际商人购买牵引4碎片，36→32，`item_000011`入包并装配；重复报价确认拒绝，严格保存重载保留UID、完整状态、编译结果。`owned.json`为实际地图前保存，不是测试赠送
- 原城镇明确拒绝战斗；通过正式地图草稿／start_map进入花园及遗迹，不直接改世界模式。真实单弹分别命中1个目标；牵引＋贯穿命中3个；牵引／贯穿／缓速／散束／节能五槽齐射命中受控的3个不同目标
- 对照无辅助原45向外冲量；选中后190朝原点。实际卸装与角色移开后，在途快照完整不变。原移动0.1秒消耗19距离，原冲量衰减至138。检查原混沌伤害及标签、无新增减速、一次暴击冻结、无接触收费
- 出生保护、真实墙体遮挡、缺蓝、冷却未结束、满投射容量和畸形固定策略拒绝均不产生新增伤害／牵引或扣费；真实重开取消载体，拥有权保持
- 独立爆炸用明确隔离的原效果探针：自然结束只结算原火焰爆炸，不带牵引，不声称正式保存构筑拥有该装备
- `old-frost/`：复用原 frost_inward_test 的正式商人／Main场景，跳过其历史编译矩阵，**179检查、0失败，exit0**；保留冰霜主命中、五发／贯穿、冰缓、冻结原点、墙体、原子拒绝和爆炸隔离
- `old-area.log`：原法术牵引的 real_enemy_movement 与 frozen_ambush_build 两个受控旧场景，**103检查、0失败，exit0**。这些旧夹具直接设置受控世界模式，用于旧路径回归，不冒充本次正式入场验收

均为有限headless测试，目标位置、生命、资源与时间用于隔离规则。不是自然游玩、原生点击、长期平衡或性能验收；未运行全套／长矩阵／600秒测试，无Windows导出或封包，无网络操作。

## 复现

```sh
python3 docs/qa/tornado-swift/prepare_baseline.py --base 6dbf3f9 \
  --out /tmp/godot-shade-inward-baseline --dependency inward_pull_support_rules \
  --dependency projectile_runtime --report /tmp/shade-baseline.json
iso=$(mktemp -d /tmp/godot-m1-shade-inward-XXXX)
mkdir -p "$iso/cache" /tmp/shade-report
XDG_DATA_HOME="$iso" XDG_CACHE_HOME="$iso/cache" \
SHADE_PULL_REPORT=/tmp/shade-report/result.json timeout 45 godot --headless --path . \
  --script res://tests/shade_inward_test.gd
```

旧冰霜入口 `tests/shade_inward_frost_regression_test.gd` 要求新的 `/tmp/godot-m1-frost-inward-*` 数据目录与 `FROST_PULL_REPORT` 输出路径；旧法术入口 `tests/shade_inward_area_regression_test.gd` 要求 `/tmp/godot-m1-v067-shade-*` 数据目录。两者各45秒上限。基线探针 `tests/shade_inward_before_test.gd` 读取提取的基线编译器，可在新代码下重复验证原拒绝。

F8只改变蚀影技能、牵引辅助、牵引规则三卡，其余3815卡字节一致。32条完整新增示例及2组规则配对；6个旧JSON容器字节前缀保持。默认Git差异会误对齐重复数据，`git diff --minimal`为7478新增／16删除，没有旧示例重排或全文件格式变化。21906锚点有效，字体无新增缺字，合并幂等。F8精确增量与原资料保留证据见 `reference-verification.json` 和 `reference-export.log`；规则说明见 `../../SHADE_INWARD.zh-CN.md`。manifest绑定代码、测试、实际保存及证据，不修改历史manifest。
