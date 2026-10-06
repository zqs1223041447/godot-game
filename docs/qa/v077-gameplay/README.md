# v077 实际 Main 验收与冻结 v076 对照

验收通过。实际 Main 共 **230 项独立检查 / 0 失败**；冻结 v076 与当前 v077 各 **21 项终态检查 / 0 失败**。Oracle 是同一段短流程在两个版本的结果，不将两次检查数累加为独立功能覆盖。最终文件 SHA 与机器可读结论见 `acceptance.json`。

## 实际 Main 覆盖

使用真实 `scenes/main.tscn`、合法普通怪物入口、既有白板 forgeblade / ashwood_bow 装備实例校验及模型穿戴 API、此前已验证的七级天赋路径与真实坚决分配/退点 API。固定目标血量、熵、位置和攻击精度是受控战斗输入；没有替换伤害、命中、投射物或奖励实现。

- 雾羽的真实普通近战、普通弓弹、三母箭龙卷。每条观察的概率来自权威 admission；龙卷观察逐条对应原始 evaded 事件的 target / cast / projectile，且熵只推进一次
- 坚决的真实近战、弓弹、龙卷必命中且熵不动；法术不误标闪避
- 负数/非有限 accuracy 与非法坚决/精准快照拒绝不生成闪避；旧投射物无效输入仍可能记 evaded，但新观察不假报
- 精确零损失保留原 damage record 且没有浮动数字；0.001 正损失保持正伤害；未知 cast / projectile 保持 0
- 真正几何 sweep 产生的墙事件只记录环境、真实投射物身份；实际出生保护结算入口记录拒绝，普通近战/射弹前置候选过滤不补虚构日志
- 实际死亡 flush、重复死亡、菜单暂停、完成地图老化、restart 清除；历史 32、pending 24、marker 8 上限；总 48 行中原伤害绝对优先
- damage_numbers 开/关产生完全相同的结果、资源、旧记录、RNG 与 accessor 输出；真实 F6 菜单仍能读到闪避与小额正损失且读操作不改战斗

`corrected-gameplay.json/.log` 是完整 228 项通过记录。随后只补逐事件身份断言并重跑最小 `real_attack_paths` section：该 section 从 25 项变为 27 项，见 `event-identity-gameplay.json/.log`。合法 source setup 是每次独立进程必要前置，不重复计入独立检查数。最后一次 fixture 修改只修正 legacy 分支的过早二次施放，未改变上述已验收 section。

## 冻结逐字对照

基线目录为现有 `v076-source-shield-recharge`，HEAD `587c195d2a78c2028f1ae781b3aa460426fc898c`。运行前后校验 **412 个**受版本控制的 scripts / scenes / data / project 文件的 Git blob 等于该提交；仅只读使用其已有 `.godot` 缓存，没有重新 import、复制整树或改写 baseline。当前版本只有预期 4 个生产脚本与版本号不同。完整 SHA-256 / Git blob 清单见 `accepted-legacy-sources.json`。

两个版本使用同一份外部测试脚本、Godot `4.6.3.stable.official.7d41c59c4`、固定 RNG seeds，在不同 `/tmp/godot-m1-v077-*` XDG data/config/cache 目录**串行**运行，分别耗时 2.825 / 2.974 秒。Runner 会检查运行期间生产源文件没有发生变化，不做 import。

60 ticks、71 个样本覆盖 8 次真实普通模式死亡/XP/装备奖励、5 shots、3 次原 evaded、12 次 hit、1 次实际墙事件，critical draws / events 均为 4。逐样本保存目标资源与 entropy、完整投射物、原事件、两条 RNG、完整 model、damage / incoming / attack admission / combat / burn traces、计时器、冷却、药剂、吸取、掉落、粒子、旧浮字、旧 damage feedback 的时间/待发/可见完整数据和当时真实磁盘字节。没有删字段、版本投影或浮点舍入，也没有拿新旧混合 `Main.damage_feedback()` 做假等价。

| 原始文件 | 字节数 | v076 / v077 SHA-256 |
| --- | ---: | --- |
| `.bin` 样本 | 6,956,972 | `53c7f5ff9fd220c052cafeb97e54c20bbb3cdcdacd646247762c359ee9c6a5b5` |
| `.save` 最终真实存档 | 12,511 | `9059b58d2a29a34779135e3c4acce4aa26225d9a80cbb41502a42a253ea64327` |

两项都是逐字相同。见 `accepted-legacy-comparison.json`、两版本 `.bin/.save/.json/.log`、`accepted-legacy-result.json`。Probe JSON 在最后“正常返回”检查前写入，故 JSON 内计数 20，终态日志计数 21；失败均为 0。

## 保留的首次失败

1. `first-gameplay.*`：fixture 误以为龙卷只有一母箭，要求仅一条 miss 且整次 cast 没伤害；合法真实三母箭实际是两 miss 一 hit。修正为逐次权威 admission / 旧事件对应，生产代码未修改
2. `legacy-v076.*`：fixture 在 0.5 秒时再次释放龙卷，被旧版本真实 cooldown 拒绝。将短流程限定为一次龙卷加一次 nova，再从头串行运行两版本。原失败 log、result、samples、source hashes 保留

## 重现

由主协调者完成当前树首次 import 后运行，runner 本身不 import：

```sh
python tools/run_v077_gameplay.py --mode all --label review
```

必要时用 `--baseline /absolute/path/to/v076-source-shield-recharge` 指定已导入且源代码仍与冻结提交一致的基线。只重跑受影响 section 可使用 `--mode gameplay --sections real_attack_paths --label review-section`。每次使用新 label 保留既有证据。

范围：有界 headless 实际 Main、合法既有 fixture 与旧行为逐字对照。没有运行旧全套、长时性能、截图或导出；不宣称 native UI / Windows / 长时性能验收。
