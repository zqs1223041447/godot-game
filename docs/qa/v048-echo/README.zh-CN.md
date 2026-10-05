# v0.48 泉脉双响：pure 调度证据

最终结果：`tests/sunwell_echo_runtime_test.gd` **878 checks, 0 failures**，Godot 4.6.3，headless，退出码 0。最终日志为 `focused-run2.log.txt`，对应源码前后 SHA256 与命令见 `tested-files-focused-run2.json`。本工作没有修改生产代码、没有运行 GUI，也没有 git 提交。

## 覆盖范围

- 真实地图编译、`MapAdmission.create_root`、`MapBossProfiles.sunwell_echo`、`MonsterCatalog.telegraph_policy` 与 `TelegraphedAreaRuntime` 连通；锁定调用方传入的玩家坐标、85 半径
- 两响在绝对时间 0.8/1.6 秒发出，同一 attack_id，pulse_index 0/1；每响原 contact 各分量 ×0.65，合计 ×1.3；同时检查混合 physical/fire/cold 分量与无额外 burn_policy
- 默认真实 Boss 机制攻速、难度词缀攻速、显式 0.5/1/2 倍基础攻速均运行两段完整 0.8 秒预警；仅 1.9 秒基础恢复沿既有攻速消费器缩放
- 第一段 `state_for` elapsed 从 0 到 0.799、index 0；第一响后第二段 elapsed 从 0 到 0.799、index 1；第二响后 recovery elapsed 从 0.8 到 0.8+recovery，结束移除；每个阶段中心固定
- 单步 3.5 秒、含零步的两段、非均匀分步、210 个 1/60 秒步与巨大有限 delta：只移除局部 step_time 后，完整事件 Variant 字节相同；累计帧起点+step_time 与绝对 deadline 的误差小于 1e-9 秒。其余事件字段不删、不舍入
- 100 个活动来源一次至多 200 个事件，按 deadline/source_id 排序；已发出与已结束的攻击不重放，零/负/非有限 delta 不推进活来源
- 错误 source、伪 Boss/root/generation、缺少权威绑定、错误视觉模式、错误或不完整覆盖参数、非有限点/数值、畸形伤害分量、错误完整来源快照均拒绝或取消；失败不消耗 attack_id
- 0.4/0.8/1.2/1.6 秒处死亡、出生保护、死亡已处理、来源移除、cancel、reset；零 delta 也先取消，后响不复活；显式重开使用新 attack_id 和完整第一段预警
- definition、start 返回值、state_for、事件与嵌套 profile/packet/tags 均是独立副本；输入、后续源数据修改、返回事件修改、reset 不污染留存值；不消耗全局 RNG

调用方是否真正传入当前玩家位置、主循环伤害/防御结算、绘制与原生截图由其他定向验收负责，本证据不将它们算作通过。

## v47 冻结 oracle

`capture_legacy.gd` 为完全相同的外部脚本，分别通过 `--main-pack` 读取已发布 v47 PCK、通过 `--path` 读取当前代码。冻结 PCK：

`/workspace/scratch/a51485f153de/v047-final-release/game.pck`

SHA256：`bd2a6506e7818b136f951d71e5bbc4a7f09385da70af198c8ef82aadfa8fbb9c`

只抓取本次受影响的纯调度路径：默认无 visual_pattern、old_garden/garden_slam、broken_ruins/ruins_mark；各包含 with_timing=false/true，共 6 条。每条完整保存来源、start 返回值、7 个 state_for 快照及 6 次 advance 返回的所有事件（零步、半预警、deadline、半恢复、恢复末端、结束后再次推进）。

`legacy-v047.bin` 与 `legacy-v048.bin` **32,420 字节完全相同**，SHA256 均为：

`d7557f47b5e2580daf3a6efd0162411f7d155aef7fe6b540a6babfe9eb4fd3db`

不改 version、不归一字段、不对 key 排序、不筛选状态。旧包日志确认 application=0.47.0、echo present=false；当前日志 echo present=true。定向测试也重新生成当前六条轨迹，并与所保存的 v47 原始整段 bytes 比较。

## 命令与隔离

从工程根目录：

```sh
python3 docs/qa/v048-echo/run_qa.py
```

仅重跑最终定向测试：

```sh
python3 docs/qa/v048-echo/run_qa.py focused
```

所有进程独立设置 XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME，位于 `/tmp/godot-m1-v048-echo/<case>/`。runner 遇 `ERROR:`、`SCRIPT ERROR:` 或 Parse Error 立即终止当前 Godot；保留日志和命令、退出状态。重复执行不会覆盖旧日志或 manifest。

## 已保留的首轮试验

`focused-attempt1.log.txt` 及 `tested-files-legacy-v047-legacy-v048-focused.json` 保留首轮失败并标明 stopped_on_error、exit=-15。错误来自测试将真实 Boss 的恢复期假设为未缩放 1.9 秒：其既有烬火专精在 `data/passive_balance.json` 提供 attack_speed +0.03315，合法恢复期会略短。

修正仅限测试夹具：显式基础攻速验证精确 1.9 秒恢复；另把真实 Boss 原攻速与难度攻速增加到完整双响轨迹中。未放宽阈值、事件预算、时间或字节断言。此后 870 检查先通过；补充死亡/出生保护的 start 拒绝及混合伤害分量断言后最终为 878 检查通过。
