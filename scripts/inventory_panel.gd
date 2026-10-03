class_name InventoryPanel
extends VBoxContainer
## Persistent equipment + backpack inspector. No UI action mutates build data directly.

signal feedback(message: String)
signal open_passives_requested

const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const GridView = preload("res://scripts/item_grid_view.gd")
const Data = preload("res://scripts/game_data.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const CraftControls = preload("res://scripts/ui/crafting_controls.gd")
const TEXT: Color = Color("3b281b")
const MUTED: Color = Color("69523a")
const CYAN: Color = Color("52623b")
const GOLD: Color = Color("79571f")
const BORDER: Color = Color("8c6b42")
const SLOT_NAMES: Dictionary = {"weapon": "武器", "armor": "护甲", "charm": "饰品"}

var selected_item_key: String = ""
var _state: BuildState
var _built: bool = false
var _grid: ItemGridView
var _usage_label: Label
var _stats_summary: Label
var _detail_name: Label
var _detail_type: Label
var _detail_status: Label
var _detail_stats: Label
var _detail_hint: Label
var _detail_art: GridView.ItemArt
var _equip_button: Button
var _unequip_button: Button
var _passives_button: Button
var _discard_button: Button
var _discard_dialog: ConfirmationDialog
var _discard_target: String = ""
var _equipment_slots: Dictionary = {}
var _craft_controls: CraftingControls
var _craft_dialog: ConfirmationDialog
var _displayed_craft_quotes: Dictionary = {}
var _pending_craft: Dictionary = {}


class EquipmentSlot extends Control:
	signal selected(key: String)
	signal activated(key: String)
	signal feedback(message: String)
	var state: BuildState
	var slot: String = "weapon"
	var selected_key: String = ""
	var _drop_state: int = 0

	func _ready() -> void:
		custom_minimum_size = Vector2(160, 96)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func refresh() -> void:
		var id: String = str(state.equipped.get(slot, ""))
		tooltip_text = "%s · 空槽\n将对应装备拖入这里" % InventoryPanel.SLOT_NAMES.get(slot, slot) if id.is_empty() else "%s\n%s\n双击或右键卸回背包；也可拖入空闲格" % [state.get_item_definition(id)["name"], state.get_item_definition(id)["description"]]
		queue_redraw()

	func _draw() -> void:
		var id: String = str(state.equipped.get(slot, "")) if state != null else ""
		var selected_now: bool = selected_key == "item:" + id and not id.is_empty()
		var line: Color = Color("52623b") if selected_now else Color("877759")
		if _drop_state != 0:
			line = Color("85e2b6") if _drop_state == 1 else Color("a13b2d")
		draw_style_box(InventoryPanel.make_style(Color("f8ecd0"), line, 6, 2 if selected_now or _drop_state != 0 else 1), Rect2(Vector2.ZERO, size))
		var font: Font = get_theme_default_font()
		draw_string(font, Vector2(12, 23), str(InventoryPanel.SLOT_NAMES.get(slot, slot)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("69523a"))
		if id.is_empty():
			var hint_entry: Dictionary = {"hint": true, "slot": slot, "id": "ember_wand" if slot == "weapon" else "guardian_robe" if slot == "armor" else "azure_charm", "color": Color("77735d")}
			GridView.draw_item_icon(self, hint_entry, Rect2(9, 29, 51, 57))
			draw_string(font, Vector2(69, 60), "空装备槽", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("69523a"))
			draw_string(font, Vector2(69, 80), "拖入对应装备", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("69523a"))
			return
		var entry: Dictionary = GridView.describe_item(state, "item:" + id)
		GridView.draw_item_icon(self, entry, Rect2(9, 28, 51, 59))
		draw_string(font, Vector2(66, 55), str(entry.get("base_name", entry.get("name", "装备"))), HORIZONTAL_ALIGNMENT_LEFT, size.x - 72, 16, PresentationTheme.ink(entry.get("color", Color.WHITE)))
		draw_string(font, Vector2(66, 77), "已装备 · 点击查看", HORIZONTAL_ALIGNMENT_LEFT, size.x - 72, 11, Color("69523a"))

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or not event.pressed:
			return
		var id: String = str(state.equipped.get(slot, ""))
		if id.is_empty():
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			selected.emit("item:" + id)
			if event.double_click:
				activated.emit("item:" + id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected.emit("item:" + id)
			activated.emit("item:" + id)
			accept_event()

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var id: String = str(state.equipped.get(slot, ""))
		if id.is_empty():
			return null
		var key: String = "item:" + id
		selected.emit(key)
		set_drag_preview(GridView.make_drag_preview(GridView.describe_item(state, key), Vector2(state.item_size(key)) * GridView.CELL))
		return {"type": "inventory_item", "key": key, "grab_offset": Vector2i.ZERO, "source_slot": slot}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if not GridView.is_item_drag(data):
			return false
		var key: String = str(data["key"])
		var id: String = key.substr(5) if key.begins_with("item:") else ""
		var valid: bool = not id.is_empty() and state.get_item_definition(id).get("slot", "") == slot and state.inventory.has(id) and state.equipped.get(slot, "") != id
		_drop_state = 1 if valid else -1
		queue_redraw()
		return valid

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if not _can_drop_data(at_position, data):
			return
		var key: String = str(data["key"])
		if state.equip(key.substr(5)):
			selected.emit(key)
			feedback.emit("已装备 · " + str(state.get_item_definition(key.substr(5))["name"]))
		else:
			feedback.emit("背包没有足够空间，无法替换装备")
		_drop_state = 0
		queue_redraw()

	func _process(_delta: float) -> void:
		if _drop_state != 0 and (not get_viewport().gui_is_dragging() or not get_global_rect().has_point(get_global_mouse_position())):
			_drop_state = 0
			queue_redraw()


func setup(state: BuildState) -> void:
	if _state != null and _state.changed.is_connected(refresh):
		_state.changed.disconnect(refresh)
	_state = state
	name = "InventoryPanel"
	add_theme_constant_override("separation", 9)
	if not _built:
		_build_interface()
		_built = true
	_grid.setup(state)
	for slot_control: EquipmentSlot in _equipment_slots.values():
		slot_control.state = state
	if not _state.changed.is_connected(refresh):
		_state.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not _built or _state == null:
		return
	var keys: Array[String] = _state.get_backpack_items()
	if selected_item_key.is_empty() or GridView.describe_item(_state, selected_item_key).is_empty():
		selected_item_key = keys[0] if not keys.is_empty() else ""
	var used: int = 0
	var jewel_count: int = 0
	for key: String in keys:
		var dimensions: Vector2i = _state.item_size(key)
		used += dimensions.x * dimensions.y
		if key.begins_with("jewel:"):
			jewel_count += 1
	_usage_label.text = "%d / 96 格  ·  %d 件物品" % [used, keys.size()]
	_usage_label.tooltip_text = "12 列 × 8 行；背包中的珠宝 %d 颗\n已装备物品和已镶嵌珠宝不占背包空间" % jewel_count
	var stats: Dictionary = _state.get_stats()
	var defense: Dictionary = Defense.defense_profile({"fire_resistance": stats.get("fire_resistance", 0.0)})
	_stats_summary.text = "生命 %d     法力 %d     护盾 %d     基伤 %.0f     攻速 %.2f     移速 %.0f" % [int(stats.get("max_health", 0)), int(stats.get("max_mana", 0)), int(stats.get("max_shield", 0)), float(stats.get("damage", 0)), float(stats.get("attack_speed", 0)), float(stats.get("move_speed", 0))]
	_stats_summary.text += "   火抗 %.0f%%" % (float(defense.effective_resistances.fire) * 100.0)
	_stats_summary.tooltip_text = "基伤是保留的通用基础伤害，不含武器本地物理、分类点伤、提高/更多与敌方抗性。K 查看实际技能命中预估，F6 分开查看通用、武器与附加分量。\n火焰抗性：合计 %.0f%% → 有效 %.0f%%（上限 %.0f%%）。只降低火焰分量，然后先消耗护盾，再消耗生命。" % [float(defense.raw_resistances.fire) * 100.0, float(defense.effective_resistances.fire) * 100.0, Defense.FIRE_RESISTANCE_CAP * 100.0]
	_grid.select_item(selected_item_key)
	_grid.refresh()
	for slot_control: EquipmentSlot in _equipment_slots.values():
		slot_control.selected_key = selected_item_key
		slot_control.refresh()
	_refresh_details()


func select_item(key: String) -> void:
	if _state == null or GridView.describe_item(_state, key).is_empty():
		return
	selected_item_key = key
	refresh()


func _build_interface() -> void:
	var summary_panel := PanelContainer.new()
	summary_panel.name = "InventoryStatsSummary"
	summary_panel.add_theme_stylebox_override("panel", make_style(Color("f8ecd0"), Color("8c6b42"), 6, 1, 8))
	add_child(summary_panel)
	var summary_row := HBoxContainer.new()
	summary_panel.add_child(summary_row)
	summary_row.add_child(_label("当前属性", 13, CYAN))
	_stats_summary = _label("", 13, TEXT)
	_stats_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_summary.name = "DerivedStatsLabel"
	_stats_summary.mouse_filter = Control.MOUSE_FILTER_PASS
	_stats_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	summary_row.add_child(_stats_summary)

	var columns := HBoxContainer.new()
	columns.name = "InventoryColumns"
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)

	var equipment := VBoxContainer.new()
	equipment.name = "EquipmentColumn"
	equipment.custom_minimum_size.x = 168
	equipment.add_theme_constant_override("separation", 8)
	columns.add_child(equipment)
	var equipment_header: Label = _label("角色装备", 17, GOLD)
	equipment_header.custom_minimum_size.y = 30
	equipment_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	equipment.add_child(equipment_header)
	for slot: String in ["weapon", "armor", "charm"]:
		var target := EquipmentSlot.new()
		target.name = "EquipSlot_" + slot
		target.state = _state
		target.slot = slot
		target.selected.connect(select_item)
		target.activated.connect(_activate_item)
		target.feedback.connect(_relay_feedback)
		equipment.add_child(target)
		_equipment_slots[slot] = target
	var equipment_help: Label = _label("拖入部位穿戴\n拖回背包卸下", 13, MUTED)
	equipment_help.custom_minimum_size.y = 44
	equipment_help.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	equipment.add_child(equipment_help)

	var backpack := VBoxContainer.new()
	backpack.name = "BackpackColumn"
	backpack.add_theme_constant_override("separation", 7)
	columns.add_child(backpack)
	var bag_header := HBoxContainer.new()
	bag_header.custom_minimum_size.y = 30
	backpack.add_child(bag_header)
	bag_header.add_child(_label("背包", 17, GOLD))
	_usage_label = _label("", 12, MUTED)
	_usage_label.name = "BackpackUsageLabel"
	_usage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_usage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bag_header.add_child(_usage_label)
	var sort_button: Button = _button("整理", "AutoSortBackpackButton", _sort_backpack)
	sort_button.custom_minimum_size = Vector2(62, 29)
	sort_button.add_theme_font_size_override("font_size", 13)
	sort_button.add_theme_stylebox_override("normal", make_style(Color("f8ecd0"), BORDER, 5, 1, 4))
	sort_button.add_theme_stylebox_override("hover", make_style(Color("fff2d5"), CYAN, 5, 1, 4))
	sort_button.add_theme_stylebox_override("pressed", make_style(Color("ead3a2"), CYAN, 5, 1, 4))
	bag_header.add_child(sort_button)
	_grid = GridView.new()
	_grid.name = "InventoryGrid"
	_grid.item_selected.connect(select_item)
	_grid.item_activated.connect(_activate_item)
	_grid.feedback.connect(_relay_feedback)
	backpack.add_child(_grid)
	var bag_hint: Label = _label("拖动整理   ·   双击装备   ·   珠宝占 1 格", 12, MUTED)
	bag_hint.name = "BackpackHelpLabel"
	backpack.add_child(bag_hint)

	var detail_panel := PanelContainer.new()
	detail_panel.name = "ItemDetailPanel"
	detail_panel.custom_minimum_size.x = 250
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", make_style(Color("f8ecd0"), BORDER, 7, 1, 13))
	columns.add_child(detail_panel)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 6)
	detail_panel.add_child(detail)
	_detail_type = _label("物品详情", 12, MUTED)
	_detail_type.name = "ItemTypeLabel"
	_detail_type.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_type)
	_detail_name = _label("选择物品", 20, GOLD)
	_detail_name.name = "ItemNameLabel"
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_name)
	_detail_art = GridView.ItemArt.new()
	_detail_art.name = "ItemDetailArt"
	_detail_art.draw_border = false
	_detail_art.custom_minimum_size = Vector2(80, 108)
	_detail_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(_detail_art)
	_detail_status = _label("", 12, CYAN)
	_detail_status.name = "ItemStatusLabel"
	_detail_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_status)
	var separator := HSeparator.new()
	separator.modulate = Color("8e8262")
	detail.add_child(separator)
	_detail_stats = _label("", 14, TEXT)
	_detail_stats.name = "ItemStatsLabel"
	_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stats_scroll := ScrollContainer.new()
	stats_scroll.name = "ItemAffixScroll"
	stats_scroll.custom_minimum_size.y = 86
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(stats_scroll)
	_detail_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_scroll.add_child(_detail_stats)
	_detail_hint = _label("", 12, MUTED)
	_detail_hint.name = "ItemHintLabel"
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_hint)
	_equip_button = _button("装备", "EquipSelectedButton", _equip_selected)
	detail.add_child(_equip_button)
	_unequip_button = _button("卸回背包", "UnequipSelectedButton", _unequip_selected)
	detail.add_child(_unequip_button)
	_passives_button = _button("前往天赋星图镶嵌", "OpenPassivesButton", _open_passives)
	detail.add_child(_passives_button)
	_discard_button = _button("丢弃这件装备", "DiscardEquipmentButton", _request_discard)
	_discard_button.add_theme_color_override("font_color",Color("9a382c"))
	detail.add_child(_discard_button)
	_craft_controls = CraftControls.new()
	_craft_controls.name = "InventoryCraftingControls"
	_craft_controls.craft_requested.connect(_request_craft)
	detail.add_child(_craft_controls)
	_craft_dialog = ConfirmationDialog.new()
	_craft_dialog.name = "CraftingConfirmation"
	# A partial theme retains inherited UI/font scaling. Only the stock grey
	# embedded title frame and its unreadable dark title gain warm wood/cream.
	var dialog_theme := Theme.new()
	dialog_theme.set_color("title_color", "Window", Color("f8ecd0"))
	for style_name: String in ["embedded_border", "embedded_unfocused_border"]:
		var frame: StyleBoxFlat = ThemeDB.get_default_theme().get_stylebox(style_name, "Window").duplicate() as StyleBoxFlat
		if frame != null:
			frame.bg_color = Color("60432f")
			frame.border_color = BORDER
			dialog_theme.set_stylebox(style_name, "Window", frame)
	_craft_dialog.theme = dialog_theme
	_craft_dialog.dialog_autowrap = true
	_craft_dialog.cancel_button_text = "取消"
	_craft_dialog.confirmed.connect(_confirm_craft)
	_craft_dialog.canceled.connect(func() -> void:
		_cancel_craft()
		refresh())
	add_child(_craft_dialog)
	_craft_dialog.get_ok_button().add_theme_color_override("font_focus_color", TEXT)
	_craft_dialog.get_cancel_button().add_theme_color_override("font_focus_color", TEXT)
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.name = "DiscardEquipmentConfirmation"
	_discard_dialog.title = "确认丢弃装备"
	_discard_dialog.ok_button_text = "确认永久丢弃"
	_discard_dialog.cancel_button_text = "保留装备"
	_discard_dialog.confirmed.connect(_confirm_discard)
	_discard_dialog.canceled.connect(func() -> void: _discard_target = "")
	add_child(_discard_dialog)


func _refresh_details() -> void:
	var entry: Dictionary = GridView.describe_item(_state, selected_item_key)
	_equip_button.hide()
	_unequip_button.hide()
	_passives_button.hide()
	_discard_button.hide()
	_craft_controls.hide()
	_detail_art.entry = entry
	_detail_art.queue_redraw()
	if entry.is_empty():
		_detail_name.text = "选择物品"
		_detail_type.text = "物品详情"
		_detail_status.text = "背包中暂时没有物品"
		_detail_stats.text = "点击背包物品或左侧装备，查看完整属性。"
		_detail_hint.text = "战斗中获得的珠宝会自动放入背包。"
		_detail_art.hide()
		return
	_detail_art.show()
	var is_jewel: bool = entry.get("kind", "") == "jewel"
	var dimensions: Vector2i = _state.item_size(selected_item_key)
	var color: Color = entry.get("color", CYAN)
	_detail_name.text = str(entry.get("name", "物品"))
	_detail_name.add_theme_color_override("font_color", PresentationTheme.ink(color))
	if is_jewel:
		var serial: int = str(entry.get("id", "")).trim_prefix("jewel_").to_int()
		_detail_type.text = "普通珠宝  ·  %s  ·  #%03d" % [entry.get("rarity_name", ""), serial]
		var in_bag: bool = _state.backpack_positions.has(selected_item_key)
		_detail_status.text = "%s  ·  占用 1 × 1 格" % ("背包中" if in_bag else "已镶嵌")
		_detail_stats.text = str(entry.get("description", ""))
		_detail_hint.text = "放入已激活的珠宝槽后，全部词缀才会生效。"
		_passives_button.show()
	else:
		var slot: String = str(entry.get("slot", ""))
		var worn: bool = _state.equipped.get(slot, "") == entry.get("id", "")
		_detail_type.text = "%s  ·  %s  ·  物品等级 %d" % [SLOT_NAMES.get(slot, "装备"), entry.get("rarity_name", "装备"),int(entry.get("item_level",1))]
		_detail_status.text = "%s  ·  占用 %d × %d 格" % ["已装备" if worn else "背包中", dimensions.x, dimensions.y]
		_detail_stats.text = "装备合计\n" + _gear_stats(entry.get("stats", {}))
		if entry.has("weapon_damage_summary"):
			# Local item damage is a separate contribution, never a character stat.
			var character_stats: String = _gear_stats(entry.get("stats", {}))
			_detail_stats.text = str(entry.weapon_damage_summary) + "\n\n角色加值\n" + ("无" if character_stats.is_empty() else character_stats)
		var rolled: Array = entry.get("affix_lines", [])
		if not rolled.is_empty():
			_detail_stats.text += "\n\n随机词缀\n" + "\n".join(rolled)
			_detail_type.text += "\nT1 入门 / T2 中阶 / T3 高阶"
		_discard_button.visible = not worn and str(entry.get("id","")).begins_with("gear_")
		_detail_hint.text = "卸下后物品会放回空闲背包格。" if worn else "装备后替换同部位物品，属性立即生效。"
		_equip_button.visible = not worn
		_unequip_button.visible = worn
		_equip_button.text = "装备到" + str(SLOT_NAMES.get(slot, "装备槽"))
		_refresh_crafting(str(entry.get("id", "")))


func _refresh_crafting(item_id: String) -> void:
	_displayed_craft_quotes.clear()
	# Hidden inventory panels still receive model signals; never read/save files
	# merely to refresh an off-screen crafting row during a hundred-enemy battle.
	if not is_visible_in_tree() or not item_id.begins_with("gear_"):
		return
	var source: Dictionary = _state.equipment_instances.get(item_id, {})
	for operation: String in CraftControls.Craft.operation_ids():
		_displayed_craft_quotes[operation] = _state.crafting_quote(operation, item_id)
	_craft_controls.set_context(item_id, source, _state.crafting_balance(),
		_displayed_craft_quotes.salvage, _displayed_craft_quotes.recalibrate, "", _displayed_craft_quotes)
	_craft_controls.show()


func _request_craft(operation: String, item_id: String, source: Dictionary) -> void:
	if _craft_dialog.visible:
		return
	var quote: Dictionary = _displayed_craft_quotes.get(operation, {})
	if not quote.get("ok", false) or quote.get("item_id", "") != item_id or not quote.has("handle"):
		feedback.emit("选择已变化，请重新选择装备。")
		return
	var definition: Dictionary = _state.get_item_definition(item_id)
	if definition.is_empty():
		return
	_cancel_craft()
	_pending_craft = {"handle": quote.handle, "source": source.duplicate(true), "operation": operation,
		"amount": int(quote.materials.get("calibration_shard", 0)) if operation == "salvage" else int(quote.cost.get("calibration_shard", 0))}
	if operation == "salvage":
		_craft_dialog.title = "确认回收装备"
		_craft_dialog.ok_button_text = "确认回收"
		_craft_dialog.dialog_text = "回收「%s」？\n获得校准碎片 %d 枚。\n这件装备将从背包与存档中删除，无法恢复。" % [str(definition.name), _pending_craft.amount]
	elif operation == "recalibrate":
		_craft_dialog.title = "确认数值校准"
		_craft_dialog.ok_button_text = "消耗 %d 枚并校准" % _pending_craft.amount
		_craft_dialog.dialog_text = "校准「%s」？\n消耗校准碎片 %d 枚。\n重掷已有词缀数值；词缀种类、阶级和物品等级保持。\n结果可能降低或不变。" % [str(definition.name), _pending_craft.amount]
	else:
		var info: Dictionary = CraftControls.Craft.metadata().operations.get(operation, {})
		if info.is_empty():
			_cancel_craft()
			return
		_craft_dialog.title = "确认" + str(info.name)
		_craft_dialog.ok_button_text = "消耗 %d 枚并%s" % [_pending_craft.amount, info.name]
		_craft_dialog.dialog_text = "%s「%s」？\n消耗校准碎片 %d 枚。\n%s\n保持物品身份、底材与物品等级；结果不会提前展示。" % [info.name, str(definition.name), _pending_craft.amount, info.description]
	_craft_dialog.popup_centered(Vector2i(500, 240))


func _cancel_craft() -> void:
	if not _pending_craft.is_empty():
		_state.cancel_crafting_quote(str(_pending_craft.handle))
	_pending_craft.clear()


func _confirm_craft() -> void:
	if _pending_craft.is_empty():
		return
	var pending: Dictionary = _pending_craft.duplicate(true)
	_pending_craft.clear()
	var result: Dictionary = _state.execute_crafting(pending.handle, pending.source)
	if not result.ok:
		feedback.emit(str(result.reason))
		refresh()
		return
	if pending.operation == "salvage":
		selected_item_key = ""
		feedback.emit("已回收装备，获得校准碎片 %d 枚。" % pending.amount)
	else:
		feedback.emit("已完成%s，消耗校准碎片 %d 枚。" % [CraftControls.Craft.metadata().operations[pending.operation].name, pending.amount])
	refresh()


func _activate_item(key: String) -> void:
	select_item(key)
	if key.begins_with("jewel:"):
		_open_passives()
		return
	var entry: Dictionary = GridView.describe_item(_state, key)
	if _state.equipped.get(entry.get("slot", ""), "") == entry.get("id", ""):
		_unequip_selected()
	else:
		_equip_selected()


func _equip_selected() -> void:
	if not selected_item_key.begins_with("item:"):
		return
	var id: String = selected_item_key.substr(5)
	if _state.equip(id):
		feedback.emit("已装备 · " + str(_state.get_item_definition(id)["name"]))
	else:
		feedback.emit("无法装备：请检查部位或背包空闲空间")


func _unequip_selected() -> void:
	if not selected_item_key.begins_with("item:"):
		return
	var id: String = selected_item_key.substr(5)
	var slot: String = str(_state.get_item_definition(id).get("slot", ""))
	if _state.equipped.get(slot, "") != id:
		return
	if _state.unequip(slot):
		feedback.emit("已卸回背包 · " + str(_state.get_item_definition(id)["name"]))
	else:
		feedback.emit("背包没有足够空闲格，无法卸下")


func _sort_backpack() -> void:
	if _state.auto_sort_backpack():
		refresh()
		feedback.emit("背包已整理 · 装备与珠宝按大小排列")
	else:
		feedback.emit("背包已经整齐排列")


func _open_passives() -> void:
	open_passives_requested.emit()


func _relay_feedback(message: String) -> void:
	feedback.emit(message)


func _gear_stats(stats: Dictionary) -> String:
	var lines: PackedStringArray = []
	for key: String in stats:
		lines.append(Passives.describe_stats({key: stats[key]}))
	return "\n".join(lines)


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PresentationTheme.ink(color))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _button(text: String, stable_name: String, callback: Callable) -> Button:
	var result := Button.new()
	result.name = stable_name
	result.text = text
	result.custom_minimum_size.y = 35
	result.add_theme_font_size_override("font_size", 14)
	result.pressed.connect(callback)
	return result


static func make_style(bg: Color, line: Color, radius: int = 6, border: int = 1, padding: int = 0) -> StyleBox:
	var frame: StyleBox=preload("res://scripts/visuals/visual_theme.gd").panel(bg,line,radius,border,padding)
	frame.content_margin_top=padding
	frame.content_margin_bottom=padding
	return frame


func _request_discard() -> void:
	if not selected_item_key.begins_with("item:gear_"):
		return
	var id: String = selected_item_key.substr(5)
	var entry: Dictionary = _state.get_item_definition(id)
	if entry.is_empty() or _state.equipped.values().has(id):
		return
	_discard_target = id
	_discard_dialog.dialog_text = "永久丢弃「%s」？\n该装备将从背包和存档中删除，无法恢复。" % str(entry.name)
	_discard_dialog.popup_centered(Vector2i(440,180))

func _confirm_discard() -> void:
	var target: String = _discard_target
	_discard_target = ""
	if target.is_empty():
		return
	if _state.discard_equipment(target):
		selected_item_key = ""
		refresh()
		feedback.emit("已丢弃装备，背包空位已释放")
	else:
		feedback.emit("未丢弃：装备已穿戴或不在背包中")
