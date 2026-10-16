# 焦点回归运行器接入核验（2026-10-15 UTC）

仅本地集成验收；无提交、推送或 PR。本批未运行完整 quick/full，没有重复执行负向 Godot 控制或历史日志复核，也没有资源导入、编辑器、性能测量或 Windows 验收。

## 实际执行

从 `cases("full")` 仅筛选新增三例，以 `run_case(..., timeout=90)` 顺序执行 Godot 4.6.3 headless，输出先写入 fresh `/tmp/transaction-regressions-focus-6di0zfj3`，再复制本目录供保全：

- skill_binding_focus_capacity10：3303 / 0，退出0，12.718秒
- skill_binding_focus_capacity11：3629 / 0，退出0，12.962秒
- talent_details_focus：5219 / 0，退出0，26.264秒
- 共3/3例、12151次累计断言，51.944秒；错误、警告、超时及保护拒绝均为零
- 20/20项Python运行器单元测试通过，完整日志在 `python-unit-tests.log`

每例独立 fresh XDG data/config/cache，结束后清理临时存档；技能两例使用 `godot-skill-focus-`，天赋使用 `godot-talent-focus-`。实际命令、隔离目录、精确计数与进程结果见 `report.json`；其中 `mode=focus-targeted-only` 明确表示只运行新增三例。日志内临时路径仅供追踪，不能据此读取已清理的存档。

## 配置与保护

quick仍为15例、1414断言。full配置由50例、67837断言扩展为53例、79988断言；该总数是配置基准，不是本次完整执行结果。

`Case.user_args` 默认为空元组，仅容量11例使用 `("--capacity11",)`，运行器拼接 `-- --capacity11`。默认10行及天赋不追加分隔符；所有正向例均不传 `--disable-follow-focus`。两套测试不读取容量或负向环境开关，因此未虚构环境变量清理。原有场景环境隔离不变。

新增Python用例核对三例full-only、脚本/摘要/前缀/精确计数、真实完整argv、新建与重复运行隔离、计数增加/减少均拒绝，以及打印成功摘要后退出1或78仍失败。原有19项测试保留，继续覆盖超时、脚本错误、错误/重复摘要、环境污染等保护。每例90秒上限不变；技能75秒及天赋80秒内置看门狗不能替代外层限制。

## 证据一致性与限制

运行前后 runner、Python测试、两套GDScript测试与技能面板hash相同，见 `source-hashes.json`。天赋生产面板另核对独立审查hash与本次结束hash一致；天赋独立审查已由协调者确认通过，无后续源码调整。完整检查数表示可能重叠的断言次数，不是独立需求数。

这是无头真实输入和1280×720逻辑布局验收，不代表原生2K、Windows像素、帧率或全仓库历史测试通过。远端发布取消阻塞保持不变，未尝试绕过。
