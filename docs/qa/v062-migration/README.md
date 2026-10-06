# v0.62 schema38 → schema39 迁移 QA

本页只整理已保存的两次迁移运行和两次 fixture 捕获记录；编写本页没有重新运行检查，也没有修改生产代码。最终有效迁移结果是 **4,451 checks / 0 failures，exit 0**。

## 两次迁移运行

| UTC 记录标识 | 检查 / 失败 | Exit | Script errors | 日志中的 ERROR | 耗时 | 输入前后相同 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 20261006T013202310966Z | 4,460 / 9 | 1 | 0 | 9 | 14.727 秒 | true |
| 20261006T013239227556Z | 4,451 / 0 | 0 | 0 | 0 | 14.754 秒 | true |

- 第一次：[原日志](20261006T013202310966Z-migration.log.txt)、[执行与完整输入哈希](20261006T013202310966Z-migration-attempt.json)、[检查结果](20261006T013202310966Z-migration-checks.json)
- 最终一次：[原日志](20261006T013239227556Z-migration.log.txt)、[执行与完整输入哈希](20261006T013239227556Z-migration-attempt.json)、[检查结果](20261006T013239227556Z-migration-checks.json)

第一次的九个失败均来自同一条测试断言：把九件内置静态装备的空 payload 传给只接受实际词缀装备实例的 Equipment.validate_instance_for_version API，并断言它们在 vocabulary37 有效。静态装备由统一物品定义校验，本来就没有这种词缀 payload。日志中的九个 ERROR 是这些断言调用 push_error 的输出；没有 GDScript 解析或执行错误。

测试随后仅在这条 API 专用循环中排除空 payload，继续对所有实际词缀装备验证 vocabulary37 接受、显式 vocabulary38 拒绝。检查数因此减少九项至 4,451，其余迁移、拒绝、备份、写失败、当前装备读写和源政策检查保留。两次记录中本页列出的生产代码输入哈希一致；修改的是测试文件，未通过改生产逻辑消除断言。

测试文件 SHA-256：

- 初次：`2d66e84f842ad5a481967874126474c03d3f37d817268e55e96c076aaec6b201`
- 最终：`77d4cf3df1d123b7690480c5f15fdab76d3ba1800d1b83eca2b708265d26b769`

## 两次 capture38 记录与最终 fixture

两次捕获都运行于 `/workspace/scratch/a51485f153de/v061-final-source-snapshot`，使用它已有的 Godot 缓存和原生 Store serializer；没有用 schema39 序列化器生成后再改版本号。两次都有独立的 `/tmp/godot-m1-v062-migration-*` XDG 目录。

| UTC 记录标识 | Exit | Script errors | 日志中的 ERROR | 耗时 | 输入前后相同 |
| --- | ---: | ---: | ---: | ---: | --- |
| 20261006T012910405907Z | 0 | 0 | 0 | 1.812 秒 | true |
| 20261006T013043973668Z | 0 | 0 | 0 | 1.771 秒 | true |

- 第一次：[原日志](20261006T012910405907Z-capture38.log.txt)、[执行与完整输入哈希](20261006T012910405907Z-capture38-attempt.json)
- 最终捕获：[原日志](20261006T013043973668Z-capture38.log.txt)、[执行与完整输入哈希](20261006T013043973668Z-capture38-attempt.json)

第一次成功捕获时，脚本输出标签仍误写为 “Frozen v060”；实际 `--path`、schema38 断言和记录的原生源码均指向 v061。随后只把捕获脚本的打印标签改成 “Frozen v061”，显式刷新捕获，以使保留的 manifest、脚本哈希和最终日志相互对应。两份历史记录均保留；manifest 指定 **第二次捕获**为最终来源。

最终 [fixture](fixtures/v38-frozen-v061.json) 和 [manifest](fixtures/manifest.json)：

- 来源发布：v0.61.0，`d884caea7a2260f4535ba4da2d7e005e6df006d4`
- 字节数：19,805；物品数：48
- fixture SHA-256：`41d1223ba3656b8d687e93754fe10acb961e4ba48d2288c5fe72bb6ac87c18ac`
- [源政策 oracle](fixtures/v38-vocabulary-oracle.json) SHA-256：`e2039f451bc9f5a1b5933425cf7840ad4872b2e5650c782878d6853092811b5f`
- 最终 capture 脚本 SHA-256：`4816e3585407b6c9ea907424a9bb7ef6edd51f5e1ecd735bed843c7a78c0f361`

Fixture 保留混合历史装备池、rimeward/stormward 双后缀物品和已经分配的 Resolute Technique 路线，也包含修订、制作修订、等级与旅程见证值。[Frozen release 证据](frozen-release-evidence.json)记录了冻结 Store、Rules、Equipment 与源政策代码和上述发布 commit 的逐字节一致性。

## 最终测试输入哈希

以下 SHA-256 均直接摘自最终成功运行的 inputs_before；相应 inputs_after 完全一致。完整输入清单，包括全部 scripts/*.gd、project.godot、测试脚本和三份锁定源数据，保存在[最终 attempt](20261006T013239227556Z-migration-attempt.json)。这里记录的是该次运行的输入，不代表在生成本页时重新执行了哈希或测试。

| 文件 | SHA-256 |
| --- | --- |
| `tests/defense_rating_affix_migration_test.gd` | `77d4cf3df1d123b7690480c5f15fdab76d3ba1800d1b83eca2b708265d26b769` |
| `scripts/save/canonical_build_rules.gd` | `8c004dd2c9ca06dccf58a9a6d31faac8ed17f41c6ba417ad89b8de94114093a3` |
| `scripts/save/canonical_build_store.gd` | `f209b8481d9e387f6f6615ed0111d4d322fbcd87a5e73d23c0fc0122a45bddf1` |
| `scripts/save/defense_rating_affix_migration.gd` | `e0b61c6ee5bb1f07acd2810dbf7de76250347d08efe118c9da7dddf205d6a763` |
| `scripts/save/resolute_technique_migration.gd` | `ced4e5adda9f14ce052a1ce07a4723fc2487c922a9ec12d89b3463d99f8a9ff5` |
| `scripts/canonical_game_state.gd` | `e2ee31a93033dd2b24b5d3f7ed6eefbbd46c5d653cb53830be3bf3738ff5fd2c` |
| `scripts/items/equipment_catalog.gd` | `5d6804a0d42bc28b711152a50659261fb533149e35161b3936b430af733859be` |
| `scripts/items/defense_rating_affix_profile.gd` | `bd2782e04a18ab1fde0c40ee852fa14b0848f6e6d177356764d53b2e0171f215` |

Fixture 和 oracle 的精确内容分别由上文 manifest 哈希以及测试内的 fixture 字节数/哈希、完整源效果对照约束。

## 冻结边界与已覆盖行为

- 当前存档 schema39、装备 vocabulary39；旧存档 schema37/38 显式映射到装备 vocabulary37，schema≤36 保留原映射。直接请求装备 vocabulary38 继续拒绝
- frozen38 的原生结构、物品、布局、技能、点数与源合法性先于可选回调；即使当前物品缓存已预热、回调总返回成功，旧37/38仍拒绝 ironhide 或 mistweave
- 新迁移只改变 version；原物品、词缀值、UID 与顺序、点数、货币、修订和旅程不变，不使用 RNG，也不赠送物品或点数
- 原 schema38 字节先保存为 `.v38-backup.json`，再提交 schema39；备份失败、备份冲突、外部改写、原子写失败均不发布新内存状态，保留对应原文件/外部写入和已有有效磁盘凭据
- 先前37→38迁移仍终止于 reason_v38，历史34/35/36/37及内置完整链均能抵达39；备份仍使用最初输入版本和原始字节
- schema39新词缀装备完整保存、重开和实际移动事务均覆盖；失败事务保持状态，重试只提交一次
- **SourceTreeRuntime.CURRENT_SAVE_VERSION 保持38，schema39执行政策也仍为38**；每个标准源节点和 mastery 的分类/效果与38相同，完整可执行节点及 grants 与冻结 v61 oracle 一致，已分配 Resolute Technique 的完整属性不变

[冻结源证据](unchanged-source-evidence.json)中的 `exact_frozen_v61_source_policy` 为 true。以下生产源与数据文件的 v62 哈希全部等于冻结 v61 哈希；此次工作没有开放源天赋、改变源解析规则、词条本地化或属性公式。

| 冻结文件 | v61 与 v62 共同 SHA-256 |
| --- | --- |
| `scripts/passives/source_tree_runtime.gd` | `40f9586a851c3445775c97602efdfcabf57aba24b931a4b990d2659042723b68` |
| `scripts/passives/source_stat_patterns.gd` | `c4c5a6a2ddd5b566982dbe7056b27b14e8a78cd5c0e4040b2d7ae3972fd8e0c5` |
| `scripts/passives/source_tree_data.gd` | `9ce28c773f4ca8b8174cca73008cd1c9002237681378d58f5108def2f761bbee` |
| `scripts/passives/source_tree_allocation_rules.gd` | `631792b2ecf06481c6cc43165cd9f97688d578f6cd5cf394905b0c9beb814ef3` |
| `data/passive_source/data.json` | `7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122` |
| `data/passives/official_tree_runtime.json` | `9774a8ec1fe16199e775fe99a20853837ca8c7725c48dfcd9d6ee69646ff934f` |
| `data/passive_source/localization_zh_CN.json` | `2d0bef4e99c4e60d1db79ec95700613dba204422be71473b4627baae8fa0c991` |
