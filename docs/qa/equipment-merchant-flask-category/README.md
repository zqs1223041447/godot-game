# 正式装备商人：装备 / 药剂分类

基线 main：`f2b4d3ef6b35ac7c56f1394e52fe365694c149d8`；分支 `codex/equipment-merchant-flask-category`。

唯一生产改动是 `scripts/ui/town_service_panel.gd`：在原滚动商品列表上方增加两个固定分类按钮。默认显示15件原装备底材；切至药剂同时显示原基础生命、魔力药剂。保留全部17个原商品行、顺序和购买处理器，仅筛选可见性，不复制商店、报价或购买逻辑。

切换分类取消原待确认报价并将滚动位置归零；重复点击当前分类没有副作用。购买后的原有刷新保留药剂分类，并重新计算余额、容量和按钮可用性。其他商人及独立测试档不显示分类。价格仍为每瓶8碎片，原UID、容量、单次保存、schema59、效果、装备使用和地图充能规则不变。

## 有限验证

- `tests/equipment_merchant_category_test.gd`：最终 X11 真实渲染 **51项、0失败，exit0**。复用既有药剂事务测试的合法余额/满包夹具和真实 Main、TownServicePanel。通过鼠标切分类、打开报价、点击确认，核实实际确认点击本身已经完成购买，再注入重复回调验证幂等性。
- 覆盖余额0、余额8且满包、余额16购两瓶；满包夹具即使消费完1×1货币格，也无法放入1×2药剂。买不起/满包的禁用点击、延迟信号、旧报价重放均拒绝且权威状态不变。两次正常购买各扣8碎片、增加一个准确报价UID、保存一次；最终余额0及时禁用按钮。
- 浏览比较模型快照、磁盘字节、保存次数、RNG、暴击状态和药剂运行时；切换和重复点击没有经济副作用。覆盖装备返回、其他商人、地图装置及测试档。
- 原 `flask_purchase_transactions_test.gd`：**58项、0失败，exit0**。仅将过时的硬编码schema55断言更新为“购买前后版本一致”；实际当前版本59。生产迁移与schema未改。
- Godot4.6.3，1280×720，隔离Xorg dummy显示器、Mesa llvmpipe。实际查看三个截图：分类沿用原魔法书外观，药剂两行与价格同时可见，原确认对话框和操作可达。修正了选中/悬浮文字的对比度。不宣称其他分辨率或Windows验收。

保留迭代证据：`visual-01`49项/0失败，但尚未明确断言实际鼠标确认先于重复回调完成购买；补上两条断言后 `visual-02`51项/2失败，定位到测试点击工具遗漏嵌入式ConfirmationDialog的窗口偏移。修正测试坐标后最终 `visual-03`51项/0失败；生产购买路径无需修改。不累加迭代通过数。最终日志仅含虚拟显示器不支持VSync的警告，无脚本错误。没有全套测试、长矩阵、模型、导出或封包。

## 截图与交付

- [装备分类](equipment.png)
- [药剂分类](flasks.png)
- [原购买确认](confirmation.png)
- 上批[地图手记截图](../map-device-description/README.md#截图)

已尝试通过Library官方批量上传辅助工具交付上批地图手记3张及本批3张截图；环境在连接工具目录阶段失败，未确认任何Library文件或library_file_id。交付以仓库中的已验证截图为准。

## 复现

需要可用X11显示器和新的隔离目录；将DISPLAY替换为实际显示器。MERCHANT_CAPTURE_DIR须事先存在。

```bash
timeout 45s env DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 XDG_DATA_HOME=/tmp/godot-merchant-category-review XDG_CACHE_HOME=/tmp/godot-merchant-category-review-cache MERCHANT_CATEGORY_REPORT=/tmp/merchant-category-review.json MERCHANT_CAPTURE_DIR=/tmp godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/equipment_merchant_category_test.gd
```

测试使用受控物理货币和容量夹具，不是自然打怪积累货币流程。`verification.json`记录最终源文件、结果和截图SHA256。

## 下一项实际玩法内容候选

可考虑一个混沌抗性地图挑战词缀。只读确认：`MapCatalog.SPECIAL`现有四项，防御项仅`elemental_aegis`；怪物和伤害系统已有混沌抗性结算。需要先核 `MapDefenseRules`当前仅接受三元素的授权边界及`Defense.chaos_resistance_profile`复用方式，明确数值后再小范围接入，不能仅复制元素字段就声称完成。保留现有费用/奖励策略、抗性上限和防重复应用规则，验证实际混沌命中与其他伤害不变。本批没有实现或开放该词缀。
