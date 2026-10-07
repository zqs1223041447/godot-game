# 环境行走 / 遮挡测试

独立 Godot 4.6 环境研究样板。不是完整游戏，也不是人物动作验收。

## 运行

首次先用 Godot 4.6.3 编辑器打开本目录 `project.godot` 完成资源导入。之后在本目录运行 `bash run.sh`，或在编辑器运行主场景；Windows可直接使用编辑器，不依赖符号链接。

- WASD / 方向键：移动
- R：回到起始点
- F1：打开 / 关闭碰撞多边形、人物半径和真实足点诊断
- Esc：退出

默认不显示工程线框。底部注明“环境行走/遮挡测试 · 人物为静态图”。八方向只换现有静态 idle 图，不播放或模拟跑步动画。

## 来源与坐标边界

- 使用冻结的专业环境导出，来源记录保留在 `assets/environment/SOURCES.md`
- 原 30 张 PNG 原字节复制，28 层可见，2 张完全遮挡的空 alpha 层仅保留碰撞
- `runtime-manifest.json` 原字节复制；20 对象 / 21 多边形直接采用 `screen_pixel`
- 本项目 **1 个坐标单位 = 原图 1 个屏幕像素**，固定 1280×720，未加 Camera2D，不套用源 manifest 的 0.65 相机换算
- 所有物件根在 `foot_screen_pixel`，Sprite offset 采用原 `sprite_offset_pixel`，缩放为 1；像素精确回到各层裁幅
- 地面及草细节固定在后，其余透明 prop 与人物同处一个 `y_sort_enabled` 父节点，统一按足点 y 排序
- 拱门保留两条独立墙腿，135 个门槛低位面已属于地面，不用整门矩形阻挡
- CharacterBody2D 圆半径 14.222px，来自 0.3m × 47.407px/m；这是保守的屏幕圆形，未声称等于3D地平面投影椭圆
- 人物母图和字体字节与静态 v108 样板一致，scale=0.115，约51–53px可见高度；仅用 Sprite region 选择安全区域、每方向脚点，不修画面、不添加图像
- 这是固定单屏测试；移动脚点限在屏内，底栏外留活动边界，不含世界切换 / 相机跟随

## 已检查

有限 headless 检查在 `qa/headless-verification.json` 和 `qa/asset-verification.json`：

- 30 层载入 / 28 层绘制、PNG 尺寸与原字节、裁幅放置和方向脚点
- 原碰撞点未修改，门中心双向实际 CharacterBody2D 通行
- 两条墙腿和岩石阻挡 sweep 及持续 CharacterBody2D 移动
- 原 prop 的排序顺序、人物门前 / 门后足点排序、地面门槛结构
- 3 次场景载入 / 释放回到同一节点及资源数

复验仅在需要时运行：`python tests/verify_assets.py`，然后 `bash run.sh --headless --fixed-fps 60 --script res://tests/verify_study.gd`。Python需要Pillow；默认按保留的原始输入SHA核对，并写入新的qa/asset-recheck.json，可通过--source-env/--source-character指定原目录。Godot复验会写qa/headless-verification.json，应在工作副本执行以保留本次原始证据。归档过程中没有重跑这两套。

上述原工作记录不含原生画面检查。之后已在原生Godot窗口通过D/W移动到门后观察遮挡，再按S返回门前恢复可见；具体记录见上级README与verification/native-observation.json。仍没有FPS / 性能、完整动作或正式游戏集成结论。

## 保留的限制

环境固定光影与物件互遮挡已烘焙，不能任意移动 / 删除原物件；植被小片共用锚点，人物进入片内的细枝交错近似。使用透明层与人物做深度排序，不代表实时3D光照。人物母图存在生成方向 / 造型误差，未在本测试中修复或验收。

没有连接主游戏伤害、奖励、地图流程或存档；没有修改旧目录、原 blend / 终图、主游戏或研究备份分支。

归档补入字体OFL许可和环境下载审计；SOURCES沿v108官方复核结果更正Grass Bermuda作者。qa/input-sha256.json与handoff.json保留工作样板交接时的历史原字节，归档当前文件以其上级verification/archive-manifest.json为准。
