# 独立遭遇选择控件

> 当前状态：v0.17已接入暂停选择与真实根/子怪入场，规则和新验收见[本轮挑战接入](ENCOUNTER_INTEGRATION.zh-CN.md)。下文保留独立组件的历史交付边界；当时的“未接入”不是当前版本状态。

基于 `encounter_catalog` / `encounter_compiler` 最终提交 `9f553d68277b88b1bde18e5b4fc2d3333a17bde1` 和当前 `VisualTheme`。仅新增本说明、`scripts/ui/encounter_controls.gd`、`tests/encounter_controls_test.gd`。

`EncounterControls` 是可嵌入的 `PanelContainer`，可供后续挑战入口使用。**尚未放入主场景或现有 UI，也未开放可玩的挑战遭遇。** 主集成后续决定放置位置；本任务没有整页、地图、奖励或新游戏架构。

## 使用接口

```gdscript
const EncounterChoices = preload("res://scripts/ui/encounter_controls.gd")

var choices = EncounterChoices.new()
choices.set_context([]) # 无选择表示普通遭遇。
choices.font_scale = 1.2 # 支持现有 100% / 120% 字体设置。
choices.encounter_requested.connect(_on_encounter_requested)
existing_container.add_child(choices) # 放置位置由后续主集成决定。

# 运行状态由上层掌握，同时禁止勾选和确认，并原样显示原因。
choices.set_context(selected_ids, "遭遇进行中，结束后才能确认新的挑战选择。")
# 解除限制时，上层重新传入合法 ID 和空原因。
choices.set_context(selected_ids, "")

func _on_encounter_requested(ids_copy: Array[String]) -> void:
    # 本示例只接收请求。主集成须另行验证当前遭遇准入和 compiler profile。
    print(ids_copy)
```

| 接口 | 契约 |
| --- | --- |
| `set_context(selected_ids, disabled_reason = "") -> bool` | 可在入树前调用；先深复制数组，再交由实际 compiler 校验。成功保存排序后的独立 ID；返回值表示选择合法性，上层禁用原因单独生效。 |
| `get_selected_ids() -> Array[String]` | 每次返回新副本，调用方修改它不会影响控件。 |
| `encounter_requested(ids_copy: Array[String])` | 每次有效确认只发一次信号，发送排序后的新副本。不会自动锁定、清空选择或启动遭遇。 |
| `font_scale` | 通过现有 `VisualTheme.apply_font_scale` 缩放，刷新选择后保留大小，切回 100% 不累积放大。 |

允许空选择、任意单选和两个不同挑战。最大数量、未知/重复/类型错误全部由 compiler 的目录规则判定，不维护第二套白名单。非法输入返回 `false`，清除内部草稿，显示 compiler 原始错误并锁住所有操作，直到上层提供新的合法 context；不能把非法输入当作普通遭遇提交。若同时存在上层原因，两个原因均保留。手动发出 disabled 按钮的 `pressed` / `toggled` 信号同样受到检查。

副本保护覆盖输入、getter、不同点击和控件内部选择。Godot 同一次信号发射的多个订阅者仍收到同一事件数组；需要私有长期存储的订阅者应自行复制。订阅者可同步调用 `set_context` 传入运行锁，后续点击立即受其约束。

## 同源显示及边界

勾选项的身份和名称来自 `EncounterCatalog.metadata().definitions`；描述、百分比风险值来自对应单挑战的真实 `Compiler.compile([id]).profile`。当前选择的生命和移动速度预览直接格式化 compiler 的 `profile.multipliers`。百分比只把 compiler 的 `relative_increase` 换成显示单位，没有重写倍率或怪物结算公式。

目录当前两项为强健与迅行，具体数值由目录维护。本控件没有另一份数值表。风险按 `parameter_only` 表达，实战难度尚未评估，不生成合并难度分数，也不宣称额外奖励。

控件只持有 UI 草稿与上层原因，不引用 main、BuildState、MonsterRuntime、存档或 RNG；确认只调用纯 compiler 并发信号。生命/护盾政策、根怪与子怪接点仍以 [遭遇编译器契约](ENCOUNTER_MODIFIERS.zh-CN.md) 为准。游戏状态、准入、存档、奖励与冻结 profile 的生命周期由后续主集成处理。

样式复用现有纸面、墨色、旧金属边框、按钮材料及字体；两个勾选项垂直排列，说明自动换行，控件高度由内容决定。可直接嵌入宽度 220 或 280 的容器。固定高度较小的宿主应沿用其现有滚动容器。

## 独立验收

入口未加入 `tools/validate.sh`，避免修改本任务范围外文件。Linux 仓库根目录执行：

```bash
set -euo pipefail
CONTROLS_TEST_DIR="$(mktemp -d /tmp/godot-controls.XXXXXX)"
export XDG_DATA_HOME="$CONTROLS_TEST_DIR/data"
export XDG_CONFIG_HOME="$CONTROLS_TEST_DIR/config"
export XDG_CACHE_HOME="$CONTROLS_TEST_DIR/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"
godot --headless --path . --editor --import 2>&1 | tee "$CONTROLS_TEST_DIR/import.log"
godot --headless --path . --script res://tests/encounter_controls_test.gd 2>&1 | tee "$CONTROLS_TEST_DIR/controls.log"
if rg -n '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$CONTROLS_TEST_DIR"/*.log; then
    exit 1
fi
```

必须同时检查退出码、最终断言摘要和日志，因为 Godot 脚本错误可能不产生非零退出码。测试中的真实构筑/存档 fixture 只写临时 XDG 目录，不使用用户存档。

覆盖空/单/双选择、逆序标准化、非法类型/未知/重复/超量、上层禁用及强制回调、输入与事件副本、逐次确认、viewport 鼠标/键盘输入与按键重复、按下到释放之间的 context 更新、同源名称/描述/风险/预览、真实存档字节/构筑/RNG 保持，以及 220/280 宽度 × 100/120% 字体下可见子控件的边界与完整换行。

项目导入会生成 `.godot/` 缓存和 UID sidecar；提交仅保留授权的三个文件，以 `res://` 路径加载。Windows 实机、长期耐久及主流程集成不属于此次独立控件验收。

## 本次执行记录与集成待办

Linux 云 checkout，Godot `4.6.3.stable.official.7d41c59c4`。仓库及可读父目录未发现 `AGENTS.md` 或本地 skills；使用独立分支与从基线导出的临时项目，缓存、存档与截图均留在临时目录。

独立控件验收：`673 checks, 0 failures`；原 encounter compiler：`5145 checks, 0 failures`；现有 `grimoire_ui_test`：`71 checks, 0 failures`；`material_frame_test`：`158 checks, 0 failures`。最终导入及这些测试的退出码均为 0，日志无 `SCRIPT ERROR` / `ERROR`。未运行 600 秒全量回归。

另外以 Linux X11 / OpenGL Compatibility / llvmpipe 实际渲染四种宽度和字体组合，检查普通、单选、双选及长禁用原因，文案完整显示且未横向裁切。此检查使用系统中文字体回退。

**随包字体待办：** 当前 `assets/fonts/arena_sans.otf` 子集缺少“健、参、层、评、遇、遭、险、难、集”等本控件/目录新增用字。Linux 可用系统 Noto CJK 回退显示；没有系统中文字体的环境仍可能缺字。按仅新增三个文件的范围，没有修改既有字体。主集成需使用现有 `tools/subset_font.py` 将新文案补进随包字体，再验收 Windows/无系统字体环境；本分支不能据此宣称跨平台文字已验收。

未合并 main/release，未接入主流程，未购买或重置额度，未派模型子代理。模型/推理/Fast 的实际运行档位没有工具遥测可核验。

## 2026-10-02 独立复核

固定基线 `48b929b528b5879c779712ab82814c535993b9a1`，独立分支 `codex/encounter-controls-review-20261002`。未发现需修改控件实现的问题；仅补上述键盘激活和中途 context 更新的测试缺口，并记录结果。

新增检查：空格勾选只改变草稿；空格/回车每次完整激活均只发一个请求，按键重复不多发；运行锁阻断键盘确认；按下后替换 context，释放时仅提交最新 ID 或普通空选择；按下后设置运行锁/非法 ID 不得提交陈旧选择；显式恢复后可提交空选择。原鼠标检查新增首次点击恰好一个事件的断言。

Godot `4.6.3.stable.official.7d41c59c4`，独立临时项目与 XDG 存档目录：基线控件 `673 checks, 0 failures`；补充后控件 `695 checks, 0 failures`；真实 encounter compiler `5145 checks, 0 failures`。导入及各测试退出码均为 0，日志无 `SCRIPT ERROR` / `ERROR`。220/280 × 100/120% 的边界/换行断言随控件测试复核通过；实际图形渲染沿用上节原执行记录，本轮未重跑截图。既有 grimoire/material 测试未重跑，未运行 600 秒全量回归。

未更改控件实现、main、catalog、compiler 或 UI 布局体系，未合并主游戏。随包字体缺字仍由另一个任务处理，本轮不修改字体，也不扩大跨平台验收结论。
