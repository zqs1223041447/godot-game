# 回收与制作四例接入隔离运行器（2026-10-16 UTC）

本批开始于 `372f1f5` 加已验收制作夹具改动；实际运行时基础提交为 `98f1e0ee2294dbd77bcc48c70b0cd164e3b2e98a`（同一组夹具已由主任务提交）。本批只改运行器、其Python测试与运行器文档，不改生产源码或四个GDScript测试；没有执行提交、推送或合并。

## 实际执行

Godot 4.6.3 headless，从 `cases("full")` 仅筛选四个新增名称，顺序调用 `run_case(case, "/usr/local/bin/godot", ROOT, fresh_output_dir, 90)`；每例fresh data/config/cache，无资源导入、编辑器、全套或并行Godot运行。

- `recovery_currency_compaction`：308断言、零失败，6.233秒
- `jewel_crafting`：1375断言、零失败，14.157秒
- `crafting_growth_transactions`：286断言、零失败，10.846秒
- `normal_gem_trade_transactions`：330断言、零失败，31.411秒

4/4通过，共2299次累计断言、62.647秒子进程累计时间。全部退出0，无错误、警告、保护拒绝或超时。每例临时XDG均已清理。四个真实摘要前缀依次为 `Recovery currency compaction:`、`Ordinary jewel crafting:`、`Crafting growth transactions:`、`Normal gem trade transactions:`；只接受唯一匹配行、精确数量和零失败。

四例保护条件均要求 `XDG_DATA_HOME` 以 `/tmp/godot-m1-` 开头；正式宝石交易还验证 user-data 目录位于其中。默认 `godot-m1-transactions-` 满足契约。脚本没有场景环境变量、用户参数或可选报告目的地；只写fresh XDG内的user://存档。保留运行器日志和report.json，不虚构独立JSON报告。未修改run_case及既有购买报告/燃烧证据隔离行为。

Python单元测试23/23通过，保留已有22项。新增检查覆盖full-only、脚本/摘要/精确数量/前缀、空参数与报告配置、fresh XDG、重复执行隔离、原进程环境不变、污染报告变量清除、摘要缺失/重复/数量上下偏差/失败数/脚本错误/非零及78拒绝。

6254个批次开始前已跟踪QA文件逐文件SHA256保持不变；清单摘要见 `historical-qa-verification.json`。四个套件源码执行前后SHA256保持不变；运行器、Python测试与文档的修改前后hash见 `source-hashes.json`。这些核验不等于重新执行历史用例。

## 配置与限制

quick仍15例/1414预期断言；full现63例/82703预期断言。仅实际执行新增四个Godot用例与Python测试，未重跑完整quick/full，不将配置数称为全量通过。累计断言不是互不重复的需求数，不代表Windows画面、FPS或性能验收。

原始输出目录 `/tmp/recovery-runner-20261016-9aul524k`；本目录包含日志与汇总持久副本，其中临时绝对路径仅用于追踪。仅本地集成验收；远端交付由主任务另行核验。
