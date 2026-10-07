# 源码批次93 混沌防御：F8有限增量

本批只运行一次独立 `tools/chaos_defense_reference.gd`，2.423秒、exit0、stderr为空。没有加载历史 `export_reference.gd`，没有调用collect、source coverage、Main、地图生成、随机装备或素材导出。项目显示版本按生产仍为0.87.0；当前存档与装备词汇51，源政策49。

## 真实输入

- [实际Main结果](../v093-integration/main-result.json)：130项、0失败；复用其蚀影飞弹与守卫攻击receipt
- [实际Main装备夹具](../v093-integration/equipped-fixture.json)：同次运行通过真实装备事务保存的两个魔法指环。导出器decode并完整验证schema51，再核对 `tests/chaos_resistance_equipment_test.gd.legal_ring`、两个实际槽位、每枚仅1条25%混抗后缀与最终50%有效混抗
- Main测试采用受控进度、资源、战斗探针与清图辅助，不是自然游玩、自然掉落概率或FPS验收。首轮测试夹具错误保留在上级integration记录中，本批读取最终130/0结果
- [导出输入指纹](export-input-sha256.json)包含136个实际输入。继承脚本依赖闭包在导出后补入并立即核对最终canonical规则SHA256；此前已冻结的全部输入没有漂移。未伪称旧Main重跑覆盖之后的历史版本门禁补丁，门禁有独立22/0记录

## 增量范围

新增混抗词缀、蚀影守卫、锁点混沌攻击、蚀影巡逻、混沌防御规则五张卡。更新原指环可选词缀、15个旧词族的新池资格、当前掉落配置与必要当前schema说明。新池只替换原30%九槽入口；明确当前新掉落分布会变化，显式旧池和旧词汇回放保持。

正文数值直接来自生产目录、DefenseRules或实际Main receipt。波级5/10无机制普通守卫的单次混沌伤害分别16.64/19.44；双戒50%后8.32/9.72。实际Main进攻62.4→46.8，受击17.2→8.6、先耗盾5、生命损失3.6，均不称为DPS。

catalog使用原token拼接；77个原顶层段完整保留，旧池、旧loot profile、旧怪物、旧攻击、源树、中文字典、旧地图元数据保持。四图路线卡及普通珠宝制作卡原字节保留；这些既有章节仍含其历史导出元数据，当前51/49/51合同由新防御卡及当前装备规则说明。全部旧PNG、字体和原图鉴静态资源保持，不新增图片。

[catalog保全](catalog-format-preservation.json)、[卡片与资源保全](preservation.json)、[逐卡SHA256](card-sha256.json)及[当前输入清单](../../reference/source_inputs.v093.manifest.json)记录精确范围。新卡直链[混沌防御合同](../../CHAOS_DEFENSE.zh-CN.md)。只做静态资料、链接、搜索字段、数值与来源核验，不声称原生F8视觉、截图、完整战斗、安装包或发布验收。

最终聚焦复核通过：3777张旧卡原字节保持，25张只在批准范围变化，新增5卡；3852个唯一锚点、本地链接与新卡搜索记录全部通过。44个展示数值核对通过，246张原PNG、1份字体及其余受保护资料共253文件原字节保持。首轮复核发现Godot再次序列化receipt时产生浮点末位变化；原失败日志保留，Python合成改为直接读取Main原JSON的receipt，最终逐值精确相同，没有重跑Godot或Main。

## 复核

```sh
python3 docs/qa/v093-reference/check-reference.py
```

合成脚本 `merge-fragment.py` 只接受基线897dbfc未改catalog，防止在已合并文件上重复插入；复核不重跑Godot导出或Main。
