extends SceneTree
## 独立控件契约测试；必须由调用方隔离 user://，不加载主场景或 BuildState。
const Controls = preload("res://scripts/ui/crafting_controls.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const Frame = preload("res://scripts/visuals/material_frame.gd")

var checks: int = 0
var failures: int = 0
var controls: Controls
var requests: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated_root: String = OS.get_environment("GODOT_CRAFTING_TEST_ROOT").replace("\\", "/").trim_suffix("/")
	var user_dir: String = OS.get_user_data_dir().replace("\\", "/")
	_expect(not isolated_root.is_empty() and user_dir.begins_with(isolated_root + "/"), "user:// 位于调用方指定的独立测试目录")
	if failures > 0:
		_finish()
		return
	print("Crafting controls isolated user://: " + user_dir)
	root.size = Vector2i(1280, 720)
	controls = Controls.new()
	controls.position = Vector2(24, 24)
	controls.size = Vector2(220, 40)
	controls.craft_requested.connect(_on_requested)
	root.add_child(controls)
	await process_frame
	_expect(_button("SalvageButton").disabled and _button("RecalibrateButton").disabled, "初始空选择禁用两个动作")
	_test_catalog_examples()
	_test_failures_and_balance()
	_test_upper_layer_reasons()
	_test_detachment_and_purity()
	await _test_real_clicks()
	await _test_layout()
	controls.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("Crafting controls: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _on_requested(operation: String, item_id: String, source: Dictionary) -> void:
	# 保留收到的实际引用，以验证订阅方修改它不会污染下次请求。
	requests.append({"operation": operation, "item_id": item_id, "source": source})


func _button(stable_name: String, target: Controls = null) -> Button:
	if target == null:
		target = controls
	return target.get_node("CraftingRow/" + stable_name) as Button


func _label(target: Controls = null) -> Label:
	if target == null:
		target = controls
	return target.get_node("CraftingRow/MaterialBalanceLabel") as Label


func _item(base_id: String = "cinder_reed", affix_id: String = "deepwell", tier_number: int = 1,
		id: String = "gear_000123") -> Dictionary:
	var tier: Dictionary = Catalog.affix_definition(affix_id).tiers[tier_number - 1]
	return {"id": id, "base_id": base_id, "rarity": "magic", "item_level": 16,
		"affixes": [{"id": affix_id, "tier": tier_number, "value": tier.min}]}


func _context(item: Dictionary, balance: int, reason: String = "") -> void:
	controls.set_context(str(item.get("id", "")), item, balance, Craft.salvage_quote(item),
		Craft.recalibrate_plan(item, 20261002), reason)


func _test_catalog_examples() -> void:
	for base_id: String in Catalog.all_base_ids():
		var family_id: String = ""
		for candidate: String in Catalog.all_affix_ids():
			if Catalog.family_eligible(candidate, base_id):
				family_id = candidate
				break
		_expect(not family_id.is_empty(), "真实目录底材存在可用词缀：" + base_id)
		if family_id.is_empty():
			continue
		var item: Dictionary = _item(base_id, family_id)
		var salvage: Dictionary = Craft.salvage_quote(item)
		var recalibrate: Dictionary = Craft.recalibrate_plan(item, 41)
		_expect(Catalog.validate_instance(item) and salvage.ok and recalibrate.ok, "真实 Craft 生成有效报价：" + base_id)
		controls.set_context(item.id, item, recalibrate.cost.calibration_shard, salvage, recalibrate)
		_expect(not _button("SalvageButton").disabled and not _button("RecalibrateButton").disabled, "恰好支付实际成本时两动作可用：" + base_id)
		_expect(_button("SalvageButton").get_tooltip().contains("%d 枚" % int(salvage.materials.calibration_shard)), "回收 tooltip 使用实际收益：" + base_id)
		_expect(_button("RecalibrateButton").get_tooltip().contains("%d 枚" % int(recalibrate.cost.calibration_shard)), "校准 tooltip 只展示实际成本：" + base_id)
		var count: int = requests.size()
		_button("SalvageButton").pressed.emit()
		_button("RecalibrateButton").pressed.emit()
		_expect(requests.size() == count + 2, "两次激活各发送一次请求：" + base_id)
		if requests.size() == count + 2:
			_expect(requests[count].operation == "salvage" and requests[count + 1].operation == "recalibrate", "请求使用 Craft 操作标识")
			_expect(requests[count].item_id == item.id and requests[count].source == item and requests[count + 1].source == item, "两操作均携带同一原始物品快照")


func _test_failures_and_balance() -> void:
	var item: Dictionary = _item()
	var salvage: Dictionary = Craft.salvage_quote(item)
	var plan: Dictionary = Craft.recalibrate_plan(item, 17)
	var cost: int = plan.cost.calibration_shard
	for balance: int in [-1, 0, cost - 1, cost, cost + 1]:
		controls.set_context(item.id, item, balance, salvage, plan)
		_expect(_label().text == "校准碎片 %d" % balance, "余额原样展示，不隐式扣减或修正")
		_expect(not _button("SalvageButton").disabled, "回收不因碎片余额不足而禁用")
		_expect(_button("RecalibrateButton").disabled == (balance < cost), "可支付判断仅比较余额与报价成本")
		if balance < cost:
			_expect(_button("RecalibrateButton").get_tooltip().contains("需要 %d 枚，现有 %d 枚" % [cost, balance]), "不足 tooltip 给出准确成本与余额")
			var count: int = requests.size()
			_button("RecalibrateButton").pressed.emit()
			_expect(requests.size() == count, "强制触发禁用按钮也不发送校准请求")
	var failed_salvage: Dictionary = Craft.salvage_quote({})
	controls.set_context(item.id, item, cost, failed_salvage, plan)
	_expect(_button("SalvageButton").disabled and _button("SalvageButton").get_tooltip() == failed_salvage.reason, "回收失败原因逐字保留")
	_expect(not _button("RecalibrateButton").disabled, "回收报价失败不禁用有效校准报价")
	var failed_plan: Dictionary = Craft.recalibrate_plan(item, "invalid_seed")
	controls.set_context(item.id, item, cost, salvage, failed_plan)
	_expect(_button("RecalibrateButton").disabled and _button("RecalibrateButton").get_tooltip() == failed_plan.reason, "校准失败原因逐字保留")
	_expect(not _button("SalvageButton").disabled, "校准报价失败不禁用有效回收报价")
	var normal: Dictionary = item.duplicate(true)
	normal.rarity = "normal"
	normal.affixes = []
	_context(normal, 100)
	_expect(_button("SalvageButton").disabled and _button("RecalibrateButton").disabled, "真实 Craft 拒绝无词缀普通装备")
	controls.set_context(item.id, item, 100, {}, {})
	_expect(_button("SalvageButton").disabled and _button("RecalibrateButton").disabled, "缺失报价失败关闭")
	for invalid_amount: Variant in [null, false, "4", -1, 4.5]:
		var malformed: Dictionary = plan.duplicate(true)
		malformed.cost = {"calibration_shard": invalid_amount}
		controls.set_context(item.id, item, 100, salvage, malformed)
		_expect(_button("RecalibrateButton").disabled and not _button("RecalibrateButton").get_tooltip().is_empty(), "不将畸形成本强制转成可用报价")
	var custom_cost: Dictionary = plan.duplicate(true)
	custom_cost.cost.calibration_shard = 3
	controls.set_context(item.id, item, 3, salvage, custom_cost)
	_expect(not _button("RecalibrateButton").disabled and _button("RecalibrateButton").get_tooltip().contains("3 枚"), "不从回收收益重算或硬编码校准成本")
	custom_cost.cost.calibration_shard = 0
	controls.set_context(item.id, item, 0, salvage, custom_cost)
	_expect(not _button("RecalibrateButton").disabled, "零成本报价遵循同一余额比较")


func _test_upper_layer_reasons() -> void:
	var item: Dictionary = _item()
	for reason: String in ["请先选择装备。", "固定装备不能制作。", "请先卸下穿戴中的装备。", "原存档受保护，暂不能制作。"]:
		_context(item, 100, reason)
		var count: int = requests.size()
		for stable_name: String in ["SalvageButton", "RecalibrateButton"]:
			var button: Button = _button(stable_name)
			_expect(button.disabled and button.get_tooltip() == reason, "上层禁用原因优先且保留 tooltip：" + reason)
			button.pressed.emit()
		_expect(requests.size() == count, "禁用时强制激活不能越过上层约束")
	controls.set_context("", {}, 100, Craft.salvage_quote(item), Craft.recalibrate_plan(item, 1))
	_expect(_button("SalvageButton").disabled and _button("RecalibrateButton").disabled, "空选择不会被先前有效报价启用")


func _test_detachment_and_purity() -> void:
	var item: Dictionary = _item()
	var before: Dictionary = item.duplicate(true)
	var salvage: Dictionary = Craft.salvage_quote(item)
	var plan: Dictionary = Craft.recalibrate_plan(item, 97)
	var cost: int = plan.cost.calibration_shard
	plan.definition = {"name": "NEVER_SHOW_RANDOM_RESULT"}
	plan.instance = {"result": "NEVER_SHOW_RANDOM_RESULT"}
	plan.seed = "NEVER_SHOW_SEED"
	controls.set_context(item.id, item, cost, salvage, plan)
	item.affixes[0].value += 999
	salvage.materials.calibration_shard = -999
	plan.cost.calibration_shard = 999999
	plan.source_instance.affixes.clear()
	var count: int = requests.size()
	_button("RecalibrateButton").button_down.emit()
	_button("RecalibrateButton").pressed.emit()
	_expect(requests.size() == count + 1, "输入报价后续修改不影响保存的支付判断")
	if requests.size() == count + 1:
		_expect(requests[count].source == before, "陈旧外部物品仍发送 set_context 时的深复制原快照")
		requests[count].source.affixes[0].value = -888
	_button("SalvageButton").pressed.emit()
	_expect(requests.size() == count + 2, "输入收益后续修改不污染回收报价")
	if requests.size() == count + 2:
		_expect(requests[count + 1].source == before, "订阅方修改先前快照不污染下一次请求")
	var text: String = _label().text + _label().get_tooltip() + _button("SalvageButton").get_tooltip() + _button("RecalibrateButton").get_tooltip()
	_expect(not text.contains("NEVER_SHOW"), "不显示报价中的随机结果、派生属性或 seed")
	item = before.duplicate(true)
	salvage = Craft.salvage_quote(item)
	plan = Craft.recalibrate_plan(item, 29)
	var input_bytes: PackedByteArray = var_to_bytes([item, salvage, plan])
	seed(20261002)
	var expected_random: int = randi()
	seed(20261002)
	for index: int in range(5):
		controls.set_context(item.id, item, cost, salvage, plan)
	_button("SalvageButton").pressed.emit()
	_button("RecalibrateButton").pressed.emit()
	_expect(randi() == expected_random, "刷新和点击不消耗或重置全局 RNG")
	_expect(var_to_bytes([item, salvage, plan]) == input_bytes, "刷新和点击不修改物品或输入报价")
	_expect(_label().text == "校准碎片 %d" % cost, "两操作均不扣除展示余额")
	_expect(controls.get_child_count() == 1 and controls.get_child(0).get_child_count() == 3, "重复 set_context 只保留一行与三个控件")


func _mouse(button: Button, pressed: bool, point: Vector2 = Vector2(-1, -1)) -> void:
	var at: Vector2 = button.get_global_rect().get_center() if point.x < 0 else point
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	root.push_input(event)


func _test_real_clicks() -> void:
	var item: Dictionary = _item()
	_context(item, 100)
	await process_frame
	await process_frame
	for stable_name: String in ["SalvageButton", "RecalibrateButton"]:
		var button: Button = _button(stable_name)
		var count: int = requests.size()
		_mouse(button, true)
		_mouse(button, false)
		_expect(requests.size() == count + 1, "一次实际鼠标点击只发一个信号：" + stable_name)
		await process_frame
	var previous: Dictionary = item.duplicate(true)
	var next: Dictionary = _item("ashwood_bow", "farweave", 1, "gear_000124")
	_context(previous, 100)
	var button: Button = _button("RecalibrateButton")
	var count: int = requests.size()
	_mouse(button, true)
	_context(next, 100)
	_mouse(button, false)
	_expect(requests.size() == count + 1, "按下至松开之间切换选择仍只发送一次请求")
	if requests.size() == count + 1:
		_expect(requests[count].item_id == previous.id and requests[count].source == previous, "陈旧鼠标点击携带按下时的原 ID 与快照，供上层拒绝")
	await process_frame
	count = requests.size()
	_mouse(button, true)
	_context(next, 100, "原存档受保护。")
	_mouse(button, false)
	_expect(requests.size() == count, "按下后变为受保护状态立即取消动作")
	await process_frame
	_context(previous, 100)
	_mouse(button, true)
	_mouse(button, false, Vector2(8, 400))
	await process_frame
	_context(next, 100)
	count = requests.size()
	button.pressed.emit()
	_expect(requests.size() == count + 1 and requests.back().source == next, "拖出按钮取消的手势不遗留旧快照")


func _test_layout() -> void:
	controls.hide()
	var item: Dictionary = _item()
	for width: int in [220, 280]:
		for font_scale: float in [1.0, 1.2]:
			var target := Controls.new()
			target.position = Vector2(24, 90)
			target.size = Vector2(width, 40)
			target.set_context(item.id, item, 12345, Craft.salvage_quote(item), Craft.recalibrate_plan(item, 11))
			PresentationTheme.apply_font_scale(target, font_scale)
			root.add_child(target)
			await process_frame
			await process_frame
			var row: HBoxContainer = target.get_node("CraftingRow")
			_expect(target.size.x <= width + 0.1 and target.get_combined_minimum_size().x <= width, "宽 %d / 字体 %.0f%% 根控件不横向撑开" % [width, font_scale * 100.0])
			_expect(row.size.x <= width + 0.1 and row.get_child_count() == 3, "紧凑布局始终保持一行")
			var previous_end: float = -1.0
			for child: Control in row.get_children():
				_expect(child.get_rect().position.x >= previous_end and child.get_rect().end.x <= row.size.x + 0.1, "控件不重叠且不溢出：" + str(child.name))
				previous_end = child.get_rect().end.x
				_expect(child.get_theme_font_size("font_size") == roundi(13.0 * font_scale), "字体比例实际应用到文字控件")
				_expect(not child.get_tooltip().is_empty(), "窄布局仍保留完整 tooltip")
			var label: Label = _label(target)
			var text_width: float = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			_expect(text_width <= label.size.x, "五位碎片余额在 %d / %.0f%% 下完整可见" % [width, font_scale * 100.0])
			for stable_name: String in ["SalvageButton", "RecalibrateButton"]:
				var button: Button = _button(stable_name, target)
				for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
					_expect(button.get_theme_stylebox(state).get_script() == Frame, "按钮沿用 VisualTheme 手绘纸面：" + state)
			target.set_context(item.id, item, 9223372036854775807, Craft.salvage_quote(item), Craft.recalibrate_plan(item, 11))
			await process_frame
			_expect(target.size.x <= width + 0.1 and label.get_tooltip().contains("9223372036854775807"), "极长余额省略显示但不撑宽，tooltip 保留完整数值")
			target.queue_free()
			await process_frame
	controls.show()
