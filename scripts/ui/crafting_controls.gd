class_name CraftingControls
extends VBoxContainer
## 只展示上层提供的报价并发送请求；不持有模型、钱包、存档或随机数生成器。

signal craft_requested(operation: String, item_id: String, source_instance_copy: Dictionary)

const DockStyle = preload("res://scripts/ui/dock_visual_style.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const MATERIAL_ID: String = "calibration_shard"

var _item_id: String = ""
var _source_instance: Dictionary = {}
var _material_balance: int = 0
var _salvage_quote: Dictionary = {}
var _recalibrate_quote: Dictionary = {}
var _disabled_reason: String = ""
var _balance_label: Label
var _salvage_button: Button
var _recalibrate_button: Button
var _pending_requests: Dictionary = {}
var _request_sequence: int = 0
var _metadata_mode := false
var _operations: Dictionary = {}
var _operation_buttons: Dictionary = {}
var _button_row: HBoxContainer
var _target_row: HBoxContainer
var _target_select: OptionButton
var _target_button: Button
var _target_operation := ""
var _target_pressed_operation := ""


class CraftButton extends Button:
	func _make_custom_tooltip(text: String) -> Object:
		return CraftingControls.wrapped_tooltip(self, text)


class CraftLabel extends Label:
	func _make_custom_tooltip(text: String) -> Object:
		return CraftingControls.wrapped_tooltip(self, text)


## Keep the entire supplied reason; constrain the native label so long reasons
## wrap within the existing parchment popup instead of extending off screen.
static func wrapped_tooltip(source: Control, text: String) -> Label:
	var label := Label.new()
	label.name = "TooltipLabel"
	label.theme_type_variation = "TooltipLabel"
	var font: Font = source.get_theme_font("font", "TooltipLabel")
	var font_size: int = source.get_theme_font_size("font_size", "TooltipLabel")
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", PresentationTheme.TEXT)
	label.text = text
	var canvas_width: float = source.get_viewport_rect().size.x if source.is_inside_tree() else 1280.0
	var natural_width: float = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label.custom_minimum_size.x = minf(maxf(1.0, canvas_width - 48.0), minf(420.0, maxf(120.0, natural_width)))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _ready() -> void:
	_ensure_interface()
	_refresh()


func set_context(item_id: String, source_instance: Dictionary, material_balance: int,
		salvage_quote: Dictionary, recalibrate_quote: Dictionary, disabled_reason: String = "") -> void:
	_metadata_mode = false
	_item_id = item_id
	_source_instance = source_instance.duplicate(true)
	_material_balance = material_balance
	_salvage_quote = salvage_quote.duplicate(true)
	_recalibrate_quote = recalibrate_quote.duplicate(true)
	_disabled_reason = disabled_reason
	_ensure_interface()
	_refresh()


## Lightweight capabilities do not contain a live crafting quote or transaction.
func set_operations_context(item_id: String,source_instance: Dictionary,material_balance: int,operations: Array,disabled_reason: String = "") -> void:
	_metadata_mode = true
	_item_id = item_id
	_source_instance = source_instance.duplicate(true)
	_material_balance = material_balance
	_disabled_reason = disabled_reason
	_operations.clear()
	_ensure_interface()
	for entry: Dictionary in operations:
		var operation := str(entry.get("operation",""))
		if operation.is_empty(): continue
		_operations[operation] = entry.duplicate(true)
		if bool(entry.get("targeted", false)): continue
		if not _operation_buttons.has(operation):
			var button := _make_button(str(entry.get("label",operation)),"Craft_"+operation,operation)
			_button_row.add_child(button)
			_operation_buttons[operation] = button
		DockStyle.style_action(_operation_buttons[operation],11)
	_refresh()


func _ensure_interface() -> void:
	if _balance_label != null:
		return
	if theme == null:
		theme = PresentationTheme.create_theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	_button_row = row
	row.name = "CraftingRow"
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	_balance_label = CraftLabel.new()
	_balance_label.name = "MaterialBalanceLabel"
	_balance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_balance_label.clip_text = true
	_balance_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_balance_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_balance_label.add_theme_font_size_override("font_size", 13)
	_balance_label.add_theme_color_override("font_color", PresentationTheme.MUTED)
	row.add_child(_balance_label)
	_salvage_button = _make_button("回收", "SalvageButton", "salvage")
	row.add_child(_salvage_button)
	_recalibrate_button = _make_button("校准", "RecalibrateButton", "recalibrate")
	row.add_child(_recalibrate_button)
	_operation_buttons["salvage"] = _salvage_button
	_operation_buttons["recalibrate"] = _recalibrate_button
	_target_row = HBoxContainer.new()
	_target_row.name = "TargetedCraftingRow"
	_target_row.add_theme_constant_override("separation", 4)
	add_child(_target_row)
	_target_select = OptionButton.new()
	_target_select.name = "TargetedCraftFamily"
	_target_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_select.custom_minimum_size = Vector2(110,28)
	DockStyle.style_action(_target_select,11)
	_target_select.item_selected.connect(_select_target)
	_target_row.add_child(_target_select)
	_target_button = CraftButton.new()
	_target_button.name = "TargetedReforgeButton"
	_target_button.custom_minimum_size = Vector2(126,28)
	DockStyle.style_action(_target_button,11)
	_target_button.button_down.connect(_capture_targeted)
	_target_button.button_up.connect(_release_targeted)
	_target_button.pressed.connect(_request_targeted)
	_target_row.add_child(_target_button)
	_target_row.hide()


func _make_button(caption: String, stable_name: String, operation: String) -> Button:
	var button := CraftButton.new()
	button.name = stable_name
	button.text = caption
	button.custom_minimum_size = Vector2(44, 28)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_focus_color", PresentationTheme.TEXT)
	button.add_theme_stylebox_override("normal", PresentationTheme.panel(Color("f8ecd0"), PresentationTheme.BORDER, 4, 1, 4))
	button.add_theme_stylebox_override("hover", PresentationTheme.panel(Color("fff2d5"), PresentationTheme.ACCENT, 4, 1, 4))
	button.add_theme_stylebox_override("pressed", PresentationTheme.panel(Color("ead3a2"), PresentationTheme.ACCENT, 4, 1, 4))
	button.add_theme_stylebox_override("disabled", PresentationTheme.panel(Color("d9c8a5"), Color("9b8560"), 4, 1, 4))
	button.add_theme_stylebox_override("focus", PresentationTheme.panel(Color(0, 0, 0, 0), PresentationTheme.GOLD, 4, 2, 0))
	button.button_down.connect(_capture_request.bind(operation))
	button.button_up.connect(_release_request.bind(operation))
	button.pressed.connect(_request_craft.bind(operation))
	return button


func _refresh() -> void:
	if _metadata_mode:
		_balance_label.hide()
		for operation: String in _operation_buttons:
			var button: Button = _operation_buttons[operation]
			button.visible = _operations.has(operation)
			if not button.visible: continue
			var entry: Dictionary = _operations[operation]
			button.text = str(entry.get("label",operation))
			var reason := _blocked_reason(operation)
			button.disabled = not reason.is_empty()
			var detail := str(entry.get("description",""))
			var risk := str(entry.get("risk",""))
			if not risk.is_empty(): detail += "\n"+risk
			var raw_cost: Variant = entry.get("cost",-1)
			var cost: int = _shard_amount(raw_cost) if raw_cost is Dictionary else int(raw_cost)
			if operation != "salvage" and cost >= 0: detail += "\n校准碎片 %d 枚" % cost
			if operation == "salvage":
				var gain := _shard_amount(entry.get("materials",{}))
				if gain >= 0: detail += "\n获得校准碎片 %d 枚" % gain
			if not reason.is_empty(): detail += "\n"+reason
			button.tooltip_text = detail.strip_edges()
		_refresh_targeted()
		return
	_target_row.hide()
	for operation: String in _operation_buttons:
		_operation_buttons[operation].visible = operation in ["salvage","recalibrate"]
	_balance_label.text = "校准碎片 %d" % _material_balance
	_balance_label.tooltip_text = "校准碎片：%d 枚\n回收会消耗所选装备；校准只消耗碎片。" % _material_balance
	var salvage_reason: String = _blocked_reason("salvage")
	var recalibrate_reason: String = _blocked_reason("recalibrate")
	_salvage_button.disabled = not salvage_reason.is_empty()
	_recalibrate_button.disabled = not recalibrate_reason.is_empty()
	_salvage_button.tooltip_text = salvage_reason if _salvage_button.disabled else (
		"回收此装备，获得校准碎片 %d 枚。\n回收会消耗所选装备。" % _shard_amount(_salvage_quote.get("materials")))
	_recalibrate_button.tooltip_text = recalibrate_reason if _recalibrate_button.disabled else (
		"消耗校准碎片 %d 枚，重掷现有词缀的数值。\n词缀种类与阶级保持不变，数值可能不变或降低。" % _shard_amount(_recalibrate_quote.get("cost")))


func _blocked_reason(operation: String) -> String:
	if not _disabled_reason.strip_edges().is_empty():
		return _disabled_reason
	if _item_id.is_empty() or _source_instance.is_empty():
		return "请先选择可制作的物品。"
	if _metadata_mode:
		var entry: Dictionary = _operations.get(operation,{})
		if not entry.get("available",false):
			var reason := str(entry.get("reason",""))
			return reason if not reason.is_empty() else "此物品不适用这项工艺"
		return ""
	var quote: Dictionary = _salvage_quote if operation == "salvage" else _recalibrate_quote
	var ok: Variant = quote.get("ok", false)
	if not ok is bool or not ok:
		var reason: String = str(quote.get("reason", ""))
		return reason if not reason.is_empty() else "暂无可用的制作报价。"
	var amount: int = _shard_amount(quote.get("materials" if operation == "salvage" else "cost"))
	if amount < 0:
		return "制作报价缺少有效的校准碎片数量。"
	if operation == "recalibrate" and _material_balance < amount:
		return "校准碎片不足：需要 %d 枚，现有 %d 枚。" % [amount, _material_balance]
	return ""


func _shard_amount(materials: Variant) -> int:
	if not materials is Dictionary:
		return -1
	var amount: Variant = materials.get(MATERIAL_ID)
	return amount if amount is int and amount >= 0 else -1


func _snapshot(operation: String) -> Dictionary:
	return {"item_id": _item_id, "source_instance": _source_instance.duplicate(true),
		"allowed": _blocked_reason(operation).is_empty(), "sequence": _request_sequence}


func _capture_request(operation: String) -> void:
	_request_sequence += 1
	_pending_requests[operation] = _snapshot(operation)


func _release_request(operation: String) -> void:
	# 松开但未激活（例如拖出按钮）时清理；pressed 会先同步消费快照。
	var sequence: int = int(_pending_requests.get(operation, {}).get("sequence", -1))
	_cancel_pending.call_deferred(operation, sequence)


func _cancel_pending(operation: String, sequence: int) -> void:
	if int(_pending_requests.get(operation, {}).get("sequence", -1)) == sequence:
		_pending_requests.erase(operation)


func _request_craft(operation: String) -> void:
	var request: Dictionary = _pending_requests.get(operation, _snapshot(operation))
	_pending_requests.erase(operation)
	var button: Button = _operation_buttons.get(operation) as Button
	if button == null or button.disabled or not request.allowed:
		return
	# 按下后选择变化仍携带按下时的原快照，由事务所有者验证是否陈旧。
	craft_requested.emit(operation, request.item_id, request.source_instance.duplicate(true))


func _refresh_targeted() -> void:
	_target_select.clear()
	var selected := -1
	var first_available := -1
	for operation: String in _operations:
		var entry: Dictionary = _operations[operation]
		if not bool(entry.get("targeted",false)): continue
		_target_select.add_item(str(entry.get("target_label",entry.get("target_id",operation))))
		var index := _target_select.item_count - 1
		_target_select.set_item_metadata(index,operation)
		var reason := _blocked_reason(operation)
		_target_select.set_item_disabled(index,not reason.is_empty())
		_target_select.get_popup().set_item_tooltip(index,reason if not reason.is_empty() else str(entry.get("description","")))
		if first_available < 0 and reason.is_empty(): first_available = index
		if operation == _target_operation: selected = index
	_target_row.visible = _target_select.item_count > 0
	if not _target_row.visible:
		_target_operation = ""
		_target_button.disabled = true
		return
	if selected < 0: selected = first_available if first_available >= 0 else 0
	_target_select.select(selected)
	_select_target(selected)


func _select_target(index: int) -> void:
	if index < 0 or index >= _target_select.item_count: return
	_target_operation = str(_target_select.get_item_metadata(index))
	var entry: Dictionary = _operations.get(_target_operation,{})
	var cost := _shard_amount(entry.get("cost",{}))
	_target_button.text = "定向重铸" + (" · %d" % cost if cost >= 0 else "")
	var reason := _blocked_reason(_target_operation)
	_target_button.disabled = not reason.is_empty()
	var detail := str(entry.get("description","")) + "\n" + str(entry.get("risk",""))
	if cost >= 0: detail += "\n消耗校准碎片 %d 枚" % cost
	if not reason.is_empty(): detail += "\n" + reason
	_target_button.tooltip_text = detail.strip_edges()
	_target_select.tooltip_text = str(entry.get("target_label","")) + ("：" + reason if not reason.is_empty() else "")


func _capture_targeted() -> void:
	_target_pressed_operation = _target_operation
	_capture_request(_target_pressed_operation)


func _release_targeted() -> void:
	var operation := _target_pressed_operation
	var sequence: int = int(_pending_requests.get(operation,{}).get("sequence",-1))
	_cancel_targeted.call_deferred(operation,sequence)


func _cancel_targeted(operation: String, sequence: int) -> void:
	if int(_pending_requests.get(operation,{}).get("sequence",-1)) != sequence: return
	_cancel_pending(operation,sequence)
	if _target_pressed_operation == operation: _target_pressed_operation = ""


func _request_targeted() -> void:
	var operation := _target_pressed_operation if not _target_pressed_operation.is_empty() else _target_operation
	_target_pressed_operation = ""
	var request: Dictionary = _pending_requests.get(operation,_snapshot(operation))
	_pending_requests.erase(operation)
	if not _metadata_mode or operation != _target_operation or not _target_row.visible or _target_button.disabled or not request.allowed: return
	craft_requested.emit(operation,request.item_id,request.source_instance.duplicate(true))
