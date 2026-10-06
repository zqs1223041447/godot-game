# v0.67 牵引辅助：纯规则、注册与编译验收

2026-10-06，基于 v066 发布基线 `8d51ac6` 的 v067 集成工作树，使用 Godot `4.6.3.stable.official.7d41c59c4`。本分支只交付必要源码、集中测试及 GitHub 更新；这里没有 Windows 导出、封包或全量历史长测。

## 最终结果

| 范围 | 结果 | 进程时间 | 原始证据 |
| --- | --- | --- | --- |
| 固定策略、向量与非法输入 | 155 检查，0 失败 | 0.467 秒 | [日志](inward_pull_rules_test.run-01.log.txt)、[命令/输入哈希](inward_pull_rules_test.run-01.json) |
| 注册、费用、组合与编译边界 | 592 检查，0 失败；21 组组合 | 0.655 秒 | [日志](inward_pull_support_compiler_test.run-02.log.txt)、[命令/输入哈希](inward_pull_support_compiler_test.run-02.json) |
| 冻结旧编译结果 | 783 行，0 失败 | 1.118 秒 | [日志](inward_pull_legacy_compile_test.run-02.log.txt)、[命令/输入哈希](inward_pull_legacy_compile_test.run-02.json) |

以上通过运行均 exit 0，零 `SCRIPT ERROR` / `ERROR`，每次记录的输入哈希在运行前后相同。纯规则通过后未修改该 provider/test，也没有为后续 compiler 边界修复重复运行。其余两项在修复后各集中重跑一次。

## 验证合同

- 仅 `nova`、`meteor` 接受 `inward_pull`；显示名为“牵引辅助”，占一个原辅助槽，schema42 拒绝、schema43 接受；既有 Ambush schema42 门槛保持。
- 唯一 provider 权威为 `{impulse_speed: 190.0, mana_multiplier: 1.20, direction: "toward_origin"}`。编译预览 `area_impulse_profile` 和冻结快照 `area_impulse_policy` 均使用加上 `enabled: true` 的四字段副本，并相互隔离。
- program 只改变魔力倍率，不添加伤害 modifier、冷却 multiplier 或 recipe factor。编译后的所有原伤害包、几何、伤害分量、暴击、偷取、点燃/余烬、感电、伏击策略及源消耗公式因子与未装牵引时一致；费用中 `support_mana`、`final_mana` 正确乘 1.20。
- 21 组覆盖单牵引、两技能各自所有合法双辅助，以及四组代表性五槽组合，包括牵引与既有伏击、广域/凝域、感电、点燃/余烬、效率、迅捷施法等组合。没有枚举所有五槽排列。
- 纯 `impulse(origin, target, policy)` 使用本次真实爆发中心，精确反向原 normalized ×190 表达式；中心重合为零，不修改输入，不消耗随机数。非有限向量、错误类型、额外/缺失字段、禁用或错误方向、非固定数字与对象形输入均拒绝；敌人死亡准入、地形、分离和衰减由原消费者负责。
- 校验与辅助准入不会执行不可信对象的字符串转换或属性访问。快照中的派生牵引字段不能伪装成原始构筑重新编译，也不能借未装辅助的编译路径获得免费牵引。
- 未选择新 provider 时继续跳过其 program，旧输出不增加新字段。新规则、编译和重复/倒序选择均保持输入所有权及全局 RNG。

## 冻结旧行为证据

新测试直接读取已提交的 [v066 oracle](../v066-runtime/legacy-support-after.json)，不重跑旧侧，也不重新制造旧预期。测试锁定其原字节 SHA-256：

`3c8262b7111eaf883b1931496ad55283118c994ea0967448b57702796eddb0de`

逐行复用其技能、原辅助选择和三类快照输入，核对当前完整编译结果与注册 program 的 `var_to_bytes` SHA-256，最后重新构造 JSON 并与原 oracle 比较全部字节和全局 RNG。该历史 oracle 覆盖所有技能的旧零/一/二槽合法选择及各一个最大五槽组合，**不包含 v066 新增的 Ambush**；牵引和既有 Ambush 的组合由上面的新组合测试覆盖。实际 Main 逐步等价由独立消费者验证负责。

## 首次失败及修正

[首次 compiler 日志](inward_pull_support_compiler_test.run-01.log.txt) 保留 487 检查 / 23 失败，没有脚本解析或运行异常：

1. 21 个组合的测试错误要求整个 `cost_factors` 保持相等，但其中两字段记录的正是支持后费用，应当乘 1.20。测试改为检查这两个金额和其余源公式因子，生产费用逻辑未改变。
2. 对新星、陨星分别测试的两个失败发现同一个真实边界缺口：原始快照注入 `area_impulse_policy` 后，在未选择牵引时也能通过编译。集成修复把 `area_impulse_policy` 和 `area_impulse_profile` 加入原有派生字段拒绝分支；保持原错误消息与判断顺序。

首次纯规则及冻结 oracle 均通过，原始日志和哈希收据全部保留。修复后只重跑受影响的 compiler 与旧编译 oracle。

## 复现

在项目已完成统一 import 后：

```sh
python3 docs/qa/v067-rules/run-focused.py rules compiler legacy --label independent-review
```

runner 为每项使用独立 `/tmp/godot-v067-rules-*` XDG data/config/cache，不执行 editor import，不访问默认用户存档；每项最多45秒，拒绝覆盖已有同名证据。非零退出、错误行或被记录输入哈希变化均视为失败。输入收据覆盖该测试递归静态 preload/load 依赖、project.godot，以及旧 oracle 文件；不是全项目变更冻结证明。

这里的结论仅覆盖纯规则和编译，不代替真实 Main、存档迁移、商店、UI 或性能验收。
