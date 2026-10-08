# 混沌防护：完整基石11455 / schema59

基线 `c74596e5a268000a4988d779c5517f712b55afe2`，独立分支 `codex/chaos-inoculation`，待审，不自动合入 main。

冻结源树3.29.1的完整原句：`Maximum Life becomes 1, Immune to Chaos Damage`。项目中文名沿用“混沌防护”，原中文句沿用“最大生命变为1，免疫混沌伤害”。没有改写英文、节点身份、源图、中文映射、装备或经济入口。

## 完整取舍与实际接点

- `SourceTreeRuntime.apply_stats` 仍先计算装备、属性、珠宝和天赋的全部容量加成，随后仅在完整11455已分配时将最终最大生命覆盖为1。覆盖发生在生命百分比再生计算前；既有狂信者的誓约继续读取最终护盾容量，生命偷取上限继续读取最终生命容量。不增加护盾偷取。
- `DefenseRules.source_profile` 接纳严格的0/1机制标记。`incoming_source_hit` 在原抗性、护甲解析后，通过明确的混沌免疫阶段把混沌分量归零，再进入原伤害承受倍率、护盾、可选魔力分担和生命结算。免疫不伪造抗性，混抗原数值/75%上限保持，解析器90%兼容钳制不改。
- 原始混沌金额保留在 `raw_components`，免疫量进入 `mitigated_components`；细节标记 `chaos_immune`，其余伤害细节及顺序保持。混合包的物理、元素等分量照常。本项目混沌原本不绕盾，本批不引入绕盾。
- `Main.hit_player_components` 的纯免疫沿既有零伤害返回false路径：没有攻击承认记录/闪避熵推进、受伤无敌、充能重置或伤害反馈。仅新增有真实原混沌金额的零伤害入账记录，保留原32条裁剪上限。实际混合伤害继续原命中流程。
- 沿用 `_on_build_changed` 的资源钳制。当前生命大于1时分配钳到1；低于1时不会治疗。退款仅恢复容量和点数，不补当前生命。模型重新加载只恢复构筑，不能描述为保存/恢复战斗中的当前生命快照。
- 当前自然混沌入口是已有蚀影守卫的攻击，经原预警调度器进入公共命中结算。没有声称覆盖尚不存在的混沌持续伤害、中毒或其他新机制；既有火焰燃烧仍可杀死1生命角色。

女巫路线（起点免费，11个付费节点）：

`54447 → 57226 → 21678 → 32210 → 8948 → 27659 → 37671 → 27415 → 32710 → 49605 → 60440 → 11455`

7级预算可分配，不代表护盾构筑已经安全。玩法取舍是以生命缓冲换混沌免疫，依赖原护盾容量、充能、元素抗性及可选既有誓约再生应对其他伤害。

## 冻结政策与迁移

schema59、源执行政策59；装备词汇仍51，无新增保存字段。`decode_v58` / `reason_v58` 先执行完整原生58验证，自定义回调只能增加限制。原57→58的末端校验固定为 `reason_v58`，不再跟随当前版本。新58→59纯迁移只改变版本，不改原分配、点数、物品、UID、技能组、货币、旅程或迁移账本。

原Store加载器仍先备份最初输入原字节，校验外部修改，再原子写并发布一次。58备份后缀为 `.v58-backup.json`；57→58→59只创建原57备份，没有中间58备份。备份失败/冲突、外部修改和最终写失败保留未发布内存及应保留的文件。健康重试复用相同原字节备份。

旧58程序不接受59文件；回退须先另存59，再手工恢复升级前58备份。备份不包含升级后的进度，也不承诺任意并发时序或断电级持久性。进行中地图字段保全不等于重建怪物、弹体与状态计时。

## 本次有限验证

Godot 4.6.3 headless，隔离 `/tmp/godot-ci-*` XDG。以下各命令上限45秒，无长跑或全组合矩阵。

| 验证 | 最终结果 | 证据 |
|---|---|---|
| 完整机制、真实Main/UI与事务 | 111 checks / 0 failures | `mechanism-03.log`、`mechanism-03.json` |
| 完整58迁移及相邻57→58固定终点 | 77 checks / 0 failures | `migration-03.log`、`migration-03.json` |
| 最小F8、冻结文件、关联链接 | 通过，248个链接 | `reference-verification.json` |

机制检查包含：原58全部节点/精通执行策略的归一化SHA256仍与修改前一致，当前只有11455开放；真实女巫从起点逐笔付10点前置和最后1点，按钮/中文细节、分配与退款写失败、桥节点拒绝退款、选中和退款后重载；高/低当前生命钳制、退款无治疗；纯混沌、混合包、物理/元素对照，盾边界、伤害原账、混抗上限不变、畸形输入不能被免疫洗白；真实蚀影守卫预警攻击；现有生命药剂与资源推进、生命偷取上限；完整合法CI+心灵升华、CI+誓约+百分比再生构筑的实际资源阶段；既有火焰燃烧仍致死。

组合与等级是明确标注的合法隔离构筑夹具，不宣称自然成长、获取装备或实战生存率。组合候选由当前完整节点连通路径构造并通过完整canonical校验；主11点路线实际执行付点/写盘事务。未运行模型、Windows导出、封包、性能长跑或无关历史测试。

迁移检查包含城镇和进行中旅程58输入、逐字段保全、原字节备份、单次写/发布、当前59无重写、原57链、原生验证不可被回调绕过、伪造新节点/非法点数/缺失物品/损坏旅程/未来版本拒绝，以及四种IO失败。修改前 `schema58-town.json`、`schema58-active.json`、`schema58-oracle.json` 和捕获脚本/日志已保存；源策略指纹与未分配数值/伤害对照来自该基线。

F8复用现有只读数据投影、精确片段合并和HTML构建器，只改变11455、源树/防御说明及版本来源文字。3816张条目中3806张逐字节保持，7张其他规则卡仅更新当前版本来源，3张为本次相关内容。源树覆盖报告仅目标节点、覆盖计数和各职业可达集合改变，七职业各增加11455。

## 运行及审阅

```bash
timeout 45s env XDG_DATA_HOME=/tmp/godot-ci-review-mechanism XDG_CACHE_HOME=/tmp/godot-ci-review-mechanism-cache CI_REPORT=/tmp/ci-mechanism.json godot --headless --path . --script res://tests/chaos_inoculation_test.gd
timeout 45s env XDG_DATA_HOME=/tmp/godot-ci-review-migration XDG_CACHE_HOME=/tmp/godot-ci-review-migration-cache CI_REPORT=/tmp/ci-migration.json godot --headless --path . --script res://tests/chaos_inoculation_migration_test.gd
python3 tools/build_reference.py --check
python3 tools/verify_chaos_inoculation_reference.py
```

使用新的临时目录以保留故障注入隔离。重建F8时先执行 `tools/chaos_inoculation_reference.gd` 的只读投影（参数为本目录 `reference-fragment.json` 和既有 `docs/reference/source-tree-coverage.json`），再执行 `tools/merge_chaos_inoculation_reference.py` 与 `tools/build_reference.py`。这是文档数据构建，不是游戏二进制导出。

## 留存的早期执行

机制首轮99项通过；加入两个直接交互后109项通过；补上高当前生命钳制与其退款边界后，最终111项通过。没有把三个阶段累计为最终测试数。迁移首次因测试脚本哈希函数名笔误、第二次因测试常量与父类重名而在解析期失败，未执行迁移；修正测试后77项通过。原日志均保留，不把早期尝试记为通过。生产功能没有因这些测试笔误反复改造。
