# godot游戏仓

使用 **Godot 4.6.3（标准版 / GDScript）** 开发的 Windows 游戏仓库。

## 方向

- 以 **构筑和技能效果组合** 为核心，参考 PoE-like 的构筑深度
- 刷怪和制作是服务于构筑体验的手段
- 目标平台：**Windows x86_64**
- 开发环境：dot 的云电脑；每次完成一批开发修改后，验证并提交、推送到 GitHub

当前仅完成可运行的工程骨架：启动界面、退出操作、Windows 导出预设及冒烟测试。尚未实现战斗、技能、构筑、掉落或制作系统，也未锁定 2D / 3D 玩法。

## 打开与运行

1. 安装 Godot **4.6.3** 标准版，无需 .NET
2. 在项目管理器中导入本目录的 `project.godot`
3. 按 **F6** 运行当前场景，或按 **F5** 运行项目
4. 点击“退出”或按 **Esc** 关闭游戏

也可在仓库根目录运行：

```sh
godot --path .
```

工程暂用 Compatibility 渲染器、1280 × 720 逻辑分辨率，不代表最终画面规格。

## 目录

```text
assets/             美术、音频等资源（预留）
data/               技能、词缀等数据（预留）
scenes/main.tscn     最小启动场景
scripts/main.gd     启动和退出逻辑
tests/smoke_test.gd 项目配置及场景冒烟测试
tools/validate.sh   Linux / macOS / Git Bash 验证入口
export_presets.cfg  Windows x86_64 导出预设
project.godot       Godot 项目入口
```

## 验证

```sh
bash tools/validate.sh
```

如 Godot 可执行文件不在 `PATH` 中，可设置 `GODOT_BIN`。该脚本会导入工程、检查标题/场景/退出信号/导出配置，再无界面启动主场景。在 Linux 上，验证期间的编辑器设置、缓存与存档放入临时目录，结束后清理，适用于受限云工作区。无界面检查不等同于 Windows 图形界面实机测试。

也可分别运行以下命令；Windows PowerShell 下将 `godot` 替换为 Godot 可执行文件的路径：

```sh
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --quit-after 5
```

## Windows 导出

在 Godot 中打开 **编辑器 → 管理导出模板**，安装与引擎完全匹配的 **4.6.3** 导出模板。然后打开 **项目 → 导出 → Windows Desktop**。

命令行导出（先创建 `builds/windows` 目录）：

```sh
godot --headless --path . --export-debug "Windows Desktop" builds/windows/GodotGame.exe
godot --headless --path . --export-release "Windows Desktop" builds/windows/GodotGame.exe
```

预设会把 PCK 嵌入 EXE；未启用签名和 Windows EXE 资源修改，因此现阶段没有自定义图标或签名。构建产物写入 `builds/`，不会进入 Git。初始云开发环境尚未安装 Windows 导出模板，Windows EXE 构建与运行仍待验证。

## 提交与备份

每一批开发修改的完成顺序：

1. 运行相关验证，并记录尚未验证的部分
2. 检查 `git diff` 与 `git status`，确认不含密钥、缓存或构建产物
3. 创建描述清楚的 Git 提交
4. 推送到 GitHub，并确认远端分支包含本次提交

本地提交并不等于已备份到 GitHub。若推送失败，应明确保留“未完成远端备份”的状态并修复。

`.godot/`、构建输出和常见秘密文件已被忽略；GDScript 的 `.uid` 文件应正常提交。不要把账号密码、令牌、签名密钥或付费资源的未授权副本加入仓库。
