# v0.47 Ember 选择、转移与烧伤存储定向证据

2026-10-05 UTC，在当前 `v047-ember-proliferation` 工作树仅运行一次
`res://tests/ember_transfer_rules_test.gd`，Godot 4.6.3 官方标准版。

结果：**1655 checks，0 failures，9 个 case 全部完成，退出码 0，ERROR / SCRIPT ERROR 0**。
`EMBER_TRANSFER_RULES_MAIN BEGIN` 和 `END` 各出现一次；这里的 main marker 表示测试脚本的主测试函数进入/结束，不表示运行了游戏主场景。

## 已覆盖

- 固定 120 中心距离，边界包含、斜角与范围外排除；源怪、死亡怪、出生中的怪不参与选择
- 最近优先，同距离按 ID；最多 8 个；24 种旋转/逆序输入输出一致；同中心的独立怪可选
- 实际 Callable 以线段/墙体交点计算 LOS；墙后近目标过滤后，较远可见目标填满上限；验证回调的来源/目标中心及调用数量
- 非法选择输入、重复 ID 和列表后部非法条目均原子失败，返回空 ID，输入字节不变
- generation 0 复制相同 raw DPS，剩余时长为原绝对 expiry 减转移时刻；仅 generation 变成 1，归属保留；generation 1、已到截止、普通 Ignite 不传播
- transfer 和 BurnRuntime 都拒绝缺少配对字段、bool/float/负数 generation、非有限或非正 expiry 等非法 lineage；非法存储申请不结算旧状态也不写入新状态
- 两个合法 generation 可存储，expiry 必须与申请时刻和持续时间相符；已接受的微小浮点偏差仍以声明的绝对截止为准
- 300 段连续推进严格停在同一绝对截止，每段 provenance 一致，累计伤害与单次推进相同，到点清理且不多支付一帧
- 强、弱、等 DPS 覆盖沿用实际获胜状态的来源、generation 与 expiry；更强普通 Ignite 胜出后不遗留 Ember 字段
- 旧无 Ember 状态和结算段完整 dictionary shape 与数值不添字段；调用方修改返回状态、列表、结算段或转移输出不影响存储/输入；全程不改变全局 RNG

## 运行与证据

```sh
XDG_DATA_HOME=/tmp/godot-m1-v047-pure/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v047-pure/config \
XDG_CACHE_HOME=/tmp/godot-m1-v047-pure/cache \
GODOT_SILENCE_ROOT_WARNING=1 \
godot --headless --path . --script res://tests/ember_transfer_rules_test.gd
```

- 原始完整输出：`ember-transfer-rules-test.log.txt`
- 退出码、错误扫描、main marker、case 计数、运行前后 SHA-256：`ember-transfer-rules-tested-files.json`
- 本测试及三个直接 pure 依赖在运行前后字节与 SHA-256 完全一致
- 静态发现的 transfer 配对/正 expiry 验证缺口已由父任务在本次运行前修正；没有运行过旧错误版本，没有丢弃失败日志
- 本子任务只新增测试、UID 和本目录证据；未改生产、未新建工作树、未提交 Git、未执行备份

此证据仅对应 pure 规则与存储，不替代游戏主场景集成、真实地形 LOS、画面、输入、发布或 Windows 实机验收；未重跑历史全量 burn 测试。
