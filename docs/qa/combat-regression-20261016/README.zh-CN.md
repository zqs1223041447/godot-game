# 战斗、投影与死亡顺序补充回归（2026-10-16 UTC）

在当前 dot 环境、源码 HEAD `6d3d5755c59c8bdeabdc2f586a070096880bb496` 上，顺序执行五个既有套件，全部通过，共503次断言。未修改生产源码或测试，没有发现需要放宽断言或修复夹具的问题。

- map_pending_death_boundary：107项；拒绝路径保留权威死亡身份、收益、队列、RNG及磁盘，恢复后只结算一次，合法重复尸体不重放收益
- canonical_game_state：27项；当前属性/战斗投影、编译缓存、真实五辅助链接、同名独立宝石、第11行容量变化及存档往返
- combat_pipeline：305项；伤害与快照、投射物谱系、返回/到期优先级、接触、时间分段、取消与容量
- ember_event_clock：45项；近似时间并列链、原始事件顺序与长运行时间下真实Main派发
- burn_same_time_cleanup：19项；同时间分支清理死亡/缺失目标、保留活动状态、刷新单跳传播并释放守卫

每例新建独立 /tmp XDG_DATA_HOME、XDG_CONFIG_HOME、XDG_CACHE_HOME，逐例上限90秒。每例退出0、摘要与预期计数一致，无ERROR、SCRIPT ERROR、WARNING或超时。子进程累计13.972秒，不作性能改善结论。完整命令、每例临时隔离路径及耗时在 report.json；引擎版本见日志。地图套件的 EXPLORATION_MAIN_OUTPUT 指向本次新证据目录，107包含该输出的文件打开检查；不设置输出时不能照搬107。

这五例未列入63例事务运行器。本批是针对性补充验收，不能代替所有游戏测试、Windows运行、像素或帧率验收。未运行历史候选 burn_prediction_equivalence 或 gem_projection_reuse；前者加载归档候选防御实现，后者明确标记未发布历史候选，不能当作当前生产投影验收。

全部8780个批次开始时已跟踪文件的前后SHA-256完全一致。完整逐文件清单仅保留在 /tmp/combat-regression-20261016-c_g4cggh/，不随Git交付；清单摘要见 tracked-integrity.json。针对性源码hash见 source-sha256.json。运行前已有未跟踪导入文件，本批未删除或纳入证据。这里只新增当前目录，未提交、推送或创建PR。
