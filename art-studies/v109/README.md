# v109 可行走环境与遮挡研究

独立研究分支基于v108提交fc2cdbb，不含v106，也没有合入main或替换正式地图。主项目继续由父目录`.gdignore`隔离本研究。

## 运行

使用Godot4.6.3，首次用编辑器打开 `godot_preview/project.godot` 并完成资源导入；随后运行主场景，或在 `godot_preview` 目录执行 `bash run.sh`。Windows直接使用编辑器，无需符号链接。

WASD/方向键移动，R复位，F1切换诊断，Esc退出。此版本为1280×720固定单屏：人物按方向切换8张静态idle图，没有跑动或攻击动画，不存在正式游戏伤害、奖励或存档流程。

## 已完成的有限验证

原样板已通过 [27项headless检查](godot_preview/qa/headless-verification.json) 和 [74项资产检查](godot_preview/qa/asset-verification.json)，原通过日志和交接记录保留。归档未重跑这两套。

原生Godot窗口实际通过D/W移动到拱门后，诊断脚点(727.8,174.6)，人物被门正确遮住；按S返回门前后重新可见。见 [观察记录](verification/native-observation.json)。该观察不代表完整动画、全地图、Windows实机或FPS验收。

## 资源与源映射

- 原30层PNG与runtime-manifest保留原字节：28层可见，2层完全被遮挡；20对象/21碰撞多边形按原screen_pixel坐标直接使用，拱门保留两条墙腿
- [专业模型及材质来源](godot_preview/assets/environment/SOURCES.md)为已核CC0资产；原场景和下载出处沿用祖先中的 [v108自包含blend](../v108/environment/sunlit-ruins-environment.blend)，没有重复复制blend、zip或原下载素材集
- 人物仍为同一AI生成静态母图，当前方向区域与脚点见 [人物记录](character-provenance.json)，不是三维角色或动作交付
- 独立项目保留普通文件以兼容Windows；人物图和字体与v108逐字相同，Git使用同一个blob，不新增重复的大对象。字体另附 [SIL OFL许可](godot_preview/assets/OFL-NotoSansCJK.txt)

环境的固定阴影和物件互遮挡已经烘焙，不能任意移动或删除原物件。片内细枝交错仍是近似，人物生成方向/造型一致性未在此验收；本项目不宣称最终美术认可。

## 归档与复验边界

运行脚本、主场景、物理参数与原headless检查脚本均保原字节；仅资产复验脚本的原目录查询改为冻结输入SHA，并支持可选原源目录，报告默认写到新文件。原已执行脚本另存于 `godot_preview/qa/original-test-sources`，未更改74项判定规则。

原qa/input-sha256.json包含修正前的Grass Bermuda署名文件SHA，原handoff.json记录原生观察前的pending状态；这两份历史证据原样保留。归档已补OFL和下载审计，署名沿v108官方复核版本；当前文件以 [归档清单](verification/archive-manifest.json) 和 [复制/引用核对](verification/archive-verification.json) 为准。

未打包Windows程序、未建Release、未重渲染素材或执行长测。
