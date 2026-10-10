# 护甲定向重铸：实际装备获取方式

基线main：`a071697f85496b8dd0f7e63aa68f7e00d74c5d80`。本轮没有发现所查装备库的“已设计却完全无法获得”缺陷；交付是一个明确的新获取选项，不宣称修复掉落或结算漏洞。

## 检查与选择依据

现有正式商人覆盖15种普通底材；当前制造池39个词缀家族的117个阶级记录均存在合法入口，见修改前捕获的`baseline.json/legal_pool_coverage`。当前正式掉落沿`canonical_v51`，地图物品等级取`clamp(wave*2-1,1,30)`；断垣III、晴泉III等已覆盖铁革T3所需等级16。商店等级1仅能制作T1，不能跳过等级门槛。

铁革`ironhide`自词汇39已存在，仅灰烬皮甲前缀：T1等级1、30–50护甲；T2等级8、55–80；T3等级16、85–120。固定值进入原角色护甲和物理命中减伤公式。原工艺有暴击、偷取、伤害及四种抗性定向，共8个目标，但没有护甲定向。原随机掉落、赋魔和重铸本来即可产生铁革。

本批仅向原`TargetedReforgeRules`追加`targeted_reforge_armour → ironhide`，成为第9个选项。沿用魔法16、稀有40碎片价格，替换全部原词缀，保证至少一条铁革；阶级、正权重、前后缀容量和合法完整结果都由原目录及算法决定。不是保留其他词缀的附魔，不保证高阶或更强。无合法目标、普通装备、已穿戴装备仍不可用。

**schema61、装备词汇51不变；没有迁移。** 底材、词缀预算、掉落池、制造算法、事务、护甲公式、Main及天赋代码均未修改。

## 实际获取与结算验收

同一正式存档中的真实路径：受控合法32枚碎片物品 → 商人买灰烬皮甲8 → 原赋魔8 → 原工匠护甲定向16 → 同UID入包 → 装备 → 原Main物理伤害结算 → 重开。

资金通过原奖励入口及Main奖励批处理加入；不声称自然刷图挣取。实际按钮/确认框信号用于验收，没有声称物理鼠标点击。最终示例得到等级1、魔法、铁革T1护甲35；100物理命中经原公式为93.4579439252，实际Main的20物理命中也检查相同公式。魔法与稀有事务另行验证精确余额、取消、写盘失败及同报价重试、重复确认、缺1碎片、装备后旧报价失效、外部修改和重开保存。

| 最终有限检查 | 结果 | 证据 |
|---|---:|---|
| 新目标规则/事务/真实商店及UI/装备/Main原生X11 | 902/0，exit0 | native.json/log、confirmation.png |
| 同范围headless，早于截图及夹具批处理整理 | 901/0，exit0 | headless.json/log |
| 当前抗性工艺元数据契约，含追加顺序 | 31/0，exit0 | current-metadata.log |
| 原抗性工艺控件，当前9选项 | 23/0，exit0 | controls.log |
| 内容数据库精确合并、卡片差异、旧数据重现 | 通过 | reference-verification.json/log |
| 当前HTML生成检查、浏览器原搜索及铁革关联链接 | 通过 | browser.json/log |

新目标测试包含192组合法计划、15底材×两种稀有度范围检查、原三个阶级和五种词缀数量见证，以及**756组修改前真实旧工艺计划的类型字节指纹比较**。原14种工艺的结果不变，全球RNG和输入不被计划调用改变。新的整段完成断言防止脚本异常提前返回被误当通过。每个Godot进程30或45秒上限，独立/tmp XDG。

## 失败尝试与历史检查边界

全部原始失败保留，未算通过：

- `parse-attempt.log`：新测试两处动态返回值缺少显式类型，解析失败exit1，已修正。
- `incomplete-attempt.json/log`：测试错误读取`health`，实际字段为`remaining_health`。脚本提前返回却打印896/0、exit0，**此记录无效，不是通过**；修正字段，并新增完整结束断言后重新执行。
- `controls-before-count-update.log`：原控件测试还期待8个目标，23项中1失败；同步当前9项后23/0。
- `historical-integrity-blocked.log`：调用旧v103依赖守卫时48项中2失败。其b7d98c5基线期望旧DamageResolver/DefenseRules哈希；这两文件在本批前后逐字节相同，证据见`historical-integrity-evidence.json`。没有把旧全套历史比较算通过，也没有修改历史哈希或冻结夹具。当前元数据31/0是单独的列表/价格/风险契约；本批结果兼容性另由a071697捕获的756组计划证实。
- `browser-attempt01.log`：浏览器文本将“稀有”和“40”间的HTML空白保留；测试改为规范化空白后检查。`browser-attempt02.log`：关联卡尚在其他分类，测试先通过原锚点导航显示铁革卡再点击链接。两次均未改产品HTML。

首次原生截图有测试直接调用奖励帮助方法引发的忙状态保存提示；最终夹具改用Main既有奖励批处理，正常保存后截图。没有清除提示来伪装成功，也未改生产保存逻辑。`native-before-fixture-batching.log`保留早期结果。

## F8与复验

复用原导出器，增加可选操作筛选，完整导出默认行为不变；本次只生成新操作示例及权威目标元数据。精确合并仅增加`crafting.targeted_reforge_armour`及材料规则中的同名操作。原数据、原例子和旧schema标注均保留。

3817张原卡片中3813张逐字节不变；修改4张为铁革、制作碎片、货币碎片、工匠索引。新增1张目标卡，共3818张。62个相关内部链接有效；新生成器+旧数据逐字节重现基线HTML，合并幂等，当前HTML通过`--check`。保存结构、装备池、伤害/防御、源树覆盖表均做基线字节比较。

```bash
XDG_DATA_HOME=/tmp/godot-armour-reference-fresh XDG_CACHE_HOME=/tmp/godot-armour-reference-fresh-cache timeout 30 godot --headless --path . --script res://tools/armour_targeted_reference.gd
python3 tools/merge_armour_targeted_reference.py
python3 tools/build_reference.py
python3 tools/verify_armour_targeted_reference.py
python3 tools/build_reference.py --check
python3 docs/qa/armour-targeted-reforge/browser_check.py
XDG_DATA_HOME=/tmp/godot-armour-test-fresh XDG_CACHE_HOME=/tmp/godot-armour-test-fresh-cache ARMOUR_REPORT=/tmp/armour-test-fresh.json timeout 45 godot --headless --path . --script res://tests/armour_targeted_reforge_test.gd
```

基线捕获脚本必须在a071697、生产修改前运行，当前版本不应覆盖原基线。原生测试用已启动的X11、`--rendering-method gl_compatibility --audio-driver Dummy`替换`--headless`并使用新的XDG路径。F8浏览器检查仅本机回环服务，结束关闭；没有外部发布或游戏F8按键验证声明。[原生确认框](confirmation.png)与[F8卡片](f8-armour-card.png)已查看。

限定交付没有执行阻塞；上述旧v103整体历史依赖检查仍未通过，保留为明确限制。未运行完整core、600秒检测，未改模型、未导出Windows或封包。
