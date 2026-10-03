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

func setup(state: RefCounted,path: String = "user://build_save.json") -> void:
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
	_rows.item_hovered.connect(func(uid: String,rect: Rect2): item_hovered.emit(uid,rect))
	_rows.hover_left.connect(func(): hover_left.emit())


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
	_summary.tooltip_text = "每一激活行均可绑定右侧按键。从右侧行囊拖入宝石，右键取回；换键或移动宝石不能重置已产生的冷却。超过容量的行仅停用，配置保留。技能行可滚动查看。预览为单次命中，不是总 DPS。"
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
	_refresh_dirty = true
	if is_visible_in_tree(): refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _refresh_dirty: refresh()


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
