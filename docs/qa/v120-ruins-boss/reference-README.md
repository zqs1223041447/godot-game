# v120 庭园缠印：F8图鉴与有界同源导出

入口：[遗迹庭园卡片](../../reference/index.html#maps-ruins_garden)。本次只更新 `exploration_maps.maps.ruins_garden` 中的 `boss_definition` 及对应地图描述；合并以单个 `ruins_garden` JSON成员为单位，其外所有catalog原字节保持。只更新这一个卡片，其他3815个卡片（包括前四图、地图装置、探索规则）保持原字节。

## 当前攻击

- 稳定ID `ruins_garden_slam`，名称庭园缠印；启动距离420
- 两段都锁玩家起手点，玩家、首领移动和第二段开始均不重新锁定
- 第一段：1.15秒完整预警，半径90实心圆
- 第二段：再完整预警1.0秒，内半径90 / 外半径210空心环
- 共两段，结算间隔1.0秒局部动作时间；每段防御前倍率0.65，合计名义1.3倍；基础恢复1.9秒，仍按攻速和既有上下限缩放
- `profile_id` / `skill_id` 为 `ruins_garden_inner_outer`；`balance_version` 为 `original-ruins-garden-inner-outer-v1`
- F8示意的两栏使用同一个坐标尺度，第一段半径90、第二段90到210；第二段用 `fill-rule="evenodd"` 实际留空内心。十字表示同一冻结锁点，不表示角色半径
- 原生地形、经济、种子119001、25个根怪、六驻点、四轮廓99顶点、14段路线及除首领定义和地图描述外的所有字段与v119片段完全相同

## 证据边界

复用未修改的 `tools/export_ruins_garden_reference.gd`，只向本目录导出。它直接调用实际MapBossProfiles与正式地图编译/原生准备/脱离角色Plan；不加载Main、不读写角色存档、不收费、不运行战斗或美术渲染。每次49项检查通过；两次导出原字节一致。旧 [v119片段和记录](../v119-reference/README.md) 原封保留，其中庭园震地是历史单圈资料，不作为本次两段攻击的证据。

图鉴检查覆盖精确参数、同尺度空心环、锁点与边界说明、实际搜索数据、唯一锚点与本地链接；对比提交 `8c10337d337ecee0f9d3c8fbcfaf1766ad2103d1` 验证只改一张卡片、一个catalog成员，成员内只改boss_definition和对应description。新生成器用v119输入重建完整v119 HTML原字节，并用去除遗迹庭园的输入重建v118原字节。历史测试与历史QA未改写。

实际Main/战斗/渲染验收由本批其他测试单独记录；本页的有限导出与静态图鉴检查不能代替这些结果，也不是平衡或自然游玩结论。

## 重建

在仓库根运行，无需全量Godot import或全量历史导出：

```sh
XDG_DATA_HOME=/tmp/godot-v120-reference/data \
XDG_CONFIG_HOME=/tmp/godot-v120-reference/config \
XDG_CACHE_HOME=/tmp/godot-v120-reference/cache \
  godot4 --headless --path . --script res://tools/export_ruins_garden_reference.gd \
  -- res://docs/qa/v120-ruins-boss/ruins-garden-fragment.json
python3 tools/merge_ruins_garden_reference.py --fragment docs/qa/v120-ruins-boss/ruins-garden-fragment.json
python3 tools/build_reference.py
python3 tools/merge_ruins_garden_reference.py --fragment docs/qa/v120-ruins-boss/ruins-garden-fragment.json --check
python3 tools/build_reference.py --check
python3 tests/ruins_garden_attack_reference_test.py --report
node --check docs/reference/reference.js
```

重复导出使用另一个隔离 `/tmp` XDG目录，目标 `/tmp/ruins-garden-v120-repeat.json`，用 `cmp` 和本目录片段比较。默认历史v119片段不覆盖。历史 `ruins_garden_reference_test.py` 仍测试v119单圈快照，不作为v120的当前验收。

## 示意图视觉检查与浏览器限制

从实际生成HTML提取未改动的SVG（只补XML命名空间），使用本机既有Inkscape命令行渲染：[SVG](reference-attack-diagram.svg) / [PNG](reference-attack-diagram.png)。已查看PNG：半径90实心圆与90/210空心环比例正确，第二段内心确实留空，中文参数与标签可读且没有裁切。像素检查另验证第一段有填色、第二段内心与底色相同、环区有填色、外侧恢复底色。这只是实际F8图中SVG的独立栅格化，不是浏览器整页截图或游戏画面。

本机既有Chromium启动时被环境的 `socket() failed: Operation not permitted` 阻止；正常调用与支持的权限升级重试都在载入页面前退出。保留 [失败日志](reference-browser.log) 和 [可重跑探针](reference-browser-probe.py)。未完成浏览器搜索/点击/前进后退验收，未取得浏览器截图，也未验证实际游戏F8按键启动；静态搜索数据、锚点和本地链接通过不替代交互测试。Inkscape退出0但产生两项Pango/Gtk包装告警，原始记录见 [渲染日志](reference-svg-render.log)，PNG已人工检查。
