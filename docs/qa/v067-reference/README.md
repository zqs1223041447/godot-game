# v0.67 F8 牵引辅助资料验证

本批新增牵引辅助元数据、四组生产 Compiler 前后状态、可见说明与交叉链接。旧技能零至双辅助示例保持，不把新辅助加入历史组合穷举。没有重新运行历史机制套件或另造展示世界。

代表状态使用同一个新建 Canonical 的战斗快照：直接新星、直接陨星、新星＋伏击＋感电，以及陨星＋伏击＋余烬＋广域＋凝域。每行只再加入牵引，最后一行达到五辅助上限。实际导出包含命中包、伤害、魔力、冷却、范围、异常配置，以及四字段 `area_impulse_profile` 和冻结 `snapshot.area_impulse_policy`。页面显示真实编译结果，不在 Python 重算机制。

执行入口：`python3 docs/qa/v067-reference/run-reference-checks.py export`、`build`、`verify`。每阶段记录命令、退出码、耗时、错误行、输入 SHA256 和执行中输入变化。唯一 Godot 导出使用独立临时 XDG 和已导入工程，不重新导入、不读取或写入玩家存档。`build --check` 只比较确定性页面结果。

聚焦验证覆盖四组新增配置与 48 个页面权威数值及可见标签、旧锚点和全部本地链接。旧 catalog 只允许新章节、辅助元数据与获取入口、两技能兼容列表、当前版本与 schema43 字段变化，其他语义必须保持；旧 source coverage、CSS、JS、图像清单、62 张运行时 PNG 和 69 张图鉴 PNG 必须保持原字节。新增 F8 PNG 必须等于运行素材原字节。

本批交付当前源码的 F8 资料，不生成 Windows、ZIP、PCK 或发布标签。编译预览不等于实际战斗、自然截图或 Windows 性能验收。完整合同见[牵引辅助规则](../../INWARD_PULL_SUPPORT.zh-CN.md)。

## 最终结果

- 唯一 Godot 导出 23.585 秒，HTML 构建 0.481 秒，确定性检查 0.468 秒，聚焦验证 3.642 秒；首次全部 exit0，无错误行或执行中输入漂移
- 四组生产 Compiler 前后状态、48 个 HTML 权威数值与可见精度通过；3821 个旧锚点全部保留，当前 3823 个唯一锚点和全部内部/本地文件链接有效
- 相对 `8d51ac6`，完整旧 catalog 只允许 29 处明确的新章节、元数据、获取入口和当前版本字段变化；旧技能示例、旧辅助 program 与整个伏击章节保持
- 源执行覆盖 JSON、冻结 26 枚里程碑奖励身份、旧装备/词缀/掉落数据保持；CSS、JS 和图像清单保持
- 旧 62 张运行时 PNG 和 69 张图鉴 PNG 原字节保持；新增后为 63 和 70，F8 牵引副本与运行素材 SHA256 同为 `386149d3ff0ecf93b2b70a7dda1af281c5e24a6bffb32f59352b00b239f47b8f`

[聚焦结果](focused-reference.stdout.log.txt) · [完整保全收据](v066-preservation.json) · [导出记录](godot-export-result.json) · [构建记录](build-result.json) · [确定性检查](build-check-result.json) · [聚焦执行记录](focused-reference-result.json)。

本资料任务只修改两个生成器、生成 catalog/HTML、新 F8 图片副本和本目录证据。未修改生产 UI、战斗运行时、存档、工程版本、项目 README 或素材原图，未提交或推送。
