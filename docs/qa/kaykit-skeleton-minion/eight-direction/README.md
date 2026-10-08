# 骷髅亡灵：八方向视觉研究入口

当前只在显式研究启动器中展示，不注册正式怪物族，不改变crawler/skitter名称、怪物生成/数值、攻击或存档。正式地图采用现有`ruins_garden`与v113自然地面材质；旧重复石地画廊只保留为前一轮历史证据。

一次头部缩放对照：[真实游戏地面对照图](../game-head-comparison.png)，同三方向Idle/Walk/Attack关键姿态，左侧缩放1.00、右侧0.85，均固定-25°俯仰。0.85露出更多躯干和手臂轮廓；原尺寸关键姿态未见颈部破口，脚部未变。采用0.85，未继续试其他比例或改背景。原GLB/texture不再跟踪；本地工作源保留，作者原字节未改，按外部路径复现。

图集及源帧：真实8方向，按E/SE/S/SW/W/NW/N/NE顺序分别在3D空间转动模型后渲染，不复制或镜像方向。Idle4、Walk8、Attack6，共144帧，128×192源格、[64,158]脚点，2048×1728图集，16列9行。源动作仍为Idle、Walking_D_Skeletons和Unarmed_Melee_Attack_Punch_A。固定镜头/材质/灯光沿前一轮，头部只应用固定仰角及0.85比例。

[渲染审计](render-audit.json)记录每帧时点、投影边界、脚部高度和冻结姿态一致性。[图集核验](atlas-verification.json)检查144张源帧无alpha裁边、与投影轮廓一致、每时点八方向真实不同、区域逐字节打包。Idle/Walk作者首尾的全部蒙皮顶点闭合（最大差0），各64时点接地抽样仍约0.955显示像素穿地；它不是连续周期的数学上界。Attack按首尾都包含的六个时点采样，不循环。

复用现有12fps帧时钟：展示Idle周期4/12秒、Walk周期8/12秒、Attack占用6/12秒（0.5秒）。作者原周期约1.067/1.600/1.467秒，视觉帧重采样到既有合同，未改变实际攻击、伤害、冷却、速度、碰撞或存档时钟。步行未完全锁脚，既不宣称滑步已经解决，也不逐帧强制抬脚或追调参数。

研究入口复用`ActorVisual._update_pose`及绘制、`ActorSpriteCatalog`校验/索引、`RetainedActorLayer`保留根节点和原接触阴影。一个仅研究脚本内的资源适配器固定图集；八个显示副本放入独立层，未加入Main敌人列表、怪物生命周期、目标索引或生成目录。阴影读原普通参照半径14；研究移动读实际普通入场crawler速度65.4，沿现有速度×delta和地图碰撞投影前进。它是速度/碰撞展示代理，未验证自然AI。

验证结果：[headless结果](headless-result.json)392/0、[原生结果](native-result.json)393/0。真实Main异步进入正式地图，加载现有自然地面shader，原25根驻留；研究层另有8个显示副本。144个动作帧槽、两种循环回卷、0.5秒攻击图像退出、根/阴影对齐和保留命令验证通过；身体源格真实投影64×96。64次步行速度探针约65.3986–65.4001世界单位/秒，对应42.51投影像素/秒；真实`Main._move_player`仍240世界单位/秒，即156投影像素/秒。固定比较与研究检查都核对原敌人表、角色资源/冷却、模型、地图几何和存档原字节保持；玩家移动按原代码产生粒子及消费运行时RNG，未更改其逻辑。

已直接查看[最终原生游戏截图](game-preview.png)：草地上正面眼窝/下颌可辨，侧后向躯干细骨比原石地清楚；后向主要读头骨、肋骨与披挂轮廓，未把背面画成正面脸。比例缩小没有用于更改碰撞半径。Linux X11/Mesa llvmpipe截图只证明此原生渲染路径，不是硬件FPS或Windows验收。

启动（正常场景不选择这些资产）：

```sh
bash tools/run_skeleton_minion_study.sh
# 有界核验；无需作者原模型，已交付图集：
bash tools/run_skeleton_minion_study.sh --headless -- --verify --report=/tmp/skeleton-study.json
bash tools/run_skeleton_minion_study.sh -- --verify --capture=/tmp/skeleton-study.png --report=/tmp/skeleton-native.json
```

启动器使用新的隔离XDG目录。WASD移动实际游侠，副本自动演示步行/停步/视觉攻击；战斗暂停，不调用副本伤害、生成、奖励或正式目标机制。

图集复现需显式外部作者文件：

```sh
python3 tools/art/skeleton_minion/inspect_source.py --source-dir /absolute/path/to/external/source
blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python tools/art/skeleton_minion/render_sample.py -- --source-dir /absolute/path/to/external/source --head-pitch -25 --head-scale 0.85 --atlas
python3 tools/art/skeleton_minion/pack_atlas.py
godot --headless --editor --path . --import
```

缺源会清楚说明官方固定URL清单，不自动下载、不运行作者脚本。[作者原许可证、SHA和固定URL](../../../../art-studies/kaykit-skeleton-minion-1.0/README.md)仍保留；不重写Git历史。QA文件夹`.gdignore`隔离原始帧证据，研究atlas单独正常导入。

未验证：正式族投放、自然敌人AI/伤害、生产稀有/首领样式、密集同屏、视口边缘裁剪、持续游玩、所有源动作、连续脚接地和硬件性能。本批不重跑战斗或迁移套件，不导出Windows、不封包、不跑600秒检测。正式内容投放另行决定。
