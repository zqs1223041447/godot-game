# v0.48 晴泉台地：地形、据点、编排

## 实现合同

- 地图 ID `sunwell_terrace` 为目录第三项；固定测试波次6，正式 I/II/III 波次3/6/10，费用0/4/8、基础完成奖励4/8/12。
- 四个泉池使用 MapGeometry 现有实体墙算法：相对 bounds 的 `(520,140,240,140)`、`(1080,140,240,140)`、`(520,430,240,140)`、`(1080,430,240,140)`。移动、弹体 sweep、LOS、绕行共用实际阻挡面；仅本图 snapshot 多出 `obstacle_style = spring_basin`。
- 西泉/北门/东阶据点保留 `camp_west/camp_north/camp_east`。中心分别 `(290,160)/(920,130)/(1550,540)`，触发点 `(290,590)/(920,550)/(1550,120)`。每组4列×3行，相邻56，共36根怪，任意顺序可同时激活。
- 入口 `(920,670)`；首领中心 `(920,355)`，触发点 `(920,670)`。没有缩减数量、固定出生位修正、停攻或第二属性解释器。实际出生仍走 MapCampAdmission → MapAdmission → 原怪物工厂；0.6秒保护、230玩家安全距、100 live上限、整组事务保持。

## 编排唯一消费者

`map_camp_state.gd` 只对本图调用 `sunwell_roster_rules.gd`。每个非灰烬名额仍调用原 `ordinary_roll` 一次，稀有度和机制不改。灰烬保留每8个全局名额一次、且不消耗普通roll；原roll所得 splitter/brood_host 保留原模板及后代。

本地序号从1起，所有名额（包括灰烬和分裂类）占位，每六个循环：

| 据点 | 六格模板 |
| --- | --- |
| 西泉 | brute, frost_guard, brute, crawler, frost_guard, skitter |
| 北门 | crawler, brute, skitter, frost_guard, crawler, storm_skitter |
| 东阶 | skitter, storm_skitter, skitter, crawler, storm_skitter, brute |

仅原roll为 crawler/skitter/brute 时替换。霜纹、雷纹门槛分别读原 MonsterCatalog 的第4/5波规则，门槛前退回 brute/skitter。地图所选巡逻词缀最后处理，以编排后模板对应的基础种类交给原 MapCompiler.special_template，优先于图内编排；元素庇护仍走原防御管线。未新增奖励或随机抽样。

## 定向验证范围

`tests/v048_sunwell_layout_test.gd` 覆盖：

- 指定目录/档位/地标/池体精确值与平移
- 小pattern全位置、冰电边界、保留splitter/brood_host
- 16种子下原ordinary RNG序列、rarity/mechanisms、灰烬名额与selected special优先
- 新图3正式+固定测试档；无普通词缀、血盾、移速攻速、伤害护甲四种代表组合，覆盖全部六个普通词缀与各合法special，共52个真实编排profile
- 实际CampAdmission在每组触发圆最不利边缘整组生成，三组共存的实体半径/位置/安全距/出生保护与事务不变
- 全组强制最大普通半径22、首领27.5；容量不足、玩家过近、末成员落池整组拒绝
- 六种激活顺序；半径10/14/22/27.5的入口/首领/三组中心及触发点两两真实direction+move通路，无永久停滞

旧图不重跑完整词缀factory矩阵。`capture_legacy.gd` 为同一个外部脚本，分别加载已发布v47 PCK和当前工程：旧6正式+2固定档，各两配置、3种子，共48 case，捕获profile、layout、完整roster/state、实际整组/首领结果；另捕获4种旧几何×2原点下snapshot、移动、sweep、LOS、寻路缓存。输出以 `var_to_bytes` 比较，保留类型和浮点位。

## 实测结果

- Godot 4.6.3；三次独立进程均 exit 0，日志无 ERROR/SCRIPT ERROR
- 新图预检 54,901 checks / 0 failures；52 profile，156整组，1,872个真实根怪
- 实际最大半径27.5；36根全组最小实体间隙12.0；整个触发圆范围的最坏玩家距离251.0（要求230）
- 半径10/14/22/27.5的所有测试地标配对均沿真实 direction+move 到达，无永久停滞；指定布局未修正
- 旧图捕获48个profile/种子case、8个几何case；两版本各6,190,976字节完全相同，SHA256 `969bc98ed3e08deb82b5910003028e025ad2b0de1272cf32256d901570500e1a`

`layout-report.json`、`legacy-equivalence.json` 保留结构化结果；`.log.txt` 保留原始引擎日志；`tested-files.json` 记录执行后源文件哈希。两份原始 Variant 字节使用无时间戳gzip保存为 `legacy-v047.bin.gz` / `legacy-v048.bin.gz`，解压即可复核。仅这些定向检查，不代表历史全量、长时模拟或GUI验收。

## 复现命令

由父协调完成统一导入后，使用独立 XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME 运行以下命令。旧版脚本必须由相同文件的绝对路径传入；其 res:// 依赖从发布PCK读取。

```sh
godot --headless --path /workspace/scratch/a51485f153de/v048-sunwell-terrace --script res://tests/v048_sunwell_layout_test.gd
godot --headless --main-pack /workspace/scratch/a51485f153de/v047-final-release/game.pck --script /workspace/scratch/a51485f153de/v048-sunwell-terrace/docs/qa/v048-layout/capture_legacy.gd -- --out=/tmp/legacy-v047.bin
godot --headless --path /workspace/scratch/a51485f153de/v048-sunwell-terrace --script res://docs/qa/v048-layout/capture_legacy.gd -- --out=/tmp/legacy-v048.bin
cmp /tmp/legacy-v047.bin /tmp/legacy-v048.bin
```
