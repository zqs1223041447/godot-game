# v0.38 密集投射：语义等价微优化

## 来源与范围

- 基线：已发布 `f074c2614540f0842964ced961b3430871adce57`，Godot 4.6.3
- 生产修改仅 `scripts/combat/projectile_runtime.gd`；`spatial_target_index.gd` 字节未变
- 没有新持久字段；未改怪物/投射物数量、命中半径、帧率、地图、渲染、UI、字体、schema、版本或发布入口
- 冻结 oracle 为 `projectile_runtime_f074c26.gd.txt`，SHA256：`fa5a7796fa498fafc2b2fed005d610b08e951af49ca64beef1b47ea707bc9af8`，等于 `git show f074c26:scripts/combat/projectile_runtime.gd`
- 测试加载 oracle 时只移除 `class_name` 注册行，避免与当前类名冲突；同仓库其余依赖保持基线

## 确认热点后修改

初始仪表化 100 目标×180 密集投射中位：advance 35.9775ms，contacts 22.2125ms（约62%），其中 broadphase query 3.2830ms、contact sort 1.2605ms；events 1.9525ms，index rebuild 0.4615ms。contacts 包含 query/sort，不应相加重复计算。这些含探针开销，只用于定位，不作为加速比。

1. 空命中台账无需为每个候选分配格式化字符串再查一个必为空的字典；非空台账仍沿原 `%s:%d` 键规则
2. 每次接触查询复用同一段的 Vector2 差与长度平方；单个候选复用偏移长度平方与半径平方。二次方程运算顺序、浮点类型、t 判定保持
3. 命中事件直接构造最终字典，移除临时 extra Dictionary 与 merge；保留原键插入顺序、序列、字段值与 payload/snapshot 引用语义

缓存只在单次 `_contacts` 的无回调循环内存活。不会把 contact_gate 可变的速度/半径/年龄/阶段/台账/载荷跨查询缓存；命中事件仍在 gate 返回后读取 shot。继续使用原候选列表、候选顺序、contact sort、事件 sort、工作排序与 `is_equal_approx` 非传递回退。不以更小网格改变可变输入下的候选集合。

## 同负载短计时

最终 `equivalence.json`：100 真实 crawler 目标，shipping bolt+pierce 编译配方，30/180 条载体，散布/密集各20次相同初值重放，单次 1/60 秒 advance。构造不计入 advance；前后调用顺序交替；完整事件/原始终止载体/幸存载体/ID 全量比较。两边的候选、工作排序次数与事件数也相等。

| 布局 | 投射物 | 原中位 ms | 新中位 ms | 时间变化 | 候选/全扫等效数 | 事件数 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| spread | 30 | 1.2695 | 1.1590 | -8.70% | 126 / 3000 | 30 |
| spread | 180 | 5.6620 | 5.9815 | +5.64% | 864 / 18000 | 180 |
| dense | 30 | 4.7045 | 3.5780 | -23.95% | 1785 / 3000 | 137 |
| dense | 180 | 33.8000 | 27.0515 | -19.97% | 13770 / 18000 | 874 |

Linux 6.18.44 x86_64，无界面共享云端 CPU；硬件型号不可用。密集180本轮约20%下降，散布180本轮约5.6%上升，前次短跑方向不同，说明轻负载/共享环境计时有波动，不能推断所有场景加速。记录全部样本，没有剔除异常值。候选密集场景仍为13770/18000，事件仍为874，收益不是降低工作语义。该数据不是完整游戏帧、Windows FPS、1440p硬件成绩，也没有承诺60FPS。

## 等价与消费者

新测试 `tests/projectile_dense_equivalence_test.gd` 共3126项：

- 80组同负载完整事件字节（含字典顺序）、shots、已终止原载体、next IDs、sequence；20重放hash稳定
- 2000组固定seed精确线段/圆计算，以及切线、起点/终点、零长度边界
- 非传递近似时间链、反向输入、重复shot ID；接触近似链、同引用重复target、非空/阶段台账
- 母子分裂、返回、自然结束、寿命/范围/墙/命中次序，容量2/3/4/180
- 20组100目标×30随机载体，多帧；可变gate改颜色、减速、速度、半径、年龄、阶段、贯穿、台账、snapshot、目标位置/半径/health/spawn；gate RNG保持
- 两个真实 main 场景运行相同seed16tick `_update_projectiles`；全量 enemy/shot、战斗/伤害/闪避trace、护盾/生命/减速/击退、60次死亡、粒子、文字、视觉cue池、队列、ID与RNG一致
- 实际消费者532 hit、7 evaded、24 spawned、8 split、46 return、46 explosion；总damage 7547.399999999965，60次死亡，末RNG state 6826029804319341626。目标为demo且无奖励权限，本测试不声称验证奖励存盘

其余仅本次相关定向：combat pipeline305、projectile schedule4725、spatial collision5357、terrain projectiles35，共13548检查、0失败。没有全历史验收或600秒模拟。

`equivalence-first.log` 保留早期测试夹具错误：非shipping尺寸被几何拒绝、字段误写 floating_texts，导致两个函数提前中断。它的“0 failures”不代表通过；已修正并增加全测试到达结束哨兵。最终 `equivalence-final.log` 无脚本异常、3126项全通过。初始运行环境缺纹理导入缓存时的诊断不作为证据；正式运行复用本基线已有导入缓存且无资源错误。

## 复现

在完成正常Godot资源导入的此工作树根目录：

```sh
mkdir -p /tmp/godot-m1-v038-projectile-tests /tmp/godot-m1-v038-projectile-cache
XDG_DATA_HOME=/tmp/godot-m1-v038-projectile-tests XDG_CACHE_HOME=/tmp/godot-m1-v038-projectile-cache godot --headless --path . --script tests/projectile_dense_equivalence_test.gd
XDG_DATA_HOME=/tmp/godot-m1-v038-projectile-tests XDG_CACHE_HOME=/tmp/godot-m1-v038-projectile-cache godot --headless --path . --script docs/qa/v038-projectiles/profile_contacts.gd
```

前者写 `equivalence.json`；后者在内存里给固定oracle加探针，写 `profile-reproduction.json`，不会改生产源码。其他四份日志来自同样隔离环境下对应 `tests/*_test.gd`，不是全套门槛。
