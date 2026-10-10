# 混沌庇护：有限实现与验证

基线main：`f5abdf8bed36c02a14ef778edf8dd81ce52345e0`。分支：`codex/chaos-aegis-map-modifier`。

## 实现和预算

新增一个显式地图特殊词缀 `chaos_aegis` / 混沌庇护：原始混沌抗性+20个百分点，最低波次4，占原特殊槽。数值对齐现有元素庇护每类+20及波次4，仅覆盖混沌一种伤害；沿用有效0%–75%、地图费用与特殊完成奖+2。不是来源游戏机制或完整平衡结论。

生产仅改三个文件：`map_catalog.gd`追加目录项；`map_defense_rules.gd`允许该明确ID、验证原始/有效混沌一致性并使用共享防御公式；`town_service_panel.gd`为原地图复选项补充深色选中/悬浮文字，修正实际截图暴露的对比度问题。没有复制商店/地图/战斗实现。原根怪、首领及子怪准入和原来源标记负责只施加一次；玩家、未选地图、三元素语义、伤害系统、掉落/RNG和schema59均保持。

## 最终验证

- `rules-02`：**84项、0失败，exit0**。所有现有怪物模板的纯应用、仅混沌变化、五类型真实DamageResolver、负数/超上限原始值、0%–75%独立上限、伪造值拒绝、不重复施加、普通地图不变、原三元素保留混沌、波次与特殊槽、原后代队列/谱系/无奖励、失败时身份回滚。
- `main-03`：**105项、0失败，exit0，无脚本错误**。实际X11鼠标选择复选项、准备、开启；正式旧庭II档原事务恰好扣4并保存一次。初入、原API重开、返城再入均检查24根怪和1首领各加20一次；后续普通地图不残留，玩家统计保持。当前未选词缀的schema59存档载入字节不变，新活动地图沿原字段可载入。非致死混合命中：各100点中仅混沌为80，先耗盾50再耗血430，不写存档。
- 既有 `map_defense_rules_test.gd`：**543项、0失败，exit0**。
- 既有 `map_aegis_admission_test.gd`：**56项、0失败，exit0**。用于保全原三元素语义及根怪/整批后代的事务回滚，不运行已脱离当前Main接口的历史大场景。
- 同源有界数据库导出、幂等增量合并、HTML确定性重建、`check-reference.py`均通过。只新增一张词缀卡，五张地图卡补充相应II/III档入口；目录其余值和其他卡片保持。新增运行时中文无缺字。没有重新导出历史构筑、地图几何、模型、美术或源树。

正式流程采用明确40物理碎片及可信的I档完成夹具；不是自然赚钱或完整清图。混合命中通过真实Main结算入口投送受控数据包，不声称自动AI/技能投射全过程或跨平台帧率。死亡后代的新词缀检查在原MapAdmission.drain层完成。原费用/奖励规则未改；本批未重跑完整奖励全流程。

## 保留的迭代证据

- `rules-01`：84项/6失败。测试误用字典浮点精确比较（55与55.000…）及将已有三元素安全上限写成85%，实际为83%。修正测试预期后规则通过；未为迎合测试修改现有上限。
- `main-01`：headless调试；一项鼠标选择检查失败，随后测试误取`map_draft().profile`触发脚本错误，30秒外部超时退出124。实际接口为`map_draft().special_ids`。
- `main-02`：渲染报告虽记录99项/0失败，但有3条脚本错误，**不算通过**。测试构造基底首领时传入普通上下文及不适用的机制重建参数，得到空字典。改为按原模板及首领上下文获取原始防御，并增加空值失败保护，最终105/0。保留本轮截图在`attempt-02/`，最终选择截图展示修正后的深色文字。
- `reference-check-01`：首轮静态检查把构建器的分类标签当作页面状态文案，断言失败；实际统一状态显示为“已实现”。改为核对真实状态标签及原奖励文案后通过，未修改页面以迎合测试。

最终渲染日志只有虚拟显示器不支持VSync的警告。Godot4.6.3，1280×720，Xorg dummy、Mesa llvmpipe；已实际查看[选择入口截图](selection.png)。没有全套/长检测、Windows导出、封包或模型工作。

## 资料和复现

- [中文玩法规则](../../CHAOS_AEGIS.zh-CN.md)
- [内容数据库入口](../../reference/index.html#map_specials-chaos_aegis)
- `verification.json`记录最终输入/结果/截图指纹。

```bash
timeout 30s env XDG_DATA_HOME=/tmp/godot-chaos-aegis-review-rules XDG_CACHE_HOME=/tmp/godot-chaos-aegis-review-rules-cache CHAOS_AEGIS_REPORT=/tmp/chaos-aegis-rules.json godot --headless --path . --script res://tests/chaos_aegis_rules_test.gd
timeout 45s env DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 XDG_DATA_HOME=/tmp/godot-chaos-aegis-main-review XDG_CACHE_HOME=/tmp/godot-chaos-aegis-main-review-cache CHAOS_AEGIS_REPORT=/tmp/chaos-aegis-main.json CHAOS_AEGIS_CAPTURE_DIR=/tmp godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/chaos_aegis_main_test.gd
python3 tools/merge_chaos_aegis_reference.py --check
python3 tools/build_reference.py --check
python3 docs/qa/chaos-aegis/check-reference.py
```

真实渲染需可用DISPLAY与新的隔离目录。数据库检查需本仓库基线提交和现有fontTools；不连接外部服务、不读取用户存档。
