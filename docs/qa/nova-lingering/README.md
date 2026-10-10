# 新星延长减速：有限机制扩展

基线 `18303a9b8012c28989b785c1809a03f4972641e4`。先完成[旧夹具修复与连锁边界核查](../chain-ambush-followup/README.md)，再明确新星规则并实现。未发现AGENTS.md或相关本地技能指令；沿用现有开发与验证工具。

## 规则和复用

新星原本有0.6秒普通减速，但寒意延长仅接受冰霜。本批开放新星：时长×1.50＝0.9秒，沿用伤害×0.90、魔力×1.10，保留范围、190击退初速、冷却和原命中身份。实际移动仍消费原0.36倍率与世界delta，同类时长取max，不新增状态机。伏击载体冻结时长；冰霜异常时长来源仍不作用于新星，未开放霜锁。

原Data增加“原生减速”能力供现有辅助准入，并集中存放新星原0.6秒常量；该能力不复制为伤害标签。Compiler仅在新星选择寒意延长时写入最终recipe.slow，未选择时维持旧编译形状。原直接新星和符印载体读取该值；载体同时校验它与辅助程序一致。预览显示同一编译值。旧冰霜消费路径、连锁、瞄准、地图完成、移动、收费、库存事务及schema61不变。

## 拥有权与实际验证

复用已提交 `docs/qa/chain-ambush/owned.json`。该存档已经拥有寒意延长 `migration_gem_000019`，直接通过原库存命令装到新星 `group_000003`，主石 `migration_gem_000003`；保持36碎片及物品总数，没有重复购买或赠送。严格保存重载后UID、完整状态和编译结果保持。`owned.json` 是进入地图前实际保存，SHA256 `cd11bb5a34a9d7a65adecde46e31aa734ce06cc2d15e77fad214a990a913e25e`。

- `attempt-01.log` 保留测试重复声明继承变量的解析失败；改为复用原变量。`attempt-02.log/json` 为316检查、0失败。
- 最终 `final.log/json`：**322检查、0失败**。基线提取复用已有工具，额外把本次改变的GameData也从基线抽出并重定向；源／脱离副本哈希见 `baseline.json`。**164组旧编译整体字节对照**覆盖全部10技能、旧空链／单辅、基础与20%冰霜异常时长快照。旧三类符印存储整体字节对照也通过。新星新组合在旧代码明确拒绝，新代码接受，含五槽辅助顺序无关、旧伤害包／范围／冷却保持与原倍率一次应用。
- 原地图实体受控站位、出生、耐久、防御、资源与时钟。实际直接新星、仅寒意延长、伏击＋寒意延长、五槽伏击／寒意延长／广域／感电／节能均核单次扣蓝、原冷却、原标签、实际伤害与190击退。出生保护不受伤或减速；伏击放置不预施加，卸下辅助并移开角色后仍应用0.9秒。伪造符印时长被原子拒绝。
- 原怪物更新中100速度、0.1秒实际移动3.6，剩余时长0.8；继续推进后减速仍超过原0.6秒，并在原时钟到期。已有1.2秒剩余减速再被0.9秒新星命中仍为1.2，不相加。缺蓝拒绝不改变施放状态。
- 原 `delivery_support_rules_test.gd`：**2762检查、0失败**。仅运行原冰霜实战的 `compiled_and_preview` 与 `flying_duration_snapshot` 两段，`frost-regression.log`：**206检查、0失败**（JSON保留写文件检查之前的205项快照，原历史脚本不改），保留3／4.5秒、源属性3.6／5.4秒及已飞行载荷不受后续源变化影响。未执行该脚本其他段或全套回归。

## 中文内容与保全

同源限定导出新增36条新星示例和1组辅助前后对照。所有旧catalog示例数值与结构保持，补充两技能原生减速能力和新星原始时长。中文运行预览、辅助描述、[机制说明](../../NOVA_LINGERING.zh-CN.md)与冰霜源属性说明同步。

`reference-verification.json` 确認只变化新星、寒意延长、冰霜异常时长三张F8卡；其余3815张卡字节一致，21674个内部锚点有效，原字体无新增缺字，合并幂等且HTML与模板同步。656个其他生产／资产文件保持基线字节，连锁执行、触发、瞄准和地图完成函数精确保持。

均为有限受控headless验证；没有原生F8点击、自然战斗录像、平衡或性能验收。旧总览性能问题仍未解决，本轮未重测。没有长矩阵、600秒检测、模型工作、Windows导出或封包。manifest绑定本批两部分代码、文档、实际存档及原始证据；历史manifest不改。

## 复现

```bash
python3 docs/qa/nova-lingering/prepare_baseline.py
XDG_DATA_HOME=/tmp/godot-m1-nova-lingering-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
NOVA_REPORT=/tmp/nova-lingering-review.json \
timeout 45 godot --headless --path . --script res://tests/nova_lingering_test.gd
XDG_DATA_HOME=/tmp/godot-m1-v082-cold-nova-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
COLD_DURATION_GAMEPLAY_SECTIONS=compiled_and_preview,flying_duration_snapshot \
COLD_DURATION_GAMEPLAY_REPORT=/tmp/nova-frost-review.json \
timeout 40 godot --headless --path . --script res://tests/cold_ailment_duration_gameplay_test.gd
python3 tools/verify_nova_lingering_reference.py
python3 tools/build_reference.py --check
```

每次使用全新隔离用户目录，报告使用各自独立目录以保留存档快照。
