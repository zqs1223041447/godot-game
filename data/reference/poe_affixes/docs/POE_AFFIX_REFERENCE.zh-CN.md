# PoE1 普通装备词缀：数据与设计参考

## 结论与范围

已实际拉取固定版本的结构化数据，筛出 **1,200 条普通显式词缀记录：732 前缀、468 后缀**，覆盖 **24 个装备类别、852 个保留底材、178 个精确标签组合**；包括 **102 个互斥组、182 个派生层级家族、158 个底层 stat ID**。一条记录是一档词缀，不是一个独立玩法机制；同一词缀适用多个部位时不重复计数。

本参考把“普通装备的普通词缀”解释为 **非特殊来源装备池的普通显式前/后缀**。它不是在说白色普通稀有度物品会随机带显式词缀。通用蓝装最多1前缀+1后缀，黄装最多3前缀+3后缀；特殊底材的例外不在此次规则中。[GGG物品说明](https://www.pathofexile.com/item-data)

准确的完成声明是：**已完整执行本文件定义的固定快照筛选，得到所选非势力底材上的普通显式词缀候选池**。这不等于已认证“当前线上所有可掉落装备/词缀”，也不等于全部词缀已经做进本游戏。

## 数据来源与版本固定

- 游戏：Path of Exile 1；不是PoE2
- 社区导出：RePoE；不是GGG官方词缀API
- 源导出版本标记：`3.29.3.3`
- 导出commit：`a77305840b4cc8555eeeea144eac3eeddeff134b`，时间2026-09-15 13:49:18 UTC
- 拉取/核验日期：2026-10-02 UTC
- 四份输入：mods 40,355条；base_items 5,461条；stats 23,346条；item_classes 103条
- 每份输入都核对了固定Git tree的blob SHA1、字节数和本地SHA256；细节在`source_manifest.json`

[固定导出](https://github.com/repoe-fork/repoe-fork.github.io/tree/a77305840b4cc8555eeeea144eac3eeddeff134b/data) · [导出站索引](https://repoe-fork.github.io/poe1.html) · [RePoE词缀字段说明](https://github.com/repoe-fork/repoe/blob/1c72e40a99aa8c8f70e9a3526155f455d5eedd43/RePoE/docs/mods.md)

源版本字符串是数据导出的版本标记；未把它冒充为已独立确认的线上最新补丁号。不同来源的天赋树、技能和装备快照可能版本不同，整合时必须各自保留pin。

## 筛选规则与未覆盖内容

底材：仅保留24个装备class、`domain=item`、`release_state=released`。排除talisman、demigods、trade_market_legacy_item、experimental_base标签；同时排除Royale、Descent、MirrorRing、Ethereal、`/Talismans/`、StormBlade ID片段。

审查发现两个不能只依赖tags的陷阱：Greatwolf Talisman没有talisman标签；Energy Blade的两个临时武器底材也被标记为released。现已按ID排除这三项，词缀数量没有减少。

词缀：`domain=item`、generation_type为prefix或suffix、非essence-only、非Royale，且至少在一个保留的裸底材标签组合上有效生成权重大于0。没有给底材添加任何势力/制作状态标签。

因此不包括：传奇专属、势力专属、精华专属、工艺台、揭露/隐匿、腐化隐式、异界隐式、合成隐式、附魔、地图/怪物/药剂/珠宝/星团/深渊珠宝词缀。Atlas、Maraketh、结界和召唤相关普通底材可以保留，其普通显式池由原始标签限定。底材released标记不证明它当前会自然掉落。

“破裂”是现有显式词缀的锁定状态，不应虚构成一套独立数值词缀。本次未建模破裂状态和制作行为。

## 数据结构：不要把四种概念混在一起

| 概念 | 保留字段 | 用途 |
|---|---|---|
| 槽位类型 | generation_type | 判断前缀/后缀占位 |
| 互斥组 | groups | 已有任一重叠组时，不能再选该词缀 |
| 机制家族 | type、ordered stats、适用底材profile | 区分相似机制的不同等级链 |
| 底层数值 | stats中的id/min/max及stats.json元信息 | 精确记录一档词缀改变哪些数值 |

`groups`不是T级列表。比如纯本地物理%与物理%+命中的复合前缀分属不同组，可以共存；同一个复合前缀里的两条stat仍只占一个前缀。增加生命、力量等高档位还会因部位不同而被排除。

`implicit_tags`是制作分类标签，名字不代表该词缀是装备隐式，更不能把它直接当作伤害事件tags。`adds_tags`则会影响后续生成资格；本池只出现has_attack_mod、has_caster_mod，已做闭包检查，没有遗漏因此才可生成的普通候选。

`grants_effects`保留完整。例外示范：MinionGrantsConvocation1还授予一级效果；仅把158个stat列成表不能完整表达它。

## 等级、范围和权重

源`required_level`来自Mods.Level，本工具用它做物品等级资格门槛；不把它当成角色穿戴等级。底材drop_level也不等于实例的item_level。

源库没有正式UI的T级字段。本工具在**同一底材profile、前后缀类型、组、type、ordered stat IDs**内，按required_level由高到低生成`tier_index_derived`。同级多记录会保留并标记歧义，本次为0。它只是可审计的派生排行，不宣称等于每种特殊情境的官方T级；先生成整个profile排行，再按查询item_level过滤，低等级物品不会把它能出的最好档重标成T1。

生成时按以下顺序：

1. 从spawn_weights第一条开始找物品已有tag，**只用第一次命中**，命中0就禁用，不能继续找后面的正数
2. generation_weights同样按顺序匹配，作为百分比乘数
3. 本池有效权重 = spawn_weight × generation_weight / 100
4. 再排除物品等级不足、互斥组已占用、前/后缀槽已满的候选
5. 如果采用“在剩余候选中加权抽一条”的本游戏算法，一条词缀的概率是其权重除以此时同池总权重

原始权重全部存在；不是自拟权重。149条词缀有非空generation_weights，其余1,051条无乘数。149条均有default=100兜底；“非空但完全匹配不到”的源行为未在本快照遇到，工具的默认100只是显式兼容策略，不冒充验证过的通用游戏规则。

权重不是百分比概率。前后缀选取步骤、制作方式、已占组、item_level都会改变分母，本工具没有声称复现整件物品的实际打造/掉落概率。

### 一个可核验的完整等级链

普通弓的本地物理伤害提高，组LocalPhysicalDamagePercent：

| 派生档位 | item_level下限 | 数值范围 | 有效权重 |
|---|---:|---:|---:|
| 1 | 83 | 170–179% | 25 |
| 2 | 73 | 155–169% | 50 |
| 3 | 60 | 135–154% | 100 |
| 4 | 46 | 110–134% | 200 |
| 5 | 35 | 85–109% | 400 |
| 6 | 23 | 65–84% | 1000 |
| 7 | 11 | 50–64% | 1000 |
| 8 | 1 | 40–49% | 1000 |

同一源mod在有wand_can_roll_caster_modifiers的法杖上还会乘50%，最高档有效权重为12.5，而不是25。浮点权重不能随便截断成整数。

其他实测切片：胸甲最高普通生命档为item_level86、+175–189；戒指不能使用这一档。普通鞋移动速度最高档是item_level86、35%；普通弓额外2箭是后缀、item_level86、权重100。这些是固定源快照数值，**不是本游戏建议直接照抄的强度**。

## 接到现有Godot战斗语义时怎样处理

当前v0.3.0已经把基础伤害包、进攻快照、载体和独立爆炸拆开。此次仅提供36项原创语义映射，见`design/godot_mapping.json`；每项标记可类比、解析器可支持但快照未接入、或待实现，不进行自动批量导入。

| 来源机制 | 应进入的阶段 | 错误接法 |
|---|---|---|
| 武器本地物理% | 装备本地基础物理，早于技能基础伤害 | 当global_increased再算一次 |
| 武器本地点伤 | 改此武器的伤害端点 | 无条件给所有技能/爆炸加伤 |
| 攻击附加元素伤害 | 带attack语义的技能基础包，先定义伤害效用 | 因爆炸来自箭就继承attack |
| 攻击技能元素提高 | attack条件 + 元素分量increased | 直接塞到无条件elemental_increased |
| 火/冰/电伤提高 | 只匹配对应分量 | 把整个混合伤害包一起乘 |
| 法术伤害提高 | 本次伤害有spell语义 | 因词缀在法杖上就当本地武器加伤 |
| 攻速/移速百分比 | 独立速度increased阶段 | 直接加到当前次数/秒或单位/秒 |
| 投射物速度 | 载体运动参数 | 当projectile_increased伤害 |
| 弓额外箭矢 | 受技能适用性限制的生成配方 | 自动增加所有技能/每代子弹数量 |
| 抗性与最大抗性 | 防御侧数值及上限 | 混入进攻伤害加法桶 |
| DoT multiplier、暴击 | 专门机制与判定作用域 | 每条都按more独立连乘 |

同一伤害分量适用的increased仍应先相加，不同more再分别相乘。GGG开发者也强调：相加的是**同一个被修改量**；伤害与承受伤害不是同一个量。[GGG机制说明](https://www.pathofexile.com/forum/view-thread/892570)

对照本游戏现有公式：全局20%、投射物50%、元素30%，100物理+100火焰箭体=170+200=370；无projectile标签的独立同基础范围爆炸=120+150=270。再加“攻击元素提高30%”时，箭体火焰再+30%，secondary爆炸不变。此处是本游戏语义测试例，不是声称PoE每个爆炸技能都遵循相同来源规则。

### 单位不能只看数字

- 百分数通常转小数：20 → 0.20，但必须按stat语义确认
- life_leech_from_physical_attack_damage_permyriad的20–40表示0.2%–0.4%；运行分数应除10000
- base_life_regeneration_rate_per_minute应除60才是每秒生命
- min/max伤害端点各有自己的roll区间，不能把两个stat误合并成一条百分比
- 源is_local以stat元信息为准，不通过“物品是武器”或者英文包含damage猜测

## 给本游戏的设计建议，而非PoE事实

现阶段优先复用“来源可追踪、量纲明确、组互斥、分档、适用标签”这套结构。现有三个装备槽与PoE24个class没有一一对应关系；应先设计本游戏自己的槽位池，再选择相关机制。返回、爆炸等已有机制装备继续走effect registry，不混进普通数值词缀。

建议第一批仅开放生命/魔力/护盾加值、明确标签的伤害increased、必要的速度百分比与箭矢数量；其他词缀在相应系统与测试完成前保持不可抽取。不要展示有文案却不生效的词缀。数值预算、等级曲线、稀有度与权重需另行结合本游戏敌人强度和战斗时长平衡，源数值只做参照。

## 文件与验证

- `normalized/mods.json`：1,200条源机械字段，保留顺序/单位原值
- `normalized/bases.json`：852底材到精确标签profile的映射
- `normalized/profiles.json`：178个profile的真实权重与派生档位
- `normalized/families.json`：182个派生家族；与102互斥组分开
- `normalized/stats.json`：158个stat的local/alias元信息
- `normalized/coverage.json`：所有24个class计数、排除计数、歧义/闭包报告
- `validation.json`：源文件校验、全profile权重重算、等级边界、互斥/复合共存等12类验证

运行命令见根目录README。查询器是研究工具，不负责前后缀槽总数、稀有度生成、货币改造或存档迁移。游戏战斗代码未因本次拉取而改变。

## 权利与发布边界

[RePoE许可](https://github.com/repoe-fork/repoe/blob/1c72e40a99aa8c8f70e9a3526155f455d5eedd43/LICENSE.md)明确区分解析器代码与GGG生成数据，MIT不能自动作为后者的商用授权。本参考不搬运美术/音效/原作词缀创意命名和描述；原始输入仅作可复现研究缓存。实际发布应排除整个研究参考目录，使用原创运行数据，并根据[GGG条款](https://www.pathofexile.com/legal/terms-of-use-and-privacy-policy)审查任何再分发。这是来源说明，不是法律许可保证。
