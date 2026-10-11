# 蚀影牵引：同源参考验证

基线 `6dbf3f9695611f68a21e8d32af1847ce46f8530e`。仅导出蚀影飞弹＋牵引在既有四种构筑中的新增示例，以及牵引规则前后配对；没有运行完整参考导出、完整辅助矩阵或全测试套件。

- `reference-fragment.json`：通过原生产编译器、伤害预览和结算器获得32条新增技能示例；既有空链／单辅助／组合示例保持原字节语义
- 牵引规则新增2组蚀影前后对照：基础8→9.6魔力；贯穿／缓速强击／专注／节能构筑10.5984→12.71808魔力。加入牵引前后伤害包、配方、冷却及原状态策略完全相同
- `reference-verification.json`：仅蚀影技能、牵引辅助、牵引规则三张F8卡变化；其余3815张卡逐字节一致，21906个内部锚点有效
- 所有旧catalog示例精确保持；四个技能示例数组及规则／程序示例容器的原始JSON字节前缀也精确保持。catalog默认Git差异会把相似数据行误对齐，`git diff --minimal`、`--histogram`及`--patience`均显示7478新增／16删除，主要是新增32条完整示例与2组配对，无旧数组重排或全文件重序列化；合并幂等，原字体没有新增缺字。658个其他生产／资产文件不变，原瞄准、连锁、范围、陷阱、地图完成和重开函数精确保持
- `reference-check.log`：提交的HTML与catalog、模板一致。这里验证静态参考内容，不声称原生F8点击或自然游玩视觉验收

## 复现

```bash
XDG_DATA_HOME=/tmp/godot-shade-reference XDG_CACHE_HOME=/tmp/godot-shade-reference-cache \
  timeout 40 godot --headless --path . --script res://tools/tornado_swift_reference.gd \
  -- inward_pull res://docs/qa/shade-inward/reference-fragment.json shade_bolt
python3 tools/merge_tornado_swift_reference.py --skill shade_bolt --support inward_pull --qa docs/qa/shade-inward
python3 tools/build_reference.py
python3 tools/verify_shade_inward_reference.py
python3 tools/build_reference.py --check
```

原始输出分别保留在本目录的reference-export、reference-merge、reference-build、reference-verification与reference-check日志。此记录只覆盖参考内容；[实际场景验收](README.md)另行记录运行时测试结果与边界。
