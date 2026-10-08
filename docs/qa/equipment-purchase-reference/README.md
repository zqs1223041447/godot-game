# 正式装备商人 F8 图鉴同步

基线为已发布的 `ba2f8c0a1e7528a7a1f8847540665384b7ac41dc`。本次只同步现有服务卡片及其导出数据，没有改动游戏运行源码或重新执行购买事务。

装备商人卡片说明正式购买普通无词缀底材：每件 8 校准碎片、物品等级 1。表格覆盖当前目录的 15 种底材，链接到原有装备卡片；保留免费测试供应说明，区分固定机制装备、药剂、珠宝和测试货币。其他四张服务卡片仅同步正式城镇开放条件中的装备商人。

`tools/equipment_purchase_reference.gd` 从现有购买服务常量和底材目录读取元数据，不实例化 Main、不访问用户存档、不执行购买或 RNG。导出保留源文件 SHA 和 schema 55，结果为 [fragment.json](fragment.json)。全量导出器调用同一个收集函数，避免后续正常重建丢失这项数据。

`tools/merge_equipment_purchase_reference.py` 只写入 `town_maps.equipment_purchase`，不重序列化其他历史数据。原执行覆盖报告和美术资产保持原样。

本次检查：

- 隔离 Linux XDG 目录中的 Godot headless 元数据导出成功，40 秒限时；[原始日志](export.log.txt)。
- `python3 tests/equipment_purchase_reference_test.py` 通过。旧数据使用更新后的生成器得到与基线逐字节相同的 HTML；原目录各既有字段值保留原始字节。
- 3816 张卡片 ID 完全一致，只有装备商人、宝石商人、工匠、珠宝商人、天赋重置五张服务卡片发生变化，3811 张卡片逐字节不变。商人 43 个内部链接均有效；15 种底材的价格、等级、无词缀条件与导出一致。[完整记录](preservation.json)。
- `python3 tools/build_reference.py --check` 和 `git diff --check` 通过。

边界：本次验证的是静态图鉴同步。没有再次打开 F8 浏览器、重复原生截图、重新跑事务或主场景、修改旧宝石测试中的目录计数、运行长期检测、封包或导出 Windows。运行功能的历史证据见 [装备购买验证](../equipment-purchase/README.md)。
