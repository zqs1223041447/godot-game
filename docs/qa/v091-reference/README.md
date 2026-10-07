# 普通珠宝工艺最小资料片段

仅游戏数据。复用 `../v091-root-ui/main-after-reforge.json`：真实Main库存UI的15项通过运行在 `/tmp/v091-root-ui-passed` 生成的隔离测试存档。测试人为放入普通魔法烬心珠宝与64碎片，确认重铸后保存为56碎片；回收取消仍保留珠宝。它不是用户正式档，也不是自然掉落概率样本。

## 交付与范围

- `jewel-crafting-fragment.json` 仅含一个顶层键 `jewel_crafting`，从独立 `tools/jewel_crafting_reference.gd` 读取现有真实规则、价格、数量与120秒期限。
- 导出器只读实际Main存档，decode并完整验证当前schema50，复算原source+revision+规则版本的种子并比对实际已保存结果；验证余额64→56、UID/底材保持，输入文件SHA256不变，零save_attempts。不创建Main实例、不花钱、不重新掉落或整库导出。
- `tools/build_reference.py` 增量函数 `merge_jewel_crafting_fragment` 仅合入这一个键。渲染新增一个规则卡、三种普通珠宝卡链接，以及现有校准碎片卡说明。特殊珠宝卡保持原字节。
- 在本树只做内存合并/HTML渲染到 `/tmp/v091-jewel-reference-preview.html`，未修改或提交旧基线 `docs/reference/catalog.json` / `index.html`。最终主线应先合新地图片段，再合此珠宝片段，单次生成最终HTML。

`verification.json`：86个原顶层字段语义保持，3797个无关卡片原字节保持；恰好改3珠宝+1碎片卡，新增1规则卡。四项价格、双稀有词缀数量、双向锚点、特殊排除、风险与真实测试夹具hash检查通过。只验证静态数据与HTML，不声称浏览器实际交互或截图验收。

## 验收命令

已导出片段可以直接复核，不需要重跑Main：

```sh
python3 tools/verify_jewel_crafting_reference.py
```

仅当珠宝规则或受验Main夹具变化时重新小片段导出：

```sh
XDG_DATA_HOME=/tmp/godot-m1-v091-reference-review/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v091-reference-review/config \
XDG_CACHE_HOME=/tmp/godot-m1-v091-reference-review/cache \
/usr/local/bin/godot --headless --path . \
  --script res://docs/qa/v091-reference/export-fragment.gd
```

最终合并后的当前catalog插入方式（由整合者执行，不使用本树旧整页覆盖地图）：

```sh
python3 - <<'PY'
import json
from pathlib import Path
from tools.build_reference import merge_jewel_crafting_fragment
path=Path('docs/reference/catalog.json')
current=json.loads(path.read_text())
fragment=json.loads(Path('docs/qa/v091-reference/jewel-crafting-fragment.json').read_text())
merged=merge_jewel_crafting_fragment(current,fragment)
assert {k:v for k,v in merged.items() if k!='jewel_crafting'}=={k:v for k,v in current.items() if k!='jewel_crafting'}
path.write_text(json.dumps(merged,ensure_ascii=False,indent='\t',sort_keys=True)+'\n')
PY
python3 tools/build_reference.py
python3 tools/build_reference.py --check
python3 tools/verify_jewel_crafting_reference.py
```

## 保留的边界发现

首尝试preload历史 `tools/export_reference.gd` 时，它现有的5处 `Arena.ARENA` 在当前大地图基线上已经不存在，导致解析失败；见 `legacy-exporter-failure.log`。本批没有扩大范围修旧整库导出器，而是使用独立纯珠宝快照模块，不加载那个旧工具。原全量入口只增加一行调用独立快照，以保留未来全量导出接点；本批所有导出/验证使用上述受限入口，成功记录在 `export.log`。
