# v108 静态美术方向样板

这是新的质量/构图方向研究，保存在独立开发分支，不合main，不包含v106。正式游戏的地图、人物、玩法和存档没有修改。本样板不是最终美术认可，也未完成角色动作、碰撞或全地图集成。

## 谁制作了什么

- **专业环境资产**：Poly Haven发布的6类模型与3类地面材质，分别由Rico Cilliers、Rob Tuytel、Kless Gyzen等作者制作；精确资产/作者与CC0链接见 [环境来源](environment/SOURCES.md)
- **本次场景工作**：对已有专业模型进行选择、布置、局部改造，制作地形/材质混合、相机、灯光和最终1280×720渲染；不是声称专业模型由AI从零生成
- **人物**：OpenAI内置图像生成工具绘制的透明idle方向母图，原PNG原样保留。Godot仅取其中一块作静态比例/方向展示；它不是三维模型或已验收动画。见 [人物来源记录](character-provenance.json)
- **字体**：与主项目相同的Arena Sans SC字体子集，随附 [SIL OFL许可](godot_preview/assets/OFL-NotoSansCJK.txt)。本目录不统一宣称全部文件为CC0

## 打开独立Godot样板

使用Godot4.6.3。首次用编辑器打开 `godot_preview/project.godot` 完成资源导入，再从仓库根目录启动：

```sh
godot --path art-studies/v108/godot_preview --script res://preview.gd
```

本项目用SceneTree脚本启动，没有main_scene。父目录的`.gdignore`只使主游戏忽略研究材料；独立项目直接使用自己的 `project.godot`。本备份保留三份 `.import` 设置以重建mipmaps，但不复制 `.godot` 缓存、日志或机器状态。

静态预览的环境图是 [实际Blender渲染](godot_preview/assets/environment-final.png)，人物是 [AI透明母图](godot_preview/assets/hero_direction_study.png)。环境图只收一份；原研究文件名 `renders/sunlit-ruins-1280x720.png` 与此图SHA完全相同。

已于2026-10-07 14:43 UTC向用户展示Godot静态样板，说明动作尚未接入、正式地图未改。本轮归档复用该观察，不重复原生画面或渲染，不据此声明帧率或最终质量达标。

## 环境源与重渲染

[自包含场景](environment/sunlit-ruins-environment.blend)约43.4MB，40份图片全部打包、没有外链Library。模型与纹理源仅保存这一份；不重复加入79MBzip、38MB原下载素材集或`.blend1`。

可在Blender4.3.2直接打开该场景。若需要另渲染，请使用新的输出路径，例如从仓库根目录：

```sh
blender --background --disable-autoexec --threads 4 art-studies/v108/environment/sunlit-ruins-environment.blend --python art-studies/v108/environment/render_packed_scene.py -- --output /tmp/v108-rerender.png
```

该入口仅重设输出目录并渲染，不下载资产、不重建场景、不改写blend或已保存beauty图。本次备份没有运行这条命令。交互打开.blend后也应先选择自己的输出位置，避免沿用建模机的上次路径。不同Blender/渲染后端不保证相同PNG字节。

`environment/build_scene.py`保留原场景编排配方，它需要本轮省略的 `environment/assets/` glTF/纹理目录，不能直接当精简备份的一键重建入口。`select_tree_data.py`及两份小源metadata记录树的有界编辑方法；该脚本会联网取原始字节区间并写文件，不能当只读检查工具。本次没有执行它们，原下载URL/完整文件MD5或范围SHA均在下载审计中。

安全的 `environment/verify_scene.py`只读取场景并打印核验结果，可选`--report`写到另一个指定JSON；已移除原研究辅助脚本改写blend的调用。原 `verification-final.json`仍原字节保留。投影与比例见 [projection-godot.json](environment/projection-godot.json)。

## 证据与范围

- [来源核验](verification/source-audit.md)：官方许可/作者，直接解析.blend打包数据和外部依赖，原77项SHA校验
- [复制记录](verification/copied-source-records.json)：精简归档与原文件逐项对应。Grass Bermuda 01作者按官方页修正为Rico Cilliers，其余源内容保留
- `environment/delivery-file-checksums.json`是完整研究源的历史77项清单，包含本次未收的原下载集；本精简归档的实际文件应以 `verification/archive-manifest.json` 为准，不能把省略的历史文件当作归档丢失
- 树采用原始树干/树枝及12万叶片三角形的编辑子集；范围下载有独立SHA和Content-Range，不能冒称整份原始树buffer的MD5已验证

没有新游戏开发、全量测试、Windows导出、Release或分层资产导出。后续分层资源是独立工作，不是本静态样板的已有完成项。
