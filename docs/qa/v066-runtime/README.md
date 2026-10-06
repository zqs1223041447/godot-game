# v066 符印伏击：纯规则、编译与载体边界

基线 `b2bd4a1eb795a39c20a47cd6c5419537b9dadd12`；Godot `4.6.3.stable.official.7d41c59c4`；全部测试使用独立 `/tmp/godot-m1-v066-*` XDG 目录。没有读写真实用户存档、重新导入项目、提交或推送。

- `tests/ambush_rules_runtime_test.gd`：195 检查，0 失败
- `tests/ambush_support_compiler_test.gd`：309 检查，0 失败；18 种辅助组合
- `tests/ambush_legacy_support_probe.gd`：基线与当前各 783 行；旧编译输出、辅助程序及全局随机序列完全相同。两份 JSON 原字节 SHA-256 均为 `3c8262b7111eaf883b1931496ad55283118c994ea0967448b57702796eddb0de`

运行时覆盖布防精确等号及前一 ULP、失效精确等号及前一 ULP、过期优先、一次性取出、同刻多个符印按 ID 顺序、全技能共享三槽、过期释放容量、只读预检与投影、拒绝后的时钟/ID/存储原子性、深层输入隔离和取出后的所有权。0%、40%、100% 暴击均接受实际 `CriticalStrikeRuntime.freeze` 结果，拒绝未冻结或伪造的结果。

输入覆盖非数字/非有限时间、倒退时钟、无效位置、非法 ID、未知或重复辅助、非本技能辅助、缺失直接命中包、重复伏击倍率、额外 trap 伤害作用域、Node/Object/Callable 引用、循环容器、过深或过大的数据，以及生产快照中合法的 StringName 键和值。新规则与运行时不使用 RNG。

编译覆盖只有 nova/meteor 适配、schema41 拒绝新辅助、schema42 接纳、两槽旧界限与五槽新组、恰好一份主命中 ×0.85 与魔耗 ×1.25、冷却不变、原始 spell/area/hit 包和最终爆炸半径保持、点燃/余烬根据已惩罚火伤派生，以及感电策略保持。没有新陷阱天赋执行器。

旧行为探针以同一文件分别运行在 v065 和 v066 项目路径。枚举每个技能旧辅助的零/一/二槽合法集合及一组最大五槽组合，分别使用基础、增伤/范围/暴击/持续伤害、坚决技艺三种快照。编译产物与辅助程序按 `var_to_bytes` 做 SHA-256；[基线](legacy-support-before.json)、[当前](legacy-support-after.json)、[汇总](report.json) 保留完整证据。

复跑示例：

```sh
env XDG_DATA_HOME=/tmp/godot-m1-v066-runtime/data XDG_CONFIG_HOME=/tmp/godot-m1-v066-runtime/config XDG_CACHE_HOME=/tmp/godot-m1-v066-runtime/cache /usr/local/bin/godot --headless --path . --script res://tests/ambush_rules_runtime_test.gd
env XDG_DATA_HOME=/tmp/godot-m1-v066-compiler/data XDG_CONFIG_HOME=/tmp/godot-m1-v066-compiler/config XDG_CACHE_HOME=/tmp/godot-m1-v066-compiler/cache /usr/local/bin/godot --headless --path . --script res://tests/ambush_support_compiler_test.gd
env XDG_DATA_HOME=/tmp/godot-m1-v066-probe/data XDG_CONFIG_HOME=/tmp/godot-m1-v066-probe/config XDG_CACHE_HOME=/tmp/godot-m1-v066-probe/cache AMBUSH_SUPPORT_PROBE_OUT=/tmp/ambush-old-support-current.json /usr/local/bin/godot --headless --path . --script res://tests/ambush_legacy_support_probe.gd
```

这里只证明纯规则、编译和载体行为；实际 Main 命中、出生保护/墙体、UI、存档迁移与发布包由其他集成验收覆盖。

## 原始回执转录与输入指纹补全

`transcribed-receipts/` 保存以上四次运行原工具返回的逐字段转录，包括输出、退出码、首次返回的 session ID 和结束轮询回执。文件均明确标为 **TRANSCRIPTION**：来自仍在本工作线程上下文中的原始 `exec_command` / `write_stdin` 返回，并非此次重新执行所得，也不是事后恢复的原始 shell 日志。工具当时只返回合并输出，不能区分 stdout 与 stderr。仅保留每次工具返回已记录的 `wall_time_seconds`，没有推算或宣称测试总耗时。

[输入 SHA-256 清单](tested-input-sha256.json) 记录最终保留的生产/测试文件及三个纯测试/探针的静态 GDScript 依赖闭包，另记录 v065 基线依赖。指纹在测试后补录，原测试未在执行前输出源文件指纹；核心文件修改时间早于最终测试回执，父任务也确认 Runtime/Compiler 最终输入随后未改。不得把这份补录清单描述为运行前生成的清单。

本次只补证据，未重跑测试、未改源码。测试后字体以及 GameState 迁移提示的变更不在本批纯测试依赖闭包中，因此这些回执不覆盖上述后改内容，也不代表完整最终包验收。
