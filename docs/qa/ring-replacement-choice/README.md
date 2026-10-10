# 双戒指右键换装目标选择

基线 `abf3c11143fabca1dfa14fd163c79ce73f5c1e46`。实际缺口是右键的目标选择：两枚戒指都已装备时，原行囊激活固定替换戒指一，比较戒指二后仍需改用拖放指定目标。原路径会安全回包旧戒指，不是物品丢失问题；容量/保存失败已有中文提示，没有为本任务虚构这些缺陷。

## 行为与边界

右键装备戒指优先使用空槽；两槽均占用时打开目标菜单，显示“替换戒指一／戒指二”及各槽当前物品名称。选择后调用原 `move_item`，取消不写盘。复用现有宝石选择菜单的 PopupMenu 生命周期与非嵌入窗口定位方式；单目标装备、拖放、待安置取回与悬停、回收/丢弃方法保持。

请求只保存 UID、目标列表和打开时的 revision；模型变化、关面板、区域变化或重新绑定模型时取消，取消后的回调不能操作。原事务仍负责容量、最终构筑验证和原子保存，原 Main 仍负责装备后资源上限收敛。没有新模型资源、掉落、赠送、出售、销毁、schema 或装备效果规则。

## 有限验证

- `baseline.json/log`：17 项通过，真实视口右键复现立即替换戒指一。
- `attempt-03.json/log`：最终 40 项通过、0 失败。右键实际打开菜单，菜单通过所属窗口的 Enter 输入选择两个目标，Esc 输入取消；有空槽仍直接装备。
- 实际正式旧庭院 I 入场及已登记首领奖励，原死亡幂等账本复核。测试用独立 oracle 在最多128个seed中找到19，并在该次首领奖励入口控制 RNG seed；原生产掷骰仅执行一次，观测结果、UID、词缀和 RNG 与原生成器一致。这是确定性受控掉落，不冒充自然游玩录像。
- 两枚事先持有的高属性戒指为明确的合法装备夹具 `gear_000004`、`gear_000005`，按目录合法四词缀和原持有校验加入并装备；测试未把它们称为自然掉落。实际首领新戒指 `gear_000006`，物品等级1、原5词缀。
- 注入写盘失败后选择戒指二：显示原中文保存错误，完整内存/存档/UID/序号保持。满包夹具下成功替换复用新戒指原格，所有物品与序号保持，不出售、不回收、不丢弃。
- 从高属性旧戒指换到真实低等级掉落后，生命/魔力/护盾上限降低，Main 将当前资源收敛到真实新上限；技能行与绑定保持，完整构筑校验通过；存档可精确重载。
- 菜单打开期间执行合法整理会取消旧选择；关行囊取消，迟到回调无副作用；重复死亡仍不新增奖励或保存。
- `recovery-regression.json/log`：复用上轮待安置流程，48 项通过、0 失败，覆盖实际首领满包奖励、悬停/Shift、满包与保存失败拒绝、腾空间取回武器并装备、旧物品保留及重载。
- `preservation.json`：除一个 UI 文件外，661 个运行/资源文件原字节保持，原移动、回包、悬停和制作方法保持；catalog 不变。F8 的3818张卡只改 `rules-ownership`，其余3817张保持，21808个内部链接有效，新增中文受现有字体覆盖。

最终实际写出的 `owned.json` 为 schema61，SHA256 `56f1a173c5e867f4432b61008a91d45447d7176c918a6f2374cd3cc6431a161f`。

原始尝试保留：`fixture-attempt-01` 为初始化时错误地重绑场景脚本且稀有夹具仅三词缀，5失败；修正为场景入树前绑定观察脚本、合法四词缀后基线通过。`attempt-01` 的测试向 PopupMenu 直接推入键盘事件未触发选择，4失败及后续位置访问错误；改用已有宝石选择测试的 window_id/physical_keycode 输入，并复用已有菜单关闭方式，`attempt-02` 40通过。`attempt-03` 把程序隐藏取消替换为实际 Esc 取消，仍40通过。未掩盖或改写这些原记录。

仅为1280×720、暂停战斗的有限 headless 控件/装备流程；没有原生截图、全套矩阵、长期平衡结论、600秒检测、模型修改或Windows导出封包。

## 复现

```bash
XDG_DATA_HOME=/tmp/godot-ring-choice-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
RING_CHOICE_REPORT=/tmp/ring-choice-review.json \
timeout 35 godot --headless --path . --script res://tests/ring_replacement_choice_test.gd
XDG_DATA_HOME=/tmp/godot-recovery-comparison-ring-review XDG_CACHE_HOME=/tmp/godot-cleave-inward-cache \
RECOVERY_COMPARE_REPORT=/tmp/ring-recovery-review.json \
timeout 35 godot --headless --path . --script res://tests/recovery_item_comparison_test.gd
python3 docs/qa/ring-replacement-choice/verify_scope.py
python3 tools/build_reference.py --check
```

使用全新隔离用户目录。`RING_CHOICE_BASELINE=1` 仅用于旧 UI 行为复现，不用于修复后的回归。
