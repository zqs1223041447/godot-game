# 行囊分页选择一致性修复

## 问题与最小修复

在正式 `scenes/main.tscn` 中打开行囊，点击第一页的初始珠宝，再点击下一页。原网格清除了不再可见的选择，但面板仍保留该 UID，因此没有选中物品的第二页仍可点击“丢弃”或工艺按钮，并操作上一页物品。

`CanonicalInventoryPanel.refresh()` 现在用当前页面条目核对选择；目标不再可见时，取消待确认的丢弃/工艺、撤销工艺报价并清空面板选择。原有网格刷新随后清空高亮，操作栏按空选择刷新。仍在当前页的有效选择保持不变。未修改模型、存档格式、物品生成或交易规则。

## 有限验证

- 基线：12 项检查中 4 项失败，确认前翻和后翻均遗留面板选择/可用丢弃按钮
- 修复后：34 项检查全部通过
- 覆盖正式 Main、初始真实珠宝、前翻/后翻、普通刷新、同页移动、跨页移动、待确认丢弃和回收中断、迟到确认无效、报价句柄撤销
- 只读 UI 操作核对模型快照、存档字节、保存计数和 RNG 不变；跨页移动只提交一次
- 使用直接网格输入与已有按钮信号检验控制器连接；这是 headless 回归，不宣称原生窗口鼠标/Windows 实机验收
- 基线日志含未设置可写字体缓存目录的 Fontconfig 警告；修复后使用独立 XDG 数据/配置/缓存目录，没有该警告

运行新回归：

```sh
isolation=$(mktemp -d /tmp/godot-inventory-page-selection-XXXX)
mkdir -p "$isolation"/{data,config,cache}
XDG_DATA_HOME="$isolation/data" XDG_CONFIG_HOME="$isolation/config" \
  XDG_CACHE_HOME="$isolation/cache" timeout 45 godot --headless --path . \
  --script res://tests/inventory_page_selection_test.gd
```

基线和修复后原始输出见 `baseline.txt`、`after.txt`。未运行全量套件；本批作为 dot 本地提交保存，尚未推送。

## 相邻旧门槛的独立限制

`canonical_menu_retention_test.gd` 额外执行了一次，未通过。它在新 Main 的城镇状态尝试 `cast_group`，第 130–142 行的四项施放/HUD 断言失败，随后第 163 行访问空控件的 `pressed`，脚本停止推进，外层 60 秒上限终止进程。

另建临时工程，复用同一资产和测试，将唯一生产改动文件替换为 `HEAD` 原文；只做一次 20 秒有界基线。出现完全相同的四项断言失败及空控件错误，退出码 124。对照见 `menu-retention-baseline.txt` / `menu-retention-after.txt`。这项旧门槛不计入通过结果，本次未扩大范围修复旧夹具。新回归的 34 项通过结果独立保留。
