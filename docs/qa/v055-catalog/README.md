# v0.55 锻纹短刃目录与纯制作验收

基线为 `5e442d98e82b248efc3a553fdf9bf95733929096`（v0.54）。本批只修改装备目录与新增独立 `ForgebladeProfile`，既有制作动作、费用、种子规则和目标候选规则均未改写。

新增底材为1×3的锻纹短刃，使用既有七字段本地武器profile；基底物理4来自 `WeaponLocalRules`。词池严格为砥刃、淬锋、深汲三个前缀，泉旋、全局暴击几率提高、全局暴击倍率三个后缀。旧原始家族字典保持，当前查找仅派生两个本地族、两个全局暴击族的新增底材资格。其余旧底材资格不变。

当前装备词汇为34。新的 `canonical_v34` 自然掉落表依次为旧build legacy25、runewood20、defense10、local weapon10、build nine slot30、forgeblade5；新增份额来自旧 `canonical_v27` 的legacy份额。所有旧命名pool/profile及旧生成适配器仍可精确回放。当前自然掉落接口显式推进到此新表。

## 单次集中运行

命令：`/usr/local/bin/godot --headless --path . --script tests/forgeblade_catalog_crafting_test.gd`

- Godot 4.6.3，独立临时 `XDG_DATA_HOME`，耗时5.128秒，exit0
- 26,540项检查，0失败
- 6族的全部64种族集合×3稀有度×6个ilvl边界；普通/魔法/稀有合法数量为1 / 6与9 / 15、6、1
- ilvl1/8/16处的全部合法混档组合；T3最多3,402种稀有族与档组合；整数掷值只测每族每档min/max及非法边界，不枚举全部整数乘积
- 非法实物涵盖同族跨档重复、双前缀魔法装、超前缀数量、非法词族、异常tick及旧1至33词汇拒绝新底材
- 新生成器验证tier门槛、rarity数量、当前6池准确分支与RNG；白装W4、合法6词T3稀有装W13；本地项不进入全局stats，global crit和资源项仍正常进入
- 既有六工艺及定向重铸沿原规则执行，身份保持、纯输入与全局RNG不变；伤害方向仅两本地族、暴击方向仅两全局暴击族；双偷取无候选，报价与计划均拒绝且无费用

## 冻结v0.54对照

`tests/fixtures/v055/oracle_manifest.json`记录精确基线提交与五个原始源码SHA256；独立oracle只移除全局class_name，并改写这五个源码之间的preload路径，未修改逻辑。原始源码与fixture哈希均已核实，测试也校验fixture哈希。

- 旧7个pool、4个命名loot profile、3个旧生成adapter，5个代表seed、ilvl1/7/8/15/16/30及所有rarity请求，共1,680个生成对照
- 每个对照均以 `var_to_bytes` 比较完整item与definition，并比较调用后的RNG state；旧长弓summary也包含在完整definition比较中
- 旧14底材、ilvl1/16、普通/魔法/稀有来源、原6工艺与4定向动作、seed0/4927/-817，共2,520个plan逐字比较；同时覆盖报价、动作元数据、种子版本与全局RNG不消耗
- 所有旧生成结果、定义、报价、计划以及可观察随机流均相等

原始日志为 `catalog-crafting.log`；命令、临时目录、退出码、耗时和当次生产/测试源码SHA256为 `catalog-crafting-result.json`。日志有Fontconfig不可写缓存的环境提示，无SCRIPT ERROR或测试失败。本报告不代替战斗、存档事务、真实UI与本地硬件性能验收。
