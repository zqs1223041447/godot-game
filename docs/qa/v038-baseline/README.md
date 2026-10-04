# 百怪性能只读基线（v0.37 / f074c26）

2026-10-04，Godot 4.6.3，dot云Linux、Mesa llvmpipe。没有修改任何生产脚本、资产、存档规则或已发布包。所有写入仅隔离诊断存档和本目录证据。native原始日志保留无音频设备导致的ALSA错误/自动Dummy fallback，不称环境日志全绿。所有诊断窗口均自行结束。

## 主要瓶颈排序

1. **每帧重复提交角色几何，尤其抗锯齿线条。** 100怪3秒固定模拟/180原生帧，draw提交均21.87ms，p95 25.16ms；其中actors均17.69ms，标记0.89ms、名字选择0.50ms、预警1.82ms。10秒模拟/600帧战斗（127击杀）中draw均24.02ms，actors18.79ms。软件渲染墙钟约98/106ms，只描述该环境，不能转成WindowsFPS。原有静态环境层均不到0.01ms。
2. **密集投射物的候选接触与事件构造可形成尖峰。** 固定100真实目录目标、30/180现有bolt+pierce弹体，20个单tick重复：散布180弹advance中位6.49ms，密集180弹35.34ms、最大38.62ms（20/20大于16.7ms、19/20大于33.3ms）；候选13,770/全扫18,000，874事件。30弹密集中位4.60ms。纯弹体构造180次中位5.52ms，明显低于密集advance；现有弹体已经是有上限的Dictionary载体，并已有空间索引，不能泛称“没有池/没有网格”。这是人工同时载体压力，不是一次合法耗魔施放；不包含后续伤害/死亡结算。每组完整弹体与事件的20次重放哈希相同。
3. **击杀峰值主要是物品奖励和完整校验，并非磁盘系统调用。** 三次隔离重复：1根死亡中位3.80ms，8根13.67ms，20根26.92ms；20根在38物品新档产出2装备+1珠宝后41物品，真实奖励RNG和一次flush保持。装备两次合计12.0–13.4ms，珠宝3.4–3.5ms，flush4.65–5.03ms；其中完整save2.26–2.34ms，原子write含close仅0.095–0.12ms。标签嵌套不可直接相加。仅3个重复的p95等于最大观测，不作稳定分位估计。自然战斗70个击杀step中位13.24ms、最大68.49ms，包含升级/稀有物品等实际变化，未把每个尖峰统一归因于同一步。
4. **断垣几何是次一级持续成本。** 100怪每场180tick，无射击奖励：普通AI均2.47ms，10预警者普通场景2.32ms，断垣4.92ms。断垣direction16,280次，move18,180次，visible59,976次；visible嵌套总均1.43ms/tick。预警空状态仍advance校验100怪约0.22ms/tick，多处仅查状态却取deepcopy，是小项，不能另发零碎优化版。

## 绘制内部证据

actor-primitives-initial.json为60帧基础拆分，actor-primitives.json为补足native polyline与字宽的20帧；两次仪器副本都与原renderer的完整RGBA和运行状态字节完全相同。仪器会增加计时开销，因此这些是路径定位，不是修复收益。

每帧约722个draw_colored_polygon、1,866个draw_polyline、402次_cached_blob、81次_blob、101次_shadow。最后20帧总提交均24.83ms，中位24.39，最大27.75；20/20大于16.7ms，0/20大于33.3ms。native polyline调用合计均11.06ms，native polygon3.52ms。cached_blob含提交6.33ms、path含提交3.52ms、动态blob1.72ms、shadow1.03ms。后四标签与native时间重叠。

真正的字体get_string_size仅18次/帧，合计均28.3微秒，不足以解释大头；名字选择总段还包括候选筛选、排序和避让。暂不为字宽缓存优先开发。

render-pixels.json采用同一冻结百怪画面：Viewport实际图像确认为1280×720和640×360，而非只改窗口外框。原始draw提交均20.50/20.13ms；墙钟108.7/97.9ms。像素数缩到1/4没有同比缩短绘制CPU，不能把主要提交成本当纯fillrate；软件渲染/驱动等待和短样本抖动仍存在。两个尺寸可见及全部显式自定义Material资源均为0，战斗窗口没有动态ShaderMaterial分配证据。GemIcon的自定义shader仅在对应UI实例ready时创建，不在本次战斗绘制路径。长短样本节点376保持、孤儿0保持、资源148保持；短样本不能排除任意长时间泄漏。

## 推荐下一批方案与取舍（尚未实施）

- **首选：原样保留静态角色绘制命令。** 将同半径/类型/颜色的静态局部轮廓、轮廓抗锯齿线条与阴影保存在可重用绘制资源或CanvasItem命令，位置/方向更新只改transform；动态步态/受击色/部位层级仍按原顺序。它直接针对polyline大头。先做一个怪物族的隔离原型与逐RGBA对照再决定合入，不能预设收益，也不能擅自量化步态、删除部件或改变透明叠放。
- **可并入：静态轮廓预三角化。** 缓存精确contour与索引，经RenderingServer三角数组提交，保持颜色/变换/抗锯齿轮廓。能避免每次polygon三角化，但当前polygon总段仅约3.5ms，不能单独宣称解决18ms角色绘制；仍有内存上传/命令提交开销。
- **奖励路径：消除重复物品验证/占格元数据构造。** 只能复用已验证且字节未变的旧实例；新掉落、最终完整candidate和实际保存继续校验。UID、容量、奖励顺序/RNG、失败回滚保持；不可用call_deferred冒称异步或绕过原子落盘。先量一个实际装备奖励内部分段，再挑最大重复项。
- **投射物：保持精确候选和顺序，减少重复事件深拷贝/无用派生与空间桶候选。** 现有稠密桶已经失去大部分稀疏收益；不要只给同一数据结构换对象池名字。压力样本需和真实支持组合重放相同命中/母子/返回/到期/墙/掉落摘要，不能降低模拟频率掩盖成本。
- **暂缓预烘焙图集。** 可能降低绘制调用，但方向、连续步态、受击、不同半径与小字号缩放都可能改变原画面和资产量，超出“同画面优化”的首选边界。

## 与另一助手建议对照

- 固定500/1200距离把AI降10Hz/1Hz并关攻击/精细碰撞：暂缓，会改变已实现远程、预警、返回与墙后战斗语义；视觉完全离屏且足迹界限证明无像素贡献的剔除可另评估
- 普通怪隐藏血条/稀有怪按等级显示：当前最多8个完整名字，血条仅受伤时显示；再隐去可用信息是UX改动，且标记成本不到角色几何的大头
- 弹体池：当前纯数据/180上限/空间网格已经存在；优先测准创建、接触、排序、事件分别成本，本次数据不支持“只做池即可修复”
- 0.2秒伤害数字聚合：自然战斗数字绘制均0.145ms，暂不优先；聚合还会改变玩家看到的单次命中反馈
- 逻辑/绘制各8ms：可作测量目标，不能作为已实现结论；目前百怪角色绘制已超过该预算

## 证据与复现范围

JSON为原始计时，summary.json统一中位/p95/max与阈值次数。native-crowd/combat由现有tools/combat_render_profile.gd只调短采样出口产生；实际原生启动经云桌面终端，不设置绕过沙箱的X11权限。frame_paths、death_paths、projectile_paths与actor计数均是目录内诊断副本/子类；不属于发布生产路径。原始日志中测试脚本的类型/缩进初错先修正后采样，没有放宽生产校验。未运行600秒或历史全量。

官方实现核对（4.6.3固定版本）：
- https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/scene/main/canvas_item.cpp ：draw_colored_polygon转交draw_polygon，queue_redraw清理并重建命令
- https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/servers/rendering/renderer_canvas_cull.cpp ：canvas_item_add_polygon每次调用Geometry2D::triangulate_polygon；triangle_array接受已有索引；抗锯齿polyline构造边缘顶点和颜色数组
- https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html
- https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html

这些引擎事实支持候选方向，不代替本项目原型前后测量。

仓库归档将诊断脚本存为.gd.txt、日志存为.log.txt，避免Godot把含本次绝对scratch路径的仪器当作运行资源扫描。复现需还原原扩展名并重建README所述scratch目录；证据JSON不依赖此操作。
