# v119 遗迹庭园图鉴增量

入口：[`index.html#maps-ruins_garden`](../../reference/index.html#maps-ruins_garden)。地图装置列出五张地图；支持中文名称、`ruins_garden`、原生地形与准备地图搜索。

## 范围

只新增 `catalog.exploration_maps.maps.ruins_garden`，并扩展相应卡片、地图装置和探索规则说明。原四图卡片逐字节保持，原四图历史证据不作为新原生地图的验证。玩法、Main、存档 schema、源执行政策、装备、美术和旧 QA 均未修改。

导出器直接调用 `MapCatalog`、`MapCompiler.compile_normal`、`MapBossProfiles`、`WorldView.exploration_arena`、`ExplorationMapLayout`、`ModularStudySession.layout`、`ModularStudyGeometry.snapshot`、`ModularStudyRoutes.prepare`、`PreparedMapEntry` 和 `ExplorationMapPlan.plan`。原生轮廓来自已有 v111 assembly/collisions/manifest JSON；没有重建轮廓或手造坐标。

只安装一个隔离原生物理空间、等待两帧同步，准备两个绕行，导出一个 I 档空词缀、种子119001的脱离角色 Plan。正式三档费用/奖励和特殊词缀资格取实际编译器。Plan 未修改传入 MonsterRuntime，随后释放隔离空间。没有加载 Main、读写玩家存档、收费、生成角色、运行战斗、全量历史构筑导出、600秒长跑或渲染。

## 当前同源结果

- 正式地图独立 ID `ruins_garden`，不在历史免费测试地图选项中；I档免费仍是正式进度
- 地图装置：选择地图/阶级/词缀 → 准备地图 → 开启地图；改选后须重新准备
- I/II/III：地图等级1/4/8；费用0/4/8；基础完成奖励4/8/12；最大词缀额外奖励2/4/4
- 3600 × 2400世界；六驻点为3/5/3/5/3/5普通根，另有1首领，共25初始真实根
- 三个原有模块，四条原生碰撞轮廓，共99顶点；`walls=[]`，SVG只画 `module_polygons`，不画包围盒假墙
- 十二条原连接经两个绕行成为十四段；全宽72通过原生验证，新绕行四条腿额外验证半径51，其他路段只承诺半路宽36
- 首领庭园震地：锁首领起手点，启动140、半径130、预警0.9秒、基础恢复1.7秒、防御前倍率1.4

## 可重复重建与检查

在仓库根目录运行；Godot4.6.3可直接加载所需脚本，无需全量工程import：

```sh
XDG_DATA_HOME=/tmp/godot-v119-reference/data \
XDG_CONFIG_HOME=/tmp/godot-v119-reference/config \
XDG_CACHE_HOME=/tmp/godot-v119-reference/cache \
  godot --headless --path . --script res://tools/export_ruins_garden_reference.gd
python3 tools/merge_ruins_garden_reference.py
python3 tools/build_reference.py
python3 tools/merge_ruins_garden_reference.py --check
python3 tools/build_reference.py --check
python3 tests/ruins_garden_reference_test.py
node --check docs/reference/reference.js
```

可给导出器追加 `-- /tmp/ruins-garden-repeat.json` 做第二次有界导出，然后与本目录片段逐字节比较。`merge_ruins_garden_reference.py`只插入/替换指定单图成员，保留其余JSON原字节，重复执行不产生变化。

首次导出49项检查通过，见 `export.log`；第二次导出和定向静态检查见对应日志。静态检查逐项对应SVG轮廓顶点、路段端点/宽度、25实体、入口与7路标，并验证中文/ID搜索数据、五图链接、唯一锚点和全部本地链接。`baseline.json`在修改前从提交 `72a20915ed4483504bd5ebedd423a09c90e70178` 捕获，验证全部旧catalog原字节、旧3815卡片（仅地图装置/探索规则允许变更）、697个运行时/资产文件、74个图鉴美术文件、4973个旧QA文件与源覆盖文件不变。

本批没有浏览器点击或实际渲染验收；搜索/跳转只验证生成的数据、锚点及未改动的JavaScript语法。原生几何准备与Plan的通过不等同于新一轮完整游戏或收费事务验收。
