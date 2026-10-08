# 来源与许可记录

## 角色来源

作者：Quaternius。以下是已批准并已取得的两个免费Standard原ZIP；本轮仅使用现有提取副本，没有新下载。两个包内 `License_Standard.txt` 均写明 CC0 1.0 Universal。

1. **Modular Character Outfits - Fantasy[Standard].zip**
   - 官方来源：https://quaternius.itch.io/modular-character-outfits-fantasy
   - 294,347,394 bytes
   - SHA-256：`c3468b18871cc8c8f05ab14df7712baf22cb9f389cbd870babf130e595187f70`
   - 使用：Female_Ranger衣装与纹理；Female_Peasant_Body仅用于恒定通道核查，未作为动作使用
2. **Universal Base Characters[Standard].zip**
   - 官方来源：https://quaternius.itch.io/universal-base-characters
   - 128,968,391 bytes
   - SHA-256：`fdbf1804c90dfc1ea03e992bff7da2dfd1a79318e13270a660180f9308455f40`
   - 使用：Superhero_Female_FullBody的头/颈、眼、眉；Hair_BuzzedFemale

原制作环境的原包位置为 `/workspace/shared/arpg_character_sources/`，不在此仓库中。复现时用 `V121_SOURCE_ARCHIVES` 指定自行取得的外部原包目录。本轮样板制作结束时两原包哈希与大小均重新核对通过，见 [original-archives-final-verification.json](reports/original-archives-final-verification.json)；本次归档保留该证据，不重跑素材处理。

精确许可另存为 `licenses/fantasy-License_Standard.txt` 和 `licenses/base-License_Standard.txt`，可供来源证据核对；包内许可与README也随仅本地的 `work_sources` 保留，逐文件来源/工作副本SHA见 [source-manifest.json](reports/source-manifest.json)。Female Base缺失的 `T_Eye_Normal_png.png` 引用仅在工作副本中指向现存 `T_Eye_Normal.png`；源检查另记录的male eye/hair两处同类修复也在副本中保留，但male资产未装入本样板。

## 许可范围说明

此处记录包内CC0声明，不把它扩写成原始素材公开再分发许可结论。先前来源检查同时记录作者通用QAL页面存在原始素材再分发限制，故保留精确原包、内置许可和来源记录；本任务没有公开上传或发布原始资产。

- CC0说明：https://creativecommons.org/publicdomain/zero/1.0/
- 作者通用许可页面：https://quaternius.com/license.html

## 环境与已有项目资产（只读）

- 灯光、色彩管理、相机参考：仓库既有 `art-studies/v111/source/modules.blend`
  - SHA-256：`2f6ffcd31cf04d2e347be087f111ead2e71968d2aab61a4a36cc1943a8fbb424`
- 原尺度技术合成背景：仓库既有 `art-studies/v118/qa/sparse-assembly.png`
  - SHA-256：`95a571895b67878e0a7084dbd0ae08046a1245910ffda059e68e7686895af4fe`
  - 合成前后背景哈希一致，见 [comparison-report.json](reports/comparison-report.json)

这些是项目既有文件，未作为新取得的CC0角色包内容，也未修改或重复拷入v121目录。此次归档不执行游戏项目或更新正式角色资源；历史报告中的绝对路径只记录原制作环境。

## 本地新增工作

手工静态预备姿、保留纹理的材质参数调整、头颈分件保留、局部静态肩内衬、自写安全导入/验证/渲染脚本和技术合成图。所有可见结果来自实际3D渲染，未把生成式图片冒充模型验证。
