class_name CanonicalInventoryPanel
extends VBoxContainer
## Independent inventory body. CanonicalGameState owns validation and persistence;
## this view never keeps a second inventory or writes a save directly.
signal feedback(message: String)
signal character_requested
signal item_hovered(uid: String, anchor: Rect2)
signal hover_left
const UnifiedGridView = preload("res://scripts/ui/unified_bag_grid.gd")
const FlaskSlotView = preload("res://scripts/ui/flask_slot.gd")
const CraftControls = preload("res://scripts/ui/crafting_controls.gd")
const ThemeStyle = preload("res://scripts/visuals/visual_theme.gd")
const RarityStyle=preload("res://scripts/ui/item_rarity_style.gd")
const EquipmentArt = preload("res://scripts/visuals/equipment_art.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const DockStyle = preload("res://scripts/ui/dock_visual_style.gd")
const SLOT_NAMES := {"weapon":"武器","body_armour":"护甲","amulet":"项链","ring_1":"戒指一","ring_2":"戒指二","boots":"鞋","belt":"腰带","gloves":"手套","helmet":"头盔"}
var model: RefCounted
var _trade_arena: Node
var save_path := "user://build_save.json"
var _grid: Control
var _slots: Dictionary = {}
var _equipment_grid: Control
var _flask_bar: HBoxContainer
var _flask_targets: Dictionary = {}
var _pending: VBoxContainer
var _summary: Label
var _page_label: Label
var _previous_page: Button
var _next_page: Button
var _bag_layout: Dictionary = {}
var _bag_page: int = 0
var _selected_uid := ""
var _craft_controls: Control
var _craft_quotes: Dictionary = {}
var _craft_metadata: Dictionary = {}
var _craft_dialog: ConfirmationDialog
var _pending_craft: Dictionary = {}
var _character: Button
var _discard: Button
var _pending_discard: Dictionary = {}
var _refresh_dirty: bool = true
var refresh_generation: int = 0

class CharacterButton extends Button:
	func _make_custom_tooltip(text:String)->Object:return CraftControls.wrapped_tooltip(self,text)

class SlotTarget extends Button:
	var owner_panel: CanonicalInventoryPanel
	var slot_id := ""
	var uid := ""
	var entry: Dictionary = {}
	func _draw() -> void:
		if not entry.is_empty():
			var caption_height: float = get_theme_font_size("font_size") + 5.0
			EquipmentArt.draw_item(self, entry, Rect2(Vector2(4,3),Vector2(size.x-8.0,maxf(8.0,size.y-caption_height-4.0))))
		var font: Font = get_theme_default_font()
		var font_size: int = get_theme_font_size("font_size")
		while font_size > 7 and font.get_string_size(CanonicalInventoryPanel.SLOT_NAMES[slot_id],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > size.x-6:
			font_size -= 1
		draw_string(font,Vector2(3,size.y-3),CanonicalInventoryPanel.SLOT_NAMES[slot_id],HORIZONTAL_ALIGNMENT_CENTER,size.x-6,font_size,Color("3b281b"))
	func _get_drag_data(_at: Vector2) -> Variant:
		if uid.is_empty(): return null
		return {"type":"unified_item","uid":uid,"revision":owner_panel.model.revision(),"grab_offset":Vector2i.ZERO}
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return owner_panel._drag_valid(data) and owner_panel.model.can_move_item(data.uid, {"kind":"equipment","slot_id":slot_id}, data.revision)
	func _drop_data(_at: Vector2, data: Variant) -> void:
		if _can_drop_data(_at, data): owner_panel._move_requested(data.uid, {"kind":"equipment","slot_id":slot_id}, data.revision)

func setup(state: RefCounted, path: String = "user://build_save.json", trade_arena: Node = null) -> void:
	model = state
	_trade_arena = trade_arena
	if _trade_arena != null and not _trade_arena.world_context_changed.is_connected(_on_trade_world_changed):
		_trade_arena.world_context_changed.connect(_on_trade_world_changed)
	save_path = path
	if _grid == null: _build()
	if not model.changed.is_connected(_on_model_changed): model.changed.connect(_on_model_changed)
	if not visibility_changed.is_connected(_on_visibility_changed): visibility_changed.connect(_on_visibility_changed)
	_refresh_dirty = true
	refresh()


func _build() -> void:
	name = "CanonicalInventoryBody"
	add_theme_constant_override("separation",5)
	var top := HBoxContainer.new()
	top.name = "BagHeader"
	top.add_theme_constant_override("separation", 4)
	add_child(top)
	_summary = Label.new()
	_summary.name = "BagSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary.add_theme_font_size_override("font_size", 11)
	top.add_child(_summary)
	var actions := HBoxContainer.new()
	actions.name = "BagHeaderActions"
	actions.add_theme_constant_override("separation", 3)
	actions.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(actions)
	var arrange := Button.new()
	arrange.name = "ArrangeUnifiedBag"
	arrange.text = "整理"
	arrange.custom_minimum_size.x = 46
	arrange.custom_minimum_size.y = 24
	arrange.add_theme_font_size_override("font_size", 12)
	DockStyle.style_action(arrange,11)
	arrange.pressed.connect(func(): _report(model.arrange_items(model.revision(), save_path)))
	actions.add_child(arrange)
	_discard=Button.new()
	_discard.name="DiscardUnifiedItem"
	_discard.text="丢弃"
	_discard.custom_minimum_size.x = 46
	_discard.custom_minimum_size.y = 24
	_discard.add_theme_font_size_override("font_size", 12)
	DockStyle.style_action(_discard,11)
	_discard.pressed.connect(_request_discard)
	actions.add_child(_discard)
	_equipment_grid = Control.new()
	_equipment_grid.name = "EquipmentSlotGrid"
	_equipment_grid.custom_minimum_size.y = 154.0
	_equipment_grid.resized.connect(_layout_slots)
	_equipment_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_equipment_grid)
	for slot: String in Slots.all_slots():
		var target := SlotTarget.new()
		target.name = "EquipmentTarget_" + slot
		target.slot_id = slot
		target.owner_panel = self
		target.text = ""
		target.alignment = HORIZONTAL_ALIGNMENT_CENTER
		target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target.custom_minimum_size = Vector2.ZERO
		target.add_theme_font_size_override("font_size",10)
		target.add_theme_constant_override("outline_size",0)
		# Preserve the approved painted equipment frames and icon-above-name
		# arrangement; only the surrounding toolbars use the quieter flat style.
		target.add_theme_stylebox_override("normal",ThemeStyle.panel(Color("e9dbc0"),Color("a88b59"),4,1,3))
		target.add_theme_stylebox_override("hover",ThemeStyle.panel(Color("fff2d5"),Color("ba9759"),4,1,3))
		target.add_theme_stylebox_override("pressed",ThemeStyle.panel(Color("dfcba3"),Color("987749"),4,1,3))
		target.pressed.connect(_activate_equipment.bind(slot))
		target.mouse_entered.connect(_hover_equipment.bind(slot))
		target.mouse_exited.connect(func(): hover_left.emit())
		_equipment_grid.add_child(target)
		_slots[slot] = target
	# Compact anatomical placement follows the user reference. Inventory actions
	# remain below the equipment rather than occupying another screen panel.
	_flask_bar = HBoxContainer.new()
	_flask_bar.name = "FlaskBelt"
	_flask_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_flask_bar.add_theme_constant_override("separation",5)
	add_child(_flask_bar)
	for index: int in range(5):
		var socket := FlaskSlotView.new()
		socket.name = "FlaskSocket_%d" % index
		socket.slot_id = "flask_%d" % (index+1)
		socket.model = model
		socket.editing = true
		socket.move_requested.connect(_move_requested)
		socket.remove_requested.connect(_return_to_bag)
		socket.item_hovered.connect(func(uid: String, rect: Rect2): item_hovered.emit(uid,rect))
		socket.hover_left.connect(func(): hover_left.emit())
		_flask_bar.add_child(socket)
		_flask_targets[socket.slot_id] = socket
	move_child(top, get_child_count()-1)
	var page_bar := HBoxContainer.new()
	page_bar.name = "BagPageControls"
	page_bar.custom_minimum_size.y = 24
	_page_label = Label.new()
	_page_label.name = "BagPageLabel"
	_page_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 12)
	page_bar.add_child(_page_label)
	_previous_page = Button.new()
	_previous_page.name = "PreviousBagPage"
	_previous_page.text = "‹"
	_previous_page.custom_minimum_size = Vector2(22, 24)
	_previous_page.add_theme_font_size_override("font_size", 12)
	DockStyle.style_action(_previous_page,12)
	_previous_page.tooltip_text = "上一页"
	_previous_page.pressed.connect(_turn_page.bind(-1))
	page_bar.add_child(_previous_page)
	_next_page = Button.new()
	_next_page.name = "NextBagPage"
	_next_page.text = "›"
	_next_page.custom_minimum_size = Vector2(22, 24)
	_next_page.add_theme_font_size_override("font_size", 12)
	DockStyle.style_action(_next_page,12)
	_next_page.tooltip_text = "下一页"
	_next_page.pressed.connect(_turn_page.bind(1))
	page_bar.add_child(_next_page)
	top.add_child(page_bar)
	_grid = UnifiedGridView.new()
	_grid.name = "SharedCanonicalBagGrid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.custom_minimum_size.y = 232.0
	add_child(_grid)
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
	_craft_controls = CraftControls.new()
	_craft_controls.name = "CanonicalCraftingControls"
	_craft_controls.craft_requested.connect(_request_craft)
	add_child(_craft_controls)
	_craft_controls._ensure_interface()
	DockStyle.style_action(_craft_controls._salvage_button,11)
	DockStyle.style_action(_craft_controls._recalibrate_button,11)
	_build_craft_confirmation()
	visibility_changed.connect(func():
		if not is_visible_in_tree(): _cancel_craft())
	_pending = VBoxContainer.new()
	_pending.name = "RecoveryQueue"
	add_child(_pending)


func refresh() -> void:
	if model == null or _grid == null: return
	if not _refresh_dirty: return
	_bag_layout = model.bag_layout() if model.has_method("bag_layout") else {"pages":1,"columns":12,"rows":8}
	var page_count: int = maxi(1, int(_bag_layout.get("pages", 1)))
	_bag_page = clampi(_bag_page, 0, page_count - 1)
	_grid.set_bag_layout(_bag_layout, _bag_page)
	var state: Dictionary = model.snapshot()
	var entries: Array = []
	for uid: String in state.locations:
		var location: Dictionary = state.locations[uid]
		if location.kind != "bag": continue
		if int(location.get("page", 0)) != _bag_page: continue
		var definition: Dictionary = model.item_definition(uid)
		var raw_size: Variant = definition.size
		var item_size: Vector2i = raw_size if raw_size is Vector2i else Vector2i(raw_size[0],raw_size[1])
		var icon: Variant = definition.get("icon_texture")
		if state.items[uid].kind == "flask" and icon == null:
			var path: String = str(definition.get("icon_path",""))
			if not path.is_empty() and ResourceLoader.exists(path): icon = load(path)
		entries.append({"uid":uid,"kind":state.items[uid].kind,"size":item_size,"cell":Vector2i(location.x,location.y),
			"art":definition,"icon":icon,"accent":definition.get("color",Gear.RARITIES.get(definition.get("rarity",""),{}).get("color",Color("aa8c59"))),
			"short_name":str(definition.get("base_name",definition.get("short_name",definition.name)))})
	_grid.set_items(entries,model.revision())
	if model.has_method("flask_slots"):
		for flask: Dictionary in model.flask_slots():
			if _flask_targets.has(flask.slot_id): _flask_targets[flask.slot_id].set_status(flask)
	var equipped: Dictionary = model.equipped_items()
	for slot: String in _slots:
		var target: SlotTarget = _slots[slot]
		target.uid = equipped.get(slot,"")
		target.entry = model.item_definition(target.uid)
		var rarity: String=str(target.entry.get("rarity","normal"))
		if not target.uid.is_empty():
			target.add_theme_stylebox_override("normal",ThemeStyle.panel(RarityStyle.background(rarity),RarityStyle.border(rarity),4,2,3))
		else:
			target.add_theme_stylebox_override("normal",ThemeStyle.panel(Color("e9dbc0"),Color("a88b59"),4,1,3))
		target.tooltip_text = "" # Shared hover owns details; no competing native tooltip.
		target.queue_redraw()
	var columns: int = int(_bag_layout.get("columns", 12))
	var rows: int = int(_bag_layout.get("rows", 8))
	_summary.text = "行囊 %d 格" % [page_count * columns * rows]
	_summary.tooltip_text = "九个装备位 · 装备、珠宝与宝石共用分页行囊。悬停看详情，Shift 对比，右键可装备。"
	_page_label.text = "%d/%d" % [_bag_page + 1, page_count]
	_page_label.tooltip_text = "%d × %d 格 · 悬停看详情 · Shift 对比 · 拖放摆放" % [columns, rows]
	_previous_page.disabled = _bag_page <= 0
	_next_page.disabled = _bag_page >= page_count - 1
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
			if model.item(uid).kind == "currency":
				button.text += " ×%d" % int(model.item(uid).payload.quantity)
			button.tooltip_text = button.text
			button.clip_text = true
			button.pressed.connect(_return_to_bag.bind(uid))
			list.add_child(button)
	_refresh_crafting()
	_craft_controls._balance_label.hide()
	_layout_slots()
	_refresh_dirty = false
	refresh_generation += 1


func _on_model_changed() -> void:
	if bool(_pending_craft.get("gem", false)): _cancel_craft()
	_refresh_dirty = true
	if is_visible_in_tree(): refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _refresh_dirty: refresh()

func _on_trade_world_changed() -> void:
	if bool(_pending_craft.get("gem", false)): _cancel_craft()
	_refresh_crafting()


func _layout_slots() -> void:
	if not is_instance_valid(_equipment_grid): return
	# Authored in a spaced 320×184 coordinate frame; scaling is uniform.
	var rects := {
		"helmet": Rect2(131,0,58,36),
		"weapon": Rect2(10,25,52,88),
		"body_armour": Rect2(126,48,68,70),
		"amulet": Rect2(220,40,35,35),
		"ring_1": Rect2(78,91,34,34),
		"ring_2": Rect2(222,91,34,34),
		"gloves": Rect2(52,141,49,40),
		"belt": Rect2(127,143,67,27),
		"boots": Rect2(218,141,49,40),
	}
	var scale_value := minf(0.82, _equipment_grid.size.x / 320.0)
	var offset := Vector2((_equipment_grid.size.x - 320.0*scale_value)*0.5,0)
	for slot: String in _slots:
		var bounds: Rect2 = rects[slot]
		_slots[slot].position = offset + bounds.position*scale_value
		_slots[slot].size = bounds.size*scale_value
	_equipment_grid.queue_redraw()


func _turn_page(delta: int) -> void:
	var page_count: int = maxi(1, int(_bag_layout.get("pages", 1)))
	var next_page: int = clampi(_bag_page + delta, 0, page_count - 1)
	if next_page == _bag_page: return
	_bag_page = next_page
	_refresh_dirty = true
	refresh()


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
	if item.get("kind","") == "currency": return
	if item.get("kind","") == "flask" and model.has_method("flask_slots"):
		for flask: Dictionary in model.flask_slots():
			if str(flask.get("uid","")).is_empty():
				_move_requested(uid,{"kind":"flask_slot","slot_id":flask.slot_id},model.revision())
				return
		feedback.emit("药剂槽已满，可拖到指定槽位替换")
		return
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
	if uid!=_selected_uid:_cancel_craft()
	_selected_uid = uid
	_refresh_crafting()


func _refresh_crafting() -> void:
	if _craft_controls == null or model == null: return
	for quote: Dictionary in _craft_quotes.values():
		if quote.has("handle"): model.cancel_crafting_quote(quote.handle)
	_craft_quotes.clear()
	var item: Dictionary = model.item(_selected_uid)
	_discard.disabled = item.is_empty() or not model.can_discard_item(_selected_uid)
	var source: Dictionary = item.get("payload",{}) if item.get("kind","") == "equipment" else {}
	if item.get("kind", "") in ["skill_gem", "support_gem"] and model.has_method("gem_recycle_info"):
		var info: Dictionary = _trade_arena.normal_gem_recycle_info(_selected_uid) if _trade_arena != null else {"available":false,"reason":"请先返回正式城镇","credit":1}
		_craft_metadata.clear()
		_craft_controls.set_operations_context(_selected_uid, item.payload, model.crafting_balance(), [{"operation":"salvage","label":"回收","available":bool(info.available),"reason":str(info.get("reason","")),"description":"回收所选宝石","risk":"仅消耗这一颗，其他同名宝石不变。","materials":{"calibration_shard":int(info.credit)}}])
		return
	if model.has_method("crafting_operations"):
		var operations: Array = model.crafting_operations(_selected_uid,save_path)
		_craft_metadata.clear()
		for entry: Dictionary in operations: _craft_metadata[str(entry.operation)] = entry.duplicate(true)
		_craft_controls.set_operations_context(_selected_uid,source,model.crafting_balance(),operations)
		return
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
	if operation == "salvage" and model.item(uid).get("kind", "") in ["skill_gem", "support_gem"]:
		_request_gem_recycle(uid, source)
		return
	var quote: Dictionary
	if model.has_method("crafting_operations"):
		quote = model.crafting_quote(operation,uid,save_path)
		if not quote.get("ok",false):
			_report(quote)
			_refresh_crafting()
			return
		if source != quote.get("source_instance",{}):
			if quote.has("handle"): model.cancel_crafting_quote(quote.handle)
			return
		_craft_quotes[operation] = quote.duplicate(true)
	else:
		quote = _craft_quotes.get(operation,{})
		if not quote.get("ok",false) or source != quote.get("source_instance",{}): return
	_pending_craft = {"quote":quote.duplicate(true),"source":source.duplicate(true)}
	var name_value: String = model.item_definition(uid).name
	if operation == "salvage":
		_craft_dialog.title = "确认回收装备"
		_craft_dialog.ok_button_text = "确认回收"
		_craft_dialog.dialog_text = "回收「%s」？\n获得校准碎片 %d 枚。\n这件装备将被消耗，无法恢复。" % [name_value,int(quote.materials.get("calibration_shard",0))]
	elif operation == "recalibrate":
		_craft_dialog.title = "确认数值校准"
		_craft_dialog.ok_button_text = "确认消耗并校准"
		_craft_dialog.dialog_text = "校准「%s」？\n消耗校准碎片 %d 枚。\n重掷已有词缀数值，结果可能降低或不变。\n种类、阶级和物品等级保持。" % [name_value,int(quote.cost.get("calibration_shard",0))]
	elif bool(_craft_metadata.get(operation,{}).get("targeted",false)):
		var metadata: Dictionary = _craft_metadata[operation]
		var target_label := str(metadata.get("target_label","所选方向"))
		_craft_dialog.title = "定向重铸 · " + target_label
		_craft_dialog.ok_button_text = "确认消耗并重铸"
		_craft_dialog.dialog_text = "重铸「%s」？\n消耗校准碎片 %d 枚。\n保证至少一个「%s」方向的合法词缀。\n全部原词缀将被替换，其他词缀随机，不保证高阶或更高数值。" % [name_value,int(quote.cost.get("calibration_shard",0)),target_label]
	else:
		var metadata: Dictionary = _craft_metadata.get(operation,{})
		var label: String = str(metadata.get("label",operation))
		_craft_dialog.title = "确认"+label
		_craft_dialog.ok_button_text = "确认消耗并"+label
		_craft_dialog.dialog_text = "%s「%s」？\n消耗校准碎片 %d 枚。\n%s" % [label,name_value,int(quote.cost.get("calibration_shard",0)),(str(metadata.get("description",""))+"\n"+str(metadata.get("risk",""))).strip_edges()]
	_craft_dialog.popup_centered(Vector2i(500,240))

func _request_gem_recycle(uid: String, source: Dictionary) -> void:
	if _trade_arena == null or source != model.item(uid).get("payload", {}): return
	var quote: Dictionary = _trade_arena.normal_gem_trade_quote("recycle", uid, model.revision())
	if not bool(quote.get("ok", false)):
		_report(quote)
		_refresh_crafting()
		return
	_pending_craft = {"gem":true,"quote":quote.duplicate(true),"target":uid}
	_craft_dialog.title = "确认回收宝石"
	_craft_dialog.ok_button_text = "确认回收"
	_craft_dialog.dialog_text = "回收「%s」？\n获得校准碎片 %d 枚。\n仅消耗所选这一颗宝石，其他同名宝石不变。" % [str(quote.name), int(quote.materials.calibration_shard)]
	_craft_dialog.popup_centered(Vector2i(500,220))


func _confirm_craft() -> void:
	if not _pending_discard.is_empty():
		var request:=_pending_discard.duplicate(true)
		_pending_discard.clear()
		_report(model.discard_item(request.uid,request.revision,save_path))
		return
	if _pending_craft.is_empty(): return
	var issued: Dictionary = _pending_craft.duplicate(true)
	_pending_craft.clear()
	if bool(issued.get("gem", false)):
		var gem_result: Dictionary = _trade_arena.execute_normal_gem_trade(issued.quote.handle, _selected_uid)
		feedback.emit("宝石已回收" if bool(gem_result.get("ok", false)) else str(gem_result.get("reason", "操作未完成")))
		refresh()
		return
	var result: Dictionary = model.execute_crafting(issued.quote.handle,issued.source)
	if result.ok: feedback.emit("装备工艺已保存")
	else: feedback.emit(str(result.get("reason","操作未完成")))
	refresh()


func _cancel_craft() -> void:
	_pending_discard.clear()
	if not _pending_craft.is_empty():
		if bool(_pending_craft.get("gem", false)):
			if _trade_arena != null and _trade_arena.state == model: _trade_arena.cancel_normal_gem_trade_quote(_pending_craft.quote.handle)
			else: model.cancel_gem_trade_quote(_pending_craft.quote.handle)
		else: model.cancel_crafting_quote(_pending_craft.quote.handle)
	_pending_craft.clear()
	if is_instance_valid(_craft_dialog): _craft_dialog.hide()


func _request_discard()->void:
	if _discard.disabled or _craft_dialog.visible:return
	_pending_discard={"uid":_selected_uid,"revision":model.revision()}
	_craft_dialog.title="确认丢弃物品"
	_craft_dialog.ok_button_text="确认丢弃"
	_craft_dialog.dialog_text="丢弃「%s」？\n仅消耗这一件实例，不影响同名物品。\n不会获得材料；保存成功后无法恢复。"%str(model.item_definition(_selected_uid).name)
	if model.item(_selected_uid).kind == "currency":
		_craft_dialog.dialog_text="丢弃这堆「%s」共 %d 枚？\n保存成功后无法恢复。"%[str(model.item_definition(_selected_uid).name),int(model.item(_selected_uid).payload.quantity)]
	_craft_dialog.popup_centered(Vector2i(500,240))
