# 正式首领寻枝晶玉保全

基线：`a0a8734b95f1f0f2c4d2af307db8590555067651`。本次只修正式地图已登记首领根怪的原寻枝奖励：有空位入包，已有待安置不阻止寻找空位，满包则追加同一实例到既有recovery。原一次性死亡账本仍决定是否发奖；没有新投放、额外奖励次数、货币、商品或工艺。

## 原模型即可表达

schema仍为58。现有 `ItemLocationRules` 的recovery接受合法珠宝，要求独立非负index且小于物品总数；`CanonicalBuildMigration.paged_location_context()` 已开启recovery。新的限定入口 `award_normal_boss_special_jewel(run_id)` 核验已打开正式存档及active run，沿用既有 `_admit_reward_item_candidate(wrapped, true)`。追加index为加入新物品后的 `items.size()-1`，不会覆盖旧队列。

`award_special_jewel()`、普通珠宝/装备奖励API、首领装备API与生成器、通用候选事务均逐字保留；没有给通用奖励API增加参数或放开旧条件。新入口仍遵守原物品总量、UID序号和revision上限。Main只对正式地图、当前登记boss身份、generation=0且已通过原死亡奖励门槛的目标调用它；其他首领使用旧入口。

成功奖励沿用Main批量保存。保存失败时旧磁盘字节保持，包含XP、击杀进度和两份奖励的完整新内存保持dirty，重试写入同一候选，不重新生成物品。这不是整次死亡内存回滚。待安置取回沿用库存UI `first_bag_position → move_item → _commit`，该移动写失败时内存、位置和磁盘都不变。

## 有限验证

Godot `4.6.3.stable.official.7d41c59c4`，Linux headless。每进程独立 `/tmp/godot-boss-jewel-…` XDG，外层上限45秒。

- 新定向Main/HUD套件：**916 checks，0 failures，21.327秒**。复用原首领装备测试的FaultModel、容量填充、死亡、重复死亡和重载助手；未执行该父套件的历史运行或schema55断言。
- 既有 `source_tree_allocation_rules_test.gd`：**80 checks，0 failures，1.120秒**。保留原小型/显著节点、半径边界、普通连通孔、精通/基石等拒绝规则及真实源图检查。
- 两个进程退出码0，最终日志均无SCRIPT ERROR/ERROR。

实际Main创建并进入原免费Old Garden I；当前入场已有24普通根怪与一名登记首领。使用现有伤害入口的确定大伤害完成死亡，不把它表述为自然游玩或原生键盘验收。满包、原recovery和耗尽上限采用明确合法防御夹具，不改生产掉落或成长预算。

| 场景 | 结果 |
| --- | --- |
| 正式首领、正常背包 | 原装备与寻枝各消耗一个连续UID；装备首次掷值/RNG保持，寻枝不抽随机数 |
| 满包，无/有原recovery | 两份首领奖励均追加保留，原条目和原物品位置不被覆盖 |
| 有原recovery但背包有空间 | 两份新奖励仍优先入包，原待安置保持 |
| 真实待安置按钮 | 满包拒绝；通过原丢弃事务只腾出1个容量夹具格，取回原1×1珠宝，同UID/全部payload保持 |
| 移动写失败 | 待安置按钮不能半移动或消耗序号；重试同按钮取回原实例 |
| 死亡批保存失败 | 旧磁盘可重载为完整旧状态；新内存保留两份奖励，失败重试不变，成功重试保存同一候选 |
| 重复死亡 | 同一尸体重复调用及去掉标记的同身份副本均不能多发、重复保存或消耗RNG |
| 重载 | 精确native加载保留全部物品；实际Main重开按原规则放弃未完地图，保留两份奖励和原待安置，不发完成奖励/解锁 |
| 真实T面板 | 取回的寻枝沿原UI装入6230；贵族58833→2151→37690→48423→6230支付4点；断连26740再付1点产生原生命回复；依赖存在时取回珠宝被原子拒绝 |
| 类型与隔离 | 实际覆盖仅small/notable；基石/起点/孔不获远程资格，原纯规则套件还核精通；普通怪无特殊奖励，测试首领满包及普通掉落维持原拒绝，demo无奖励 |
| 原上限 | 错run、无active run、序号/revision耗尽、物品总量上限都拒绝且不消耗身份 |

初轮夹具错误地沿用旧据点延迟生成流程，提前击杀了已在场首领，导致6个场景准备失败及1个覆盖断言失败。保留 `attempt01*`；修正夹具为直接使用当前入场已登记的首领后，两项有限套件通过。生产修复没有为迁就旧夹具修改地图或奖励规则。

## 文案与静态保全

运行时说明改为“小型与显著天赋”，明确排除基石、精通、起点或珠宝孔；原280半径、每点费用、普通连通支撑孔与依赖移除限制保持。

F8目录只更新 `jewels.branchfinder.description`，从通过的真实运行时描述写回；生成器仅给该珠宝卡补正式获取/待安置说明。**只改 `jewels-branchfinder`，其他3815张卡逐字节相同**，4条相关本地链接有效。保存规则/迁移、物品位置规则、库存与天赋UI、源图/词条/可分配政策、普通购买/工艺、死亡账本以及相关旧测试源码均与基线逐字节相同。详见 [scope-reference.json](scope-reference.json)。

证据：[Main逐项结果与实例](formal_boss_jewel_recovery_test.json)、[Main日志](formal_boss_jewel_recovery_test.log.txt)、[Main命令/输入SHA256](formal_boss_jewel_recovery_test-run.json)、[原分配规则日志](source_tree_allocation_rules_test.log.txt)、[规则命令/输入SHA256](source_tree_allocation_rules_test-run.json)。复现限定检查：

```sh
python tools/validate_formal_boss_jewel_recovery.py
python tools/verify_formal_boss_jewel_reference.py
python tools/build_reference.py --check
```

没有全套测试、长时战斗、Windows导出、封包或模型工作。
