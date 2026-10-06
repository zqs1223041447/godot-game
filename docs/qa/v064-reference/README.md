# v0.64 图鉴资料验收

基线为 v0.63 `76e2abccf533cd31c20daea92c0e05b02c0980af`。本批只更新当前版本、源执行政策、10661 执行/本地化状态，以及新增铁反射（闪转甲）规则和对应交叉链接；保持原有离线图鉴布局。

`tools/export_reference.gd` 通过真实 CanonicalGameState 导出三组合法装备/源路线的点前、点后六份状态。所有候选通过完整构筑与源树验证；每份保存尝试为零。角色最终值和 get_defense_conversion_profile 是显示权威源，物理命中、元素命中、燃烧与敌方攻击命中率分别调用生产规则，不在 HTML 二次推算。

复验入口：

- `python3 docs/qa/v064-reference/run-reference-checks.py export --prefix new-`
- `python3 docs/qa/v064-reference/run-reference-checks.py build --prefix new-`
- `python3 docs/qa/v064-reference/run-reference-checks.py verify --prefix new-`

每个 Godot 进程只运行导出，独立 `/tmp` XDG，120 秒上限，首个错误行终止；没有重复导入、600 秒挂起或重跑源机制套件。每次保留输入哈希、原始 stdout/stderr、退出码、耗时和运行期间源文件变化检查。

首次导出在 17.474 秒首错停止：新导出断言误把元素命中报告中随构筑变化的完整护甲元数据也要求相同。修正后逐元素比较真正的 damage_total，并继续要求完整燃烧结果相同。此为导出检查修正，生产防御逻辑没有修改。`corrected-godot-export-result.json` 为成功导出收据（22.281 秒，exit 0）。首次 HTML 构建因新规则函数未定义局部源句本地化助手而首错停止；补上直接读取已有本地化表的助手后重新构建，原始失败收据保留。

首次聚焦检查发现旧四词胸甲的19.5闪避在当前敌命中100下已经处于100%命中上限，因而前后命中率相同；修正了将六组状态都要求严格上升的检查，并在F8明示此边界。双防御胸甲两组仍从73%/71%升到100%。

覆盖报告检查首次还把说明字符串当统计分组处理；改为只遍历两个实际统计分组，失败收据保留。

聚焦检查核对新条目显示值与 catalog 一致、全部 HTML 锚点/本地资源链接、合法词缀限制、模型点数预算、敏捷命中保持、转换输入与输出、元素与燃烧不变，以及旧图鉴内容的精确允许变更范围。`v063-preservation.json` 保留全部 61 张原图、68 张图鉴 PNG、CSS、JS 与美术清单的逐字节哈希；装备、词池、掉落配置全值保持。

生成的 `source-tree-coverage.json` 随当前源政策重新导出；源节点与完整机制的专门验收由 [v064-source](../v064-source/) 负责。本目录没有宣称额外实战、截图、性能或 Windows 帧率验证。

最终结果：81 个同源显示值、6 份合法 Model 状态、3818 个 HTML ID、所有锚点与本地资源链接通过；旧 catalog 只出现34处允许变化。覆盖报告精确等于旧报告只开放10661后的结果，七职业各增加此1个可达节点。61张原图与68张图鉴PNG全部原字节保持，CSS、JS、美术清单和装备/掉落值也保持。最终收据为 `corrected-godot-export-result.json`、`final-build-result.json`、`final-build-check-result.json` 与 `verified-focused-reference-result.json`。保全报告重复执行时须完全一致，不能覆盖不同结果。
