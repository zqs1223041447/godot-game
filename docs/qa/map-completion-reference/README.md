# 地图清图与普通奖励口径同步

运行基线：`b46668444d1f491a7eb1d37adb63fc6e41016d45`，已正常快进合入 main。文档分支 `codex/map-completion-reference` 单独供审。

现有探索合同、路线说明及 F8 清图说明仅描述根怪/首领/活后代/队列清空，未说明必需谱系的合法死亡结算与进度/奖励独立口径。本次只补齐这些已落地边界：登记身份推进根怪完成；原standard资格控制经验、掉落、里程碑与药剂充能；来源/路由失效的未结算必需尸体保留并阻塞，权威身份账本防重，HUD同口径。

F8只更新已有探索规则和地图装置卡片及对应搜索文字，3816张卡中的其余3814张逐字节保持；替换这两张卡和搜索段后整页与基线逐字节相同。相关13个链接通过。`catalog.json`、完整源树覆盖、JS/CSS、运行代码逐字节保持；没有刷新历史schema标签、地图数值、图片或历史验证计数。

未来机制仍只接受空配置、空可选遭遇与standard路线；没有开放赛季、精华、封印交互或新经济来源。没有运行Godot导出、战斗、收费/存档验证或其他运行测试。

本次仅重建一次 `python tools/build_reference.py`，运行 `python tools/build_reference.py --check` 确认一致，再做上述两卡/搜索及输入保全核对。`verification.json` 保存精确基线、保全SHA-256、修改文件指纹和链接检查范围。

运行行为证据仍见[清图接缝](../map-completion-reward-seams/README.md)及[未结算尸体边界](../map-completion-reward-seams/pending-death-boundary/README.md)；本次没有重跑或累加其检查数字。

首次静态脚本对搜索记录ID重复添加类别前缀，导致断言失败；已按原数据中的完整ID修正检查，没有因此修改文档内容。
