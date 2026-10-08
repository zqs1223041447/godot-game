# KayKit Skeleton Minion：三方向近战美术小样

仅做新亡灵外观族的适配研究，未接入正式敌人、替换蜘蛛或改变游戏机制。来源固定为[KayKit Skeletons 1.0指定提交](../../../art-studies/kaykit-skeleton-minion-1.0/README.md)，保留作者三份原文件及CC0许可证，不上传整个角色包。

## 同源检查

[source-audit.json](source-audit.json)核对GLB大小、Git blob、SHA256、41骨骼皮肤、9个带JOINTS/WEIGHTS的网格和95个实际动画条目；GLB内嵌贴图与相邻PNG原字节相同。所选Idle有19个变化通道，Walking_D_Skeletons有29个，Unarmed_Melee_Attack_Punch_A有28个。三段在0/25/50/75%时点实际蒙皮顶点均发生变化，原样最大位移分别约0.047、0.570、0.917模型单位，见[原样渲染审计](render-audit.json)。不是根据动画名称推断有动画。

源格128×192、脚点[64,158]；预览显示格64×96，原样实际可见身体高度约38–55.5px，适配样43–57px（随姿势/方向变化），没有把整格尺寸称为人物高度。55°正交镜头、固定暖主灯/冷补灯、AgX沿用现有英雄素材处理；保留作者贴图和眼部材质，仅将骨骼主材质设为粗糙度0.75/金属0。三个方向是屏幕下、右下、右，没有其余五方向。

原姿态从高处看，头顶遮挡眼窝，原尺寸正面难以辨认为骷髅。只测试一项固定适配：每个作者姿态后给head骨骼施加-25°俯仰（面部朝镜头抬起），见[适配审计](head-fit/render-audit.json)。原模型/动画原字节保持；适配样是修改过的展示姿态，不能称为原样作者渲染。渲染前冻结当次采样姿态，并核对冻结前后顶点一致，防止渲染时动画重求值把头部调整覆盖。

## 自检结果与证据

已直接查看[原样原尺寸卡片](actual-size-contact.png)、[适配原尺寸卡片](head-fit/actual-size-contact.png)、[Godot原样原生截图](native-author.png)和[Godot适配原生截图](native-head-fit.png)。固定仰角后，Idle、步行和攻击的眼窝、鼻口与下颌能在当前尺寸辨认；侧向的肋骨和细骨轮廓仍可见。米白骨骼在现有偏暗石地上有足够主体对比，细骨仍接近1–2显示像素，不宜据此承诺更小尺寸或全部背景可读。

[frame-verification.json](frame-verification.json)：两种变体共72张稀疏采样帧均无alpha裁边；每段每时点有三个实际不同方向，各段各方向至少三个不同像素姿态。实际PNG轮廓与投影网格边界相符。两变体脚点及脚部高度保持一致；抽样最深脚顶点为z=-0.05551，对当前55°镜头与尺寸约0.955显示像素穿地，只记录此限制，没有逐帧抬脚。没有静态全周期最大值证明，也没有原地滑步/移动速度匹配验收。

PNG透明背景没有烘焙地面或阴影。Godot隔离画廊复用现有`FantasyActors._shadow`，双层静态接触阴影只随显示脚点平移；用已有普通巡游体radius14计算阴影作为视觉参照，不创建新怪物或半径。地面沿用`FantasyEnvironment`的0.4世界缩放×0.65镜头缩放及配色。截图原生Linux X11/Mesa llvmpipe，960×540且关闭窗口内容缩放，保证一绘制单位等于一截图像素；只出现软件驱动不支持V-Sync的提示。

四帧稀疏动画：原样[Idle](idle-sample.gif)/[Walk](walk-sample.gif)/[Attack](attack-sample.gif)，适配[Idle](head-fit/idle-sample.gif)/[Walk](head-fit/walk-sample.gif)/[Attack](head-fit/attack-sample.gif)。GIF使用作者周期按四等分播放并取10ms时间精度；它们用于看采样差异，不代表最终流畅度。作者周期分别约1.067、1.600、1.467秒，未当作游戏攻击时长。

## 复现与后续最小接入

```sh
python3 tools/art/skeleton_minion/inspect_source.py
blender --background --factory-startup --disable-autoexec --python tools/art/skeleton_minion/render_sample.py
blender --background --factory-startup --disable-autoexec --python tools/art/skeleton_minion/render_sample.py -- --head-pitch -25
python3 tools/art/skeleton_minion/pack_sample.py
bash tools/art/skeleton_minion/run_preview.sh -- head-fit
# 或 -- author；无参数默认展示头部适配样。
```

原生截图复现给变体后增加输出路径，例如`bash tools/art/skeleton_minion/run_preview.sh -- head-fit /tmp/skeleton-fit.png`。运行器创建隔离XDG目录；画廊不加载Main、不生成怪物、不读写构筑档。步行栏的平移是画廊演示，不能用来证明游戏移动速度已匹配。

自主结论：固定头部适配值得作为后续新亡灵外观族候选，仍先保持当前小样，不做八方向批量。最小正式接入应复用`ActorSpriteCatalog`现有128×192、[64,158]脚点、18帧/方向（Idle4、Walk8、Attack6）及`ActorVisual`/`RetainedActorLayer`；通过明确的新族键`undead_minion`选择，与crawler/skitter原族分开。源图要先补齐真正八方向并验证转向、实际游戏缩放/移动速度、全步行周期接地和已有攻击提示窗口；视觉采样可适配既有12fps约定，实际攻击、伤害、冷却、速度、碰撞与存档均沿原路径。此处只记录方案，未加生产目录条目、族选择或新敌人。

未验证边界：其余92条动画、剩余五方向、正式战斗/伤害、全动作周期、死亡、密集同屏、稀有/首领配色、自然游玩和性能。未导出Windows程序、封包或跑600秒检测，未重跑战斗/迁移测试。
