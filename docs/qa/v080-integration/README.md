# v080 九条资源词缀文字收口

基线为 33ed04b73edf3545b98339291df81b4c49f891cf。仅修正九个完整英文 key 的中文值，并在生成器 SINGLE_LINE_OVERRIDES 中作相同精确覆盖。没有改通用术语模板、其他翻译、节点名、ID、源英文、图结构、typed grants 或当前支持状态。

两句技能魔力消耗修正语序；其余句明确再生、偷取每秒回复速率及总速率上限。偷取速率提高不增加单次偷取总量。原有 increased / more 运算没有变动。

- 实际面板短检查一次 447 checks / 0 failures、exit 0，见 ../v080-wording/README.md。七个代表完整节点、21次中文名/英文名/ID搜索及只读模型、存档、revision、全局 RNG 检查通过；没有战斗或实际分配测试。
- 静态检查仅九个映射值与九条精确 override 改变；生成器其余 AST 不变。源树、执行器、面板、原字体均与基线字节相同，字体覆盖全部新文案。
- F8 只替换23个 JSON字符串片段：9行缓存及14个节点的对应引用。混合或未可达节点引用相同英文行时，仅该行文字同步，其余未实装标记保留。
- catalog 其他字节保留；没有 Godot 大图鉴导出。沿已有 Python 模板更新对应 HTML 文本与必要数据指纹，确定性检查通过，3874个锚点和71个图片引用的顺序保持。
- 统一 import 一次 22.766秒、exit 0。测试前独立版本查询的字体缓存警告由测试记录单列；实际隔离测试没有 SCRIPT ERROR / ERROR。

游戏版本0.78、schema48及源政策48保持。没有素材、布局、Windows导出、打包、tag或Release。

证据：exact-wording-check.json、html-check.json、import-result.json、import.log.txt。check_exact_wording.py 可复核指定基线并执行同样的精确缓存同步；运行期验证有独立单次运行器。
