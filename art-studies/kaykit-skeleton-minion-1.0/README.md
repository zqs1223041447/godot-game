# KayKit Skeletons 1.0：单模型源归档

当前跟踪范围仅保留作者`LICENSE.txt`和下载溯源清单，不再跟踪原GLB/texture。已存在的本地原字节保留并忽略；没有重写历史。复现脚本必须显式传入外部`--source-dir`，缺文件会说明固定官方来源，不自动下载或运行作者脚本。未下载整套角色包，未混用1.1。校验与固定原文件URL见[source-manifest.json](source/source-manifest.json)。

- 官方仓库：[KayKit Character Pack Skeletons 1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0/tree/15b62b9bad122f72926c10fb14d622c73819fa54)
- 固定提交：`15b62b9bad122f72926c10fb14d622c73819fa54`
- 模型：4,814,296字节，Git blob `3b7e7ee4f1c8dd6dd99ddad27824ef1dc52ff12d`，SHA256 `6ffc003f895bed0b074791e0e490846210a2e2f8fc7da300aba53cc185f95968`
- 作者：Kay Lousberg；随包[原许可证](source/LICENSE.txt)明确CC0，允许个人、教育和商业使用。我们保留作者署名和完整许可证。

上级`art-studies/.gdignore`隔离原始研究文件，不自动注册模型到游戏。模型内95个动画条目、41骨骼蒙皮、9个蒙皮网格已实际解析；Idle、Walking_D_Skeletons、Unarmed_Melee_Attack_Punch_A进一步通过曲线变化及Blender多时点实际顶点变形核验。未声称全部95条均可直接用于本游戏。

[三方向小样、固定头部适配与后续最小接入方案](../../docs/qa/kaykit-skeleton-minion/README.md)。
