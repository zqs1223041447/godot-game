# v058 纯共享防御：魔力先于生命承伤

## 合同

`DefenseRules.mana_guard_profile(stats)` 读取 `damage_taken_from_mana_before_life`。缺省为数字 0，返回 `{ok, reason, enabled, fraction}`；只接受有限数字且在 `[0,1]` 内，不钳制错误值。当前天赋的 40% 是调用方提供的 `0.4`，共享纯规则不硬编码该天赋或给自然怪新增资源。

三个旧入口只追加可选参数：

- `incoming_hit(components, defense_stats, shield, health, actor="player", hit_taken_increased=0, mana=0, ratio=0)`
- `incoming_source_hit(components, stats, shield, health, actor="player", hit_taken_increased=0, mana=0, ratio=0)`
- `incoming_burn(raw_amount, fire_resistance, shield, health, actor="player", mana=0, ratio=0)`

数字 `0` / `0.0` / `-0.0` 比例直接保留原结算分支，包括忽略不参与结算的 mana 参数，返回字典不新增字段，旧输入的错误优先级保持。旧火抗入口仍只接受其原来的火抗 schema，源树入口仍由调用方显式传入该 profile 的 fraction。

启用时通过 `settle_with_mana(resolved, shield, health, mana, ratio)`：

1. 保留 `settle_resolved` 的原盾/血及完整 resolved 合同校验、分量和防御明细；原始输入错误优先于新增参数错误
2. 验证 ratio 为有限 `[0,1]` 数字，非零时验证 mana 为有限非负数字。失败只返回 `{ok:false, reason}`，不更改输入
3. 防御、元素抗性、命中护甲、命中感电倍率全部先完成；burn 只有原火抗，不新增感电或护甲
4. 先耗护盾，剩余伤害乘 ratio 得请求魔耗；实际魔耗 `min(current_mana, remainder*ratio)`，不足部分全部继续由生命承担
5. 生命损失不超过当前生命，剩余伤害写入 overkill。追加 `mana_spent` 与 `remaining_mana`，原 `health_lost` / `shield_spent` 始终只表示实际盾血损失

例如 100 伤害、20 盾、100 魔、200 生命、40%：损盾 20、耗魔 32、损血 48。魔只有 10 则损盾 20、耗魔 10、损血 70。若生命只有 10、魔足够，则损盾 20、耗魔 32、损血 10、overkill 38。

无新增 RNG、持久状态、缓存、队列、存档或 UI。

## 独立旧基线

`v057-defense-rules.txt` 来自已发布提交 `3718d74691f3a7f9e2280fc26419c093b26ee4ac` 的 `scripts/mechanics/defense_rules.gd`，原字节完整保存。

SHA256：`2c9640795202f607be9dbae6da6eed5911d5b8409a64fba44e8c6835567c8141`

测试先验证 SHA256，再仅在内存移除全局 `class_name DefenseRules` 声明以避免重名，作为独立 GDScript 编译运行。旧分支对照使用 `var_to_bytes` 比较完整 Variant，包括类型、字典插入顺序、嵌套明细、失败原因及返回字段。不是由新实现反推期望或把新函数复制当旧版。

旧对照包括三个入口、省略参数的旧 arity、整数/浮点/负零显式 ratio、未启用的无效 mana、两种 actor、有效/非法感电倍率、各类伤害/资源/防御同时非法时的优先级、原 settlement 错误矩阵和明细隔离。

新规则覆盖全盾、破盾、无盾、空魔、少魔、全耗尽、零生命、overkill、ratio=1、空包、五混伤、抗性封顶、护甲、一次感电倍率、玩家/纯怪物一致、命中/burn相同资源字节、实际盾血和魔耗分离、非法参数原子拒绝、重复性和输入/输出嵌套隔离。另测 mana / shield / life 分界上下 1 ULP、最小正次正规数与最大有限 double。

## 执行

统一 import 完成后执行一次：

```sh
python3 docs/qa/v058-rules/run-focused.py
```

runner 本身不 import，不加载场景、不创建状态对象或存档；Linux XDG data/config/cache 在唯一 `/tmp/godot-m1-v058-rules-*` 隔离，GDScript 再核验。仅运行本新增纯规则测试，最多 60 秒进程保护。证据记录本纯测试全部输入文件哈希、前后不变、引擎错误扫描、typed-byte 案例数与检查数。不会执行历史全量或 600 秒测试。

消费者、迁移、实际场景、UI 和发布验证不在本纯规则证据范围内。

## 实际结果（2026-10-05）

- 首轮：1.118 秒，`82,067` 检查、`9` 失败；独立 v57 的 `74,025` 个 typed-byte 案例已经全部通过。另有一个末尾浮点测试访问缺失 `mana_spent` 的脚本错误。保留 [首轮 evidence](evidence-n0ujds7y.json) 和 [完整失败日志](rules-n0ujds7y.log.txt)，不将首轮称为全过
- 原因是测试源码的 `5.0e-324` / `-5.0e-324` 在本 Godot 4.6.3 GDScript 中解析成正/负零。正零比例本应走旧返回、没有 `mana_spent`；负零也不是非法负数，所以原极值用例期望错误。将测试极值改为 `PackedByteArray.encode_s64/decode_double` 按 IEEE-754 位生成，即 `adjacent(0.0, 1)` 及其相反数
- 修正测试后的同一 focused 单文件补验：1.225 秒，`82,070` 检查、`0` 失败、`74,025` 个旧 typed-byte 案例通过；exit 0，无脚本/引擎错误。补验已经发起后才收到复用旧案例、不再重复的指导，之后没有再执行。证据：[最终 evidence](evidence-3p51fc2t.json)、[最终日志](rules-3p51fc2t.log.txt)
- 两轮之间生产 Defense 文件没有修改，SHA256 同为 `7c84a7fedef8c7d978056d232889715d598264e447b05e0c9ce9d2705aee5476`；每轮输入前后哈希保持。两轮均不 import，没有运行其他测试集合或 UI

此证据证明本共享纯规则和旧分支的精确兼容性；实际玩家消费者、存档迁移和原生界面须使用各自独立证据。
