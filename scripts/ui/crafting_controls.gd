class_name CraftingControls
extends VBoxContainer
## 只展示上层提供的报价并发送请求；不持有模型、钱包、存档或随机数生成器。

signal craft_requested(operation: String, item_id: String, source_instance_copy: Dictionary)

const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
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
var _expansion_menu: MenuButton
var _extra_quotes: Dictionary = {}
var _menu_requests: Dictionary = {}
var _menu_operations: Array[String] = []
var _pending_requests: Dictionary = {}
var _request_sequence: int = 0


class CraftButton extends Button:
	func _make_custom_tooltip(text: String) -> Object:
		return CraftingControls.wrapped_tooltip(self, text)


class CraftMenuButton extends MenuButton:
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
		salvage_quote: Dictionary, recalibrate_quote: Dictionary, disabled_reason: String = "",
		extra_quotes: Dictionary = {}) -> void:
	_item_id = item_id
	_source_instance = source_instance.duplicate(true)
	_material_balance = material_balance
	_salvage_quote = salvage_quote.duplicate(true)
	_recalibrate_quote = recalibrate_quote.duplicate(true)
	_disabled_reason = disabled_reason
	_extra_quotes = extra_quotes.duplicate(true)
	_ensure_interface()
	_refresh()


func _ensure_interface() -> void:
	if _balance_label != null:
		return
	if theme == null:
		theme = PresentationTheme.create_theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
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
	_expansion_menu = _recalibrate_button as MenuButton
	_expansion_menu.about_to_popup.connect(_capture_menu)
	_expansion_menu.get_popup().id_pressed.connect(_request_menu)
	_expansion_menu.get_popup().popup_hide.connect(_close_menu)


func _make_button(caption: String, stable_name: String, operation: String) -> Button:
	var button: Button = CraftMenuButton.new() if operation == "recalibrate" else CraftButton.new()
	button.name = stable_name
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
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
	var popup: PopupMenu = _expansion_menu.get_popup()
	popup.clear()
	_menu_operations.clear()
	var metadata: Dictionary = Craft.metadata().operations
	var offered: Array[String] = ["recalibrate"]
	offered.append_array(Craft.Expansion.OPERATIONS.keys())
	for operation: String in offered:
		var index: int = _menu_operations.size()
		_menu_operations.append(operation)
		var quotation: Dictionary = _recalibrate_quote if operation == "recalibrate" else _extra_quotes.get(operation, {})
		var price: int = _shard_amount(quotation.get("cost", {}))
		var caption: String = str(metadata[operation].name)
		if price >= 0:
			caption += " · %d 碎片" % price
		popup.add_item(caption, index)
		var reason: String = _blocked_reason(operation)
		popup.set_item_disabled(index, not reason.is_empty())
		popup.set_item_tooltip(index, reason if not reason.is_empty() else str(metadata[operation].get("description", "保持词缀种类与阶级，只重掷数值，可能降低或不变。")))
	if _extra_quotes.is_empty():
		popup.clear()
		_menu_operations.clear()
		_recalibrate_button.text = "校准"
	else:
		_recalibrate_button.text = "工艺"
		var any_allowed: bool = false
		for operation: String in offered:
			any_allowed = any_allowed or _blocked_reason(operation).is_empty()
		_recalibrate_button.disabled = not any_allowed
		_recalibrate_button.tooltip_text = "选择数值校准、赋魔、升格、补缀或重铸。执行前会确认成本与结果范围。"


func _capture_menu() -> void:
	if not _menu_requests.is_empty():
		return
	_request_sequence += 1
	for operation: String in _menu_operations:
		_menu_requests[operation] = _snapshot(operation)


func _close_menu() -> void:
	_clear_menu.call_deferred(_request_sequence)


func _clear_menu(sequence: int) -> void:
	if sequence == _request_sequence:
		_menu_requests.clear()


func _request_menu(index: int) -> void:
	if index < 0 or index >= _menu_operations.size():
		return
	var operation: String = _menu_operations[index]
	var request: Dictionary = _menu_requests.get(operation, {})
	_menu_requests.clear()
	if request.is_empty() or not request.get("allowed", false) or not _blocked_reason(operation).is_empty():
		return
	craft_requested.emit(operation, request.item_id, request.source_instance.duplicate(true))


func _blocked_reason(operation: String) -> String:
	if not _disabled_reason.strip_edges().is_empty():
		return _disabled_reason
	if _item_id.is_empty() or _source_instance.is_empty():
		return "请先选择可制作的装备。"
	var quote: Dictionary = _salvage_quote if operation == "salvage" else (_recalibrate_quote if operation == "recalibrate" else _extra_quotes.get(operation, {}))
	var ok: Variant = quote.get("ok", false)
	if not ok is bool or not ok:
		var reason: String = str(quote.get("reason", ""))
		return reason if not reason.is_empty() else "暂无可用的制作报价。"
	var amount: int = _shard_amount(quote.get("materials" if operation == "salvage" else "cost"))
	if amount < 0:
		return "制作报价缺少有效的校准碎片数量。"
	if operation != "salvage" and _material_balance < amount:
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
	if operation == "recalibrate" and not _extra_quotes.is_empty():
		_menu_requests.clear()
		for offered: String in _menu_operations:
			_menu_requests[offered] = _snapshot(offered)


func _release_request(operation: String) -> void:
	# 松开但未激活（例如拖出按钮）时清理；pressed 会先同步消费快照。
	var sequence: int = int(_pending_requests.get(operation, {}).get("sequence", -1))
	_cancel_pending.call_deferred(operation, sequence)


func _cancel_pending(operation: String, sequence: int) -> void:
	if int(_pending_requests.get(operation, {}).get("sequence", -1)) == sequence:
		_pending_requests.erase(operation)
		if operation == "recalibrate" and not _expansion_menu.get_popup().visible:
			_menu_requests.clear()


func _request_craft(operation: String) -> void:
	if operation == "recalibrate" and not _extra_quotes.is_empty():
		return
	var request: Dictionary = _pending_requests.get(operation, _snapshot(operation))
	_pending_requests.erase(operation)
	var button: Button = _salvage_button if operation == "salvage" else _recalibrate_button
	if button.disabled or not request.allowed:
		return
	# 按下后选择变化仍携带按下时的原快照，由事务所有者验证是否陈旧。
	craft_requested.emit(operation, request.item_id, request.source_instance.duplicate(true))
