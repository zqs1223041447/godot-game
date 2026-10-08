# v126 Ranger 八方向动作图集

固定批次：**256个独特姿态、一个2560×3584透明图集、每方向45条逻辑帧、全局12fps**。保留最终肩桥与原骨架/权重，未改运行时、release、伤害、碰撞或CD。

## 已完成与范围

- 八方向顺序：E、SE、S、SW、W、NW、N、NE
- 每方向独特源姿态：Idle10＋Walk16＋Attack6，共32；八方向256
- 统一160×224源像素格，2×密度，实际显示80×112画布；固定root脚点(80,174)
- 55°原相机、既有灯光/材质/比例；没有逐帧缩放、重定位、IK或抬地
- 角色alpha不含地面和阴影。阴影仍由运行时独立绘制，半尺寸world[32,10]
- 已实际查看原128×192的8方向f23小样，发现E/W手指与SW脚部碰边后统一扩格；最终256姿态几何最小边距9.505px，渲染alpha最小边距9px
- 已实际查看最终8方向Idle、跨步、Attack首尾共32个静态格。方向和恢复姿态连贯，未见明显裁切/身体丢失；不把自然扭身按胸部朝向反旋
- **本批连续动画和完整游戏内八方向表现未验收**。此前单方向预览的通过不能替代本批验收

## 全局fps合同

schema1每方向总逻辑条目最多64。精确使用16Walk帧/0.743682s需要21.51456fps，Idle约54逻辑帧，加Walk16与Attack6共76条，超过上限。

本批采用最小无运行时变更方案：

| clip | 偏移/数量 | 逻辑构成 | 显示周期 |
|---|---|---|---|
| Idle | [0,30] | 10源姿态各连续重复region3次 | 2.5s |
| Walk | [30,9] | 从完整16源姿态均匀抽取9格 | 0.75s |
| Attack | [39,6] | 六格出手后恢复切片 | 0.5s |

Walk逻辑源索引：`[0,2,4,5,7,9,11,12,14]`，来自对`i×16/9`四舍五入。完整16源相位仍保存在图集中，未删除未选格。

Walk0.75s相对横向拟合0.7436822467s长约0.8495%。这是明确的稀疏显示采样选择，不能称完全锁脚。现运行时按经过时间播放，并未实现位移相位；纵深/斜向投影步距不同，不能只靠同一周期保证全方向无滑步。

## 源动作及采样

- Idle：原Game_Idle_Loop，2.5s/75源帧；独特帧`[0,7.5,15,22.5,30,37.5,45,52.5,60,67.5]`，不重复闭环端点
- Walk：v125固定80% Walk＋20%真实Jog，保持原同侧支撑对齐。16源相位`i/16`；使用隔离Trial动作虚拟源帧`i×30/16`
- Attack：v123 Game_Cast_Simple_Composite的f23→38，出手后的0.5s恢复段，不声称f23是释放事件
- Attack六源帧：`[23,25.5,28,30.5,33,38]`。正常12fps最后一格本为35.5，明确重采样为38，以保留恢复端点；最后源间隔33→38为5帧，其余间隔2.5帧。没有改变任何战斗计时

## 方向、尺度与锚点

模型local -Y为前向，Assembly统一yaw：`[90,45,0,-45,-90,-135,180,135]`度。沿用游戏既有8方向约定，属于模型地面45°步进；55°投影压缩纵深，屏幕斜向约39.32°，不是重新按胸向或精确屏幕45°纠偏。

水平47.4074074、纵深38.8338747、竖直27.1917718显示px/m。`world_units_per_source_pixel=1/(2×0.65)=0.7692307692`，0.65镜头下每个源像素显示0.5px。root是固定世界地面原点的投影，不是靴底或最低alpha。

## 文件与使用

- `atlas/ranger_v126.png`：单图集，16物理列×16物理行；每方向32格，顺序Idle10、Walk16、Attack6
- `atlas/ranger_v126.json`：schema1研究metadata，360条region引用，重复Idle不复制像素；每方向45条
- `reports/atlas-audit.json`：256格原PNG/解码RGBA哈希、region、alpha边界，全部atlas裁回RGBA一致
- `reports/render-config.json`：方向、实际尺度、源帧与末格重采样说明
- `samples/final-8direction-review.png`：最终32格实际尺寸静态复核拼图
- `scripts/`：有界渲染、打包与只读校验流程

研究目录由`.gdignore`隔离。metadata中的研究纹理路径不是已经导入并接入正式角色的声明；获准接入时需移动/映射到可导入资源目录。无需新schema或新动画框架。

## 复现

Blender4.3.2，CPU Cycles12samples、无降噪；Python打包需Pillow。只读使用此前已批准的本地v125场景（包含v123动作与真实Jog）。原模型包、场景、纹理包不随公开归档分发。

设置`V126_SOURCE_BLEND`为该场景，`V126_OUTPUT_DIR`为独立输出目录，然后：

```sh
V126_MODE=samples blender --background --disable-autoexec --threads 8 --python scripts/render_atlas.py
V126_MODE=bounds blender --background --disable-autoexec --threads 8 --python scripts/render_atlas.py
V126_MODE=batch blender --background --disable-autoexec --threads 8 --python scripts/render_atlas.py
python scripts/pack_atlas.py
python scripts/verify_atlas.py
```

本轮没有修改或保存输入场景。源SHA记录在报告中；PNG元信息含渲染时间，因此复现侧验证姿态/像素布局，不承诺跨环境文件字节完全相同。
