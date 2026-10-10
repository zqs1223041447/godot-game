# 待安置物品详情与装备比较

基线：`818b9a395b9a461e63f45fa8bfeb2ec71d316dd1`。仅修改 `CanonicalInventoryPanel` 的待安置标题、悬停进入/离开信号；复用 HUD、UnifiedItemPresentation、ItemHoverCard 和原点击取回事务。既有装备、背包和药剂悬停路径不变。

## 玩家缺口和结果

满包时正式地图首领的稀有装备和寻枝珠宝已合法进入待安置，但此处按钮只有底材名称的原生提示，无法直接看词缀或比较已装备目标。基线实际鼠标复现了该缺口，而既有只读展示接口已能返回所需内容。

现在可直接悬停待安置物品查看完整详情，装备可按住 Shift 对比；释放 Shift 恢复单卡。标题提示腾出空间后点击取回。没有新增自动领取、出售、回收、销毁或过滤规则，也未修改掉落、奖励幂等、容量、保存、schema61、装备效果或模型资源。

## 有限实际流程证据

- `baseline.json` / `.log`：修改前 17 项通过，确认真实指针进入按钮却无共享详情卡。
- `attempt-01.json` / `.log`：修改后第一轮 44 项通过。
- `attempt-02.json` / `.log`：增加同队列珠宝与列表重建悬停生命周期检查，最终 48 项通过、0 失败。
- 复用既有首领测试的 Main、故障模型、容量夹具和死亡账本帮助方法；不执行其历史套件或旧 schema 断言。实际正式旧庭院 I 入图、已登记首领死亡、原稀有装备掷骰与寻枝奖励、两件各一 UID、重复死亡拒绝均沿当前生产流程。
- 本次稀有弓为 `gear_000205`，4 条原词缀；同场寻枝独立保留。满包点击拒绝后，将 6 颗容量夹具宝石通过原移动接口装入合法辅助槽，腾出 2×3 连续空间；没有丢弃、出售或回收物品。
- 悬停、Shift 按下/释放、点击取回使用视口输入事件。原行囊激活信号完成换装。写盘故障的实际点击保持完整内存、旧存档字节、UID、序号和奖励账本；解除故障后取回并装备原 UID，替换下来的装备及待安置珠宝均保留。最终存档可精确重载。
- `owned.json` 为最终实际写出的 schema61 存档，SHA256：`0952b8791fb9ba8daea29916409b54c1c3a9dff447ef0bcd492b81aebb24bfd3`。
- `preservation.json`：其余 661 个运行/资源文件原字节保持，原移动/激活方法保持，catalog 保持；3818 张 F8 卡仅 `rules-ownership` 改变，21808 个内部链接有效，新增 UI 汉字受现有字体覆盖。中文刷图说明同步。

检查为 1280×720、暂停战斗的有限 headless 实际控件流程。满包由既有合法容量夹具构造；不是自然游玩录像、原生 F8 点击或长期平衡测试。未执行长矩阵、600 秒检测、Windows 导出或封包。此前总览性能问题仍未解决，本轮未测。

## 复现

```bash
XDG_DATA_HOME=/tmp/godot-recovery-comparison-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
RECOVERY_COMPARE_REPORT=/tmp/recovery-comparison-review.json \
timeout 35 godot --headless --path . --script res://tests/recovery_item_comparison_test.gd
python3 docs/qa/recovery-item-comparison/verify_scope.py
python3 tools/build_reference.py --check
```

使用独立临时用户目录；该测试只删除自身隔离目录下的两种测试存档。基线记录使用同一检查的 `RECOVERY_COMPARE_BASELINE=1`，在生产文件尚未改变时运行。此开关验证旧行为，不能在修复后当作回归运行。
