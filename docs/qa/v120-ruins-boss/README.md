# v120 遗迹庭园：庭园缠印

基线：v119 `8c10337d337ecee0f9d3c8fbcfaf1766ad2103d1`。当前攻击仍使用严格地图身份 `ruins_garden_slam`，不迁移存档，不增加怪物、掉落、地图档位或经济。

## 当前合同

- 起手距离420；锁定施法开始时的玩家位置，不是首领位置
- 首段完整预警1.15秒，半径90实心圆；第二段再完整预警1.0秒，内90 / 外210空心环
- 两段使用同一个冻结圆心，不因玩家或首领移动、第二段开始而追踪或重新锁点
- 每段使用起手冻结的原接触伤害各分量 × 0.65；防御前名义合计1.3倍，不保证两段命中或等量扣血
- 第二段结束后进入基础1.9秒恢复；既有攻速策略只缩放恢复，不压缩完整预警
- 半径15玩家的第二段几何安全条件：中心距d＜75或d＞225，内外相切均算重叠；最终仍须通过墙体视线和既有防御/保护
- 冻结暂停来源局部动作时钟；来源死亡、移除、恢复出生保护、显式取消/重置沿现有取消链，不结算剩余段
- 收据使用 `profile_id` / `skill_id=ruins_garden_inner_outer` 和 `balance_version=original-ruins-garden-inner-outer-v1`；事件schema仍1

生产修改仅四个脚本：`map_boss_profiles.gd` 的遗迹庭园单行配置、`telegraphed_area_runtime.gd` 的既有两段/环形严格ID许可、`telegraph_renderer.gd` 的新ID空心环准入，以及 `exploration_map_layout.gd` 的遗迹庭园单行说明。没有新调度器、任意profile开放、Main修改或新碰撞。其他四图配置和描述原行逐字节保持。

## 已验证

- [runtime-result.json](runtime-result.json)：新ID定向100项，0失败，Godot4.6.3。完整时序、同中心、单段各一次、帧切分、伤害快照、攻速恢复、冻结、死亡/移除/出生保护/取消/重置、伪造参数及来源拒绝、内外相切、所有特效等级的真实环形绘制primitive。见 [runtime-first.log](runtime-first.log)
- [main-result.json](main-result.json)：真实Main341项，0失败，13组，见 [main-run.log](main-run.log) 和 [main-report.md](main-report.md)。新建合法schema54角色，经正式异步 `open_map` 进入遗迹庭园；独立地图/碰撞/攻击ID、420启动边界、25初始根、真实按键退圈再进、完整预警、同一玩家锁点、内外边界、保护到期、冻结、原生轮廓LOS、正式返城与真实来源死亡取消
- [legacy-renderer.log](legacy-renderer.log)：未修改的银杏环形绘制测试90项，0失败
- [legacy-before.bin](legacy-before.bin) / [legacy-after.bin](legacy-after.bin)：同一有限探针分别在v119和v120运行，旧四图的policy、起手结果、七个短时间片事件/快照/绘制primitive完整原字节相同，均76764字节。SHA256 `b127b6932036c79bbcd6c077e1ecc64c2dfa9e1b8191da908f366f3059f1b583`。这是所列短轨迹的等价，不是全系统/全输入证明
- [preservation.json](preservation.json)：639个已跟踪脚本/资产/数据/场景/项目文件中只有上述四个改变，其他635个原字节相同；全部历史已跟踪QA未修改
- [F8图鉴记录](reference-README.md)：复用v119单图导出/单成员合并；真实参数、同尺度两段示意与原生地图同源。单图成员外catalog及其余3815卡片原字节保持。旧v118/v119输入仍生成完整历史HTML原字节

Main测试冻结其他根的移动/攻击，并显式控制首领及玩家位置、资源和死亡；只有退圈再进的路线使用真实输入和tick。没有把测试控制当自然游玩，没有完整清图、600秒战斗、旧迁移测试、全套回归、Windows性能、平衡结论或游戏内截图验收。F8的Chromium浏览器在socket权限处中止，支持的升级重试也失败，因此没有浏览器点击或截图通过声明。已用本地SVG渲染器将新图示栅格化并查看，中文标签、同尺度圆形与安全空心区域清楚；这不替代实际浏览器或游戏内预警像素验收。

## 冷缓存与历史证据边界

第一次Main预检因全新工作树缺导入缓存和全局类缓存而失败，原始 [main-preflight.log](main-preflight.log) 保留。随后一次约15秒编辑器导入建立缓存；未完整排除历史文档，意外扫描了历史QA图片。日志另有编辑器配置目录不可写和两张历史QA图片导入失败，详见 [main-import.log](main-import.log)。这些不是当前游戏纹理或本次通过的Main运行错误；没有修改原历史图片，所有新生成历史旁文件已清除。后续实际Main运行日志无错误。没有再运行编辑器导入。

`tests/ruins_garden_entry_test.gd --boss-only` 的v116断言要求新旧庭攻击完全相同；v119 `ruins_garden_reference_test.py` 固定旧震地与生产文件哈希。这些原始历史快照及QA均保留，不能作为v120当前通过项目。新的v120测试验证当前合同，没有改旧证据以伪造通过。

## 定向复验

在已有正常导入缓存的仓库执行；Main须使用全新独立XDG目录，不能覆盖用户角色：

```sh
XDG_DATA_HOME=/tmp/godot-v120-runtime/data \
XDG_CONFIG_HOME=/tmp/godot-v120-runtime/config \
XDG_CACHE_HOME=/tmp/godot-v120-runtime/cache \
  godot --headless --path . --script res://tests/ruins_garden_boss_runtime_test.gd
```

Main命令见 [main-report.md](main-report.md)，图鉴命令见 [reference-README.md](reference-README.md)。旧四图有限探针 `tests/ruins_garden_boss_legacy_probe.gd` 支持绝对脚本路径及一个输出路径参数，可用相同脚本分别以 `--path` 指向v119与v120，然后用 `cmp` 比较输出。不需要全量历史导出或重跑旧迁移。

提交时只去除了 `main-import.log` 的行尾空白及 `reference-browser.log` 的空末尾行；报错内容保持。其他原始失败信息没有删改。
