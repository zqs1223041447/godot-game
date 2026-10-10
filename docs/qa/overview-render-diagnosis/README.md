# 探索总览：渲染阶段有限诊断

生产基线 `9123d117995af72b87d145aa248cea198eeaa881`。**关闭总览也有高帧间隔；本轮没有证明静态图层重绘或字体是主因，没有修改生产绘制，也没有解决或宣称解决卡顿。** 本目录提交诊断代码和证据，供下一轮继续定位。

## 结果

以下均为每窗口8帧的墙钟中位数，单位ms。窗口按表中顺序执行，全部原始帧和峰值保留；不是足够长的性能保证。

| 窗口 | 总览模式 | 正常 Main/HUD | 冻结 Main/HUD |
|---|---|---:|---:|
| 0 | 关闭 | 104.607 | 92.155 |
| 1 | 完整 | 106.427 | 163.397 |
| 2 | 保留上次绘制命令，停止重绘回调 | 163.811 | 127.369 |
| 3 | 完整 | 124.500 | 159.498 |
| 4 | 去除总览文字 | 176.865 | 66.544 |
| 5 | 完整 | 143.191 | 65.899 |
| 6 | 总览打开但绘制回调直接返回 | 90.271 | 61.903 |
| 7 | 关闭 | 93.627 | 158.123 |

1. 本轮正常处理的关闭基准已为93.6–104.6ms，与此前开启约95–101ms处于同一数量级；不能把这整个间隔归因于总览。
2. 完整总览 `_draw` 正常处理窗口的中位耗时为249–281µs。保留命令窗口确实记录到 **0次** 总览绘制回调，帧间隔仍高。冻结 Main/HUD 后，Main处理计时为0，状态字节保持不变，依然慢且剧烈波动。没有证据支持通过拆分静态/动态图层解决主要间隔。
3. 冻结窗口4与5相邻且比较稳定，去字66.544ms，完整65.899ms；正常处理窗口也未显示去字收益。不能证明字体是主因。完全移除总览绘制后仍有61.903ms，也不能证明总览多边形提交是主因。
4. 冻结期间 `frame_pre_draw`→`frame_post_draw` 中位数与整帧间隔接近（例如完整窗口5为65.096/65.899ms，关闭窗口7为157.715/158.123ms）。视口渲染CPU/GPU计时同样为几十至百余ms。证据将大段时间定位在渲染执行/等待区间，但不能继续区分光栅化、驱动同步等待与宿主调度。
5. 有效cgroup测量的冻结8窗口仅第0窗口发生42µs节流，其余为0；单工作线程对照也全部为0。CPU配额节流无法解释这些采样窗口的几十至百余ms间隔。此结论不覆盖未成功读取cgroup的首轮，也不排除宿主调度竞争。
6. 追加一次 `LP_NUM_THREADS=1` 冻结对照，关闭/完整/完整/关闭中位数为229.124/163.523/162.413/156.720ms，没有观察到改善。不是严格相同冻结快照的跨进程比较，不能据此量化线程数因果效应，也不建议修改游戏启动配置。

剩余限制：这是Mesa llvmpipe软件渲染、X11 dummy环境，不是目标玩家GPU。Godot视口“GPU”计时在此代表软件渲染管线的计时，不能解释为独立物理GPU负载；CPU/GPU指标可能重叠且返回上一帧，不相加。驱动报告不支持修改VSync，虽然查询值为禁用，也不能据此排除所有显示同步。8帧样本的p95就是最大值，不适合推断尾部概率。需要可控图形环境与渲染器/驱动级跟踪才能进一步归因；本轮没有开展长矩阵。

## 方法、边界与原始记录

- Godot4.6.3，X11，1280×720，GL Compatibility，Mesa25.0.7 llvmpipe LLVM19.1.7。`Engine.max_fps=0`，低处理模式关闭。有效cgroup配额为400000/100000µs。Xorg配置保存在 `xorg.conf`。
- 复用既有正式银杏I入场及原37怪密集夹具。入场前和战斗前均设seed526917，运行时提高双方耐久、移动原怪物，不新增实体。三次初始敌人/玩家/RNG指纹均为 `281696ff4a3170f536d3cfcae30e86718a50a5bfe3611ca79e7c8948b1998404`，也匹配上一批有效初始夹具。
- 启动8个渲染帧暖机；每模式切换后5帧不采样，再采8帧。所有模式共用时钟钩子、渲染测量和观察器。记录在内存，采样窗口结束后才读cgroup，所有窗口结束才写报告。
- 冻结轮在8帧暖机后暂停Main/HUD。冻结点由渲染帧数决定，各进程暖机实际时间不同，因此 **不能声称跨进程冻结状态完全相同**。每个冻结进程内部已验证整轮敌人、时间、玩家、RNG与角色状态字节不变；打开完整/去字/空白模式时显式请求每帧重绘。
- `retained`、`no_text`、`empty` 只是消融诊断。保留旧命令会留下过期玩家位置/目标，绝不是可交付的游戏优化。
- `instrument.py` 复用上一批计时器，仅在 `/tmp/godot-overview-profile-src` 生成诊断副本；临时调用旧生成器后恢复旧 `instrumentation.json` 原字节。生产Main、HUD、总览的SHA在本目录 `instrumentation.json`，全部与基线相同。
- `default/`：正常处理，64采样帧，22检查/0失败。使用 `initial-probe.gd.txt`。首版以文件长度读cgroup伪文件得到空值，`cpu_delta={}`，**表示缺数据，不是零节流**。`cgroup-observed.txt` 是外部单点观察，不能充作窗口前后差值。
- `frozen/`：修正伪文件为逐行读取，64采样帧，22检查/0失败。
- `single-worker/`：相同窗口尺寸/渲染模式、冻结，进程局部 `LP_NUM_THREADS=1`，32采样帧，14检查/0失败。没有并行运行诊断进程。
- `summary.json` 由 `summarize.py` 从三份原始 `render.json` 生成。共160个诊断采样帧，每进程45秒上限。
- `live/`：另用未插桩生产场景执行已有 `overview_query_live_test.gd`，32检查/0失败，验证按住移动后的玩家位置/朝向标记、真实鼠标瞄准/发射、敌人击杀关闭总览、原生地图准备取消/重试/重开。本次功能短测自身也出现117–522ms等高间隔，结果全部保留；它不是同一计时夹具，**不并入上表，功能通过不表示性能通过**。没有改变玩家、目标、清图更新逻辑。

## 复核入口

在该基线或本证据提交上运行 `python3 docs/qa/overview-render-diagnosis/instrument.py`，然后设置已有X11显示、独立的新临时用户目录、已存在的独立输出目录：

```bash
mkdir -p /tmp/overview-render-review
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
XDG_DATA_HOME=/tmp/godot-overview-render-review \
XDG_CACHE_HOME=/tmp/godot-overview-render-cache \
OVERVIEW_OUTPUT=/tmp/overview-render-review \
timeout 45 godot --path . --rendering-method gl_compatibility \
  --audio-driver Dummy --script res://tests/overview_render_diagnosis_probe.gd
```

冻结增加 `OVERVIEW_RENDER_FROZEN=1`；单工作线程四窗口对照再加 `OVERVIEW_RENDER_CONTROL=1 LP_NUM_THREADS=1`。每次换新用户/输出目录，逐次运行，勿覆盖已保存证据。当前脚本包含伪文件修复及冻结支持；首轮原版另已冻结保存。`python3 docs/qa/overview-render-diagnosis/summarize.py` 仅重算统计，不启动游戏。

计时定义依据 [Godot4.6 RenderingServer文档](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html)；软件渲染与线程控制依据 [Mesa LLVMpipe](https://docs.mesa3d.org/drivers/llvmpipe.html) 和 [Mesa环境变量](https://docs.mesa3d.org/envvars.html)。渲染计数器仅作原始观察，不用其部分可见绘制调用计数反推全部2D字体成本。
