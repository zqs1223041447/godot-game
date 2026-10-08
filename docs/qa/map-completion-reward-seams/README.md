# 地图清图身份与普通奖励接缝

基线：`b4cec15d61cfef890993714849d72f5a49009187`。实现分支：`codex/map-completion-reward-seams`，供审查，未合入 main。

下述首轮 963 项验证及 `verification.json` 输入指纹对应 `aa0f44e9af0955ce9879bad3881ebea71c26f811`。后续未结算必需尸体的既有边界修补与两项增量验证见 [pending-death-boundary/README.md](pending-death-boundary/README.md)；首轮记录保留原指纹，没有重新运行整套。

修改仅涉及 MapRun 身份登记、Main 死亡/清图/HUD 查询与异常提示。已登记根怪的死亡进度不依赖普通奖励资格；经验、普通掉落、里程碑、药剂充能继续使用原有 `eligible` 判断。奖励路由检查仍在一次性死亡账本之前。没有改变 schema、默认怪物内容、地图配置或费用，也没有开放新配置、奖励路由、冻结交互、精华货币或赛季。

## 成员完整性与未来边界

- `ExplorationMapPlan` 在独立运行时构造完整普通根怪和首领，`register_initial_group` 校验总数、身份不重叠与首领模板，然后登记整组。Main 在原收费/保存事务成功后接纳同一批根怪、记录、运行时 checkpoint 和 MapRun。
- 地图内 `_spawn_enemy` 拒绝新增根怪，`_update_map_spawning` 只接纳现有有限死亡队列；后代保留原 `root_id`，沿用原入场事务及预算。
- `completion_members` 以已登记普通根怪和首领身份为必需谱系。HUD 与完成判断共用其存活成员、待生成数量。未知成员返回失败；死怪过滤和 FIFO 入场之前也检查，防止异常尸体被先移除或未知队列被先消耗。
- 可选遭遇仍为空。没有新增可选成员登记表或默认假遭遇；未来开放可选遭遇时必须先实现明确的接纳/清图策略。当前不能把未登记怪物当成“可选”静默忽略。

## 有限验证

Godot `4.6.3.stable.official.7d41c59c4`，每个进程最多 60 秒，独立新建 `/tmp` 用户目录。

| 最终验证 | 检查 / 失败 | 范围 |
|---|---:|---|
| 固定种子正式 Main 默认流程 | 137 / 0 | 原生根怪/首领/有限后代、重复死亡、领取结算、付费重入保存失败及重试、未知配置/路由拒绝 |
| 明确标注的语义/异常夹具 | 130 / 0 | 普通奖励资格为 false 时仍推进已登记根怪；无普通经验/物品/里程碑/药剂充能；原尸体及旧副本防重；必需队列/活后代阻塞；未知活怪、尸体和队列拒绝；退出清理 |
| 现有地图生成计划 | 352 / 0 | 默认地图及现有修饰组合、原生地形、整组身份和失败原子性；奖励资格字段仍要求 bool 类型 |
| 现有有限分裂子集 | 110 / 0 | 原 splitter/brood、防重、代数/每次/谱系预算、容量、FIFO、取消与重置；复用原测试函数 |
| 现有 HUD query/lineage 子集 | 234 / 0 | 只读查询、最近目标、驻点/首领后代、待生成队列、重开后身份及提示一致性 |

最终共 **963 / 0**。基线另运行 137 / 0，未计入最终总数。

修改前后使用相同固定种子和相同新测试入口。44 次实际 Main 死亡结算分别记录状态、运行时及药剂指纹、随机状态、根怪进度和 HUD；同时保存入场记录、完整结算与最终存档。两份 `default-contract.json` **字节完全相同**，SHA-256 为 `84fd424092a955598bdac49d846e672ba3dea26af2196c768520a23f947431f1`。证据不使用修改前后自生成的相同“预期值”替代比较：基线在运行代码修改之前独立采集。

语义夹具在真实正式地图 roster 上显式改变运行时奖励标记，异常夹具显式注入未登记成员；这些只证明分离边界，不代表赛季已经可玩。默认对照使用原有正式流程及受控防御结算死亡，没有自然战斗录像、UI 时钟或性能验收声明。

`verification.json` 保存各轮结果、输入文件 SHA-256、未改的生成/接纳/死亡预算/schema 来源与精确默认对照。`attempt-01-parse-error.*.txt` 保留首次新夹具的解析失败：动态返回值缺少显式 Dictionary 类型，已补齐；该轮未计入成功结果；失败 stdout 仅去除末尾空行，stderr 保留原文。默认及最终夹具日志无脚本错误。

## 复跑

在仓库根执行，输出到独立临时目录。已有 import cache 可复用；无需导出或长期检测。

```bash
task_output="$(mktemp -d /tmp/map-completion-seams-results-XXXXXX)"
run_case() {
  local task_case="$1" task_script="$2"
  shift 2
  local task_data
  task_data="$(mktemp -d "/tmp/godot-m1-${task_case}-XXXXXX")"
  mkdir -p "$task_output/$task_case"
  env XDG_DATA_HOME="$task_data" XDG_CONFIG_HOME="$task_data/config" \
    XDG_CACHE_HOME="$task_data/cache" \
    EXPLORATION_MAIN_OUTPUT="$task_output/$task_case" "$@" \
    timeout 60s godot --headless --path . --script "$task_script"
}
run_case v086-exploration-default tests/map_default_death_contract_test.gd EXPLORATION_MAIN_SAVE_ONLY=1
run_case map-seams-fixture-check tests/map_completion_reward_seams_test.gd
run_case seams-plan tests/exploration_map_plan_test.gd
run_case seams-split tests/map_completion_split_boundaries_test.gd
run_case v100-hud tests/exploration_cleanup_hint_test.gd \
  CLEANUP_GUIDANCE_GROUPS=query,lineage \
  CLEANUP_GUIDANCE_REPORT="$task_output/v100-hud/result.json"
cmp docs/qa/map-completion-reward-seams/baseline-default-contract.json \
  "$task_output/v086-exploration-default/default-contract.json"
```
