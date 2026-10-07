# 3件独立环境模块 / Godot拼装小样

仅使用已取得的真实模型和既有Blender渲染：短墙、可通行拱门、苔岩。不是AI概念图，也不是原场景裁图。此次没有新增下载，没有修改冻结的v108/v109。本目录现为独立研究分支中的源码备份，主游戏保持原样。

## 打开与核对

- 原生Godot：`./run.sh`。F1显示碰撞与公共脚点，F2切换地面，Esc退出
- 原生截图：`./run.sh --capture=/absolute/path/native.png`。需要图形Display；截图来自实际Godot viewport
- 无窗口物理检查：`./run.sh --qa`
- `qa/native-window.png`：2026-10-07 17:30 UTC实际Godot窗口截图，保留窗口比例/黑边；实际观察已检查默认纹理地面与F2纯色底，未见方形旧地面底色或白边，独立投影可见
- `qa/assembly.png`：真实透明PNG按契约拼装的技术合成图，非游戏截图
- `qa/assembly-neutral-ground.png`：完全相同的模块与脚点，换成纯色地面，核对无旧地面底色
- `qa/assembly-collision-check.png`：4块碰撞轮廓、共同脚点、门洞通行线
- `qa/module-contact-sheet.png`：3件在棋盘底上的独立精灵与地面投影

## 最小运行契约

1. 相机固定55°正交，原27m视宽、原太阳方向与物件朝向。只支持水平z=0地面的XY平移；不能直接旋转、镜像、变高程或放到斜坡
2. 每件精灵、投影、门槛共享同一物理脚点。PNG分别裁边，但完整渲染脚点均为 `[640,360]`。每层设置 `centered=false`、`offset=-foot_local_pixel`，父节点位置就是实例脚点
3. 绘制顺序：地面 → 所有投影 → 门槛地面层 → 按脚点Y排序的立体物件。门槛与门框同脚点，禁止当作独立障碍或抬到角色上方
4. 本小样直接使用源像素坐标，1源像素=1 Godot单位，不设Camera2D缩放；碰撞读取 `foot_relative_screen_pixel`。如接入原0.65镜头，精灵比例用 `1/0.65`，碰撞改读 `godot_local_world`，不要重复应用原模型变换
5. x/y地面投影密度约47.4074/38.8339 px/m；0.30m圆形角色在像素空间是半轴14.2222/11.6502px的椭圆，不是同半径屏幕圆
6. 原生小样仅装配3个实例。`exports/assembly-layout.json`存放平移与同一整数脚点；所有层一起取整，最大误差不足0.5源像素

## 碰撞与门洞

- 短墙1块、拱门2块独立腿、苔岩1块保守凸轮廓，共4块，来自真实规范化网格
- 拱门导出的腿间净宽约2.576m；半径0.30m角色剩余中心通道约1.976m
- 门槛为独立可通行地面细节。真实最高高度约0.15008m；2D控制器视为平地，3D控制器需至少0.151m台阶能力或等效坡道
- Godot 4.6.3原生PhysicsServer2D实测：四块阻挡体均命中；保守64边投影椭圆沿门洞正反连续扫掠安全比例均1.0，201个采样姿态均无碰撞
- 真实网格验证另外覆盖1.8m身高和门楣净空。Godot测试只是2D碰撞，不代表动画、3D跨阶或主游戏集成已通过

## 投影及限制

- 投影是每件物件的独立透明中性黑贴花。没有原邻居、旧地面颜色或整场景遮挡；保留物件自身烘焙受光/自阴影
- 初始Cycles阴影捕捉PNG存在1/255灰RGB及低alpha背景。原始3张已完整保存在 `source/raw-shadow-renders/`
- `source/prepare_sample.py`可重复执行：RGB明确置0；按原PNG边框最大alpha+1去除低强度底噪并归一化，短墙12/255、拱门17/255、岩石5/255。裁框、脚点、方向不变，半影主体保留；低于阈值的弱广域半影会被舍弃。逐文件公式、原始哈希保存在manifest
- 这是水平地面固定光下的贴花近似。不是动态光照；不生成物件互投影；叠加阴影可能过暗；换不同地面时不模拟彩色间接反射
- 大物件和新增角色的遮挡可能仍需分层/多个排序锚点。此小样没有引入角色素材，也不替代角色阴影工作
- 原始轮廓边缘已有抗锯齿；推荐线性过滤、保持既定比例，不做像素风最近邻放大

## 复现与证据

现有渲染日志正常结束于 `ALL_MODULE_EXPORTS_COMPLETE`。接续工作没有重复Blender渲染。

```sh
/usr/bin/python3 source/prepare_sample.py
./run.sh --qa
```

准备脚本需要现成的Pillow、NumPy、GDAL/GEOS，标注图使用系统字体 `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`；碰撞工具还需要SciPy。物理小样仅需Godot 4.x，既有验证为4.6.3。`prepare_sample.py`始终从保留的原始阴影生成，重复执行不会累积去alpha。未来如重新渲染，先把本轮 `source/raw-shadow-renders` 改名保留，再运行现有 `source/render_modules.py` 与上述准备脚本，让新一轮原始阴影另建备份。`source/modules.blend`已打包纹理；应保持关闭自动执行脚本。

检查记录：`qa/export-verification.json`、`qa/godot-physics-verification.json`、`qa/native-visual-review.json`、`source/collision-work/independent-verification.json`。原生窗口截图与技术合成图分别标注。当前原生观察不等于角色遮挡、动画或整张地图已通过。

许可与来源见 `SOURCES.md`。本目录的运行小样与导出数据可独立备份；无需改动原v108/v109。

## 归档可搬迁边界

独立入口为本目录的 `project.godot` / `sample.tscn`。主游戏由上层 `art-studies/.gdignore` 隔离；打开本项目即可运行，不需要主游戏导入缓存。`qa/assembly-ground.png` 是运行所需地面资源，虽然位于qa仍必须保留。

- Godot运行、已有PNG阴影处理以及使用 `source/modules.blend` 重新渲染/提取规范化网格均只读本包相对路径输入；不需要复制v108的43MB整场景。重新渲染须有Blender，使用 `--disable-autoexec`；备份原导出后在工作副本执行
- `source/setup_modules.py` 是从原v108场景重新生成规范化三件模型的历史配方，依赖本包同级原目录 `v108-professional-environment` 的场景及 `exports/collision-work/gate-threshold-polygon-indices.json`，并会重新保存模型/导出。紧凑归档未附这些祖先大文件，现成小样无需运行它
- `source/collision-work/verify_collisions.py` 的用途是再次比较祖先网格身份，除本包还需要同级原v108目录中的场景、`actual-meshes-metadata.json` 和 `actual-meshes.npz`（后两者位于 `exports/collision-work`）。因此它不是本紧凑包单独即可执行的复验命令。原已通过报告保留
- `source/module-definitions.json` 中的绝对 `source_scene` 仅为历史出处，运行与重渲染不读取该路径；该文件与碰撞记录有哈希绑定，未改写它
- 运行小样（含原生查看）会写 `qa/godot-physics-verification.json`。处理脚本也会更新PNG/manifest/标注图和QA记录；复验请在工作副本执行，以保留本次原始证据
- `qa/package-sha256.json` 是原工作目录54项历史清单。归档有意排除1项Python字节码缓存，并补可搬迁说明/来源记录；当前文件以 `qa/archive-sha256.json` 为准。保留三张原始阴影和三张处理后阴影，没有重复复制祖先模型或素材ZIP

本次归档只核对字节、路径与脚本语法，复用已有四阻挡/201门洞姿态及17:30原生观察；未重跑完整测试、Blender渲染或新截图，也没有导出程序/创建Release。截图仍是无角色模块小样，不代表主游戏接入通过。
