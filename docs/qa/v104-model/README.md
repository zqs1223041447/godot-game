# v104：真实天赋预览、旧事务差分与面板交叉验证

最终验证覆盖 **1,108 项不同检查**：core 553、mastery 254、jewels 184、boundaries 101、panel 16。前四类模型与真实面板均使用 `CanonicalGameState` 和锁定源树 3.29.1；没有使用旧 `build_state` 原型天赋图。最终测试文件采用已实际通过的逐元素严格类型重载比较版本。边界重试不计入新的覆盖数量。

- Godot：4.6.3.stable.official.7d41c59c4；Linux headless
- 生产事务基线：181216b；测试内冻结复制原 `allocate_passive` / `refund_passive` 两个方法
- 锁定源 SHA256：7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122
- 隔离目录：`XDG_DATA_HOME=/tmp/godot-m1-v104-model/data`；config/cache 同在该隔离根下
- 测试期间没有修改生产模型、UI、规则、存档格式或点数规则
- 未执行历史全量、Windows 实机或图形截图验收

## 覆盖

1. 初始可分配、已分配、合法叶退款、桥接断路、保留职业起点、无点仍可退款、未知 ID、节点/精通参数类型、普通节点不能携带精通选择，以及完整存档修订上限
2. 原图支持路径 BFS，实际连通的未实装节点22497；可达支持节点709个；精通4139、同组显著53118、效果47642；未选/非法效果、无同组显著、退款依赖和精通自身退款
3. Scion原路径2151→37690→48423→6230，真实特殊珠宝入袋/插孔；已插孔退款拒绝、断开支持孔路径拒绝、26740断连分配/退款合法。另验证桥55906有珠宝时可退、相同正常连通夹具无珠宝时不能退，保留特殊珠宝例外
4. 每个比较用例分别执行真实分配/退款和冻结基线事务，比较完整返回、完整内存、实时属性及最终保存字节；全体非天赋/修订字段保持，含物品、UID、货币、物品序号、制作修订和旅程状态
5. 每次预览严格检查原始 `var_to_bytes(snapshot)`、实时属性/战斗快照/技能配方/cache、revision、changed、save_attempts、successful_saves、写调用、磁盘收据和磁盘字节/文件列表、last_error/busy/content epoch不变；固定全局RNG前后对照；选择和修改返回值不污染后续结果
6. 已允许预览之后变化仍由真实提交重查修订和节点成员关系；分配及退款各自注入保存失败，未改变内存/磁盘/资金，恢复后同修订重试只保存和通知一次；外部改写/删除文件不影响合法性预览，真实提交仍检查磁盘收据
7. 真实 `CanonicalPassivePanel` 与模型交叉：树点击桥接显示拒绝→叶节点清旧原因→实际按钮退款/再分配；下一帧无残留busy；隐藏时changed仅保留dirty，重开刷新一次；可见时外部事务使用deferred刷新

## 执行记录与保留的失败

| 执行 | 退出码 | 检查 | 结果与用时 |
| --- | --- | --- | --- |
| `first/run.log` | 1 | 未执行 | 测试脚本自身第309行Variant推断错误；另有Fontconfig不可写缓存告警。补Dictionary显式类型并设置隔离cache/config |
| `first-execution/run.log` | 1 | 1,108 | core553、mastery254、jewels184、panel16全部通过；boundaries两处重载原始Variant字节比较失败。五组分别38,835 / 16,358 / 13,187 / 2,938 / 1,495 ms |
| `boundaries-retry/run.log` | 0 | 101 | 仅受影响边界组，逐元素严格类型比较通过；3,236 ms |
| `boundaries-order-diagnostic/run.log` | 1 | 101 | 仅边界诊断。故意加强为只排序Dictionary后仍要求Variant容器字节相同，重现两处失败，列出全部差异路径；2,801 ms |

首两次失败的完整测试源分别保存在 `first/failed-test-source.gd.txt` 与 `first-execution/failed-test-source.gd.txt`。已通过边界版本在 `boundaries-retry/passed-test-source.gd.txt`，与最终 `tests/passive_action_preview_test.gd` 运行逻辑相同；最终仅补充JSON容器元类型边界的注释。诊断版本也单独保留。已通过的四组没有重跑。

### 重载比较的实际边界

不能把最初两处失败描述为“只有Dictionary键序变化”。完整诊断还发现：

- `$`、`$.items`等Dictionary按canonical JSON保存时重排插入顺序，报告记录具体前后键列表
- `$.migration_ledger.legacy_allocated_nodes` 从 `Array[String]` 容器元类型（Godot builtin 4）变为JSON解析后的普通 `Array`（builtin 0）
- 以上数组的元素顺序、每个元素的类型和值均保持；整个构筑排序JSON完全一致，所有递归键/数组索引/原始数值类型和值以及live stats一致

该容器元类型现象属于原有JSON保存/读取路径：当前批次未修改 `_init`、`_persist`、`load_build`或解码；旧迁移初始数据使用 `Array[String]`，JSON本身不保存该容器注解。最终重载断言复用现有 `CraftingTransactionPlanner._same_data`，严格区分int/float，按数组索引比较全部元素；不把JSON未承诺保留的Array容器注解作为v104功能不变量。**预览前后仍要求未归一化的原始typed bytes完全相同**，没有降低预览只读检查。

## 复现

```bash
mkdir -p /tmp/godot-m1-v104-model/{data,config,cache/fontconfig}
XDG_DATA_HOME=/tmp/godot-m1-v104-model/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v104-model/config \
XDG_CACHE_HOME=/tmp/godot-m1-v104-model/cache \
V104_MODEL_OUT="$PWD/docs/qa/v104-model/new-run" \
/usr/local/bin/godot --headless --path . --script res://tests/passive_action_preview_test.gd
```

仅重跑受影响组时设置 `V104_MODEL_CASE=core|mastery|jewels|boundaries|panel` 中一个值。不要把此命令改为历史全量入口。日志及报告是实际执行证据，不将重试次数叠加为新增覆盖。
