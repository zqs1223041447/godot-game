# 普通珠宝工艺集中验证

基线 `8944b8f1d3ae5a4552393affc8de21b03de20d03`；实现首批 `03b34293ffc11a1b4092530b4a99d91753b64481` 已独立推送。Godot 4.6.3；全部 user:// 写入使用 `/tmp/godot-m1-v091-*` 隔离，未导出程序、跑长压力测试或改schema。

## 已完成

- 首次 `--headless --editor --import` 完成，无SCRIPT ERROR/ERROR；见 `import.log`。
- `tests/jewel_crafting_test.gd` 修复后 1375项 / 0失败，见 `model.log`。一次集中运行覆盖纯规则与真实CanonicalGameState事务，不依赖UI模拟替代模型。
- UI由实际Main实例与库存面板另验；见 `../v091-root-ui/`。所选payload、报价、取消、真实重铸扣8、保底材、重复确认、成功后即时回收可用、珠宝用词共15项通过。原首轮失败和窄诊断保留。

规则覆盖三底材、两稀有度，共192个固定seed重铸；原词池、min/max/step、唯一族、魔法1前1后、稀有1–2前2后及输入不变。金样验证普通自然生成的实例和完整RNG状态不变；真实装备校准/重铸/定向伤害重铸仍对应原种子文本结果。

事务覆盖真实分散币栈扣费、无预掷结果泄露、对外报价副本篡改不影响权威报价、失败候选/写盘回滚、重试、重复提交、取消/过期/8句柄淘汰、换物/读取/全局修订/换档/磁盘重编码、待安置、特殊、真实天赋孔、两页满背包释放原格落币、币量上限与新增币栈序号耗尽。特殊珠宝仍能支持真实断连节点26740，普通背包珠宝制作不改变其支持、实算属性、天赋或孔位；原移除依赖保护仍拒绝。

## 发现并修复

首轮模型记录 `first-failure.log` 为1341项 / 42失败，不能作为通过证据。主要真实问题是GDScript点号插入新的item_id/revision字典键生成StringName，严格报价边界拒绝合法珠宝执行；改为显式String键插入，未放松校验。另修两处测试夹具：recovery使用真实index字段；混合装备size经统一metadata读取Array，避免错误Vector2i断言。

实际UI另发现changed同步发生于事务busy域，轻量工艺状态可被缓存为忙碌；UI在selected jewel的模型changed后deferred重新刷新工艺状态，模型报价与执行busy保护保留。最终日志记录真实成功扣费与后续回收按钮恢复。

## 复现

```sh
XDG_DATA_HOME=/tmp/godot-m1-v091-check/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v091-check/config \
XDG_CACHE_HOME=/tmp/godot-m1-v091-check/cache \
/usr/local/bin/godot --headless --path . --script res://tests/jewel_crafting_test.gd
```

聚焦通过不代表全历史测试或Windows实机验证；不需要为本批重跑无关性能、完整图鉴导出或历史长测。
