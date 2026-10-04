# v0.30 元素庇护：单一地图特殊词缀

基线 v0.29 冻结 6bccd1daf9a370be68fb363b96bb510d77b3a740。后端独占新的地图防御应用/原子入场模块、main接点、MapCatalog/Compiler及定向测试/图鉴。root独占UI与WorldMarkers，以及MonsterCatalog.mechanism_text显示函数。v29冻结物不变。

`MapCatalog.SPECIAL.elemental_aegis`：`name` 元素庇护，`kind="defense"`，`minimum_wave=4`，`resistance_bonus=0.20`，`damage_types=["fire","cold","lightning"]`。所有实际地图怪物包括首领/死亡后代的原始三元素抗性各加20个百分点；共用 `DefenseRules.source_profile(actor="monster")` 计算0–75%有效值。物理/混沌与护甲、生命/护盾资源、伤害、速度、稀有度、机制及奖励保持。仍最多1特殊词缀，与霜纹/雷纹巡逻互斥；地图选择/制作免费测试政策不变。

怪物字段供UI直接读取：

- `defense_stats.fire_resistance/cold_resistance/lightning_resistance`：加成后原始合计，不可直接当减伤百分比显示
- `resistances.fire/cold/lightning`：最终有效值，实际 `DamageResolver` 与UI都读这里
- `map_defense_source={modifier_id,source_stats,raw_resistances,effective_resistances}`：本次来源与只应用一次标记；字段存在即拒绝再次应用，不随死亡复制到标准子怪

MapDefenseRules只产生候选副本，不变异输入；MapAdmission在标准根怪/后代生成、旧普通遭遇词缀之后调用。配置校验早于RNG/ID，应用失败恢复整份工厂队列/身份/谱系/trace，不降级普通怪。后代从原模板生成，再各自应用一次，不从父代有效抗性重复叠加。

测试：三元素分量分别结算、混合命中/盾后生命顺序、原25%火抗变45%而冰电20%、原始超上限仍有效75%、物理/混沌不变；相同种子自然根怪/死亡后代身份与稀有度奖励不变；重复/非法配置与保存/运行时分离。仅本批及直接依赖，不运行600秒/历史全量。

当前数值是本游戏测试平衡，非PoE地图经济或掉落收益承诺。schema19、原v021目录/测试隔离、240格、已得物品与资源不新增持久字段。
