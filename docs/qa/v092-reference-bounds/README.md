# 历史资料导出器的边界引用修复

基线：613183c258e6d08906b7d7546d9dfd30de21421f。

`Main.ARENA` 在探索地图接入后已是实例属性。导出器的五处旧静态引用因此不再合法。五处均属于历史小据点/测试城镇示例，仍使用 `MapCampLayout.layout` 或 `MapGeometry.configure`；不能把它们机械替换成大探索地图坐标。

本次仅把五处边界改取 `WorldView.WORLD_ARENA` 的具名历史别名。其精确表达式仍是 `Rect2(Vector2(42,104),Vector2(1196,462)/0.65)`，没有把高度舍入为711。当前探索图仍由 `WorldView.exploration_arena` 和 `MapGeometry.configure_exploration` 取得3600×2400边界、六驻点和独立入口。

一次定向调用检查42项全部通过，退出码0，无脚本错误。实际加载完整导出器并调用 `town_map_examples`，核四地图历史墙数0/2/4/3、历史出生点和已有三图据点序列；另以当前权威接口核四图大世界几何与已保存F8快照逐项相等。静态检查确认五处全部替换且补丁无其他改动。

使用已验证同源资源的导入缓存，未重复导入素材。未执行 `collect` 或全量导出，不把本次调用检查表述为整个历史导出集合已通过。游戏源码、数据、素材、版本、存档结构以及F8成品均未改变；精确哈希与路径保持证明见 `preservation.json`。运行输出及真实退出码/耗时见 `calls.log`、`calls-result.json`。
