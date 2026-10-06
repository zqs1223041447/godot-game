# v078 转换与穿透实际 Main 验收

2026-10-06，Godot 4.6.3，Linux headless。新增实际 Main **1837 项独立检查 / 0 失败**。旧无转换／仅转火短对照在冻结 v077 与 v078 各 **99 项 / 0 失败**、各10个样本；同一对照的两次检查不累加为功能覆盖。

## 本次实际覆盖

- `typed-fixture-gameplay.json/.log`：8个section、1803/0，4.377秒。模型真实分配女巫23级的27点（24普通点＋三精通，另有免费起点），真实 `_commit`、`allocate_passive`、`refund_passive`、装备／宝石移动及存档读回；没有仅修改stats冒充source连通性
- `source_matrix_and_previews`：单冷、单雷、冷雷、火冷、三转，逐个搭配合法 forgeblade、ashwood_bow、runewood_focus，再读取真实 basic、cleave、tornado 的Stats、Compiler与Preview。所有装备先过真实Catalog实例校验，旧v069的本地四词缀武器继续合法；runewood使用两前缀＋两后缀，提供真实全局附加物理／火焰
- 实际近战普攻、弓普攻、裂刃、龙卷命中；三转剩余物理严格0，120%请求按比例归一。独立oracle从原始base、modifier数组、lineage计算最终类型，不调用转换实现来制造期望值
- 物理／火焰专注不同MORE、同ID不同数组条目不去重、双类型单条只应用一次；原生火焰独立。实际护甲只吃残余physical，全部攻击偷取基于真实盾＋生命损失，物理专属仅吃残余physical份额，过杀不偷取；暴击每cast冻结一次
- v2火焰燃烧基数只读最终fire一次，已有ignite／ember传播和faster／DoT作用一次；DoT不转换、不穿透、不新抽暴击／装备RNG、不产生偷取。普通攻击／裂刃不获得燃烧资格，龙卷／裂刃不因转冷雷获得霜锁／感电或新的类型专注兼容
- 主箭、子箭、返回、纯火寿命终点爆炸，真实精通退款与武器换装后冻结来源保持；纯火P0secondary无新空字段。实际Nova陷阱在转换精通、两个穿透notable退款及辅助卸下后仍按放置时冻结来源命中，未来cast则失去穿透
- 冷／雷穿透对最终类型限定，90%、0、-100%及超边界输入，先基础clamp再减6个百分点、最终仅下限；目标抗性输入不变，真实 `Defense.settle_resolved`保留detail，实际损失不超过资源
- `strict-packets-gameplay.json/.log`：只新增严格包section34/0，重复必要setup49不重复计数。6种损坏分别改requested、effective、remaining、converted、penetration及额外字段；真实 `Base.packet_error`与冻结 `Combat.tornado_packet`拒绝，Main `_execute_compiled`发射失败且不花mana、不推进crit/RNG/cooldown/ID、不改存盘；不调用内部damage helper伪造事务要求

## 合法同源F8输入

`fixtures/`保留真实存档，`reference-acceptance.json`列SHA256与通过标记。zero、cold、lightning、cold-lightning、fire-cold、fire-cold-lightning均在同一合法forgeblade装备保存；selected是初始完整27点配置。zero表示没有转换精通，路线两个notable的冷／雷6%穿透仍在，不冒充“无新stat”旧基线。F8以这些Canonical JSON只读重建Stats/Compiler，不另造装备或路线。严格section再次保存的selected与原SHA完全相同。

## 冻结旧行为对照

基线现有目录 `v077-combat-outcome-feedback`，提交 `07922581e2924dbb6fbadd1fb51242ae87a16293`。只读其已有import cache，未重import、复制整树或改写生产文件。最终脚本 `elemental_conversion_legacy_probe.gd`作为相同外部脚本在两树运行；基本攻击用原v069合法source路径分配／退款65020，再走真实 `_update_auto_attack`准入，其他主动技能走真实 `_execute_compiled`。每组zero/fire-only各覆盖basic、cleave、tornado、nova、meteor，共10样本。每次8个0.1秒投射物步，非长时历史回放。

`accepted-legacy-comparison.json`是最终结果：

- 未投影typed raw snapshot、全compiled packets、Damage receipts、Main damage/burn traces、carrier、events、leech、资源、两条RNG及模型combat snapshot：**311776字节完全相同**，SHA256 `526e6e70c1eaa22fdf0ab328c55df5fbe049d5733d503f0d7dee85b0752307a2`
- 原始actors各42016字节，**不同**，保留两份原文件。仅10个真实source_ember_power actor各4处metadata发生已预期升级：`mechanism_policy`和`mechanism_source_grants/0/{source_policy,source_save_version,policy_version}`中的45→48，共40处逐路径列出；仅这些结构位置对齐后42016字节相同。没有泛删任意同名字段，也不声称整个actor原字节一致
- 实际最终存档各15162字节，原字节不同；JSON仅顶层version47→48，其他完整内容相同。source_save_version的旧值是45，不是Canonical schema47
- 两树运行时分别使用独立 `/tmp/godot-m1-v078-gameplay-*` data/config/cache，源SHA在各次运行中未变化。基线每个tracked生产文件Git blob均匹配07922581；当前旧有生产文件在Main、legacy、strict之间完全相同。新模块hit_penetration_rules等完整生产快照另见acceptance.json，其版本与已有纯层通过记录及604c76bf一致

## 留存失败与范围

1. `first-gameplay.log`：新测试自身4处Variant类型推断缺显式类型，parse阶段未运行功能；补类型后1803全过
2. `legacy-first-v077.log`：测试误送basic到只接受主动技能的 `_execute_compiled`，合法basic应使用 `_update_auto_attack`；最终改用真实v069source模型及原生普攻入口
3. `legacy-basic-entry-*`为排查时的basic直接结算中间证据，不作为最终准入验收
4. `source-policy-v077.log`、`legal-basic-v077.log`：测试给固定mist_skitter强塞不合法magic机制被拒；最终使用既有v075已验wave6 crawler＋source_ember_power合法入口。仅legacy对照重跑，1803功能场景未重复

无生产修改、提交、索引或remote操作；没有全历史测试、600秒性能、截图、native UI或打包结论。最终test只追加了34检查的独立section，已通过的8个section未改动。runner收尾仅加强未来新生产文件的哈希记录，未改变Godot测试参数或断言。

## 复现

协调者完成一次统一import后：

```sh
python tools/run_v078_gameplay.py --mode all --label review
```

仅验证受影响section：`--mode gameplay --sections strict_frozen_packet_admission --label review-strict`。runner不import；每次使用新label留存旧证据。基线可用`--baseline /absolute/path/to/v077-combat-outcome-feedback`明确指定，必须保持冻结源码和既有class cache。
