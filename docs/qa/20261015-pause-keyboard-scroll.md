# 暂停菜单键盘焦点滚动回归（2026-10-15）

## 缺陷与修复边界

暂停菜单已经将遭遇选项嵌入 `PanelScroll`。原构造使用 Godot 默认的 `follow_focus=false`：真实 Tab 可以把焦点移至裁切区外的选项和确认按钮，滚动位置却停在 0。程序调用 `ensure_control_visible` 后点击成功，不能证明玩家的键盘导航可用。

本次只在 `scripts/game_hud.gd` 的窗口构造中设置 `scroll.follow_focus = panel_name in ["pause", "settings"]`。设置页的独立复现与验收见 `20261015-settings-keyboard-scroll.md`；其他面板保留默认行为，没有改变遭遇定义、玩法、保存、重开或确认逻辑。

## 新增验收

`tests/pause_keyboard_scroll_test.gd` 使用真实 `main.tscn`、Canonical 模型和正式的离镇练习入口。场景及 HUD 的战斗处理停用，UI 仍处理真实输入。

- 只建立一次起始焦点；随后通过 viewport 注入按下/释放 `InputEventKey`，顺序经过图鉴按钮、六个遭遇选项和确认按钮，再用 Shift+Tab 返回
- 每次验证实际焦点归属、排除可见滚动条后的内容裁切区和真实逻辑 viewport 内的完整按钮矩形；只允许 1 个逻辑像素的整型滚动/小数缩放舍入误差
- 验证正向实际向下滚动、反向实际向上滚动；包含前置图鉴按钮，以免正常比例下六个选项恰好已经同时可见而错误要求滚动
- 在键盘到达的位置注入真实鼠标事件，检查勾选/取消、打开重开确认及取消；未直接发出按钮 pressed 信号
- 验证除暂停和设置外的所有窗口仍然关闭跟随焦点
- 比较整个 Canonical build 快照、实际存在的正式保存字节及练习保存字节、运行修订、当前遭遇选择、场景 RNG 和全局 RNG
- 外部 `timeout 90`，脚本内部 75 秒兜底；必须使用新的 `/tmp/godot-*` XDG 目录，否则拒绝运行

## 覆盖与解释

窗口请求尺寸 1280×720、2560×1440，字体比例使用 `VisualSettings.FONT_SCALES` 的全部 1.0/1.1/1.2，UI 比例使用 `UI_SCALES` 的全部 0.9/1.0/1.1，共 18 组。每组断言逻辑 viewport 为 1280×720，并在日志报告 `root.get_visible_rect().size`；当前项目 `canvas_items` 拉伸下，两种窗口请求的真实逻辑 viewport 都是 1280×720。因此这不是两种不同逻辑分辨率或 Windows 原生画面验收。

## 可复现命令

```sh
xdg=$(mktemp -d /tmp/godot-pause-keyboard-XXXX)
XDG_DATA_HOME="$xdg/data" XDG_CONFIG_HOME="$xdg/config" XDG_CACHE_HOME="$xdg/cache" \
  timeout 90 godot --headless --path . --script tests/pause_keyboard_scroll_test.gd
```

负向对照使用另一个全新 XDG 目录，并在命令末尾添加 `-- --disable-follow-focus`。该开关仅在测试里关闭真实暂停 ScrollContainer 的跟随焦点；所有正常可见性、真实输入和数据保护断言原样保留，应非零退出。每组末尾恢复原跟随焦点值，避免负向修改污染下一组的生产范围断言。它不会补滚动、扩展裁切区或修改控件尺寸来制造通过。

## 结果

Godot 4.6.3 Linux headless，最终暂停/设置双面板范围：正常运行 1070 项、0 失败，退出 0；关闭跟随焦点的负向对照同样执行 1070 项，450 失败，退出 1。负向各组滚动位置始终为 0，并报告焦点裁切及不可点击确认，证明回归能捕获原缺陷。正常各组确认位置为 341–639，返回图鉴位置为 324–389；所有状态、保存及 RNG 保护断言通过。

本地原始日志：`/tmp/pause-keyboard-scroll-final-positive.log`、`/tmp/pause-keyboard-scroll-negative.log`（临时运行证据，不是仓库交付文件）。无截图、原生视觉、性能、FPS 或全量回归通过的声明。
