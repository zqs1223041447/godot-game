# 贯穿辅助：集成与 UI 自动验收

验收基线为 `codex/v014-pierce-integration` 的 `e570b2b4596c908d82968117b90570a0ea515ea3`，独立分支为 `codex/v014-pierce-acceptance`。本次只新增两份可执行测试、本文件和一份 literal v9 fixture，没有修改核心、图鉴、既有断言或验证总入口。

2026-10-02 UTC，Linux / Godot `4.6.3.stable.official.7d41c59c4` 的实际结果：

| 检查 | 结果 | 实际隔离运行目录 |
| --- | --- | --- |
| 资源导入 | 通过，无 `SCRIPT ERROR:` / `ERROR:` | `/tmp/godot-pierce-acceptance-g_i35we4` |
| `tests/pierce_integration_test.gd` | **843 项，0 失败** | `/tmp/godot-pierce-acceptance-3vw2ywub` |
| `tests/pierce_ui_test.gd` | **233 项，0 失败** | `/tmp/godot-pierce-acceptance-h7let456` |

日志在对应运行目录的 `proof.log` / `result.log`；以下命令会在新目录生成自己的完整日志。两套测试都完成了所有用例，合计 **1076 项检查**，未发现实际核心缺陷。未运行重复的 600 秒总回归。

## 隔离证明与复现

**必须先证明 userdata 隔离，再启动导入或验收。** 本轮每次运行都先打印实际路径，并确认隔离目录没有已有 `build_save.json`：

```text
ISOLATION PROVED: user://=/tmp/godot-pierce-acceptance-3vw2ywub/data/godot/app_userdata/godot游戏仓
ISOLATED EXISTING SAVE: false
Pierce integration: 843 checks, 0 failures

ISOLATION PROVED: user://=/tmp/godot-pierce-acceptance-h7let456/data/godot/app_userdata/godot游戏仓
ISOLATED EXISTING SAVE: false
Pierce UI: 233 checks, 0 failures
```

测试脚本在创建场景或写任何 fixture 之前，还会检查：`PIERCE_QA_ROOT` 与 `XDG_DATA_HOME` 相同；路径属于 `/tmp/godot-pierce-acceptance-…`；`ProjectSettings.globalize_path("user://")` 位于该目录且等于 `OS.get_user_data_dir()`；默认存档不存在。UI 测试还拒绝已有显示设置。缺少隔离配置时退出码为 2。两份脚本都支持 `-- --probe-only`，只证明隔离而不创建场景或存档。

在 Linux 仓库根目录执行以下命令。每个检查使用新的 data 子目录，config/cache 也位于同一临时根目录；探针不预加载任何游戏代码，因此首次导入前也可以运行。正常退出码之外，还检查 Godot 可能仅写日志的脚本错误。

```bash
set -euo pipefail
project_dir="$PWD"
godot_bin="${GODOT_BIN:-godot}"
qa_root="$(mktemp -d /tmp/godot-pierce-acceptance-XXXXXX)"
export XDG_CONFIG_HOME="$qa_root/config"
export XDG_CACHE_HOME="$qa_root/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME/fontconfig"

cat > "$qa_root/userdata_probe.gd" <<'GD'
extends SceneTree
func _initialize() -> void:
    var expected: String = OS.get_environment("PIERCE_QA_ROOT").simplify_path()
    var actual: String = ProjectSettings.globalize_path("user://").simplify_path()
    if not expected.begins_with("/tmp/godot-pierce-acceptance-") or expected != OS.get_environment("XDG_DATA_HOME").simplify_path() or not actual.begins_with(expected + "/") or actual != OS.get_user_data_dir().simplify_path() or FileAccess.file_exists("user://build_save.json"):
        push_error("ISOLATION REFUSED: " + actual)
        quit(2)
        return
    print("ISOLATION PROVED: user://=" + actual)
    print("ISOLATED EXISTING SAVE: false")
    quit(0)
GD

run_qa() {
    local label="$1"
    shift
    export XDG_DATA_HOME="$qa_root/$label/data"
    export PIERCE_QA_ROOT="$XDG_DATA_HOME"
    mkdir -p "$XDG_DATA_HOME"
    timeout 120s "$godot_bin" --headless --path "$project_dir" \
        --script "$qa_root/userdata_probe.gd" 2>&1 | tee "$qa_root/$label-proof.log"
    if rg -n '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$qa_root/$label-proof.log"; then
        return 1
    fi
    timeout 120s "$godot_bin" --headless --path "$project_dir" "$@" \
        2>&1 | tee "$qa_root/$label.log"
    if rg -n '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$qa_root/$label.log"; then
        return 1
    fi
}

run_qa import --editor --import
run_qa integration --script res://tests/pierce_integration_test.gd
run_qa ui --script res://tests/pierce_ui_test.gd
printf '验收日志保存在 %s\n' "$qa_root"
```

## 已测范围

### 实际构筑、编译、施放与命中

测试直接经过 `SupportRegistry`、`BuildState.add_skill_support/set_skill_supports/remove_skill_support/get_skill_cast`、`main.cast_skill`、真实投射物推进及场景伤害结算。没有在测试中手工拼接扩展编译结果。

| 配置 | 飞弹单枚总命中容量 | 冰霜单枚总命中容量 | 投射物击中倍率 | 飞弹实际耗魔 | 冰霜实际耗魔 |
| --- | --- | --- | --- | --- | --- |
| 无辅助 | 2 | 3 | 1 | 7 | 16 |
| `pierce` | 4 | 5 | 0.85 | 8.40 | 19.20 |
| `volley + pierce` | 4 | 5 | 0.80 × 0.85 = 0.68 | 10.92 | 24.96 |
| `focus + pierce` | 4 | 5 | 1.25 × 0.85 = 1.0625 | 10.08 | 23.04 |

- `pierce` 不增加初始投射物；飞弹仍为 3 枚，冰霜仍为 5 枚；`volley` 各增加 2 枚。两种旧辅助与贯穿的输入顺序均已测试。
- 快照中每个辅助修饰器仅有一份，原始伤害包保持未乘辅助的点数；实际载体伤害和目标生命损失按独立数值公式断言，防止重复乘 0.85 或旧辅助。
- 线性目标实测飞弹 2→4、冰霜 3→5，分别覆盖空间索引启用/关闭、分段推进、按接触几何排序和最终碰撞消耗。
- 同一目标身份在同相位再次进入扫掠区域不会重复命中或扣次数。实际归航披风授予的返回保留年龄、1.7 秒寿命和剩余次数：出程先命中一次，返程共享剩余预算，总数仍为 4/5；同目标可在返程再命中一次。
- 正好足额魔力可施放，差 0.001 时拒绝。容量少一格时整组拒绝、刚好够时全部发射、完全满时拒绝；拒绝保留已有载体、魔力、冷却、射击计数和 cast ID。
- 重复/未知/不兼容辅助、超过两槽及损坏运行时配置在实际边界拒绝；不部分修改构筑，不先扣魔。
- 飞行中通过实际支持事务、卸装和快捷栏交换改变构筑，旧载体保留伤害包、辅助、穿透、返回与爆炸；新施放才采用新构筑。旧击中使用当前目标抗性。实际独立爆炸保留旧装备增伤，但排除 `pierce/focus` 和投射物提高；辅助不泄漏至普攻或次级包。

### Literal v9、v10 与保护边界

`tests/fixtures/pierce_v9_build.json` 是独立编写的历史记录，未由当前 `_snapshot()` 降版本生成；SHA-256 为 `09fc16be7a2293c95e879cac3c5b6589a7b9dbf13be79f7a779f446e7a0f3ed9`。含有白蜡长弓及两条局部前缀、合法稀有装备词缀、旧防御掷值、装备/珠宝编号间隔、已镶特殊珠宝、旧辅助和背包坐标。

JSON 解析的数字是浮点数；预期记录独立按存档协议把整数域规范化，随后比较完整 16 字段快照，不丢弃字段、身份或掷值。新增存档按当前规范比较完整序列化字节；历史备份始终比较原字节。

- v9 读取只做内存迁移，保留旧文件；schema10 明确映射装备词汇 9，能够读、写、再次加载装备和新辅助。
- save-as 不消耗原路径保护；原路径的绝对别名首次写入前创建逐字节相同的 `.v9-backup.json`；后续写入不改变备份。
- 备份语义相同但编码不同、源文件被外部改写时均拒绝覆盖。
- 实际主场景启动使用由同一 literal 文本构造的 BOM、CRLF、前后空白源字节，打开 K；首次辅助变更触发实际自动保存，备份完整保留这些字节，主文件写成 v10，重载不再次迁移。
- v1–v9 每个旧版本先加载独立、有效的历史对照记录，再注入 `pierce`，确认拒绝、完整构筑不变、原字节不变、路径别名也禁止保存，且不生成替换临时文件或迁移备份。v11 明确拒绝，装备映射不能绕过未来版本围栏。

### K / 热键栏与 720p 最大字号

`pierce_ui_test.gd` 调用真实 `_unhandled_key_input` 的 K 路由和已连接按钮的 `pressed` 信号，包含故意向禁用按钮发信号以检查 handler 内拒绝。它验证程序行为与布局，不代表物理鼠键、GPU 渲染或悬停测试。

- 图标、名称和描述来源正确；飞弹/冰霜可添加，其余六个实际技能禁用并展示与状态 API 相同的原因。
- 两槽总限额、第三个不同辅助的禁用、重复添加、按显示身份取下、过期删除信号不会取下移位后的贯穿。
- 辅助跟随技能而不是槽位；交换、关闭/重新打开不丢配置或重置冷却；场景自动保存可完整加载。
- K 和热键栏显示独立断言的耗魔、初始枚数、逐枚伤害、穿透与总命中容量、去返共享规则；差 0.001 和正好足额的可负担状态正确；损坏配置不会显示免费或就绪。
- 1280×720、UI 110%、字体 120% 的实际 viewport/scale 值已断言。K 外框在 viewport 内、辅助子控件无横向越界、纵向滚动存在且能显示完整贯穿添加按钮；取下/重新添加保持最大字号和两槽结构。显示设置与构筑存档独立。

## 未测范围与停止点

真实渲染、真实鼠标/键盘输入、悬停、截图与字体视觉质量由主集成负责。本轮未执行完整旧测试总回归、图鉴导出或 `catalog.json` drift 收口，也未验收打包/发行；这些项目不能据本报告声称通过。图鉴已知 drift 的处理保留给主集成。

本轮完成后保存到独立验收分支，推送并核对远端 SHA，然后停止。没有合并 main 或 release，没有派发模型子代理、调用额外模型、购买或重置额度；额度余量未知，按最新约束不再派发。剩余工作是主集成的渲染/鼠键验收、图鉴收口和其最终回归。
