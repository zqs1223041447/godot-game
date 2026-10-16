# 天赋详情键盘焦点滚动核验（2026-10-15）

## 缺陷与修复

真实 `main.tscn` 的天赋窗口在 1280×720 **逻辑视口**、UI 1.1 / 字体 1.2 时，Tab 可以到达详情区的分配、退还按钮，但原详情 ScrollContainer 不跟随焦点，按钮被裁剪。起点详情在 UI 1.1 / 字体 1.1、UI 1.0 / 字体 1.2 也有裁剪。插槽、专精和较长详情还会增加内容高度。

生产改动仅一行：`scripts/ui/canonical_passive_panel.gd` 中已有右侧详情 ScrollContainer 设置 `follow_focus=true`。不修改外层滚动、焦点顺序、按钮禁用规则、树交互、分配/退还事务、存档格式或玩法。

## 回归方法与边界

新增 `tests/talent_details_focus_test.gd`，载入真实主场景并暂停场景/HUD 的过程推进。通过真实保存 API 建立基线，之后只浏览节点及导航，不触发分配、退还或镶嵌。

- 支持的 UI 0.9/1.0/1.1 × 字体 1.0/1.1/1.2，共 9 格
- 5 个真实详情变体：已分配起点 `58833`、可分配节点 `15144`、专精 `89`、插槽 `6230`、按源词条长度选择的长详情 `861`
- 每格每变体关闭并重新打开两次，共 90 个详情场景；验证关闭后面板实际隐藏
- 从搜索框出发，通过 `root.push_input` 发送真实 Tab 按下/释放，遍历全部可见详情焦点控件；移至下一个焦点后再逐个 Shift+Tab 返回搜索框。未用 `ensure_control_visible` 帮测试滚动，也未直接聚焦目标按钮
- 验证实际焦点身份、每层裁剪祖先、完整内容区及交互中心、逻辑视口；整数滚动导致边框最多一个局部滚动单位的量化误差按实际 transform 换算，内容区必须完整可见
- 每次详情焦点检查都要求外层横、纵滚动为 0
- 验证全部模型字段、正式及练习存档的存在性和字节、设置文件存在性和字节、界面设置值、场景/global RNG、运行修订号及冷却快照不变
- `--disable-follow-focus` 只在测试实例中禁用详情跟随；其余输入与断言完全相同，每场景恢复原值

这是 Linux Godot 4.6.3 headless 的真实输入/逻辑布局核验，不是 Windows 原生截图、像素或全量游戏验收。没有修改技能面板等并行工作的文件。

## 执行结果

所有正式运行均采用独立新建 XDG data/cache 目录，外部 `timeout 90`，测试内部另有 80 秒失败退出保护；未运行 editor import。

| 项目 | 结果 | 原始日志 |
|---|---|---|
| 最终正向矩阵 | 5219 checks / 0 failures；exit 0 | `/tmp/talent-focus-final-positive.log` |
| 最终禁用跟随负向对照 | 5219 checks / 1420 failures；exit 1，正常执行至摘要 | `/tmp/talent-focus-final-negative.log` |
| 原有动作呈现测试 | 13 checks / 0 failures；exit 0 | `/tmp/talent-passive_action_presentation.log` |
| 原有说明搜索测试 | 312 checks / 0 failures / 40 submissions；exit 0 | `/tmp/talent-passive_description_search-final.log` |

正向及负向日志没有 `SCRIPT ERROR`。负向失败是目标可见性断言，不能将其计为通过的功能检查。检查数含相同场景中多层祖先与重复导航的断言，不代表独立功能数量。

复现命令（每次使用新的目录；负向在末尾加 `-- --disable-follow-focus`）：

```sh
D=$(mktemp -d /tmp/godot-talent-focus-check-XXXX)
XDG_DATA_HOME="$D/data" XDG_CACHE_HOME="$D/cache" \
  timeout 90 godot --headless --path . --script tests/talent_details_focus_test.gd
```

开发中曾有一处 GDScript 局部变量类型推断错误，修正为显式 float 后重新执行；最初搜索回归的 XDG 前缀不符合其保护规则，exit 78，改用该测试要求的新 `/tmp/godot-passive-search-*` 目录后正式通过。上述早期失败没有计入通过数。

本记录仅证明本地验收。独立审查由上层协调，远端发布受既有取消阻塞约束；未创建提交、PR 或合并，未输出新 Windows 包。
