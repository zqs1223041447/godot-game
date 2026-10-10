# 地图装置：当前地图手记

基线 main：`ae75ff6117143043531bea2b24268179c7dc9f52`；分支 `codex/map-device-description`。

唯一生产改动 `scripts/ui/town_service_panel.gd`。在原地图/档位选择下增加现有羊皮纸风格的可展开卡片：默认一行布局摘要，点击“布局与首领 · 展开”显示完整说明，再次点击收起。沿用原字体、材质边框和滚动容器，不添加新绘制资产、不移动城镇窗口或修改玩法按钮。

说明只来自 `Main.map_options()` 已返回的 `ExplorationLayout.description(map_id)`。这五份现有说明描述当前已实现的地图碰撞、驻点/首领数量及预警机制；核对来源为 `exploration_map_layout.gd` 与 `monsters/map_boss_profiles.gd`，没有新增赛季机制或将计划内容写成已实现。生产地图资料、战斗/模型接口、费用、schema和存档实现均未改。

切图的实际 `item_selected` 信号同步更新卡片，保留展开状态以便比较。准备后的面板重建和隐藏重开重新读取对应地图资料。缺失、空白或非字符串description显示“这张地图暂时没有可用说明。”并禁用展开按钮，先前地图正文被完全替换。

## 有限验证

- `tests/map_device_description_test.gd`：X11真实渲染 **93项、0失败，exit0**。复用已有费用预览测试的canonical UI夹具和权威状态观察，不执行其较大场景。逐一检查五图的折叠/展开、连续切图、准备后重新选择、隐藏重开、独立测试档，以及空/非字符串资料降级。
- 比较模型、准备草案、地图运行状态、磁盘字节、保存计数与RNG，浏览说明不写入或准备地图。真实鼠标点击“准备地图”产生恰好一次原事务；切到其他地图继续禁止使用旧草案开启。
- 既有 `map_selection_cost_preview_test.gd`：**59项、0失败**（headless），覆盖原费用、奖励、背包余额、准备/入图和独立测试档合同。未改旧测试、未运行全套回归。
- Godot 4.6.3，1280×720，隔离Xorg dummy显示器、Mesa llvmpipe软件OpenGL。已实际查看 `collapsed.png`、`expanded.png`、`actions.png`：紧凑卡片保持魔法书样式，完整说明可读，操作区仍沿原滚动区域可达。准备/开启按钮布局边缘有0.6px的原滚动取整差，检查容许1px取整，并由实际鼠标准备操作验证可点击，不宣称所有分辨率/字体缩放均已视觉验收。

首轮 `visual-01` 为93项/1失败：按钮矩形严格encloses受亚像素滚动取整影响，且首版标题留白令完整说明略高。缩减标题留白、卡片边距，将折叠摘要从两行收为一行，并增加真实鼠标操作检查后通过。保留首轮JSON/日志和 `attempt-01/` 截图，不累加两轮通过数。两个渲染日志只有虚拟显示器不支持VSync设置的警告，无脚本错误。没有模型工作、Windows导出、封包或长矩阵。

## 截图

- [折叠摘要](collapsed.png)
- [展开完整说明](expanded.png)
- [原准备与开启操作区](actions.png)

## 复现

渲染检查需要可用的X11显示器；下例使用DISPLAY=:99，须替换为实际显示器，使用新的隔离目录：

```bash
timeout 45s env DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 XDG_DATA_HOME=/tmp/godot-map-notes-review XDG_CACHE_HOME=/tmp/godot-map-notes-review-cache MAP_NOTES_REPORT=/tmp/map-notes-review.json MAP_NOTES_CAPTURE_DIR=/tmp godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/map_device_description_test.gd
```

无显示器可改为 `--headless`，自动跳过3项截图保存检查。权威状态与鼠标路由检查仍执行；不把headless结果当作视觉验收。`verification.json` 记录源文件、最终结果和截图指纹。

## 下一项实际内容可达性缺口

正式装备商人的 `town_stock` 把基础生命/魔力药剂追加在装备底材列表末尾，`TownServicePanel` 逐行平铺，无分区导航。下一小批次可在原商人样式中增加“装备 / 药剂”分类或直达药剂入口，让现有基础药剂更容易找到；沿用原有报价、收费和入包事务，不增加赠送或新药剂效果。本批只确认现有调用链，未实施此项。
