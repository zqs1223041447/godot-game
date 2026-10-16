# 购买六例接入隔离运行器（2026-10-16 UTC）

基础提交：`3b68b81`。本批只改运行器、其Python测试及文档，不修改生产逻辑或六个GDScript测试；没有提交、推送或合并。

## 实际执行

Godot 4.6.3 headless。从 `cases("full")` 选择名称含 `purchase` 的六例，顺序调用 `run_case(case, "/usr/local/bin/godot", ROOT, fresh_output_dir, 90)`。每例独立fresh XDG，无导入、编辑器或并行Godot运行。

- `equipment_purchase_transactions`：115断言、零失败，10.545秒
- `equipment_purchase_gameplay`：73断言、零失败，6.185秒
- `flask_purchase_transactions`：58断言、零失败，10.295秒
- `flask_purchase_gameplay`：79断言、零失败，6.535秒
- `jewel_purchase_transactions`：48断言、零失败，9.794秒
- `jewel_purchase_gameplay`：43断言、零失败，5.483秒

6/6例通过，共416次累计断言，子进程累计48.837秒。全部退出0，无错误、警告、保护拒绝或超时。临时XDG已清理；五份JSON报告清理后仍存在并复制到本目录。装备事务没有单独JSON输出，保留日志。

外层故意将五个购买报告变量设为 `/tmp/purchase-runner-contamination-must-not-write`，实际报告全部位于本轮fresh输出目录；污染路径未创建。装备证据由套件原子新建目录，四个可选报告各使用运行器新建随机目录；不用历史仓库目标。

Python单元测试22/22通过，新增购买矩阵精确配置、full-only、计数上下偏差拒绝、真实保护前缀、空用户参数、环境污染清除、原环境不变、重复隔离、报告保留和重复目标不覆盖检查。已有错误/78/超时等严格门槛不变。历史QA的6213个已跟踪文件逐文件SHA256前后相同；见 `historical-qa-verification.json` 的清单摘要。

## 配置与限制

quick仍15例/1414预期断言；full现59例/80404预期断言。本批只实际运行新六例与Python测试，未重跑完整quick/full，也未复跑历史游戏日志或全仓库套件。累计断言不等于互不重复的需求数。玩法测试为headless实际游戏流程，不代表Windows画面、原生2K、FPS或性能验收。

`report.json`及日志保留原始临时绝对路径用于追踪；仓库内对应日志与 `*-results.json` 为持久副本。原始目录：`/tmp/purchase-runner-20261016-pbl6wc5u`。源码hash见 `source-hashes.json`；本目录所有结果都是本地验收，远端交付由后续独立发布核验确认。
