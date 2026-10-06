# v0.61 坚决技艺图鉴证据

基线：v0.60 `b389993ed7f7a90f4043c668704583d44b22f343`。本批只改同源导出、静态页面与说明，不运行历史全量、工程导入、长时间战斗或新截图门槛。

运行命令、输入SHA256、首次错误和后续必要纠正由 `run-reference-checks.py` 分阶段留存，不覆盖已存在的证据。Godot使用隔离可写XDG，任何SCRIPT ERROR/ERROR/Assertion立即终止进程，不等待超时。字体阶段只跟踪字体检查实际读取的全部运行时输入、检查器、字体、清单和许可证，不将无关tools并发改动算成字体输入漂移。

正式0.61导出一次通过：16.810秒、exit0、无错误行和输入漂移。HTML构建0.518秒、确定性校验0.484秒、JS语法0.060秒均通过。`focused-reference-result.json`记录本批聚焦校验3.269秒、exit0、无输入漂移。

`v060-projection-preservation.json`证明：59个页面数值逐一读取权威导出；7类前后命中角色；3814个唯一HTML锚点、全部内部与本地资源链接；57处许可catalog变化精确投影后，旧语义SHA256仍为`830b8deb12f9a478c06ed625e606383e03a2c2d8c37a7b59f576ed2e2b2c5dee`。装备、词缀、当前掉落与所有旧池完全相同，61张运行时PNG与68张图鉴PNG原字节保留。覆盖JSON只允许31961的执行状态、相关计数和七职业各新增一个可达节点，其余完整结构精确相同。

字体首扫：175份运行时文件，required1651（汉字1529）、mapped1655；唯一missing为U+62EC“括”，来源`damage_preview.gd:47`，无旧字丢失、空汉字、轮廓或度量错误；90.055秒exit1的首次结果完整保留。集成使用原同源字体仅补“括”。`check-font-addition.py`定向验收1.070秒、exit0、无错误或输入漂移，证明175份运行时输入逐字节不变，旧1655全部字形轮廓/水平advance/垂直度量/全局布局/家族/许可保持，唯一新增U+62EC为非空字形；mapped1656覆盖原required1651，missing为0。完整结果见`font-addition-preservation.json`与`targeted-font-addition-result.json`。未重新执行90秒全扫描、Godot导出、F8或历史战斗。集成补集生成记录见`../v061-integration/font-subset.json`；该生成会话退出码不可恢复，不把生成记录冒称为exit0，完成性由现存输出字节与本次独立只读验收证明。

`baseline-capture-first-failure.json`保留首次PNG筛选前提错误：旧61图分布不止assets/art，已复用完整路径成员并从v60提交独立读取所有字节。
