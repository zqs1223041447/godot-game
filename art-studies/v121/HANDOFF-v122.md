# v122肩部接入说明

## 当前结论

v121只解决这一静态预备姿的视觉衔接。**新增内衬未蒙皮，动画肩部尚未解决。** 源65骨Jog名下没有运动；旧53骨UAL不在此样板内。后续动作应沿独立、已核实的真实动作来源处理。

## 可定位对象

- 对象：`Static_Shoulder_Lining_Bridge`
- Mesh：`Pose-specific shoulder gusset mesh`
- 父对象：`Ranger_Sample_Assembly`，不是Armature
- 133顶点、108四边面；无vertex groups/Armature modifier；仅0.7mm、向内的Solidify
- Material：`Sample olive shoulder lining`，roughness .90
- 精确world bounds、19对锚点与原几何签名：[shoulder-correction-report.json](reports/shoulder-correction-report.json)

锚点按画面肩顶到肩底排序。每行 `chest_world` 来自 `Female_Ranger_Body` 的评估后表面，`pauldron_world` 来自 `Female_Ranger_Acc_Pauldrons` 的评估后表面；对应屏幕坐标只用于识别采样位置，最终内衬是实际3D弧面，不是贴图遮盖。网格顶点存储在Assembly局部空间；world坐标不要直接当rest/bone-local坐标用。

## 后续必须做的事（本轮未执行）

1. 先确定真正的动画输入、骨架映射与rest-pose变换
2. 将肩内衬设计成适合运动的衣片或合并至衣装，选择可信的绑定与权重；不要把此静态world-space桥片直接拿去跑动作
3. 检查举臂、前后摆臂、躯干扭转，以及不同视向的肩甲/胸衣/内衬交叠、开缝和厚度
4. 确认许可与任务授权后再做动作/八方向/游戏内集成；本包没有这些成果

## 现存边界

中央肩缝射线采样已覆盖；上/下终端边缘仍有6条精确边缘射线未命中角色，未声明水密。修整没有改动13件原角色网格、三具65骨骨架或权重。短发与兜帽的零交叉和颈口遮挡结论也仅对应静态姿态。
