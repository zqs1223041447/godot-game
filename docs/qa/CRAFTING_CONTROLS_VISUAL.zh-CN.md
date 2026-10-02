# 制作控件真实渲染验收

**结果：不通过。** 2026-10-02 UTC，在非 headless Godot 窗口中完成 8 组渲染与 GUI 输入验收，保留 28 张原始 PNG。最终测试 **2604 项检查、16 项失败、退出码 1**；失败集中于焦点态浅色文字和长单行 tooltip 越界，两类问题各在 8 组组合中复现。没有把这些失败改成预期通过。

本轮后端为 **Linux / X11 / Mesa llvmpipe 软件渲染**，有实际绘制与像素读回；这份证据不能作为 Windows 硬件渲染验收。

## 输入与文件范围

| 输入 | 固定版本 |
| --- | --- |
| 控件与 Craft | `codex/crafting-controls-v013-desktop-fbrtnr7` / `c2e711bdcccaefbbfdcc7bb9e8dd41db5010287f` |
| 最新字体 | `codex/font-coverage-v014-20261002` / `0d8d19985ac8ca265059b78110d5bc2ef88a953b` |
| 本地组合基线 | `1d077d05691627806751d0ff81a32745c0867c50`，仅在独立 QA 分支合入两个既有输入 |
| 字体 SHA256 | `8c522b1e7139e8a5768e5e88ea6a74dbd64ec7dbf31f1a83ca005840cb50aeac`，337516 字节、890 个 cmap 映射 |
| 验收分支 | `codex/crafting-controls-visual-20261002` |

QA 提交相对于组合基线只新增 [测试脚本](../../tests/crafting_controls_visual_test.gd)、本文、`crafting-controls/.gdignore` 和该目录中的 28 张截图。仓库和上层工作目录未发现 `AGENTS.md` 或 `SKILL.md`。

`crafting_controls.gd`、`crafting_rules.gd` 与控件输入提交逐字节一致；`VisualTheme` 保持原样；`assets/fonts/*` 与 `InventoryPanel` 和字体输入提交一致。保留原有纸面纹理、棕色墨迹、按钮样式、一行三控件和字体导入设置。

## 环境与临时场景

- Godot：`4.6.3.stable.official.7d41c59c4`。
- X11：临时解包的 Xvfb 21.1.16，2560×1440×24 屏幕；未安装到系统目录。
- 渲染器：`gl_compatibility`，OpenGL 4.5，Mesa `25.0.7-2+deb13u1`，`llvmpipe (LLVM 19.1.7, 256 bits)`。
- 实际 `user://`：`/tmp/crafting-visual-run/data/godot/app_userdata/godot游戏仓`；XDG 数据、配置、缓存均隔离。
- 工程从固定基线归档至 `/tmp/crafting-visual-run/project`，只执行独立 `SceneTree` 脚本，不加载 `main.tscn`、BuildState 或真实存档。
- 物理窗口/截图分别为 1280×720 与 2560×1440，逻辑画布保持项目原有 1280×720 `canvas_items` stretch。2K 图片来自 2K viewport 的真实读回。
- tooltip 使用 Godot 原生 `PopupPanel` / `TooltipLabel`，在临时根窗口中嵌入，以便截图包含弹窗；没有实现自定义 tooltip 或添加换行、宽度修正。

临时卡片只是展示六份上下文的夹具，没有实例化或接入主 InventoryPanel。金色卡片边框标记夹具中的当前物品；实际选中焦点验收针对原控件的 `RecalibrateButton`。

装备为合法的 `gear_000123`：魔法白蜡长弓、16 物品等级、远织 T1、数值取真实目录下限。`Craft.salvage_quote()` 返回回收收益 **2 枚**，`Craft.recalibrate_plan(..., 20261002)` 返回校准成本 **4 枚**。没有虚构成功报价或显示计划中的随机结果。六种上下文为：

| 状态 | 输入与观察 |
| --- | --- |
| 选中 / 可用 | 余额 12345，真实有效报价，校准按钮获得焦点 |
| 穿戴中 / 禁用 | 上层原因“请先卸下穿戴中的装备。”，两个按钮均禁用 |
| 余额不足 | 余额 3，小于实际成本 4；回收可用、校准禁用 |
| 报价失败 | 合法普通无词缀实例，实际 Craft 拒绝，两个按钮均禁用 |
| 长原因 | 真实有效报价加上明确标注的上层长文本夹具，两个按钮禁用 |
| 极长余额 | `9223372036854775807`，行内省略，原生 tooltip 保留完整数值 |

## 两个可复现缺陷

### CCV-01：获得焦点的可用按钮变为浅色文字

触发：选择有效装备，给原 `RecalibrateButton` 调用 `grab_focus()`，将指针移到按钮外，再等待绘制。点击按钮后移走鼠标也会保留焦点，是应进一步在正式接入中核对的交互路径。

实际读到的 `font_focus_color` 是 `(0.95, 0.95, 0.95, 1)`，正常文字是 `#3b281b`，纸面基色为 `#f8ecd0`。相对亮度计算得到正常字色对基色 **11.89:1**，焦点字色仅 **1.05:1**。截图中金色焦点边框仍可见，但“校准”两字接近纸面颜色；100% 与 120%、720p 与 2K 都出现。

测试以有效主题颜色和纸面基色做小字对比诊断，并结合真实纹理截图观察，阈值取 [W3C 小字对比参考 4.5:1](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)。没有把禁用按钮纳入可用小字的对比断言。原主题没有设置 `font_focus_color`，运行时沿用 Godot 默认浅色；这是结合代码与有效主题取值作出的原因判断。

证据：[720p / 220 / 120%](crafting-controls/1280x720-w220-f120-matrix.png)、[2K / 220 / 120%](crafting-controls/2560x1440-w220-f120-matrix.png)。8 张状态矩阵左上角都能观察到此问题。

### CCV-02：长单行拒绝原因超出窗口，文字不可完整阅读

上层 `disabled_reason` 接受任意字符串。测试先调用真实 Craft 得到以下三条原因，以空格连接，再重复四次，得到 **187 字符**的单行聚合提示：

```text
普通无词缀装备不支持回收或数值校准。 装备实例未通过当前目录验证。 校准种子必须为整数类型。
```

这是上层聚合长文本的压力夹具，**不是 Craft 自己返回的单条原因**。没有修改 Craft 的成功报价、失败结果或控件。复现时将该字符串传入 `set_context()` 的最后一个参数，悬停禁用“校准”按钮，等候默认 tooltip 延迟。

实际原生弹窗边界为 **`position=(0,614), size=(2880,40)`**；可见逻辑画布为 1280×720。完整文本仍保存在原生 Label 中，但弹窗没有自动换行，右侧超出画布，截图和窗口中的后半段被裁切。2K 沿用原画布比例，同样越界。每个组合均保留失败断言。

证据：[720p 长单行](crafting-controls/1280x720-w220-f120-long-error.png)、[2K 长单行](crafting-controls/2560x1440-w220-f120-long-error.png)。对照：[显式三行原因](crafting-controls/1280x720-w220-f120-multiline-error.png)可完整显示，原生弹窗为 312×94，底边 708，在画布内。该对照不是对缺陷的修复。

## 布局、文字与鼠标结果

除上述两类失败，最终运行没有其它失败或脚本解析错误。

| 行宽 / 字号 | 实际行大小 | 余额 Label 可用宽 | 五位余额文本宽 |
| --- | --- | --- | --- |
| 220 / 100% | 220×28 | 124 | 91 |
| 220 / 120% | 220×29 | 124 | 112 |
| 280 / 100% | 280×28 | 184 | 91 |
| 280 / 120% | 280×29 | 184 | 112 |

两个物理分辨率下，上述逻辑尺寸相同。控件字号由 13 变为 16；三个子控件均在指定行宽内，没有重叠。人工检查 8 张状态矩阵，正常/禁用字形未出现方框或缺字。测试还直接查询实际 FontFile 的首个原生字体 RID，核对控件余额、按钮、长原因和校准说明中的中文具有原生字形；没有让系统字体回退冒充这些文字的覆盖。

原生 tooltip 均保持 **16 逻辑字号**，100% / 120% 都如此，这是现有 `TooltipLabel` 显式主题字号的实测行为。本轮没有声称 tooltip 随字体设置放大。

余额不足原生提示为“校准碎片不足：需要 4 枚，现有 3 枚。”，297×40；校准风险说明为 376×67；穿戴中禁用原因为 200×40；完整极长余额提示为 312×67。这些弹窗的全文和 Label 大小已实际核对，在被测位置没有裁切。

鼠标验收使用 `Window.warp_mouse()` 移动 X11 指针，使用 `Window.push_input(..., true)` 注入 GUI 按下/松开，经过真实窗口的 GUI 命中路由，没有直接发射按钮 `pressed` 信号。每组检查六行的两个按钮，实际悬停目标均是相应按钮；可用按钮的按下状态正确，每次点击只发一次携带原实例的请求。全部 **42 次允许请求**中包含两张按住按钮时的截图，截图前再次核对按钮确实处于按下状态。禁用按钮不发请求，拖出后松开取消动作；已弹出的 tooltip 没有挡住其悬停目标。

这证明独立夹具中的 GUI 命中与事件路由。物理鼠标设备、Windows 输入路径和主 InventoryPanel 集成的遮挡仍需在相应环境独立验收。

## 原始截图索引

PNG 为最终运行中直接 `Viewport.get_texture().get_image().save_png()` 的结果，共 **28 张、24582218 字节**，没有裁剪、拼图、重绘或后期缩放。证据目录的 `.gdignore` 防止这些图片进入游戏资源导入。

| 物理分辨率 | 行宽 | 字号 | 状态矩阵 / 焦点问题 | 长单行问题 |
| --- | --- | --- | --- | --- |
| 1280×720 | 220 | 100% | [矩阵](crafting-controls/1280x720-w220-f100-matrix.png) | [越界](crafting-controls/1280x720-w220-f100-long-error.png) |
| 1280×720 | 220 | 120% | [矩阵](crafting-controls/1280x720-w220-f120-matrix.png) | [越界](crafting-controls/1280x720-w220-f120-long-error.png) |
| 1280×720 | 280 | 100% | [矩阵](crafting-controls/1280x720-w280-f100-matrix.png) | [越界](crafting-controls/1280x720-w280-f100-long-error.png) |
| 1280×720 | 280 | 120% | [矩阵](crafting-controls/1280x720-w280-f120-matrix.png) | [越界](crafting-controls/1280x720-w280-f120-long-error.png) |
| 2560×1440 | 220 | 100% | [矩阵](crafting-controls/2560x1440-w220-f100-matrix.png) | [越界](crafting-controls/2560x1440-w220-f100-long-error.png) |
| 2560×1440 | 220 | 120% | [矩阵](crafting-controls/2560x1440-w220-f120-matrix.png) | [越界](crafting-controls/2560x1440-w220-f120-long-error.png) |
| 2560×1440 | 280 | 100% | [矩阵](crafting-controls/2560x1440-w280-f100-matrix.png) | [越界](crafting-controls/2560x1440-w280-f100-long-error.png) |
| 2560×1440 | 280 | 120% | [矩阵](crafting-controls/2560x1440-w280-f120-matrix.png) | [越界](crafting-controls/2560x1440-w280-f120-long-error.png) |

以下额外截图均为行宽 220、字号 120%：

| 场景 | 720p | 2K |
| --- | --- | --- |
| 余额不足提示 | [原图](crafting-controls/1280x720-w220-f120-insufficient.png) | [原图](crafting-controls/2560x1440-w220-f120-insufficient.png) |
| 实际成本与风险说明 | [原图](crafting-controls/1280x720-w220-f120-enabled-warning.png) | [原图](crafting-controls/2560x1440-w220-f120-enabled-warning.png) |
| 禁用提示 | [原图](crafting-controls/1280x720-w220-f120-disabled-equipped.png) | [原图](crafting-controls/2560x1440-w220-f120-disabled-equipped.png) |
| 完整极长余额 | [原图](crafting-controls/1280x720-w220-f120-full-balance.png) | [原图](crafting-controls/2560x1440-w220-f120-full-balance.png) |
| 显式多行错误对照 | [原图](crafting-controls/1280x720-w220-f120-multiline-error.png) | [原图](crafting-controls/2560x1440-w220-f120-multiline-error.png) |
| 原按钮按下状态 | [原图](crafting-controls/1280x720-w220-f120-pressed.png) | [原图](crafting-controls/2560x1440-w220-f120-pressed.png) |

## 重复执行

下面从已含 QA 提交的检出建立临时工程。使用已有的 X11 图形显示服务；本轮 `DISPLAY=:93`，其屏幕容纳 2K 窗口。

```bash
task_dir="$(mktemp -d /tmp/crafting-controls-visual.XXXXXX)"
mkdir -p "$task_dir/project" "$task_dir/data" "$task_dir/config" "$task_dir/cache" "$task_dir/output"
git archive HEAD | tar -xf - -C "$task_dir/project"
export XDG_DATA_HOME="$task_dir/data"
export XDG_CONFIG_HOME="$task_dir/config"
export XDG_CACHE_HOME="$task_dir/cache"
export GODOT_CRAFTING_TEST_ROOT="$task_dir"
godot --headless --path "$task_dir/project" --editor --import
LIBGL_ALWAYS_SOFTWARE=1 godot --audio-driver Dummy --path "$task_dir/project" \
  --script res://tests/crafting_controls_visual_test.gd -- --output "$task_dir/output"
```

导入可使用 headless；像素验收命令必须有图形显示服务。对照单组复现可追加 `--case 1280x720-w220-f120`。当前输入版本的完整渲染退出码应为 **1**，不能将其当作通过。`observations.json` 写在临时输出目录，记录实际布局、原生 popup 边界、字色和失败清单，不加入限定的仓库交付范围。

本轮最终运行记录：

| 检查 | 结果 |
| --- | --- |
| 工程导入 | 退出码 0，无脚本解析错误 |
| 原 `crafting_controls_test.gd` | 228 项检查、0 失败、退出码 0；这是契约检查 |
| 新真实渲染测试 | 2604 项检查、16 失败、42 请求、退出码 1 |
| headless 守卫 | 拒绝像素验收，退出码 2 |
| `user://` 隔离守卫 | 拒绝目录不匹配的运行，退出码 2 |

最终渲染日志只有上述 16 个验收错误，启动另有软件驱动不能切换 V-Sync 的警告。显式使用 `--audio-driver Dummy`，避免没有声卡的环境干扰视觉记录。最终日志与测量文件位于 `/tmp/crafting-visual-run/evidence-render.log` 和 `/tmp/crafting-visual-run/final-evidence/observations.json`。

本次没有运行 600 秒全量、制作发布包或修改 main/release。后续仍需在允许修改相关源文件的任务中处理 CCV-01/02，然后重新执行本测试；Windows 硬件与正式主面板集成验收尚未完成。
