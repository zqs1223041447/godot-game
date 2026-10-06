# v0.61 源节点31961与schema38迁移验收

此批仅开放源节点31961 Resolute Technique（既有中文名称：坚决技艺）。原stats数组仍只有一个条目，精确文本为 `Your hits can't be Evaded\nNever deal Critical Strikes`。解析器只在一般拒绝换行之前整体精确匹配此条，授予单一 `resolute_technique: 1.0` flat字段；两个效果不可拆分。默认源策略与存档升为38，37及36的源策略继续固定36，装备词汇仍为37。

本目录记录一次独立旧源捕获及两项集中验证，均由 `run-focused.py` 执行；没有editor import、历史全量或600秒长跑。Godot版本为4.6.3 stable，写盘全部处于 `/tmp/godot-m1-v061-source-*` 隔离目录。

## 结果

- 源规则：5,197项检查，0失败，3.278秒；日志 `20261006T003318477975Z-rules.log.txt`
- 严格迁移：193项检查，0失败，11.731秒；日志 `20261006T003318477975Z-migration.log.txt`
- 冻结旧树独立捕获：0引擎错误，1.710秒；日志 `20261006T003318477975Z-capture37.log.txt`
- 三个进程均exit0、0 SCRIPT ERROR、0 ERROR；记录的生产输入运行前后哈希相同

源规则验证旧v060独立oracle中的769个full标准节点及1,837个mastery选项，现有full节点效果不变，新增full恰好为31961。原始源、规范化源、标准图与中文mapping四份文件均与b389993原字节一致，见 `unchanged-source-evidence.json`。

整条支持后，动态中文状态一次性显示“你的击中无法被闪避 / 不会造成暴击”，消费者清单核对真实model、snapshot、compiler、命中与暴击执行文件。独立句、错误大小写、CRLF、空格/标点变体、任意其他多行、条件精准技艺63620、自我不能闪避与免晕40907/35448、嘲讽及敌人不能暴击等保持拒绝；无mastery新开放。

## 实际路线与事务

七职业在全部旧full节点构成的合法图上均能到达31961：Marauder与Templar各11点（最低7级），Scion与Duelist各15点（最低11级），Witch18点（最低14级），Ranger23点（最低19级），Shadow25点（最低21级）。各完整路径在 `20261006T003318477975Z-rules-checks.json`。

真实Marauder路线：47175 → 31628 → 9511 → 23881 → 26523 → 6446 → 10221 → 50422 → 50570 → 29353 → 63282 → 31961。初始等级7、预算11点；实际完成12次分配与12次退款（包括最后节点退款后重分配），每次恰好一个点/修订/通知，最终返还全部点数并移除flag。分别在31961分配和退款注入实际临时文件碰撞，验证失败不改变点数、flag、修订、通知、存档内容或disk receipt；正常已分配与完全退款状态均能重载。分支断开退款被拒绝。

## 冻结37来源与严格迁移

`fixtures/v37-frozen-v060.json` 是测试生成存档，非原用户存档。它由独立 `/workspace/scratch/a51485f153de/v060-final-source-snapshot` 中未修改的v060原Store验证并序列化，未使用38代码改version冒充37。捕获脚本运行前要求Rules.VERSION=37、Source.CURRENT_SAVE_VERSION=36。该fixture含47个物品，覆盖8个旧装备池与同时持有rimeward/stormward的完整装备，另保留非默认成长、修订、制作修订与旅程值；18,510原字节与SHA-256记录在 `fixtures/manifest.json`。同一旧源独立输出 `v37-vocabulary-oracle.json`，避免用新代码当自己的旧标准。

`decode_v37` 与 `reason_v37` 在外加callback前完成原生完整验证，宽callback无法放行schema37注入31961、坏UID/位置/预算/来源/装备/旅程/绑定/ledger以及非有限与错误类型。新decode只接受38，冻结decode只接受37。迁移仅改version，保持所有其他字段、物品插入顺序、装备roll、UID、点数、货币、技能组及旅程，且不消耗全局RNG；嵌套对象独立拷贝。

实际37加载先保存完全相同的 `.v37-backup.json`，再原子提交38，重复加载不迁移/不重写。备份失败、冲突备份、备份期间外部改写与实际原子写盘失败均不发布新内存/通知，并保护原文件；原子故障移除后可复用相同备份重试一次。失败的旧存档替换还验证先前已接受的38快照与disk receipt保留。

旧36→37迁移固定终点 `reason_v37`，默认链及load链接齐36→37→38；直接35/34与完整legacy链同样到38并只备份最原始版本一次。save schema35/36继续映射装备34，schema37/38映射装备37；旧37冰霜/闪电两新后缀的原roll原样保留。

本证据限于源解析、图准入、模型聚合及存档事务；战斗快照、实战命中与UI由同批其他证据覆盖。
