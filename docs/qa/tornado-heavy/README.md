# 龙卷缓速强击：有限兼容扩展

基线 `af02c5ed9b934c4b1cafbe3da12c4b16314bbfea`。本轮先实际执行工作区/Git/Godot检查：文件与命令可用，工作区干净，本地和远端main一致，Godot4.6.3可启动；没有仅凭任务状态判断环境恢复。未配置缓存目录时的Fontconfig警告通过本轮独立 `XDG_CACHE_HOME` 避免。

## 对象与既有边界

只开放现有 `heavy_projectiles` 对 `tornado` 的兼容，沿用速度×0.75、主命中伤害×1.20、魔力×1.15。原来是明确排除，不当作历史缺陷。可核实的旧技术边界是速度编译只处理普通飞弹；上一轮已补齐龙卷母箭/子箭最终速度快照，本轮没有再次实现。原主命中标签为hit/attack/projectile，恰好覆盖母箭和子箭；独立爆炸没有projectile标签，因此不会获得增伤。没有找到要求改变伤害类型、分裂或返回顺序的机制冲突。

生产仅调整 `delivery_support_rules.gd` 的白名单、中文说明和对应元数据校验；Compiler、Main、DamageResolver、ProjectileRuntime、库存交易与schema61均不改。缓速与疾速可同装，各占一槽，速度相乘为1.0125，魔力相乘为1.265，主命中仍只增加20%。这是有限的内容取舍，不是平衡或DPS保证。

## 验收证据

- `attempt-01.json` / `.log`：首轮即 **555检查、0失败**。包含158组全部10技能的空链/原有单辅助编译完整字节对照，基线与当前一致；两种快照分别为基础及带真实已支持的攻击点伤/投射速度增幅。
- 新组合为缓速单辅助、缓速＋疾速、以及两个五槽组合：散束/物理专注/点燃/节能＋缓速，凝束/火焰专注/余烬/疾咏＋缓速。核验辅助顺序无关、原始伤害包和类型不变、各主命中分量总增恰好一次20%、独立爆炸不变、燃烧由火焰主命中派生而不重复乘算、距离/寿命/冷却/数量不变。
- 同一纯运行器对两种快照下的单辅助与疾速组合各推进有限2.5秒：3次母箭分裂、9次子箭返回、9次自然结束爆炸，全部清理。逐事件确认母箭先分裂而不返回/爆炸，子箭返回后寿命仍为1.7秒，结束事件在独立爆炸前；速度只改变事件发生时间。此为无目标/无地形的确定性机制检查，不是持续游玩录像。
- 复用上一轮正式交易与实际Main施放夹具：从零碎片进入原免费I阶地图，有限清理25个初始实体及后代，领取4碎片，正常报价/确认购买缓速宝石，入包并装进已有龙卷组。扣4碎片、一次保存/修订、重复确认拒绝、运行状态保持及保存重载均通过；没有注入货币或使用免费测试供应。
- 实际Main施放扣20.7魔力，母箭315、分裂子箭195。施放后卸下辅助，整个在途载体字节不变，随后分裂仍用195，下一次编译恢复原速。载体采样时间改为由实际射程/速度计算，从而复用原疾速夹具而不复制一套购买流程。
- 实际Main结算入口对同一高耐久、零护甲/闪避、有3护盾的受控敌人作母箭、子箭、独立爆炸对照。目标物理抗性25%、火抗50%。母箭物理15.45→18.54、火焰6.70→8.04；子箭物理10.815→12.978、火焰4.69→5.628；独立爆炸火焰11.70→11.70。核对真实护盾与生命扣减及事件标签。此段直接调用Main命中结算入口，不声称经过自然寻敌/扫掠碰撞。
- `delivery-rules.log`：既有定义/程序规则测试 **2765检查、0失败**。原疾速付费与载体流程因共享夹具改动另窄复验，`swift-regression.json`：**317检查、0失败，156组旧编译字节对照**。不汇总或修补无关历史计数。
- F8由已有同源导出器生成40条新组合示例，保留此前所有示例。`reference-verification.json` 确认只改变现有 `skills-tornado`、`supports-heavy_projectiles` 两张卡，其余卡逐字节一致；全部内部链接、现有字体覆盖、合并幂等及核心生产文件未改均验证。没有新增模型或图标。

## 复用与限制

`tests/tornado_heavy_test.gd` 继承上一轮付费获得→入包→装配→施放→卸下→分裂夹具，覆写辅助身份、定向编译/伤害检查与报告。上一轮基线提取和资料导出/合并脚本仅增加参数以复用，默认入口保持；原始证据仍绑定各自提交，未覆盖旧日志。

这次不改schema、不封包、不做Windows导出、不重复受限图形环境的性能测量。探索总览高帧间隔仍未解决。全部游戏验证为headless、有限受控检查，未做原生F8浏览器点击或正常画面验收，也不声称完整回归或平衡验证。

```bash
python3 docs/qa/tornado-swift/prepare_baseline.py \
  --base af02c5ed9b934c4b1cafbe3da12c4b16314bbfea \
  --out /tmp/godot-tornado-heavy-baseline --report /tmp/tornado-heavy-baseline.json
XDG_DATA_HOME=/tmp/godot-m1-tornado-heavy-review XDG_CACHE_HOME=/tmp/godot-heavy-cache \
HEAVY_REPORT=/tmp/tornado-heavy-review.json \
timeout 45 godot --headless --path . --script res://tests/tornado_heavy_test.gd
```

每次使用新的临时用户目录。规则入口 `tests/delivery_support_rules_test.gd` 上限15秒。资料复核用 `python3 tools/build_reference.py --check` 与 `python3 tools/verify_tornado_heavy_reference.py`，不需要全套导出/测试。
