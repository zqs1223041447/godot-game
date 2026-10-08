# v121 Female Ranger 静态质量样板

已完成独立3D衣装装配、一个手工静态预备姿、一轮肩内衬修整与对应尺度复验。**不是走动动画，不是游戏内截图，未接入正式游戏。**

## 先看这两张

- [质量图：1200 × 1200](renders/ranger-quality.png)：55°俯角，与环境同灯光/色彩管理，仅放大观察
- [原尺度对照图：1680 × 800](renders/ranger-actual-scale-comparison.png)：左侧环境保持1280 × 720源像素，角色仅整数平移，未放大；右侧是4倍最近邻细节
- 最终Blender工作文件仅本地保留，**本仓库不含blend或原始模型/纹理**。复现需自行取得并校验[SOURCES所列外部原包](SOURCES.md)，见[复现说明](REPRODUCE.md)

## 装配与尺度

Female Ranger衣装 + Female Base的头/颈、眼与眉 + BuzzedFemale短发。未恢复衣服下面的整具Base。三具保留骨架均为相同的65骨结构，源rest矩阵逐骨最大误差0；当前头与衣装姿态矩阵误差约1.79e-7。原皮肤权重、骨架和衣装网格不变。

静置体高归一为1.80m，55°正交，横向视域27m、源图1280 × 720，47.4074像素/米。1.8m竖直标尺投影48.95px；受身体深度与姿态影响，实际几何轮廓约29.90 × 61.62px，带抗锯齿alpha外框32 × 64px。不能把“约49px”当作整个姿态的包围框高度。

暖阳、冷色大面积补光、天空环境和AgX设置取自冻结环境文件，见[环境参数](reports/environment-settings.json)。质量图与尺度图没有改换透视或灯光。

## 肩部本轮修整

新增唯一对象 `Static_Shoulder_Lining_Bridge`，133顶点、108四边面，0.7mm内衬厚度，橄榄色哑光布料。它在胸衣边与肩甲抬起的内沿之间形成一个小型弧面，不移动肩甲、不改原衣装顶点、不改骨架或权重。

这是**当前静态姿态专用、未蒙皮的内衬**。不能称为动画肩部已修好。后续v122如使用，需重新设计其随骨骼运动的绑定，并验证极端姿态。

- [局部修整报告与19对世界坐标锚点](reports/shoulder-correction-report.json)
- [v122接入说明](HANDOFF-v122.md)
- [修整前质量图](reports/ranger-quality-before-shoulder.png) / [修整后肩部放大](reports/shoulder-after-inspection.png)

原稀疏射线主要命中深陷上臂/肩甲内面；扩大采样后还发现少量真开缝。本轮内衬改善中央开缝与黑色断裂感。最终范围内143条射线中，中央段未命中数为0，位于最上/最下端边界的6条射线仍未命中角色表面；**没有宣称整个肩部封闭或网格水密**。见[最终复验](reports/final-sample-verification.json)。13件原角色网格及三具骨架/姿态/权重的保存后签名与修整前一致。

## 动画证据更正

包内名为 `Jog_Fwd_Loop` 的片段虽然有195通道、每通道29采样、1.1666667秒时间范围，但实际BIN中所有通道分量变化范围都是0。它是重复的恒定T-pose，不能用于运动验证。工作文件保留的同名来源Action仅供查看，未赋给任何角色骨架。

- [原ZIP/BIN直接检查](reports/source-jog-constant-channel-verification.json)
- [源BIN哈希一致的工作副本复查](reports/source-jog-working-copy-recheck.json)
- 上游角色源检查文档已经添加醒目更正，原元数据JSON保留
- 旧53骨UAL未用于本样板；真实UAL动作接入属于后续独立工作

## 已验证与限制

- 短发对兜帽的双向边/三角形静态交叉检测均为0；所保留颈切口120个采样点在当前视向及8个55°方位均被衣装遮挡
- 头颈与兜帽有隐藏的局部交叠，未将“不可见”说成“没有交叠”；这是单姿态数值检查，不是连续动画/全姿态认证
- 原尺度图是独立角色与投影阴影的技术合成；阴影为平地近似，未处理邻近建筑遮挡、动态重照明或引擎内比例验证
- 仅一个方向、一个静态姿态；没有八方向/逐帧动作、武器、魔法效果、运行时控制器或Godot导入验证
- 原ZIP、冻结环境与正式游戏未改写；本目录仅备份脚本、效果图、报告、来源许可摘要与精确哈希，未公开发布原始素材

## 复现与来源

见 [REPRODUCE.md](REPRODUCE.md)、[SOURCES.md](SOURCES.md) 和 [SHA256SUMS.txt](SHA256SUMS.txt)。

## 备份边界

[DELIVERY-MANIFEST.json](DELIVERY-MANIFEST.json) 将文件分为备份内容、外部必需输入和仅本地保留三组。本目录位于独立分支 `codex/v121-ranger-sample` 的 `art-studies/v121`，基于 `1602cbd055a58968a65c5851574d20173f715b50`；保留上层 `art-studies/.gdignore`，不参与Godot资源导入。本次仅归档40个内容文件与4个归档元数据文件，未改运行游戏、冻结图或模型，未创建PR或Windows导出。局部 `.gitattributes` 防止Git转换两份原许可文本的换行，以保留其精确SHA。

最终blend、work_sources、原ZIP、原模型/纹理及仅本地哈希清单均不在仓库内。所有已归档文件（除哈希清单自身）均列于 [SHA256SUMS.txt](SHA256SUMS.txt)，完整文件白名单见 [PUBLIC-BACKUP-FILES.txt](PUBLIC-BACKUP-FILES.txt)。历史技术报告原字节保留，其中绝对路径表示原验证环境，不表示仓库包含这些输入。仅文档、清单与3处脚本路径做了归档适配；本次未重渲染或重跑几何验证。
