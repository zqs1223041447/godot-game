# 龙卷试装失败提示：装备中文名称

日期：2026-10-15。基线：`e9a0c95`。当前 dot 环境，Godot 4.6.3 Linux 无头验收。

## 改动边界

仅修改 `scripts/main.gd` 中 `equip_tornado_example()` 的装备失败提示分支：从 `state.item_definition(id)` 读取现有权威名称；名称不存在、空白或非字符串时使用通用提示“所需装备”。不新增或猜测装备名，不变更事务、成功提示、布局或存档格式。

现有目录名称：

- `prism_bow` → 棱光长弓
- `return_mantle` → 归航披风
- `detonation_charm` → 终焰护符

失败文案保留“龙卷组合未完成”“已完成的设置已保留”和重试指引，不宣称所有效果或按键已经可用。

## 实际验收

新增 `tests/tornado_failure_labels_test.gd`。每例通过真实主场景 `_unhandled_key_input()` 的 F6 事件打开战斗面板，再触发可见试装按钮的已连接 `pressed` 信号；不是直接调用通知函数。故障注入位于实际保存边界。

12 个隔离场景全部通过，每例 21 项，共 252 项，退出码均为 0；日志中无脚本错误或引擎错误：

- 3 个装备阶段分别写入失败，显示该装备的现有中文名称，不显示任何内部装备 ID
- 同样 3 个阶段分别覆盖缺失定义、空白名称、null 名称，安全回退为“所需装备”
- 检查停止在所选失败写入边界；先前成功装备保留，失败及后续装备未装配
- 失败前最后一次有效存档的字节完全不变，内存快照完全不变，重新读盘等于当前部分构筑
- 解除故障后重试成功，所有装备到位，成功提示及持久化一致

补充已有 `tornado_example_failure_test.gd` 的 `TORNADO_FAIL=3 TORNADO_UNBOUND=1` 场景：17 项通过，退出码 0。覆盖缺失键位修复后发生装备写入失败、重试完成及重复完成操作不写盘。

本地日志：`/tmp/godot-trial-label-matrix-ngyuXu/<mode>-<stage>/run.log`；补充回归：`/tmp/godot-trial-labels-existing-AjDlia/run.log`。首个开发冒烟与矩阵重叠，不重复计数。

## 复现

每次运行均需全新的 `/tmp` XDG 隔离目录，单例最多 90 秒；不需要重新导入资源。依次枚举 `mode=catalog missing blank null` 与 `stage=0 1 2`：

```sh
run=$(mktemp -d /tmp/godot-trial-labels-XXXXXX)
XDG_DATA_HOME="$run/data" XDG_CONFIG_HOME="$run/config" XDG_CACHE_HOME="$run/cache" \
TORNADO_LABEL_STAGE=0 TORNADO_LABEL_MODE=catalog \
timeout 90 godot --headless --path . --script res://tests/tornado_failure_labels_test.gd
```

成功摘要：`TORNADO_LABEL_RESULT stage=0 mode=catalog checks=21 failures=0`。非零失败摘要、脚本错误或非零进程退出均不得计为通过。

本次是失败提示与保存安全的定向验收，不代表全量回归、像素布局检查、Windows 实机或性能测试。提交、推送、PR 和合并由集成发布流程单独核验。
