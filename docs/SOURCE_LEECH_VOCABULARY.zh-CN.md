# v0.40 双资源偷取：源词汇与 schema25 边界

锁定源：PoE 3.29.1，SHA-256 `7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122`。本次不改源图、源节点文字、连线、职业起点、专精组与原数值。

## 仅开放八种完整英文格式

`X` 接受非负整数或小数；保留源百分数的 `X / 100`，不把普通天赋的 0.4% 偷换成较大的演示数值。正则两端锚定；前后空格、换行、标点、大小写变体、附加条件、武器词尾均不接受。

| 完整格式 | 字段 | 模式 |
| --- | --- | --- |
| X% of Attack Damage Leeched as Life | attack_life_leech | flat |
| X% of Attack Damage Leeched as Mana | attack_mana_leech | flat |
| X% of Physical Attack Damage Leeched as Life | physical_attack_life_leech | flat |
| X% of Physical Attack Damage Leeched as Mana | physical_attack_mana_leech | flat |
| X% increased total Recovery per second from Life Leech | life_leech_rate_increased | increased |
| X% increased total Recovery per second from Mana Leech | mana_leech_rate_increased | increased |
| X% increased Maximum total Life Recovery per second from Leech | life_leech_max_rate_increased | increased |
| X% increased Maximum total Mana Recovery per second from Leech | mana_leech_max_rate_increased | increased |

`flat` 在这里是偷取比例，不是立即恢复的生命/魔力点数。速率与最大总速率是两种独立修正。本文件只规定源数据准入，战斗实例、逐次命中与恢复行为由战斗规则处理。不新增基础偷取，不开放法术偷取、元素偷取、护盾偷取、立即偷取、满资源保留、条件偷取、召唤物或武器限定机制。

## 整个节点和整个专精选项必须完整支持

节点任意一行不受支持，就不能分配；已解析的偷取行不能替同节点的未知行放行。新增完整普通节点共 **21** 个：

`1382, 22356, 28311, 29547, 35507, 3634, 36704, 37800, 39530, 41819, 4378, 50038, 51420, 54872, 61039, 62094, 62108, 63422, 65053, 8001, 9171`

其中 **20** 个可从七个真实职业起点分别沿完整支持的源连线到达。每职业可达普通节点共 **676** 个（不计自己的起点）；这不是可同时花点取得的数量。可达测试对每条新增节点路径单独执行完整预算/连通性校验，并禁止借其他职业起点、专精、代理或珠宝绕过连线。`8001 Clever Thief` 虽然两行都支持，仍被不支持的邻接路径隔离。

新增完整专精选项仅 **1 个唯一 effect ID：15133**，内容为 0.5% 攻击生命偷取与 0.5% 攻击魔力偷取。它出现在四个 Wand Mastery 入口 `35038 / 48411 / 53828 / 56128`，不计为四个新效果。四组前置显著天赋均含未支持的魔杖限定词条，因此 **可达新专精效果为 0**，不能在当前规则下分配。

另有 **11** 个普通节点保留为部分支持。特别是 `27422 Spirit of War` 的 0.5% 物理攻击魔力偷取本行可以解析，但 `25% increased Cost Efficiency of Attacks` 未接入，故整个节点仍锁定。不能声称已有可分配的物理攻击魔力偷取源路径。其余条件、双手武器、匕首和异常状态伴随词条同样保留锁定。

详尽节点文本、七职业每条最短源路径、11 个部分支持节点与四个专精入口，见 [source-leech-coverage.json](qa/v040/source-leech-coverage.json)。

## 可复现的真实构筑路线

以下使用职业 `4` 的源起点 `50986`；每一步都通过真实 `available()` 与完整保存校验，未写入伪造偷取数值。

- 双资源基础：`50986 → 39725 → 63649 → 49806 → 6580 → 19711 → 20010 → 36704`，7 点，源比例分别 0.4%
- 从 `36704` 分支至 `9171 → 39530` 与 `54872 → 1382`，同时取得生命/魔力速率与各自最大总速率；最终生命/魔力攻击偷取分别 1.4%，两资源速率分别 +60%，两资源最大总速率分别 +40%
- 物理生命与速率/上限：`50986 → 47389 → 42911 → 40867 → 476 → 24865 → 6741 → 14056 → 34400 → 24914 → 61262 → 37800 → 35507 → 22356`，13 点，物理攻击生命偷取 0.6%，生命速率 +160%，生命最大总速率 +40%

以上两组分支还可合并成同一合法构筑。可直接用于战斗测试的完整分配数组、最低等级、花点与原始修正汇总见 [source-leech-example-paths.json](qa/v040/source-leech-example-paths.json)。

## 保存与迁移

schema25 才执行新词汇。`decode_v24` / `reason_v24` 保留 schema24 旧词汇；源行缓存、节点缓存、构筑分析缓存均带执行版本。schema19–24 的每版本 4224 条节点/专精结果，与未修改的 v0.39 基线完全相同。

`SourceCriticalMigration` 固定输出 schema24；新增 `SourceLeechMigration` 先按旧 schema24 完整校验，随后仅把 version 改成 25。完整迁移链仍逐层经过旧版本规则。schema14–24 的旧格式中注入新偷取节点，在备份和写盘前拒绝；源版本13完整迁移仍只做一次最终原子提交。

字面 schema24 默认和旧暴击构筑夹具来自未修改提交 `d6c8165d01783525469e9876c9e779e64e818b03`，不是将新保存倒改版本号。旧暴击夹具有独立 UID、序号、修订和进度，迁移后除版本外完全相等。夹具包含前导空白与 CRLF；首次备份保留全部原始字节。备份冲突、主文件写入失败、外部改写和未来版本继续保护原文件及内存，不通知半成功状态；可恢复写入失败允许安全重试。当前 schema25 也拒绝额外持久化的偷取实例字段。

基线与哈希见 `tests/fixtures/v040_leech/manifest.json`、`old-source-gates.json`。验证日志在 `docs/qa/v040/source-leech-*.log.txt`；每次测试使用独立 `/tmp/godot-m1-*` XDG 目录，没有访问真实用户保存。
