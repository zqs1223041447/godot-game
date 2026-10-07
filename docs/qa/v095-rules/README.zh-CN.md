# v095 普通怪物燃烧 profile 提前分支：纯规则字节等价

基线：`eaf298a8cbd22c8387da28da118a15afdcd2afb5`。本批只检查
`DefenseRules.incoming_burn` 将既有普通怪物零 ratio / 零 bonus 分支移到
`defense_profile` 之前这一处改动。生产实现由主线程提供；本目录没有修改生产代码。

## 结果

仅运行一次新测试 `tests/burn_profile_shortcut_equivalence_test.gd`：

- Godot 4.6.3，**58,671 项检查，0 失败**
- **58,611 次完整 `var_to_bytes` 比较**；包括字典字段/顺序、String 与
  StringName 键、整数/浮点类型、typed arrays 与浮点精确位型
- exit 0，6.048307 秒，无 `SCRIPT ERROR:` / `ERROR:`
- 所有记录输入在测试开始、结束时 SHA-256 一致
- 独立 `/tmp/godot-m1-v095-rules-*` XDG 根；入口同时校验实际 userdata 路径

证据：`results.json`、`stdout.log.txt`、`stderr.log.txt`、`run-start.json`、
`run-record.json`、`input-sha256-before.json`、`input-sha256-after.json`。
本次没有 import、微基准、历史套件、Main/场景运行、导出或存档修改。
6.048307 秒是验证批次耗时，不是规则调用性能结论。

## Oracle 与共享依赖边界

`source/scripts/mechanics/defense_rules.gd.txt` 保存指定 eaf commit 的原始 Git
字节，blob 为 `2e35f225146954938b3b0ed67151ee2138d038ea`。
`frozen/scripts/mechanics/defense_rules.gd` 只删除 `class_name DefenseRules` 行，
其余代码原样保留。`manifest.json` 保存 Git blob ID、原始与变换后 SHA-256。

**只有 DefenseRules 被独立冻结**。oracle 的 DamageResolver preload 明确保留
当前生产路径；完整 literal preload/load 依赖闭包为：

- `scripts/combat/damage_resolver.gd`
- `scripts/combat/hit_penetration_rules.gd`
- `scripts/combat/damage_base_compiler.gd`
- `scripts/items/weapon_local_rules.gd`

Python runner 在开始与结束时，重新从 eaf Git 对象读取源字节、核对 blob、
验证 manifest 和 oracle 转换，并验证所有共享依赖与 eaf 字节完全一致。
GDScript 也在用例批次开始与结束核对 oracle 与四个依赖的 SHA-256。
因此这是冻结 Defense、共享且核实未变依赖的比较；不是冻结整个独立执行闭包。
runner 另验证当前 Defense 的所有函数集合未变，只有 `incoming_burn` 函数文本变化。

## 覆盖与风险审阅

复用既有有效边界、拒绝优先级与 detached return 夹具，修正 oracle 验证到当前基线，
并移除所有旧微基准函数/调用。没有执行旧测试或写入旧证据目录。

- 双 actor 有效标量网格 7,800 例；subnormal、最大有限 double、整数精度边界
- 6,000 个确定性任意有限浮点位样本；1,215 个负零/整数零/浮点零组合
- 护盾与生命共 2,720 个单 ULP 边界，以及耗尽、过量伤害
- 17,745 个两项非法输入组合、455 个单项非法/忽略项与完整错误顺序
- raw → actor → fire → shield → health → ratio → mana → bonus 的拒绝顺序
- 18,000 个玩家/魔力/最大火抗 fallback，96 个忽略/验证 mana 的组合
- 公共 settlement 的畸形 packet、资源与明细校验；其他公开 hit/profile 适配
- 当前 chaos fallback 63 例及火抗/混抗 metadata 的完整字节与字段类型
- 保留 receipt 的 `Array[Dictionary]`、actor/stage 的 StringName 键、字段顺序、
  `-0.0` component 和累加后 `+0.0` damage_total；嵌套返回对象不相互别名

审阅未发现生产行为差异：新分支仍先验 raw；只对已知 monster 且有限数值零
ratio/bonus 跳过通用 profile；火抗 finite 检查、0–75% clamp、乘法和资源错误顺序
保持；玩家、未知 actor、非零或非法可选参数继续走原路径。

## 复现入口

主线程完成项目共享 import 后，使用 `python3 docs/qa/v095-rules/run.py`。
runner 不执行 import，并拒绝覆盖已经存在的 `run-record.json`，以保留本次唯一证据。
如以后确有新改动需要复验，应先另存本次证据，再为新输入保留独立记录。

本结果只证明本次输入和覆盖范围的纯规则等价；不宣称实战帧耗、分配量或整场景等价。
