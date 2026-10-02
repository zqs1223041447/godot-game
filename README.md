# godot游戏仓 · 裂隙试炼

以 **构筑与技能效果组合** 为核心的 Windows 游戏。基于 **Godot 4.6.3 标准版 / GDScript**，目标平台 **Windows x86_64**。

## 第一阶段：可玩原型 v0.1.0

在俯视平面竞技场中，角色自动发射投射物攻击主动接近的敌人。可以边战斗边试验装备、天赋与五个主动技能的组合；打开构筑面板会暂停战斗。

### 已完成

- WASD / 方向键移动，平面地图边界，三种敌人，随时间增强的波次
- 自动锁敌射击、鼠标手动瞄准、穿透投射物、减速、范围伤害、击退、连锁闪电
- 生命 / 魔力 / 能量护盾 HUD，护盾优先承伤，受击 4 秒后开始回复
- 1—5 技能槽，魔力消耗与冷却显示，鼠标也能点击施放
- 7 种技能：飞弹、冰霜、新星、冲刺、结界、陨星、闪电
- 装备背包：6 件初始装备、武器 / 护甲 / 饰品槽，装备 / 卸下立即影响属性
- 天赋：5 条成长路线，每条 5 级，初始 5 点；击杀升级获得更多点数，可免费重置
- 技能面板：选择目标槽位后换装技能，已装配技能会交换位置，不重复占槽
- 补给拾取、伤害数字、战斗反馈、暂停、死亡与重新挑战
- 本地 JSON 存档保存装备、天赋、技能槽、等级和经验；重新挑战保留构筑
- 自带中文字体子集，不依赖 Windows 已安装中文字体

这是功能原型。当前美术由程序绘制，没有最终角色动画或音效；尚未加入随机词缀、掉落装备、刷图关卡、制作、技能辅助宝石、联机与完整 PoE 式天赋树。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动 | WASD / 方向键 |
| 自动攻击 | 默认开启；Q 切换 |
| 手动瞄准射击 | 按住鼠标左键并指向目标 |
| 主动技能 | 1 / 2 / 3 / 4 / 5，或点击 HUD 技能槽 |
| 快速冲刺 | 空格（需要在技能槽中装配“闪光冲刺”） |
| 装备背包 | I / B |
| 天赋 | T |
| 技能配置 | K |
| 暂停 / 关闭面板 | Esc |
| 死亡后重新挑战 | R，或点击“重新挑战” |

普通射击不消耗魔力。魔力持续恢复，护盾在停止受伤后恢复；每四次击杀掉落一次生命/魔力补给，靠近自动拾取。每 30 秒进入更强的一波。

## 运行

### Windows 玩家

解压发布包，双击 `GodotGame.exe`，无需安装 Godot。当前是未签名开发原型；不要绕过系统的安全警告，可先使用 Godot 编辑器打开源工程。Windows 可执行文件已导出并检查格式，但本环境没有 Windows / Wine，**尚未完成 Windows 实机启动验证**。

### 开发者

安装 [Godot 4.6.3 标准版](https://godotengine.org/download/archive/4.6.3-stable/)，导入根目录 `project.godot`，按 F5。也可运行：

```sh
godot --path .
```

使用 Compatibility 渲染器，逻辑分辨率为 1280 × 720。窗口可缩放，保持宽高比。

### 存档

Windows 默认路径：`%APPDATA%\Godot\app_userdata\godot游戏仓\build_save.json`。

仅保存构筑成长，不保存当前怪物、生命、波次和战斗计时。存档是带版本的 JSON，写入前验证，使用临时文件后原子替换；损坏、未知或越界数据不会被部分加载。装备、天赋与技能操作会立即保存，战斗也定期保存。存档和运行产物不进入 Git。

## 项目结构

```text
scripts/main.gd          单轮战斗、输入、敌人、投射物与地图绘制
scripts/game_hud.gd      HUD、装备/天赋/技能/暂停/死亡界面
scripts/build_state.gd   构筑状态、派生属性、升级与安全存档
scripts/game_data.gd     装备、技能、天赋目录
scenes/main.tscn         入口场景
assets/fonts/           中文字体子集与许可证
tests/build_test.gd     170 项构筑/存档模型检查
tests/smoke_test.gd     49 项战斗/UI 集成检查
tools/validate.sh       可重复的隔离验证入口
tools/subset_font.py    可选字体子集再生成工具
export_presets.cfg     Windows x86_64 导出预设
```

## 验证

```sh
bash tools/validate.sh
```

可用 `GODOT_BIN` 指定引擎。脚本将 Linux 设置、缓存与存档隔离到临时目录，检查 Godot 输出中的脚本错误，即使引擎退出码为 0 也不会误报成功。

当前通过：

1. Godot 4.6.3 工程导入与脚本解析
2. 170 项模型检查：装备替换、天赋边界/重置、技能交换、经验升级、存档往返和损坏/越界数据拒绝
3. 49 项战斗/UI 集成检查：移动边界、敌人追击、真实投射物碰撞、七种技能、承伤/回复、冷却/魔力不足、菜单暂停、装备/天赋/换槽按钮、死亡/重试、存档与导出配置
4. 主场景 300 帧无界面启动
5. 云端 Linux 桌面实际图形验证：中文渲染、战斗和冷却/魔力反馈、暂停/关闭、死亡后重试、天赋分配、技能交换；UI 界面未见溢出

无界面检查和 Linux 图形检查不等同于 Windows 实机验证。

## Windows 导出

先安装与引擎匹配的 **4.6.3** 导出模板。在 Godot 中使用“编辑器 → 管理导出模板”，再打开“项目 → 导出 → Windows Desktop”。

```sh
mkdir -p builds/windows
godot --headless --path . --export-release "Windows Desktop" builds/windows/GodotGame.exe
```

PCK 嵌入 EXE；未签名，也未启用 Windows 资源修改。模板来自 [Godot 官方 4.6.3 发布](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable)。导出产物放在 `builds/`，不进入 Git。

## 字体

`assets/fonts/arena_sans.otf` 为 Noto Sans CJK SC 的 UI 文本子集，修改后的字体家族名为 Arena Sans SC。按 SIL Open Font License 1.1 分发，版权和完整许可证见同目录 `OFL-NotoSansCJK.txt`。

新增中文 UI 文本后，可安装 Python `fontTools` 并重新生成子集：

```sh
python tools/subset_font.py /path/to/NotoSansCJK-Regular.ttc
```

运行和导出不需要 Python。原型图形由项目代码直接绘制，不使用第三方付费美术资源。

## 提交与远端备份

每批开发都先验证、检查改动不含密钥/缓存/产物，创建本地提交，再上传并核对 GitHub 远端内容。本地提交不等于远端备份。

由于初始云环境通过已登录的 GitHub 网页上传，远端提交历史与本地历史不同；以下载后逐文件内容核验为准，**不要强推覆盖远端历史**。
