# v0.56 短刃近战普攻同源图鉴验收

结论：集中图鉴检查通过。唯一一次Godot导出12.606秒、exit0、无错误行；导出前后生产来源指纹一致。Python构建、确定性构建检查、近战普攻聚焦检查与JS语法检查均exit0。

## 本批结果

- 新规则卡`rules-melee_basic`直接使用实际BASIC_MELEE/SkillCompiler recipe与packet：melee、半径60、全角90°、最多1目标、基础系数与附加效用各1.0，只有direct、没有secondary
- 对照裂刃原半径95、全角180°、多目标、2.8/2.8、12魔力和1.4秒冷却；近战普通攻击沿原attack_timer、不产生技能资源字段
- 5件原合法短刃样本的basic更新为近战；总共90个真实命中包。局部W只进入basic/direct与cleave/direct，其他role完整保持
- 2件真实Canonical装备UID，经生产位置规划器、完整schema34校验、实际get_basic_cast生成：白装原包22、默认20力量后22.88；合法六族T3原包31、默认力量后32.24。只装备短刃，其他装备已通过同一位置规划器移入背包，没有额外分配天赋
- Canonical示例只在新建内存模型提交纯位置计划；save_attempts=0，没有调用玩家save/equip落盘路径
- 2份从独立v0.55提交63d84b2原catalog提取的短刃飞箭快照，当前冻结读取器返回原B18 projectile与原secondary；无短刃W，不重解释为新近战
- 26个新卡数值加72个短刃卡数值，共98个HTML数值逐一核对；内部锚点、全部旧卡ID和本地素材有效
- 完整旧catalog经精确许可投影后语义SHA-256保持；source_tree全部结构、原始词句、几何和execution保持；source-tree-coverage.json字节保持；全部68张旧PNG字节保持，无新图

图鉴明确说明：贴身普通攻击与裂刃组合输出提高是新行为，不承诺旧短刃同seed战斗等价。单次成功命中不是实战DPS。运行时准入、墙体、手动空挥、投射物容量和资源路径由本版本独立玩法套件负责；图鉴的静态文字不能替代这些运行时验证。

## 精确旧目录保护

`capture-v055-baseline.py`读取git对象63d84b2中的已发布v55数据，未用v56生产逻辑重建基线。`v055-reference-baseline.json`保存原完整catalog指纹、源树与覆盖指纹、旧卡ID、68图指纹和有限许可差异。

完整投影仅允许：

1. 一个新melee_basic导出段
2. 5个短刃basic对象从projectile/secondary改成唯一direct及其新伤害；这些是明确批准的新行为，单独按近战合同验证
3. 3处普通近战消费者元数据
4. 19处精确匹配的短刃消费者文本；带词缀的复合description只替换固定首句，其余每字保持
5. 游戏版本0.55.0→0.56.0，保存schema仍为34

除以上内容外，对整个旧catalog做同一个语义hash检查。没有豁免整个forgeblade、旧装备、旧技能、源树或词缀段；裂刃编译数值也完全保持。具体路径见`catalog-diff-review.json`。

## 命令与日志

在父任务确认工程版本及生产来源稳定后运行：

```sh
python3 docs/qa/v056-reference/run-reference-checks.py --export
python3 docs/qa/v056-reference/capture-v055-baseline.py
python3 docs/qa/v056-reference/run-reference-checks.py
```

唯一导出记录：`godot-export-result.json`与`godot-export.stdout.log`/`stderr.log`。生产来源指纹：`export-source-sha256.json`。四项聚焦结果与时长：`python-validation-results.json`。最终交付指纹：`final-artifact-sha256.json`。

首次基线捕获器只识别完整description相等，未涵盖实际装备description后接词缀行，故断言拒绝；失败日志保留为`baseline-capture.stderr.log`。修正为只允许固定首句替换且其余字符串完全不变，第二次捕获成功，见`baseline-capture-corrected.*.log`。没有Godot导出或聚焦套件失败，也没有为此修改生产代码或再次导出。

脚本不覆盖既有证据。只重做Python验证时使用`--check-prefix`传入新的日志前缀；独立旧基线不重写。

没有运行历史全量、600秒、工程再次导入或每版截图验收；不声称完成浏览器交互验证或Windows硬件性能验收。本任务不修改LUNA内容。
