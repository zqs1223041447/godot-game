# v0.41 普通地图阶级：纯规则验收

本批为普通旅程增加两图各三阶的编译入口。测试模式仍调用旧 `MapCompiler.compile()`，固定旧庭波次4、断垣波次5；正常旅程调用 `compile_normal()`，使用真实阶级波次，并在规范地图配置中写入费用及完成奖励。没有存档、钱包、运行态或随机数操作。

## 固定预算与接口

| 地图 | I / II / III 波次 | 普通根怪目标 | I / II / III 费用 | I / II / III 基础完成奖励 |
| --- | --- | --- | --- | --- |
| 旧庭 | 1 / 4 / 8 | 24 | 0 / 4 / 8 | 4 / 8 / 12 |
| 断垣 | 2 / 5 / 9 | 36 | 0 / 4 / 8 | 4 / 8 / 12 |

完成奖励为基础值，加每个普通词缀1、每个特殊词缀2；最多两个普通、一个特殊，所以额外奖励最高4。特殊词缀门槛读取真实阶级波次：元素庇护、霜纹巡逻至少4，雷纹巡逻至少5。两图I阶初始开放，各图自己的最高完成阶级只解锁自身下一阶。

`NormalMapCatalog.definition(map_id, tier)` 返回独立字典，包含 `map_id/tier/label/wave/ordinary_target/cost/base_reward`；无效地图或非整数1–3阶返回空字典。`tiers(map_id, best_completed)` 返回三行上述字段及布尔 `unlocked`、字符串 `reason`，用于同源界面展示。

`MapCompiler.compile_normal(map_id, tier, normal_ids, special_ids)` 与旧编译器返回形状一致。配置保留原地图ID、描述、普通根怪目标和首领字段，名称带I/II/III，波次取阶级值；新增 `normal_map: true`、`journey_tier`、`fee`、`base_completion_reward`、`completion_reward`。地形仍按原ID取值。

`profile_reason()` 从ID、阶级、词缀重新编译并逐层核对类型和值。假标志、缺失/多余字段、错误阶级、整数字段替换为浮点数、嵌套伪造均拒绝。合法字典改变键插入顺序仍可验证。`special_template()` 沿用规范配置门禁，因此支持合法普通地图，且不替换原灰烬名额。

## 实际检查

Godot 4.6.3 headless运行 `tests/normal_map_tiers_test.gd`：7,251项断言，0失败。

- 穷举两图三阶×22个合法普通词缀选择×4个特殊选择。实际合法数为374，分别22/66/88与22/88/88；非法门槛不生成配置。
- 逐个合法选择检查地图继承字段、规范模式标志、真实波次、费用、奖励、普通词缀顺序独立和特殊模板映射。
- 明确拒绝布尔、浮点、StringName、非法阶级、未知ID、重复ID、超限词缀、非数组选择。所有正常及拒绝路径共同覆盖全局随机序列不变。
- 校验0/1/2/3最高完成阶级的每行解锁状态与原因，两图互不影响。
- 修改返回目录行、选择输入、深拷贝配置及旧编译结果，验证目录/后续编译/原始配置独立。
- 对全部规范字段的删除和关键字段篡改进行拒绝验证，嵌套类型或额外字段也不能通过来源校验。

## 未改动v40的字节对照

先在 `/workspace/scratch/a51485f153de/v040-dual-resource-leech` 运行 `map-tiers-legacy-capture.gd`，读取当时未改动的旧编译器；没有编辑该基线。捕获两图×22个普通选择×4个特殊选择的176个完整返回结果，其中154个合法。

原始Godot Variant字节共646,316字节，保存为 `map-tiers-v040-profiles.bin`，SHA-256：

`9e0d797df09283b58a1c24cdff3a7cfb6c94f78986b859a8ecab355c7307f721`

最终定向测试逐项比较 `var_to_bytes(actual_result)`，也重新拼接整批176条并与原文件逐字节比较，全部一致。旧固定4/5波次、返回形状、说明、词缀语义及无普通旅程奖励字段均保持。

首个基线启动因默认用户目录不可写而在输出前终止；设置本任务专用 `XDG_DATA_HOME` 和 `XDG_CACHE_HOME` 后成功捕获。最终定向测试同样使用该隔离目录；不读取或修改用户存档。

验证命令：

```sh
XDG_DATA_HOME=/tmp/v041-map-tiers-data XDG_CACHE_HOME=/tmp/v041-map-tiers-cache godot --headless --path /workspace/scratch/a51485f153de/v041-normal-map-loop --script res://tests/normal_map_tiers_test.gd
```

只运行本批纯规则和旧编译字节比较，没有项目全量导入、历史全量套件或600秒模拟。本证据不代表保存事务、主场景入场、结算和界面已经通过；这些由各自定向验收证明。
