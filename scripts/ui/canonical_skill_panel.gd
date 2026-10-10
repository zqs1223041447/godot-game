class_name CanonicalSkillPanel
extends VBoxContainer
signal feedback(message: String)
signal item_hovered(uid: String,anchor: Rect2)
signal hover_left
const Rows = preload("res://scripts/ui/skill_group_rows.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const ThemeStyle = preload("res://scripts/visuals/visual_theme.gd")
var model: RefCounted
var save_path := "user://build_save.json"
var font_scale := 1.0:
	set(value):
		font_scale = value
		if is_instance_valid(_rows): _rows.font_scale = value
var _rows: Control
var _summary: Label
var _rendered_snapshot: PackedByteArray = PackedByteArray()
var _refresh_dirty: bool = true
var _gem_picker: PopupMenu
var _gem_choices: Dictionary = {}
var _gem_destination: Dictionary = {}
var _gem_revision := -1

func setup(state: RefCounted,path: String = "user://build_save.json") -> void:
	_cancel_gem_picker()
	model = state
	save_path = path
	if _rows == null: _build()
	if not model.changed.is_connected(_on_model_changed): model.changed.connect(_on_model_changed)
	if not visibility_changed.is_connected(_on_visibility_changed): visibility_changed.connect(_on_visibility_changed)
	_refresh_dirty = true
	refresh()


func _build() -> void:
	name = "CanonicalSkillPanel"
	custom_minimum_size.y = 410
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size",11)
	add_child(_summary)
	_rows = Rows.new()
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.font_scale = font_scale
	add_child(_rows)
	_rows.set_drop_validator(func(uid: String,destination: Dictionary,revision_value: int)->bool: return model.can_move_item(uid,destination,revision_value))
	_rows.move_requested.connect(_move)
	_rows.return_requested.connect(_return_gem)
	_rows.binding_requested.connect(_bind)
	_rows.empty_slot_requested.connect(_open_gem_picker)
	_rows.item_hovered.connect(func(uid: String,rect: Rect2): item_hovered.emit(uid,rect))
	_rows.hover_left.connect(func(): hover_left.emit())
	_gem_picker = PopupMenu.new()
	_gem_picker.name = "OwnedGemPicker"
	# Keep the choice alive until id_pressed consumes it; native auto-hide fires first.
	_gem_picker.hide_on_item_selection = false
	_gem_picker.max_size = Vector2i(420,360)
	add_child(_gem_picker)
	_gem_picker.id_pressed.connect(_choose_gem)
	_gem_picker.popup_hide.connect(_cancel_gem_picker)


func refresh(force: bool = false) -> void:
	if model == null or _rows == null: return
	if not force and not _refresh_dirty: return
	var snapshot: Dictionary = model.snapshot()
	var render_token: PackedByteArray = var_to_bytes([model.get_instance_id(), snapshot])
	if not force and render_token == _rendered_snapshot:
		_refresh_dirty = false
		return
	var capacity: int = model.active_group_capacity()
	_summary.text = "%d 行" % capacity
	_summary.tooltip_text = "每一激活行均可绑定右侧按键。点击空孔选择行囊中的可用宝石，或从行囊拖入；右键取回。换键或移动宝石不能重置已产生的冷却。超过容量的行仅停用，配置保留。技能行可滚动查看。预览为单次命中，不是总 DPS。"
	var bindings := {}
	for binding: Dictionary in snapshot.bindings: bindings[binding.group_id] = int(binding.keycode)
	var rows: Array = []
	for index: int in range(snapshot.skill_groups.size()):
		var group_id: String = snapshot.skill_groups[index].id
		var content: Dictionary = model.skill_group(group_id)
		var main: Dictionary = _gem_view(content.main_uid)
		var supports: Array = [{},{},{},{},{}]
		for uid: String in content.support_uids:
			supports[int(snapshot.locations[uid].index)] = _gem_view(uid)
		var cast: Dictionary = model.get_group_cast(group_id)
		var summary := "装入主动宝石"
		var tooltip := ""
		if cast.get("ok",false):
			summary = "%.2f 魔力 · %.2fs" % [cast.mana,cast.cooldown]
			if int(cast.initial_count) > 0: summary += " · %d 发" % int(cast.initial_count)
			elif cast.recipe.has("radius"): summary += " · 半径 %.1f" % float(cast.recipe.radius)
			tooltip = Preview.summary(cast) + "\n" + Preview.details(cast)
		else:
			tooltip = str(cast.get("error",""))
		var name_value := "%d · %s" % [index+1,str(model.item_definition(content.main_uid).get("short_name","空行"))]
		if not content.main_uid.is_empty(): name_value += "  ·  %d 级" % int(model.item(content.main_uid).payload.level)
		rows.append({"group_id":group_id,"name":name_value,"active":index<capacity,"main":main,"supports":supports,
			"preview":summary,"preview_tooltip":tooltip,"binding_keycode":bindings.get(group_id,0)})
	_rows.set_rows(rows,model.revision())
	_rendered_snapshot = render_token
	_refresh_dirty = false


func _on_model_changed() -> void:
	_cancel_gem_picker()
	_refresh_dirty = true
	if is_visible_in_tree(): refresh()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): _cancel_gem_picker()
	if is_visible_in_tree() and _refresh_dirty: refresh()


func _open_gem_picker(destination: Dictionary, revision_value: int, anchor: Rect2) -> void:
	_cancel_gem_picker()
	if model == null or not is_visible_in_tree() or revision_value != model.revision(): return
	if destination.get("kind", "") not in ["skill_main", "skill_support"]: return
	var snapshot: Dictionary = model.snapshot()
	# This convenience entry fills an empty slot; replacement remains explicit drag/drop.
	if destination in snapshot.locations.values(): return
	var wanted := "skill_gem" if destination.kind == "skill_main" else "support_gem"
	var needs_main: bool = wanted == "support_gem" and str(model.skill_group(str(destination.get("group_id",""))).get("main_uid","")).is_empty()
	_gem_picker.clear()
	_gem_picker.add_item("行囊 · 可装入的宝石")
	_gem_picker.set_item_disabled(0, true)
	for uid: String in snapshot.locations:
		var location: Dictionary = snapshot.locations[uid]
		if needs_main or location.kind != "bag" or snapshot.items[uid].kind != wanted: continue
		if not model.can_move_item(uid, destination, revision_value): continue
		var definition: Dictionary = model.item_definition(uid)
		var id := _gem_picker.item_count
		_gem_picker.add_item("%s · 行囊%d" % [str(definition.name),int(location.page)+1], id)
		_gem_picker.set_item_tooltip(id, "%s\n行囊第%d页 · 第%d行第%d列" % [str(definition.get("description","")),int(location.page)+1,int(location.y)+1,int(location.x)+1])
		_gem_choices[id] = uid
	if _gem_choices.is_empty():
		_gem_picker.add_item("请先装入主动宝石" if needs_main else "行囊中没有可装入此孔的宝石")
		_gem_picker.set_item_disabled(1, true)
	_gem_destination = destination.duplicate(true)
	_gem_revision = revision_value
	_gem_picker.size = Vector2i.ZERO
	_gem_picker.position = Vector2i(anchor.position + Vector2(0,anchor.size.y))
	if not _gem_picker.is_embedded(): _gem_picker.position += get_window().position
	_gem_picker.popup()


func _choose_gem(id: int) -> void:
	if not _gem_choices.has(id) or _gem_destination.is_empty(): return
	var uid: String = _gem_choices[id]
	var destination := _gem_destination.duplicate(true)
	var revision_value := _gem_revision
	_cancel_gem_picker()
	_move(uid, destination, revision_value)


func _cancel_gem_picker() -> void:
	_gem_choices.clear()
	_gem_destination.clear()
	_gem_revision = -1
	if is_instance_valid(_gem_picker): _gem_picker.hide()


func _gem_view(uid: String) -> Dictionary:
	if uid.is_empty(): return {}
	var item: Dictionary = model.item(uid)
	var definition: Dictionary = model.item_definition(uid)
	return {"uid":uid,"definition_id":item.definition_id,"icon":definition.icon_texture}
func _move(uid: String,destination: Dictionary,revision_value: int)->void:
	_report(model.move_item(uid,destination,revision_value,save_path))
func _return_gem(uid: String,revision_value: int)->void:
	var destination: Dictionary = model.first_bag_position(uid)
	if destination.is_empty(): feedback.emit("背包空间不足，宝石保持原位置")
	else: _move(uid,destination,revision_value)
func _bind(group_id: String,keycode: int,revision_value: int)->void:
	_report(model.unbind_group(group_id,revision_value,save_path) if keycode == 0 else model.bind_group(group_id,keycode,revision_value,save_path))
func _report(result: Dictionary)->void:
	if not result.get("ok",false) and not str(result.get("reason","")).is_empty(): feedback.emit(result.reason)
	# Rejected requests must restore control choices without retaining a request latch.
	refresh(true)
