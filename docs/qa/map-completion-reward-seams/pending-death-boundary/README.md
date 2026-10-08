# 未结算必需尸体失败关闭边界

审查基线：`aa0f44e9af0955ce9879bad3881ebea71c26f811`。这是既有故障边界修补，不将其归因于本次清图接缝回归。独立追加提交到原审查分支，未合 main。

原边界：所有必需根怪/首领已死、队列为空，仅剩最后一只必需后代。若其来源或路由失效，死亡入口拒绝且未记账，但 health 已非正；仅统计存活数量会允许清图，下一次过滤还会移除尸体。

最小修补只改 Main 和 MapRun：三个共用成员查询传入现有 `MonsterRuntime.roots` 身份账本。必需尸体的 `(root_id, id)` 未在 `processed` 账本中时，查询失败、HUD 阻塞，过滤和完成判断停止。检查不信任 actor 的 `death_processed` 标记；合法处理过的身份副本即使标记过期也可过滤。

没有新增死亡账本或改变谱系回收生命周期。正常 Main 在过滤前做校验，随后才调用 `collect_lineages`；在怪物集合中的合法尸体仍有其谱系账本。合法尸体过滤后，原账本可按现有规则回收。测试分别覆盖回收前的合法尸体副本和回收后的重复死亡通知；后者不重新插入怪物集合或产生新身份。未结算尸体在过滤前被拦住，原账本因此保留供合法重试。

本次只运行两项，均使用新 `/tmp` 用户目录、60 秒进程上限：

| 增量验证 | 检查 / 失败 |
|---|---:|
| 最后必需后代的故障/恢复/重复身份夹具 | 107 / 0 |
| 原固定种子默认 Main 对照 | 137 / 0 |

共 **244 / 0**，未重跑首轮 963 项。默认完整记录仍与修改前基线字节相同，44 次死亡，SHA-256 `84fd424092a955598bdac49d846e672ba3dea26af2196c768520a23f947431f1`；相同 artifact 已保存在上级目录，无需重复保存。

新夹具在合法正式 roster 上通过原防御/资源结算留下最后一具后代尸体，分别注入未知路由、来源键失配、来源记录缺失；每次检查死亡账本、普通奖励、FIFO、RNG、存档字节不变，尸体保留，不清图，HUD 查询只读。另验证 actor 标记为 true 不能冒充权威记账。恢复原来源和 standard 路由后合法重试一次；后代不增加普通奖励，过期 false 标记的已处理副本不重结算且可正常清理，最终完成并退出。没有声称自然战斗或赛季可玩。

没有修改 schema、配置开放、奖励路由开放、预算、存档协议或模型。`verification.json` 包含本轮输入指纹和对照结论，`result.json` 保留四个阻塞阶段，stdout/stderr 为原进程输出。

复跑使用上级 README 的 `run_case` 函数，添加：

```bash
run_case map-death-boundary-check tests/map_pending_death_boundary_test.gd
run_case v086-exploration-default tests/map_default_death_contract_test.gd EXPLORATION_MAIN_SAVE_ONLY=1
cmp docs/qa/map-completion-reward-seams/baseline-default-contract.json \
  "$task_output/v086-exploration-default/default-contract.json"
```
