# v081 地图装置刷新定向验证

基线：`7475800c1d21688a87a439b59c1ec631845a72da`。本目录记录一次 Linux headless 短验，使用实际 `main.gd`、canonical 存档模型、TownServicePanel、背包回收按钮和确认框。测试没有复制费用规则；地图成本、完成奖励、可开启性及失败理由均读取 `main.map_draft()`。

## 结果

首次且唯一运行：**53 checks / 0 failures，exit 0，6.295 秒**。完整日志没有 `ERROR` 或 `SCRIPT ERROR`，没有重跑。执行前由 root 完成统一 import；本测试没有另做 import、战斗、长测或导出。

- 正式地图Ⅱ档已经合法解锁，余额为3。真实面板准备旧庭Ⅱ档后，模型返回 cost4 和碎片不足；原开启按钮禁用并显示该理由。
- 保持地图装置和真实背包同时打开，通过现有回收按钮及确认框信号回收所选宝石，余额3→4。延迟刷新后，**原按钮实例**启用、原摘要实例移除不足理由，地图选择控件没有重建。
- 在仍可支付的旧草案上，将控件改选为断垣Ⅱ档及一条合法普通词缀、一条合法特殊词缀，暂不准备。第二枚宝石回收使余额4→5，再发送连续世界状态通知：所有选择及控件实例保留，开启按钮仍禁用，不能自动启用旧草案。
- 交易完成立即取 checkpoint，再比较延迟刷新及额外世界通知后的状态。canonical snapshot、draft（含 revision）、世界状态、模型/main 保存次数与尝试次数、磁盘字节、RNG、运行状态及 run revision 全部保持。刷新自身不扣费、不保存、不增加草案 revision。
- 显式准备新的选择才增加 draft revision。一次真实开启按钮信号按权威 cost4 扣款（5→1），生成一个持久化 run receipt。对同一按钮重复发出两次 pressed 信号，余额、存档、run ID、世界和运行状态均不再变化。
- 隐藏面板时，实际模型变化及世界通知触发 **0次** map_draft 调用；可见时排队后立即隐藏，执行阶段仍为 **0次**。真实回收模型/世界通知叠加5次世界通知，只派生 **1次**；未准备选择及纯世界通知场景也各只派生 **1次**。这只是事件调用数检查，不是性能或帧率结论。

## 合法且隔离的前置

测试仅接受 `/tmp/godot-m1-v081-map-refresh/<attempt>/data` 下的新 user data 目录，且拒绝已有正式/测试存档。实际运行目录为 `/tmp/godot-m1-v081-map-refresh/attempt-01/data`。

前置通过 canonical 的 `normal_start_map`、可信 `normal_complete_map`、`normal_claim_rewards` 事务分别建立旧庭和断垣Ⅰ档完成记录，取得8枚真实奖励碎片。没有模拟战斗，也没有伪造旅程字典。随后使用 v044 的合法 catalog 碎片构造器和 `_admit_reward_item` 补11枚，真实商人购买两枚独立 bolt 宝石后留3枚。两个回收对象均为实际购买、背包持有的独立 UID。正常旅程根怪计数最终仍为0。

测试内 `ObservedArena` 只覆写 `map_draft()` 以计数并原样返回 `super.map_draft()`；不改生产模型、权威计算、world 模式或 UI 连接。测试期间关闭 main 自动处理和自动攻击，只测试地图准入，不推进战斗。

## 证据与范围

- `attempts/01/run.log.txt`：未经覆盖的完整 Godot 输出
- `attempts/01/run.json`：命令、exit、耗时、隔离目录及执行前输入 SHA256；输入运行后完全未变
- `attempts/01/result.json`：53项断言和10个状态 checkpoint，包含 snapshot/disk SHA256、余额、draft、revision、保存计数与 run ID
- [map_device_refresh_test.gd](../../../tests/map_device_refresh_test.gd)：实际测试入口位于仓库 `tests/map_device_refresh_test.gd`

被测 panel SHA256：`1abb70807f88b6ea1b3a90edb7792014fbdfcd6481986c900a0cb630a76dcfa6`。

这是实际控件的连接信号验收，**没有实体鼠标操作、截图/排版检查或 Windows 原生性能验收**。没有额外扩大到测试档切换回归；正常/测试模式切换不计入本次53项通过结果。main、canonical 模型、商人和背包回收流程均直接复用当前生产实现。
