# 遗迹庭园 HUD 重试派发修复

基线：`86350b7ac9a6e55d637ffae51f94973698d09db8`。
分支：`codex/ruins-hud-retry`；运行时修复提交 `41881ae9c49b1331f653151e554d772ec4950593`。审查后补充正常帧与原生窗口鼠标验证，见 [NORMAL_FRAMES.md](NORMAL_FRAMES.md)。

## 问题与范围

死亡界面的 `RetryButton`（重新挑战）与暂停界面的 `RestartButton`（重新开始）共同调用 `GameHUD._restart()`，此前总是派发同步 `retry_normal_map()`。该 API 有意拒绝原生遗迹庭园，导致两个可点击按钮都只能报“遗迹庭园重开必须先准备原生地形”。Main/R 键另有原生派发，因此先前 `ruins_garden_entry_test.gd` 调用 `Main.restart_run()` 的验收没有覆盖这两个 HUD 按钮。

运行时仅修改 `scripts/game_hud.gd`：

- 原生地图按钮等待既有 `retry_native_map()`；普通正式地图仍调用原同步路径，测试/练习入口保持原分支。
- HUD 请求期间禁用两个重试按钮并显示“准备地形…”，重复信号直接返回；面板重建仍保持等待状态。
- 关闭/切换所属菜单时调用既有 `cancel_map_preparation()`，由原一次性地形所有者回收候选。不新建地形、地图、付费或重试事务。
- 结果复核原 arena、model、保存路径、菜单归属与世界修订；用户已取消或转到其他上下文时不改新菜单/反馈。
- 识别 Main 成功采用新 run 后自行关闭旧面板的既有行为。成功后解除死亡菜单锁定；失败保留原菜单并使用既有反馈显示真实原因，恢复原按钮。

所有 Main、ModularStudySession、PreparedMapEntry、存档/历史迁移、经济、地图目录、掉落、模型、素材及 F8 文件逐字节未改，见 `scope.json`。

## 有限验证

Godot `4.6.3.stable.official.7d41c59c4`，Linux headless，独立 `/tmp/godot-m1-ruins-hud-retry.*` XDG，每个进程最多45秒。

`tests/ruins_hud_retry_test.gd`：**216 checks / 0 failures**；最终日志 `targeted.log`，逐项证据、源码及原夹具 SHA256 为 `report.json`。

从既有不可变的真实四碎片存档启动，仅完成一张实际遗迹庭园 I 档有限地图并领取原奖励，建立八碎片、II 档已解锁的合法测试种子；不注入货币或解锁。每个按钮场景通过现有收费入口进入 II 档后剩四碎片，实际按钮重试再收费四碎片。死亡状态、写入错误和候选原生碰撞不可用为明确故障夹具；以实际 HUD 节点的 `pressed` 信号为入口，没有用私有重试提交替代按钮。

覆盖：

- 暂停/死亡两个按钮：等待期间保持原地图、重复信号及重建按钮仅调用一次原生 API；成功只收费/保存一次，同候选安装、原几何释放、恢复生命和关闭菜单；奖励计数及物品 serial 不增长。
- 两按钮的写盘失败、原生准备失败：完整原 state/disk/world/RNG/敌人/几何/vitals 保持，候选释放，真实错误可见；同一失败菜单在故障解除后再次点击成功，只有一个最终收费保存。
- 等待期间关闭、关闭再重开相同暂停菜单、切换设置、死亡按钮返城、直接依法返城、实际 canonical 库存修改：旧请求不创建 run 或扣费、不覆盖后续世界/菜单/反馈，候选释放。库存修改保持同菜单时显示真实上下文失败原因。
- 旧庭的暂停/死亡两个按钮继续走一次同步合法收费保存，原地图身份、生命和菜单关闭行为保持。
- 成功及失败结果精确 canonical 重载；原真实夹具保持字节相同；`git diff --check` 通过。

首次运行保留在 `attempt01.log/json`：唯一失败为 Main 成功重试自行关面板被最初 HUD 取消钩子误判，死亡 latch 未立即解除。已修正成功提交后的关闭识别，再补验证失败后的健康再次点击；最终所有检查通过。

复跑：`RUINS_HUD_RETRY_REPORT=/absolute/report.json bash tools/validate_ruins_hud_retry.sh`。

## 边界

上述 216 项为真实场景、控件和信号的 headless 功能验证。后续独立短冒烟补充 Main/HUD 正常帧、原生 X11 窗口中四次 XTest 系统鼠标点击和一张实际截图；详见 [NORMAL_FRAMES.md](NORMAL_FRAMES.md)，没有重跑 216 项。未重新运行既有完整入口/战斗/事务套件、长期检测、模型或 Windows 导出。测试/练习分支保持代码不变，本次只动态核对普通正式旧庭及原生遗迹庭园。

取消覆盖用户能在两物理帧准备等待中发起的操作；原事务进入同步 `in_use` 保存阶段后继续沿用原不可中途释放规则，不新增回滚机制。没有新增崩溃持久性、扩大物品/序号上限或改写已完成地图必须返城结算的规则。
