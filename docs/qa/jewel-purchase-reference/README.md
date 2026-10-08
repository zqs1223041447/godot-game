# F8 正式珠宝购买说明

基线为已发布的 `baefe3004901abef10cbb3fd2a90507a8da1984d`。本次仅同步珠宝商人和三个已有基础珠宝商品卡片，没有修改运行源码或重跑购买事务。

珠宝商人说明正式购买每件 8 校准碎片、固定最低数值魔法品质、购买不随机、特殊珠宝不售、只入背包及合法珠宝孔条件。三张基础珠宝卡片展示各自既有固定词缀数值与购买入口，不赠点、不改变连通。原独立测试供应说明和四件测试目录仍保留。

`tools/jewel_purchase_reference.gd` 只读取既有实例工厂、价格、回收值和 formatter；每条词缀断言为原目录最低值。不实例化 Main，不读写用户存档，不执行交易或随机生成。全量导出器复用同一收集函数，未来重建可保留此说明；本次没有运行全量导出。

验证结果：

- 隔离 Linux XDG 目录中的 Godot headless 元数据导出成功，40 秒限时。[片段](fragment.json)与[日志](export.log.txt)。
- `python3 tests/jewel_purchase_reference_test.py` 通过：3816 个卡片 ID 不变，仅 `jewels-emberheart`、`jewels-tideglass`、`jewels-windweave`、`town_services-jewel_merchant` 四张卡变化，其余 **3812 张逐字节不变**。
- 目录所有既有字段值保留原始字节；掉落、制作、特殊珠宝卡片、运行源码、美术和执行覆盖报告不变。旧输入经更新后的生成器得到与基线逐字节相同的 HTML。
- 三件商品的价格、品质、数值与导出一致，相关 42 个内部链接有效。生产源 SHA 与当前文件一致；仍为 schema 55。[完整检查记录](preservation.json)。
- `python3 tools/build_reference.py --check` 和 `git diff --check` 通过。

边界：本次只检查静态图鉴，没有打开 F8 浏览器、重拍原生截图、重跑购买或其他事务、封包、导出 Windows 或长期检测。运行功能证据见 [基础珠宝购买验证](../jewel-purchase/README.md)。
