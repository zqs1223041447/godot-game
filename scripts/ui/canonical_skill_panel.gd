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
var _bag: HFlowContainer
var _summary: Label
var _rendered_snapshot: PackedByteArray = PackedByteArray()

class BagGem extends Button:
	var owner_panel: CanonicalSkillPanel
	var uid := ""
	func _get_drag_data(_at: Vector2) -> Variant:
		return {"type":"unified_item","uid":uid,"revision":owner_panel.model.revision(),"grab_offset":Vector2i.ZERO}


func setup(state: RefCounted,path: String = "user://build_save.json") -> void:
	model = state
	save_path = path
	if _rows == null: _build()
	if not model.changed.is_connected(refresh): model.changed.connect(refresh)
	refresh()


func _build() -> void:
	name = "CanonicalSkillPanel"
	custom_minimum_size.y = 410
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size",14)
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
	var title := Label.new()
	title.text = "背包中的宝石 · 拖入主槽或辅助孔 · 右键孔可放回背包"
	title.add_theme_font_size_override("font_size",13)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	var bag_scroll := ScrollContainer.new()
	bag_scroll.name = "SharedBagGemTray"
	bag_scroll.custom_minimum_size.y = 82
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(bag_scroll)
	_bag = HFlowContainer.new()
	_bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(_bag)


func refresh(force: bool = false) -> void:
	if model == null or _rows == null: return
	var snapshot: Dictionary = model.snapshot()
	var render_token: PackedByteArray = var_to_bytes([model.get_instance_id(), snapshot])
	if not force and render_token == _rendered_snapshot: return
	var capacity: int = model.active_group_capacity()
	_summary.text = "已激活 %d 行 · 每行 1 主 + 5 辅 · 滚动查看全部行" % capacity
	_summary.tooltip_text = "每一激活行均可绑定右侧按键。选择已有按键会转交给本行；换键或移动宝石不能重置已产生的冷却。超过容量的行仅停用，物品与配置保留。预览为单次命中，不是总DPS。"
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
		rows.append({"group_id":group_id,"name":name_value,"active":index<capacity,"main":main,"supports":supports,
			"preview":summary,"preview_tooltip":tooltip,"binding_keycode":bindings.get(group_id,0)})
	_rows.set_rows(rows,model.revision())
	for child: Node in _bag.get_children():
		_bag.remove_child(child)
		child.queue_free()
	for uid: String in snapshot.locations:
		if snapshot.locations[uid].kind != "bag" or snapshot.items[uid].kind not in ["skill_gem","support_gem"]: continue
		var definition: Dictionary = model.item_definition(uid)
		var button := BagGem.new()
		button.owner_panel = self
		button.uid = uid
		button.name = "BagGem_" + uid
		button.custom_minimum_size = Vector2(44,44)
		button.expand_icon = true
		button.icon = definition.icon_texture
		button.add_theme_constant_override("icon_max_width",34)
		button.mouse_entered.connect(_hover_bag_gem.bind(uid,button))
		button.mouse_exited.connect(func(): hover_left.emit())
		_bag.add_child(button)
	_rendered_snapshot = render_token


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

func _hover_bag_gem(uid: String,button: Control)->void:
	item_hovered.emit(uid,button.get_global_rect())
