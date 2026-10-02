# 回收与数值校准：独立规则原型

> v0.15已接入游戏的回收/校准与持久化，见[制作集成](CRAFTING_INTEGRATION.zh-CN.md)。下文保留独立组件交付时的接口边界；不能把纯组件说明当作完整游戏事务。

本模块基于远端 v0.13.0 提交 `a4a306a6d8c14320fce383dccf6ad7ca40836757`，只新增纯数据规则、独立测试和本文档。**尚未接入游戏、钱包、装备表、交互界面或存档；没有发布。** 主集成负责统一事务、属性刷新与存档。

实现：[crafting_rules.gd](../scripts/items/crafting_rules.gd)。装备内容唯一来源仍为 [EquipmentCatalog](../scripts/items/equipment_catalog.gd)，不复制底材、词缀数值表或本地伤害公式，也不读取离线图鉴。当前覆盖 9 种实际底材、19 个词缀族、91 个合法底材/族组合、57 个族/档位；包括符木法器附加伤害、灰烬皮甲火抗、白蜡长弓的两种本地词缀。

## API 与返回值

```gdscript
const Craft = preload("res://scripts/items/crafting_rules.gd")

var info: Dictionary = Craft.metadata()
var quote: Dictionary = Craft.salvage_quote(instance)
var plan: Dictionary = Craft.recalibrate_plan(instance, 20261002)
if plan.ok:
    var replacement: Dictionary = plan.instance
    var preview: Dictionary = plan.definition
    # 此处只是计算结果；不要在界面层直接扣款、替换装备或调用存档。
```

两个操作返回相同的结构：

| 字段 | 含义 |
|---|---|
| `ok` / `code` / `reason` | 是否成功、稳定错误码、中文原因；成功时后两者为空字符串 |
| `operation` / `rules_version` | `salvage` 或 `recalibrate`；当前为 `original-crafting-prototype-v1` |
| `cost` | 待扣材料数量字典；回收为 `{}` |
| `materials` | 待获得材料数量字典；校准为 `{}`；不是余额 |
| `consumes_item` | 成功回收报价为 `true`，表示提交时消耗源物品；调用函数本身不消耗物品 |
| `source_instance` | 源实例的深拷贝，可用于主集成的过期报价检查 |
| `instance` | 校准后的新字典；回收为 `{}` |
| `definition` | 由 `EquipmentCatalog.definition(instance)` 重新派生的预览；回收为 `{}` |

所有返回结构均可独立修改，既不引用输入，也不泄漏目录常量。失败时 `cost/materials/source_instance/instance/definition` 全部为空，`consumes_item=false`；不得应用失败结果。

错误码为 `invalid_instance`（目录验证或资格失败）、`no_affixes`（目录合法的普通无词缀装备）、`invalid_seed`（种子类型不合法）、`unsupported_rarity`（未来稀有度未配置经济规则）、`invalid_result`（重掷后的目录验证或派生失败）。非法普通装备仍先返回 `invalid_instance`，只有目录合法的无词缀装备返回 `no_affixes`。

## 数值与随机数契约

- 两个操作均先调用 `EquipmentCatalog.validate_instance`，并复用 `base_definition`、`affix_definition`、`family_eligible`。普通无词缀装备不支持这两种工艺；固定装备定义、伪造 ID、越界数值、错误底材资格、重复族/组、未解锁档位和非法前后缀数量均拒绝。
- 校准保留 `id/base_id/rarity/item_level`、词缀数量、数组顺序、族 ID 与 tier；只在各现有 tier 的包含端点整数范围内重掷 `value`。不会换底材、换族、升档、增删词缀或提升物品等级。
- 百分比仍以整数百分点存储，转换由目录负责。JSON 解码后的有限整值浮点实例按目录规则接受；保存的等级、tier 保持原表示，重掷的 `value` 是整数。小数、布尔、字符串、NaN/Inf 不会被截断或修复成合法实例。
- `seed_value` 必须是 Godot 的实际 `int`（有符号 64 位），支持零、负值及两端极值，拒绝布尔、字符串和浮点数（包括 `1.0`）。如需把 seed 存入 JSON，主集成应以十进制字符串另存并严格解析，避免 JSON 浮点丢失大整数精度；本模块不负责 seed 持久化。
- 每次校准创建独立 `RandomNumberGenerator`，显式设置 seed，并按已有词缀顺序调用 `randi_range(min, max)`。相同实例与 seed 在相同 Godot RNG 实现及目录/规则版本下得到相同结果；不承诺跨引擎 RNG 算法版本复现。
- 新值可能与旧值相同，也可能更低；没有保底提升或强制不同。掷值不依赖原 `value`，不同 seed 也可能碰撞。调用不使用、重设或推进全局 RNG；调用方的掉落 RNG 不参与。

本地武器 W 由现有 `EquipmentCatalog.definition()` → `weapon_profile()` → `WeaponLocalRules.resolve()` 链重新派生。`plan.definition` 提供新 `weapon_profile/weapon_damage/weapon_damage_summary`，本地物理点伤及提高不会进入角色全局属性。`plan.instance` 仍只有五个规范字段，不持久化 W、profile、预览文本或报价。普通攻击、龙卷箭体与法术作用域仍由现有战斗编译器决定，本模块不改战斗规则。

## 原创、可调整的经济原型

材料 ID 为 `calibration_shard`，显示名「校准碎片」。这是待主集成引入的材料契约，当前游戏没有因为本模块而获得材料钱包。

实现中的 `BALANCE` 是经济参数唯一来源，`metadata().balance` 返回其深拷贝，计算也直接使用同一常量。当前：

```text
回收获得 = 稀有度基础枚数 + Σ(现有词缀 tier) × 每档枚数
稀有度基础枚数：magic=1，rare=3；每档枚数=1
校准消耗 = 同一实例的回收获得 × 2
```

| 实例 | 回收获得 | 校准消耗 |
|---|---:|---:|
| 魔法，单 T1 | 2 枚 | 4 枚 |
| 魔法，两条 T3 | 7 枚 | 14 枚 |
| 稀有，T3/T2/T1/T3 | 12 枚 | 24 枚 |
| 稀有，六条 T3 | 21 枚 | 42 枚 |

回收不额外收费，但提交时销毁源物品。校准只收材料，不产生材料，不销毁源物品而是按相同 ID 替换它。价格不取决于掷值高低或 ilvl，所以同一物品校准后回收收益不变；当前参数下校准后回收不会净增材料。这只描述单件交易算术，**未做完整游玩或经济平衡验收**，也不保证整体经济无漏洞。修改 `BALANCE` 时应同时更新规则版本、独立经济期望与本文示例，再重新评估主集成交易逻辑。

`metadata()` 还提供原型状态、材料名称、操作说明、公式、保留字段、全部底材/族 ID，以及直接调用目录资格函数生成的 `eligible_families_by_base`。它是可接入图鉴或界面的数据入口，本次没有修改现有图鉴生成器或 UI。元数据的资格列表是族/底材范围；具体等级、稀有度和完整实例仍必须逐件校验。预览 `definition` 含 `Vector2i/Array[String]`，不应当作 JSON 存档对象。

## 主集成事务边界

建议接入顺序如下，属于待主集成实现的职责：

1. 从权威装备表取实例，验证玩家所有权、当前位置/装备状态、存档写保护状态及操作策略。传入一个目录合法实例并不等于玩家拥有该实例。
2. 生成报价/计划用于展示；主集成选择并持有本次 seed。该模块无法防止重复预览挑 seed、请求重放或并发提交，主集成需要定义预览与确认策略、操作 ID 和版本/修订号。
3. 确认操作时进入主集成已有事务边界，再核对实例与 `source_instance`、材料余额、规则版本及修订号；从权威数据重新计算计划，不能信任由界面传回且可修改的 `cost/materials/instance`。过期、重复或余额不足请求必须无副作用地拒绝。
4. 先构造并验证完整候选状态。回收同时删除源物品、处理位置/已装备引用并增加材料；校准同时扣材料、按原 ID 替换实例并保留合法位置。候选状态中任一步失败，不得留下半次扣款或半次替换。
5. 主集成统一提交完整状态，必要时刷新已装备物品的角色属性与派生战斗快照，调用现有进度批处理和存档流程保存一次。材料与装备必须处于同一存档事务；保存失败的回滚/重试、保护提示、幂等处理均由该层定义与验证。

当前 v9 装备实例仍维持五字段契约。钱包或顶层材料字段尚未接入；不能直接给现有严格存档结构塞入额外字段，也不能把报价当成已执行事务。后续主集成需要相应 schema/迁移、保护存档及恢复测试，本独立测试不声称覆盖这些尚未实现的行为。

## 独立验证

在仓库根目录运行；不依赖 `tools/validate.sh` 接线：

```bash
mkdir -p /tmp/crafting-rules-test/{data,cache/fontconfig,config}
XDG_DATA_HOME=/tmp/crafting-rules-test/data \
XDG_CACHE_HOME=/tmp/crafting-rules-test/cache \
XDG_CONFIG_HOME=/tmp/crafting-rules-test/config \
godot --headless --path . --script res://tests/crafting_rules_test.gd
```

测试见 [crafting_rules_test.gd](../tests/crafting_rules_test.gd)，包括全部 91 个合法底材/族组合 × 3 档的最小/最大输入、档位解锁边界、每个越界端点拒绝；每个族/档全部整数掷值可达；所有底材的合法前后缀数量组合、等级 1/7/8/15/16/30、自然生成的混合档位；JSON 往返、非法结构/资格/seed、种子极值、输入深拷贝、返回对象隔离、目录不变、全局 RNG 和调用方 RNG 不变，以及白蜡长弓新 W 与现有解析器/独立算术一致。

实际引擎：Godot `4.6.3.stable.official.7d41c59c4`。验收应同时检查退出码和日志中的 `SCRIPT ERROR:` / `ERROR:`，因为 Godot 的脚本错误并非总伴随非零退出码。本次只验证规则模块及相关既有目录/本地武器回归，未进行原生交互、钱包事务或存档接入测试。

2026-10-02 云环境实测以下六个独立套件均退出 0，日志无 `SCRIPT ERROR:` / `ERROR:`：

| 测试脚本（`tests/`） | 检查数 | 失败数 |
|---|---:|---:|
| `crafting_rules_test.gd` | 91,707 | 0 |
| `equipment_catalog_test.gd` | 1,132,901 | 0 |
| `typed_affix_catalog_test.gd` | 314,545 | 0 |
| `defense_equipment_catalog_test.gd` | 24,643 | 0 |
| `local_weapon_catalog_test.gd` | 38,645 | 0 |
| `local_weapon_compiler_test.gd` | 524 | 0 |

新增套件深检 2,415 份合法校准计划，并另对 57 个族/档各跑 256 个 seed 检查全部整数掷值可达。上述回归不是完整 `tools/validate.sh`、发布包或原生游戏流程验收；本次未运行这些更大范围检查，也未修改验证入口。
