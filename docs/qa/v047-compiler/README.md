# v047 余烬扩散辅助编译定向证据

2026-10-05，Godot 4.6.3。新增定向测试 **602 检查 / 0 失败**，覆盖 **11 个合法新辅助配对**。独立探针的 **38 条旧施放记录与冻结 v046 完整字节一致**，其中 8 条带点燃、30 条不带燃烧辅助。未运行历史全量。

## 已实现合同

- `ember_proliferation` / 余烬扩散辅助仅适配陨星、龙卷；附加火伤不能打开其他技能资格
- 注册资格、真实编译与保存链接在两个排列下都拒绝与点燃同时装配；非法选择不会部分执行、收费或修改输入
- 独立政策 `{duration: 3.0, rate_fraction: 0.20, hit_multiplier: 0.75, mana_multiplier: 1.30}`；原点燃政策保持 30% / 1.20
- 主命中所有伤害分量仅乘一次 0.75，消耗仅乘一次 1.30；其他辅助与源成本因子仍同源组合，冷却不变
- `snapshot.burn_policy` 与点燃同形；`snapshot.burn_proliferation` 复制传播规则的唯一 `POLICY`
- `burn_profile.roles.direct` 或 `parent/child` 保留 `fire_before_defense`、`dps`、`total`；非暴击、防御前火伤经全部主命中修饰后取 20%，实际 `BurnRules.from_fire_hit` 与预估一致
- `burn_profile.proliferation` 同源保存半径120、最多8个目标、一跳、保留原到期时间；快照、预估、后续施放彼此独立
- 母箭、子箭与返回保持被冻结的两项政策及单次辅助因子；独立爆炸不吃主命中减伤，不携带燃烧或传播政策
- schema28拒绝新辅助链接，schema29接受；原点燃schema28门槛保持。物品实例及迁移验证另见保存模块证据

## 冻结基线

`capture_v046.gd` 是同一份外部探针，先在未含余烬、已含点燃的冻结 v046 工程下运行，再原样在候选工程下运行。不是在新代码内关闭功能来模拟旧版。

基础与富属性两种快照各覆盖：十个主动技能空链、普通攻击，以及陨星/龙卷的旧双辅助、旧五辅助、单点燃、点燃五辅助。富属性包含附加伤害、多个真实作用域、成本、空间、暴击与偷取。比较包括输入、辅助顺序及整个 `var_to_bytes(cast)`，不删字段、不舍入、不筛选数值。两个 `.bin` 外层元数据的源码哈希与新辅助存在标志不同是预期；38条记录逐字节相同。

## 文件与运行

- `compiler-focused.log.txt`：602项定向结果
- `compiler-v046.bin` / `compiler-v046.log.txt`：冻结 v046 原始结果与逐条摘要
- `compiler-v047.bin` / `compiler-v047.log.txt`：候选原始结果与38条完整字节对照结果
- `compiler-tested-files.json`：被测源码、测试和证据的 SHA-256 与文件尺寸
- `tests/ember_support_compiler_test.gd`：定向入口

在已导入工程中运行：

```sh
godot --headless --path "$V047_PROJECT" --script res://tests/ember_support_compiler_test.gd

godot --headless --path "$V046_PROJECT" --script "$V047_PROJECT/docs/qa/v047-compiler/capture_v046.gd" -- --output="$V047_PROJECT/docs/qa/v047-compiler/compiler-v046.bin"
godot --headless --path "$V047_PROJECT" --script res://docs/qa/v047-compiler/capture_v046.gd -- --output="$V047_PROJECT/docs/qa/v047-compiler/compiler-v047.bin" --compare="$V047_PROJECT/docs/qa/v047-compiler/compiler-v046.bin"
```

实际执行使用独立 XDG 数据、配置及缓存目录；不读写玩家正常存档。初次冻结探针的字体缓存警告不影响编译结果或退出码。

本目录只证明辅助注册、编译、预估、冻结投射物和旧配方保持；死亡传播的目标筛选/剩余寿命/奖励事件、商店获取、迁移与界面验收由各自定向证据负责。
