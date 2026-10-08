# v125 Ranger 单方向步态研究归档

这是已制作导出资产的源码备份，**不是正式角色替换**。本目录的 `.gdignore` 将整个研究包隔离于 Godot 资源导入。

## 已存内容与验收边界

- 16张原始透明PNG，单一向右方向，128×192、2×像素密度；最终显示画布64×96
- 80% Walk＋20%真实Jog，按同侧支撑中点对齐；每循环16个独立相位，闭环终点不重复计入
- 原v123最终肩桥、13个原网格及其权重保留，root无位移；没有IK、逐帧抬地或动作平滑
- 已查看选定静态姿态/接触拼图。**连续动态脚感、完整游戏内运动及八方向均未验收**
- 几何零穿透未过：固定地面下最大穿透19.71mm，约0.536显示像素；较低一脚最大离地27.34mm，约0.743显示像素。亚像素误差与视觉接受度分别记录，不能称为完美足锁
- 横向47.4074074px/m、纵深38.8338747px/m、竖直27.1917718px/m。固定root锚点为源格(64,158)，不追踪最低alpha
- 拟合展示周期0.743682247s，地面相对移动156显示px/s。相位由表现时钟控制，不得改变游戏位移、移速、碰撞或战斗/CD事件

归档只复制已有产物，没有重渲染或修改动作。未包含原模型包、`.blend`、大日志、缓存、临时下载副本或对照Walk/Jog图片。正式运行时未修改。

## 文件

- `frames/candidate/00.png`–`15.png`：16张作者制作导出帧，与已有v125产物逐字节一致
- `reports/trial-metadata.json`：固定混合参数、相位偏移、源帧列表、周期、固定地面投影与明确验收状态
- `reports/contact-samples.json`：原97个连续相位诊断样本，含重复闭环端点；不是新增试验
- `reports/invariants.json`、`final-reload-check.json`：原网格/权重/rest骨架/动作曲线签名与隔离文件重读结果
- `reports/source-frame-hashes.json`：16张归档帧与已有v125源帧的SHA256对应
- `scripts/build_trial.py`、`finalize_trial.py`：原自写Blender流程的路径参数化归档版，只生成候选16帧
- `scripts/verify_archive.py`：只读归档校验，不渲染、导入或运行游戏
- `SOURCES.md`、`licenses/`：来源、许可证原文与上游包SHA256
- `MANIFEST.json`、`SHA256SUMS.txt`：文件清单及校验和

## 只读校验

在仓库根目录执行：

```sh
python art-studies/v125/scripts/verify_archive.py
cd art-studies/v125 && sha256sum -c SHA256SUMS.txt
```

校验使用Python标准库和Pillow；验证16张RGBA图、尺寸、帧哈希、相位表、许可证记录、脚本语法与禁收文件。不会执行Blender脚本或改变图片。

## 可复现条件

需要Blender4.3.2及已批准的本地v123/v124来源场景。原场景没有放入仓库；仅凭本包不能从零重新生成几何。脚本会验证输入场景SHA256，并要求仓库研究包外的输出目录。没有下载或安装步骤。

```sh
export V125_BASE_BLEND=/path/to/v123/ranger-game-clips.blend
export V125_JOG_BLEND=/path/to/v124/ranger-jog-probe.blend
export V125_OUTPUT_DIR=/path/to/separate/v125-rebuild
blender --background --disable-autoexec --threads 8 --python art-studies/v125/scripts/build_trial.py
blender --background --disable-autoexec --threads 4 --python art-studies/v125/scripts/finalize_trial.py
```

归档时没有执行上述渲染命令。路径参数化和仅导出候选帧属于打包调整，未改混合权重、相位、骨变换、相机、材质、采样或渲染参数。PNG包含渲染时间/文件元信息，重新渲染并不承诺得到相同文件字节；本包的字节一致性结论只指现有16张源帧与仓库归档副本。

## 后续接入边界

当前只有横向样本。八方向至少需要每方向的屏幕朝向、统一相位0、root锚点、实际显示密度和投影步距；最终相位应参考碰撞结算后的实际位移。当前数值不是已通过的八方向运行时配置。

16帧保持带来的离散步进是正常显示边界，不作为额外的逐显示帧绝对足锁门槛，也不能用连续姿态拟合残差宣称完整运行时已验收。
