class_name CanonicalInventoryPanel
extends VBoxContainer
## Independent inventory body. CanonicalGameState owns validation and persistence;
## this view never keeps a second inventory or writes a save directly.
signal feedback(message: String)
signal item_hovered(uid: String, anchor: Rect2)
signal hover_left
const CraftControls = preload("res://scripts/ui/crafting_controls.gd")
const ThemeStyle = preload("res://scripts/visuals/visual_theme.gd")
const EquipmentArt = preload("res://scripts/visuals/equipment_art.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const SLOT_NAMES := {"weapon":"武器","body_armour":"护甲","amulet":"项链","ring_1":"戒指一","ring_2":"戒指二","boots":"鞋","belt":"腰带","gloves":"手套","helmet":"头盔"}
var model: RefCounted
var save_path := "user://build_save.json"
var _grid: Control
var _slots: Dictionary = {}
var _paper: Control
var _pending: VBoxContainer
var _summary: Label
var _selected_uid := ""
var _craft_controls: Control
var _craft_quotes: Dictionary = {}
var _craft_dialog: ConfirmationDialog
var _pending_craft: Dictionary = {}

class SlotTarget extends Button:
	var owner_panel: CanonicalInventoryPanel
	var slot_id := ""
	var uid := ""
	var entry: Dictionary = {}
	func _draw() -> void:
		if not entry.is_empty():
			EquipmentArt.draw_item(self, entry, Rect2(Vector2(6,5), size - Vector2(12,25)))
		var font: Font = get_theme_default_font()
		var font_size: int = get_theme_font_size("font_size")
		draw_string(font,Vector2(3,size.y-5),CanonicalInventoryPanel.SLOT_NAMES[slot_id],HORIZONTAL_ALIGNMENT_CENTER,size.x-6,font_size,Color("3b281b"))
	func _get_drag_data(_at: Vector2) -> Variant:
		if uid.is_empty(): return null
		return {"type":"unified_item","uid":uid,"revision":owner_panel.model.revision(),"grab_offset":Vector2i.ZERO}
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return owner_panel._drag_valid(data) and owner_panel.model.can_move_item(data.uid, {"kind":"equipment","slot_id":slot_id}, data.revision)
	func _drop_data(_at: Vector2, data: Variant) -> void:
		if _can_drop_data(_at, data): owner_panel._move_requested(data.uid, {"kind":"equipment","slot_id":slot_id}, data.revision)

class PaperFigure extends Control:
	func _draw() -> void:
		var scale_value: Vector2 = size / Vector2(400,470)
		var color := Color("c4ac7e",0.45)
		draw_circle(Vector2(210,70) * scale_value, 30 * minf(scale_value.x,scale_value.y), color)
		var points := PackedVector2Array()
		for point: Vector2 in [Vector2(177,112),Vector2(244,112),Vector2(276,170),Vector2(253,292),Vector2(166,292),Vector2(142,170)]: points.append(point*scale_value)
		draw_colored_polygon(points,color)
		for limb: Array in [[Vector2(153,146),Vector2(100,260)],[Vector2(268,146),Vector2(318,260)],[Vector2(187,290),Vector2(172,443)],[Vector2(233,290),Vector2(248,443)]]:
			draw_line(limb[0]*scale_value,limb[1]*scale_value,color,26*minf(scale_value.x,scale_value.y),true)


func setup(state: RefCounted, path: String = "user://build_save.json") -> void:
	model = state
	save_path = path
	if _grid == null: _build()
	if not model.changed.is_connected(refresh): model.changed.connect(refresh)
	refresh()


func _build() -> void:
	name = "CanonicalInventoryBody"
	add_theme_constant_override("separation",10)
	var top := HBoxContainer.new()
	add_child(top)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_summary)
	var arrange := Button.new()
	arrange.name = "ArrangeUnifiedBag"
	arrange.text = "整理背包"
	arrange.pressed.connect(func(): _report(model.arrange_items(model.revision(), save_path)))
	top.add_child(arrange)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",16)
	add_child(row)
	_paper = PaperFigure.new()
	_paper.name = "EquipmentFigure"
	_paper.custom_minimum_size = Vector2(320,420)
	_paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paper.size_flags_stretch_ratio = 0.38
	row.add_child(_paper)
	_paper.resized.connect(_layout_slots)
	for slot: String in Slots.all_slots():
		var target := SlotTarget.new()
		target.name = "EquipmentTarget_" + slot
		target.slot_id = slot
		target.owner_panel = self
		target.text = ""
		target.alignment = HORIZONTAL_ALIGNMENT_CENTER
		target.add_theme_font_size_override("font_size",13)
		target.add_theme_constant_override("outline_size",0)
		target.add_theme_stylebox_override("normal",ThemeStyle.panel(Color("e2c997"), Color("967347"),4,1,4))
		target.pressed.connect(_activate_equipment.bind(slot))
		target.mouse_entered.connect(_hover_equipment.bind(slot))
		target.mouse_exited.connect(func(): hover_left.emit())
		_paper.add_child(target)
		_slots[slot] = target
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.62
	row.add_child(right)
	var grid_script: Script = load("res://scripts/ui/unified_bag_grid.gd")
	_grid = grid_script.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_grid)
	_grid.set_drop_validator(func(uid: String, destination: Dictionary, revision_value: int) -> bool: return model.can_move_item(uid,destination,revision_value))
	_grid.set_external_item_resolver(func(uid: String) -> Dictionary:
		var definition: Dictionary = model.item_definition(uid)
		if definition.is_empty(): return {}
		var dimensions: Variant = definition.size
		return {"uid":uid,"size":dimensions if dimensions is Vector2i else Vector2i(dimensions[0],dimensions[1])})
	_grid.move_requested.connect(_move_requested)
	_grid.item_selected.connect(_select_item)
	_grid.item_activated.connect(_activate_item)
	_grid.item_hovered.connect(func(uid: String, rect: Rect2): item_hovered.emit(uid,rect))
	_grid.hover_left.connect(func(): hover_left.emit())
	var hint := Label.new()
	hint.text = "悬停查看详情 · Shift 对比 · 右键装备 · 拖动选择目标"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size",13)
	right.add_child(hint)
	_craft_controls = CraftControls.new()
	_craft_controls.name = "CanonicalCraftingControls"
	_craft_controls.craft_requested.connect(_request_craft)
	right.add_child(_craft_controls)
	_build_craft_confirmation()
	visibility_changed.connect(func():
		if not is_visible_in_tree(): _cancel_craft())
	_pending = VBoxContainer.new()
	_pending.name = "RecoveryQueue"
	right.add_child(_pending)


func refresh() -> void:
	if model == null or _grid == null: return
	var state: Dictionary = model.snapshot()
	var entries: Array = []
	for uid: String in state.locations:
		var location: Dictionary = state.locations[uid]
		if location.kind != "bag": continue
		var definition: Dictionary = model.item_definition(uid)
		var raw_size: Variant = definition.size
		var item_size: Vector2i = raw_size if raw_size is Vector2i else Vector2i(raw_size[0],raw_size[1])
		entries.append({"uid":uid,"kind":state.items[uid].kind,"size":item_size,"cell":Vector2i(location.x,location.y),
			"art":definition,"icon":definition.get("icon_texture"),"accent":definition.get("color",Gear.RARITIES.get(definition.get("rarity",""),{}).get("color",Color("aa8c59"))),
			"short_name":str(definition.get("base_name",definition.get("short_name",definition.name)))})
	_grid.set_items(entries,model.revision())
	var equipped: Dictionary = model.equipped_items()
	for slot: String in _slots:
		var target: SlotTarget = _slots[slot]
		target.uid = equipped.get(slot,"")
		target.entry = model.item_definition(target.uid)
		target.tooltip_text = "" # Shared hover owns details; no competing native tooltip.
		target.queue_redraw()
	_summary.text = "共享行囊 12 × 8"
	for child: Node in _pending.get_children():
		_pending.remove_child(child)
		child.queue_free()
	var pending: Array = model.pending_items()
	_pending.visible = not pending.is_empty()
	if not pending.is_empty():
		var title := Label.new()
		title.text = "待安置 %d 件 · 腾出空间后取回" % pending.size()
		_pending.add_child(title)
		var list := HFlowContainer.new()
		_pending.add_child(list)
		for uid: String in pending:
			var button := Button.new()
			button.text = str(model.item_definition(uid).get("base_name", model.item_definition(uid).name))
			button.pressed.connect(_return_to_bag.bind(uid))
			list.add_child(button)
	_refresh_crafting()
	_layout_slots()


func _layout_slots() -> void:
	if not is_instance_valid(_paper): return
	var shapes := {"helmet":Rect2(173,12,74,68),"amulet":Rect2(183,93,54,54),"weapon":Rect2(33,151,66,128),
		"body_armour":Rect2(164,158,92,126),"gloves":Rect2(310,157,68,76),"ring_1":Rect2(63,306,58,58),
		"ring_2":Rect2(298,306,58,58),"belt":Rect2(166,298,90,54),"boots":Rect2(166,380,90,78)}
	var scale_value: Vector2 = _paper.size / Vector2(400,470)
	for slot: String in _slots:
		var rect: Rect2 = shapes[slot]
		_slots[slot].position = rect.position * scale_value
		_slots[slot].size = rect.size * scale_value
	_paper.queue_redraw()


func _move_requested(uid: String, destination: Dictionary, revision_value: int) -> void:
	_report(model.move_item(uid,destination,revision_value,save_path))
func _report(result: Dictionary) -> void:
	if not result.get("ok",false) and not str(result.get("reason","")).is_empty(): feedback.emit(result.reason)
func _return_to_bag(uid: String) -> void:
	var target: Dictionary = model.first_bag_position(uid)
	if target.is_empty(): feedback.emit("背包空间不足，物品保持原位置")
	else: _move_requested(uid,target,model.revision())
func _activate_equipment(slot: String) -> void:
	var uid: String = _slots[slot].uid
	if not uid.is_empty(): _return_to_bag(uid)
func _activate_item(uid: String) -> void:
	var item: Dictionary = model.item(uid)
	if item.get("kind","") != "equipment":
		feedback.emit("主动与辅助宝石在 K 技能界面装配；珠宝在 T 天赋界面镶嵌")
		return
	var targets: Array = Slots.targets_for_category(model.item_definition(uid).category)
	if targets.is_empty(): return
	var occupied: Dictionary = model.equipped_items()
	var target: String = targets[0]
	for slot: String in targets:
		if not occupied.has(slot):
			target = slot
			break
	_move_requested(uid,{"kind":"equipment","slot_id":target},model.revision())
func _hover_equipment(slot: String) -> void:
	var target: SlotTarget = _slots[slot]
	if not target.uid.is_empty(): item_hovered.emit(target.uid,target.get_global_rect())
func _drag_valid(value: Variant) -> bool:
	return value is Dictionary and value.size() == 4 and value.get("type") == "unified_item" and value.get("uid") is String \
		and value.get("revision") is int and value.get("grab_offset") is Vector2i


func _select_item(uid: String) -> void:
	_selected_uid = uid
	_refresh_crafting()


func _refresh_crafting() -> void:
	if _craft_controls == null or model == null: return
	for quote: Dictionary in _craft_quotes.values():
		if quote.has("handle"): model.cancel_crafting_quote(quote.handle)
	_craft_quotes.clear()
	var item: Dictionary = model.item(_selected_uid)
	var source: Dictionary = item.get("payload",{}) if item.get("kind","") == "equipment" else {}
	var reason := "选择背包中的随机装备可回收或校准"
	if not source.is_empty() and model.location(_selected_uid).get("kind","") == "bag":
		reason = ""
		for operation: String in ["salvage","recalibrate"]:
			_craft_quotes[operation] = model.crafting_quote(operation,_selected_uid,save_path)
	_craft_controls.set_context(_selected_uid,source,model.crafting_balance(),_craft_quotes.get("salvage",{}),_craft_quotes.get("recalibrate",{}),reason)


func _build_craft_confirmation() -> void:
	_craft_dialog = ConfirmationDialog.new()
	_craft_dialog.name = "CanonicalCraftConfirmation"
	var dialog_theme := Theme.new()
	dialog_theme.set_color("title_color","Window",Color("f8ecd0"))
	for style_name: String in ["embedded_border","embedded_unfocused_border"]:
		var frame: StyleBoxFlat = ThemeDB.get_default_theme().get_stylebox(style_name,"Window").duplicate() as StyleBoxFlat
		if frame != null:
			frame.bg_color = Color("60432f")
			frame.border_color = ThemeStyle.BORDER
			dialog_theme.set_stylebox(style_name,"Window",frame)
	_craft_dialog.theme = dialog_theme
	_craft_dialog.dialog_autowrap = true
	_craft_dialog.cancel_button_text = "取消"
	_craft_dialog.confirmed.connect(_confirm_craft)
	_craft_dialog.canceled.connect(func(): _cancel_craft(); _refresh_crafting())
	add_child(_craft_dialog)
	_craft_dialog.get_ok_button().add_theme_color_override("font_focus_color",ThemeStyle.TEXT)
	_craft_dialog.get_cancel_button().add_theme_color_override("font_focus_color",ThemeStyle.TEXT)


func _request_craft(operation: String,uid: String,source: Dictionary) -> void:
	if _craft_dialog.visible or uid != _selected_uid: return
	var quote: Dictionary = _craft_quotes.get(operation,{})
	if not quote.get("ok",false) or source != quote.get("source_instance",{}): return
	_pending_craft = {"quote":quote.duplicate(true),"source":source.duplicate(true)}
	var name_value: String = model.item_definition(uid).name
	if operation == "salvage":
		_craft_dialog.title = "确认回收装备"
		_craft_dialog.ok_button_text = "确认回收"
		_craft_dialog.dialog_text = "回收「%s」？\n获得校准碎片 %d 枚。\n这件装备将被消耗，无法恢复。" % [name_value,int(quote.materials.get("calibration_shard",0))]
	else:
		_craft_dialog.title = "确认数值校准"
		_craft_dialog.ok_button_text = "确认消耗并校准"
		_craft_dialog.dialog_text = "校准「%s」？\n消耗校准碎片 %d 枚。\n重掷已有词缀数值，结果可能降低或不变。\n种类、阶级和物品等级保持。" % [name_value,int(quote.cost.get("calibration_shard",0))]
	_craft_dialog.popup_centered(Vector2i(500,240))


func _confirm_craft() -> void:
	if _pending_craft.is_empty(): return
	var issued: Dictionary = _pending_craft.duplicate(true)
	_pending_craft.clear()
	var result: Dictionary = model.execute_crafting(issued.quote.handle,issued.source)
	if result.ok: feedback.emit("装备工艺已保存")
	else: feedback.emit(str(result.get("reason","操作未完成")))
	refresh()


func _cancel_craft() -> void:
	if not _pending_craft.is_empty(): model.cancel_crafting_quote(_pending_craft.quote.handle)
	_pending_craft.clear()
	if is_instance_valid(_craft_dialog): _craft_dialog.hide()
