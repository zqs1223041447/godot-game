# 立体美术制作路线

## 当前选择

保留权威二维战斗、碰撞与地图坐标，使用真实三维模型离线渲染的多方向动画。人物、怪物和立体地景共用脚点深度排序；地图地面使用统一低对比材质，预警仍由真实判定范围绘制。

这是一组可玩的美术样板，不代表所有怪物和地图已完成替换。图像生成负责造型参考与地面纹理，Blender负责模型、关节动作和固定相机渲染，Godot负责精灵显示与遮挡。未使用外部付费网格服务，也不依赖其账号。

## 选择依据

- 同一个三维模型渲染八个方向，能固定服饰、武器侧别、比例与动作时序，避免逐帧生成的身份漂移
- 复用既有二维战斗，避免一次迁移碰撞、投射物、技能判定、地图和存档
- 共享图集与材质，不为每只怪建立三维视口或独立动画播放器
- 经典魔法冒险风：石、木、皮革、旧银与少量琥珀色魔法；主光温暖、阴影可读，无科技光环

## 制作规格

- 本地工具：Blender 4.3.2、Godot 4.6.3
- Blender固定正交相机，俯角55度；左上主光、柔和环境补光；Cycles CPU，无去噪器依赖
- 人物/怪物帧128×192，8方向。方向依次为东、东南、南、西南、西、西北、北、东北
- 每方向idle4帧、walk8帧、attack6帧。图集16列、9行，帧索引为方向×18＋动作偏移＋帧号；偏移0、4、12
- 动画12帧/秒，实际位移照原逻辑同步。冻结、暂停和低动态设置只影响表现，不以动画触发伤害
- 每种资产使用自己的真实锚点和透明边界，禁止用不一致锚点补偿裁切
- 地景按原碰撞脚印建模，纵深投影补偿；长墙分段，树只放在原障碍内或场外，不引入假碰撞
- 原始建模文件与脚本保留，运行时只加载PNG与清单。原始模型目录应忽略Godot自动导入

## 工具调研结论与备选

Meshy和Tripo具备生成网格与自动绑定能力，但输出仍需要检查拓扑、权重、动作、穿模与授权。没有把“自动生成网格”视为“完整可用角色”。本轮已有本地Blender，先避免增加账号、订阅或外部上传依赖。

直接AI生成多方向二维精灵是备用路线，适合静态高细节资产，但跨方向/跨动作一致性需逐帧检查。PixelLab有专门多方向工具，偏像素美术，不是当前首选。图像参考的质量不代表程序式三维模型已达到同等高模细节。

## 官方参考

- Blender命令行渲染：https://docs.blender.org/manual/en/5.1/advanced/command_line/render.html
- Godot二维精灵动画：https://docs.godotengine.org/en/stable/tutorials/2d/2d_sprite_animation.html
- Godot Y排序：https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-y-sort-enabled
- Godot透明混合性能：https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html#transparency-and-blending
- Godot二维灯光阴影限制：https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html
- Meshy自动绑定：https://docs.meshy.ai/en/webapp/guides/3d-model/rigging
- Meshy API绑定边界：https://docs.meshy.ai/en/api/rigging
- Tripo绑定API：https://developers.tripo3d.ai/en/docs/animations-rig
- PixelLab八方向工具：https://www.pixellab.ai/docs/tools/create-8-rotations-pro
- OpenAI图像生成一致性限制：https://developers.openai.com/api/docs/guides/image-generation#limitations

调研日期：2026-10-07。未购买、注册或上传项目到上述第三方生成服务。
