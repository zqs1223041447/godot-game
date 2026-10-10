class_name SkillGroupRows
extends ScrollContainer
## Read-only projection of canonical skill groups. The owning controller supplies
## snapshots and remains responsible for every state change and validation.

signal move_requested(uid: String, destination: Dictionary, revision: int)
signal return_requested(uid: String, revision: int)
signal item_hovered(uid: String, anchor: Rect2)
signal hover_left
signal binding_requested(group_id: String, keycode: int, revision: int)

const TooltipFactory = preload("res://scripts/ui/crafting_controls.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const GemIconView = preload("res://scripts/ui/gem_icon.gd")
const DockStyle = preload("res://scripts/ui/dock_visual_style.gd")
const MAX_ROWS: int = 64
const VISIBLE_ROWS_MIN: int = 10
const BASE_ROW_HEIGHT: float = 70.0
const ROW_SEPARATION: float = 5.0
const BASE_SLOT_SIZE: float = 44.0
const ROW_FIELDS: Array[String] = [
	"group_id", "name", "active", "main", "supports", "preview", "preview_tooltip", "binding_keycode"
]
const GEM_FIELDS: Array[String] = ["uid", "definition_id", "icon"]
const BINDING_CODES: Array[int] = [
	0,
	KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_E, KEY_F, KEY_G, KEY_H, KEY_J, KEY_L, KEY_Z, KEY_X, KEY_V, KEY_N, KEY_M,
]

class PreviewLabel extends Label:
	func _make_custom_tooltip(text: String) -> Object:
		return TooltipFactory.wrapped_tooltip(self,text)

class GemSlot extends Button:
	var owner_rows: SkillGroupRows
	var group_id: String = ""
	var role: String = ""
	var support_index: int = -1
	var gem_uid: String = ""
	var gem_definition_id: String = ""
	var generation: int = -1
	func _draw() -> void:
		if role != "support": return
		var center := size * 0.5
		var radius := minf(size.x,size.y)*0.5-2.0
		draw_circle(center+Vector2(0,1),radius+1.0,Color("ab9770"))
		draw_circle(center,radius,Color("796348"))
		draw_circle(center,radius-2.5,Color("514331"))
		draw_arc(center,radius-0.5,PI,TAU,48,Color("d8bb7d"),1.0,true)
		draw_arc(center,radius-3.0,0,PI,48,Color("a1875c"),0.8,true)
		if is_hovered():
			draw_arc(center,radius+1,0,TAU,48,Color("cfa661"),1.5,true)


	func _get_drag_data(_at: Vector2) -> Variant:
		if not is_instance_valid(owner_rows) or gem_uid.is_empty() or not owner_rows._is_current_slot(self):
			return null
		# This exact four-field payload is shared with the canonical inventory view.
		return {
			"type": "unified_item",
			"uid": gem_uid,
			"revision": owner_rows._revision,
			"grab_offset": Vector2i.ZERO,
		}


	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return is_instance_valid(owner_rows) and owner_rows._can_drop_to(data, _destination(), generation)


	func _drop_data(_at: Vector2, data: Variant) -> void:
		if is_instance_valid(owner_rows):
			owner_rows._accept_drop(data, _destination(), generation)


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not gem_uid.is_empty() and is_instance_valid(owner_rows):
				owner_rows._return_from_slot(self)
			accept_event()


	func _destination() -> Dictionary:
		if role == "main":
			return {"kind": "skill_main", "group_id": group_id}
		return {"kind": "skill_support", "group_id": group_id, "index": support_index}


var font_scale: float = 1.0:
	set(value):
		font_scale = clampf(value, 0.8, 1.6)
		_update_density()

var _revision: int = 0
var _generation: int = 0
var _rows: Array[Dictionary] = []
var _rows_by_id: Dictionary = {}
var _drop_validator: Callable
var _rows_container: VBoxContainer
var _row_controls: Array[PanelContainer] = []
var _binding_controls: Dictionary = {}
var _binding_requests: Dictionary = {}


func _ready() -> void:
	_ensure_interface()
	_update_density()
	if not resized.is_connected(_update_density):
		resized.connect(_update_density)
	_render_rows()


## Replace the displayed snapshot. Nested Dictionaries and Arrays are copied so
## caller mutations cannot alter what an already displayed row represents.
func set_rows(rows: Array, revision: int) -> void:
	_revision = revision
	_generation += 1
	_rows.clear()
	_rows_by_id.clear()
	_binding_controls.clear()
	_binding_requests.clear()
	for value: Variant in rows:
		if _rows.size() >= MAX_ROWS:
			break
		if not _valid_row(value):
			continue
		var row: Dictionary = value.duplicate(true)
		if _rows_by_id.has(row.group_id):
			continue
		_rows.append(row)
		_rows_by_id[row.group_id] = row
	_ensure_interface()
	_render_rows()
	_update_density()


## The parent owns all location rules, including compatibility and capacity.
func set_drop_validator(validator: Callable) -> void:
	_drop_validator = validator


func _ensure_interface() -> void:
	if _rows_container != null:
		return
	clip_contents = true
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	custom_minimum_size.y = 220.0 * font_scale
	_rows_container = VBoxContainer.new()
	_rows_container.name = "SkillGroupRows"
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", int(ROW_SEPARATION))
	add_child(_rows_container)


func _render_rows() -> void:
	if _rows_container == null:
		return
	for child: Node in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()
	_row_controls.clear()
	_binding_controls.clear()
	for index: int in range(_rows.size()):
		var row: Dictionary = _rows[index]
		var panel: PanelContainer = _build_row(row, index)
		_rows_container.add_child(panel)
		_row_controls.append(panel)
	_update_density()


func _build_row(row: Dictionary, row_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SkillGroupRow_%02d" % row_index
	panel.set_meta("group_id", row.group_id)
	panel.custom_minimum_size.y = BASE_ROW_HEIGHT * font_scale
	panel.add_theme_stylebox_override("panel", DockStyle.surface(
		DockStyle.PAPER if row_index % 2 == 0 else Color("e9dec6"),8.0))
	if not bool(row.active):
		# Keep controls enabled so users can still reorganize preserved inactive rows.
		panel.modulate = Color(0.70, 0.70, 0.70, 1.0)
		panel.tooltip_text = "此技能行未激活；配置与宝石位置已保留，宝石仍可整理。"

	var contents := VBoxContainer.new()
	contents.name = "SkillGroupContents_%02d" % row_index
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 3)
	panel.add_child(contents)

	var header := HBoxContainer.new()
	header.name = "SkillGroupHeader_%02d" % row_index
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	contents.add_child(header)

	var title := PreviewLabel.new()
	title.name = "SkillGroupName_%02d" % row_index
	title.text = str(row.name) + (" · 未激活" if not bool(row.active) else "")
	title.tooltip_text = str(row.name)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", roundi(11.0 * font_scale))
	title.add_theme_font_override("font",DockStyle.bold_font(load("res://assets/fonts/arena_sans.otf")))
	title.add_theme_color_override("font_color", PresentationTheme.TEXT if row.active else PresentationTheme.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Keep the full compiled preview available to assistive/hover inspection;
	# the long explanation no longer consumes a wide column beside every row.
	title.tooltip_text = str(row.name) + "\n" + str(row.preview) + "\n" + str(row.preview_tooltip)
	header.add_child(title)
	var binding := _make_binding_picker(row, row_index)
	binding.name = "SkillBinding_%02d" % row_index
	header.add_child(binding)
	_binding_controls[row.group_id] = binding

	var slot_row := HBoxContainer.new()
	slot_row.name = "SkillGroupSlots_%02d" % row_index
	slot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_theme_constant_override("separation", 9)
	contents.add_child(slot_row)
	_add_labeled_slot(slot_row, row, row_index, "main", -1, row.main, "主")
	for support_index: int in range(5):
		var supports: Array = row.supports
		_add_labeled_slot(slot_row, row, row_index, "support", support_index, supports[support_index], "辅%d" % (support_index + 1))
	return panel


func _add_labeled_slot(parent: HBoxContainer, row: Dictionary, row_index: int, role: String,
		support_index: int, gem: Dictionary, caption: String) -> void:
	var column := VBoxContainer.new()
	column.name = "SkillSlotColumn_%02d_%s" % [row_index, "main" if role == "main" else str(support_index + 1)]
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 1)
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", roundi(11.0 * font_scale))
	label.add_theme_color_override("font_color", PresentationTheme.MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.hide() # Slot roles are shown by large primary art and five round sockets.
	column.add_child(label)
	var slot := _make_slot(row, row_index, role, support_index, gem)
	slot.name = "MainGem_%02d" % row_index if role == "main" else "SupportGem_%02d_%d" % [row_index, support_index]
	column.add_child(slot)


func _make_slot(row: Dictionary, row_index: int, slot_role: String, support_index: int,
		gem: Dictionary) -> GemSlot:
	var slot := GemSlot.new()
	slot.owner_rows = self
	slot.group_id = str(row.group_id)
	slot.role = slot_role
	slot.support_index = support_index
	slot.generation = _generation
	slot.gem_uid = str(gem.get("uid", ""))
	slot.gem_definition_id = str(gem.get("definition_id", ""))
	slot.text = ""
	slot.tooltip_text = _slot_tooltip(slot_role, support_index, gem)
	slot.alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.focus_mode = Control.FOCUS_NONE
	slot.add_theme_font_size_override("font_size", roundi(11.0 * font_scale))
	slot.add_theme_stylebox_override("normal", DockStyle.inset_slot())
	slot.add_theme_stylebox_override("hover", DockStyle.inset_slot(true))
	slot.add_theme_stylebox_override("pressed", DockStyle.inset_slot(true))
	slot.add_theme_stylebox_override("focus", PresentationTheme.panel(Color(0, 0, 0, 0), PresentationTheme.GOLD, 4, 1, 0))
	if slot_role == "support":
		for state_name: String in ["normal","hover","pressed","focus"]:
			slot.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
	if not gem.is_empty():
		var gem_icon: Variant = GemIconView.new()
		gem_icon.name = "GemIcon"
		gem_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		gem_icon.offset_left = 0.0
		gem_icon.offset_top = 0.0
		gem_icon.offset_right = 0.0
		gem_icon.offset_bottom = 0.0
		gem_icon.custom_minimum_size = Vector2.ZERO
		gem_icon.circular = slot_role == "support"
		gem_icon.set_gem_icon(gem.get("icon") as Texture2D, str(gem.definition_id),
			"active" if slot_role == "main" else "support")
		slot.add_child(gem_icon)
	slot.mouse_entered.connect(_on_slot_entered.bind(slot))
	slot.mouse_exited.connect(_on_slot_exited.bind(slot))
	return slot


func _make_binding_picker(row: Dictionary, row_index: int) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = "SkillBinding_%02d" % row_index
	picker.custom_minimum_size = Vector2(48.0, 20.0)
	picker.add_theme_font_size_override("font_size", roundi(10.0 * font_scale))
	DockStyle.style_action(picker,roundi(10.0*font_scale))
	for index: int in range(BINDING_CODES.size()):
		picker.add_item("未绑定" if BINDING_CODES[index] == 0 else OS.get_keycode_string(BINDING_CODES[index]))
		picker.set_item_id(index, BINDING_CODES[index])
	picker.select(_binding_index(int(row.binding_keycode)))
	picker.item_selected.connect(_on_binding_selected.bind(str(row.group_id), _generation))
	return picker


func _on_binding_selected(index: int, group_id: String, generation: int) -> void:
	if generation != _generation or not _rows_by_id.has(group_id) or index < 0 or index >= BINDING_CODES.size():
		return
	var row: Dictionary = _rows_by_id[group_id]
	var keycode: int = BINDING_CODES[index] if index >= 0 and index < BINDING_CODES.size() else 0
	var picker: OptionButton = _binding_controls.get(group_id) as OptionButton
	if picker != null:
		# A selection is a request only. Keep the displayed snapshot until the
		# parent supplies a newer revision reflecting an accepted binding change.
		picker.select(_binding_index(int(row.binding_keycode)))
	if keycode == int(row.binding_keycode):
		return
	var previous_request: Dictionary = _binding_requests.get(group_id, {})
	if previous_request.get("revision", -1) == _revision and previous_request.get("keycode", -1) == keycode:
		return
	_binding_requests[group_id] = {"revision": _revision, "keycode": keycode}
	binding_requested.emit(group_id, keycode, _revision)


func _on_slot_entered(slot: GemSlot) -> void:
	if slot.gem_uid.is_empty() or not _is_current_slot(slot):
		return
	# With-canvas transform yields canvas logical coordinates, not physical pixels.
	var anchor: Rect2 = slot.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, slot.size)
	item_hovered.emit(slot.gem_uid, anchor)


func _on_slot_exited(slot: GemSlot) -> void:
	if _is_current_slot(slot):
		hover_left.emit()


func _return_from_slot(slot: GemSlot) -> void:
	if _is_current_slot(slot) and not slot.gem_uid.is_empty():
		return_requested.emit(slot.gem_uid, _revision)


func _is_current_slot(slot: GemSlot) -> bool:
	return slot.generation == _generation and _rows_by_id.has(slot.group_id)


func _can_drop_to(data: Variant, destination: Dictionary, generation: int) -> bool:
	if generation != _generation or not _valid_destination(destination):
		return false
	var payload: Dictionary = _validated_payload(data)
	if payload.is_empty() or int(payload.revision) != _revision or not _drop_validator.is_valid():
		return false
	var accepted: bool = bool(_drop_validator.call(str(payload.uid), destination.duplicate(true), int(payload.revision)))
	return accepted and generation == _generation and int(payload.revision) == _revision and _valid_destination(destination)


func _accept_drop(data: Variant, destination: Dictionary, generation: int) -> void:
	if not _can_drop_to(data, destination, generation):
		return
	var payload: Dictionary = _validated_payload(data)
	move_requested.emit(str(payload.uid), destination.duplicate(true), int(payload.revision))


func _valid_destination(destination: Dictionary) -> bool:
	if not destination.has("group_id") or not destination.group_id is String or not _rows_by_id.has(destination.group_id):
		return false
	if destination.get("kind", "") == "skill_main":
		return _exact_keys(destination, ["kind", "group_id"])
	if destination.get("kind", "") == "skill_support":
		return _exact_keys(destination, ["kind", "group_id", "index"]) and destination.index is int \
			and destination.index >= 0 and destination.index < 5
	return false


func _validated_payload(data: Variant) -> Dictionary:
	if not data is Dictionary or not _exact_keys(data, ["type", "uid", "revision", "grab_offset"]):
		return {}
	if data.type != "unified_item" or not data.uid is String or data.uid.is_empty() \
			or not data.revision is int or not data.grab_offset is Vector2i:
		return {}
	return data


func _update_density() -> void:
	if _rows_container == null:
		return
	custom_minimum_size.y = 220.0 * font_scale
	var available_width: float = maxf(size.x - 24.0, 1.0)
	var binding_width: float = minf(48.0 * font_scale, available_width * 0.2)
	var slot_width: float = minf(BASE_SLOT_SIZE * font_scale, maxf(24.0, (available_width - 45.0) / 5.4))
	var row_height: float = 18.0 * font_scale + slot_width + 9.0
	for index: int in range(_row_controls.size()):
		var panel: PanelContainer = _row_controls[index]
		panel.custom_minimum_size.y = maxf(BASE_ROW_HEIGHT * font_scale, row_height)
		var contents: VBoxContainer = panel.get_child(0) as VBoxContainer
		if contents == null or contents.get_child_count() != 2:
			continue
		var header: HBoxContainer = contents.get_child(0) as HBoxContainer
		var title: Label = header.get_child(0) as Label
		title.custom_minimum_size.x = 0.0
		var binding: OptionButton = header.get_child(1) as OptionButton
		binding.custom_minimum_size.x = binding_width
		var slots: HBoxContainer = contents.get_child(1) as HBoxContainer
		for column_index: int in range(slots.get_child_count()):
			var column: VBoxContainer = slots.get_child(column_index) as VBoxContainer
			var side: float = slot_width if column_index == 0 else slot_width*0.88
			column.custom_minimum_size.x = side
			var slot: GemSlot = column.get_child(1) as GemSlot
			slot.custom_minimum_size = Vector2(side, side)
			var caption: Label = column.get_child(0) as Label
			caption.add_theme_font_size_override("font_size", roundi(11.0 * font_scale))


func _binding_index(keycode: int) -> int:
	return BINDING_CODES.find(keycode) if BINDING_CODES.has(keycode) else 0


func _slot_tooltip(slot_role: String, support_index: int, gem: Dictionary) -> String:
	var slot_label: String = "主动宝石" if slot_role == "main" else "辅助宝石 %d" % (support_index + 1)
	if gem.is_empty():
		return slot_label + " · 空槽"
	return "" # The shared item hover card owns non-empty gem details.


func _valid_row(value: Variant) -> bool:
	if not value is Dictionary or not _exact_keys(value, ROW_FIELDS):
		return false
	if not value.group_id is String or value.group_id.is_empty() or not value.name is String \
			or not value.active is bool or not value.main is Dictionary or not value.supports is Array \
			or value.supports.size() != 5 or not value.preview is String or not value.preview_tooltip is String \
			or not value.binding_keycode is int or not BINDING_CODES.has(value.binding_keycode):
		return false
	if not _valid_gem(value.main):
		return false
	for gem: Variant in value.supports:
		if not _valid_gem(gem):
			return false
	return true


func _valid_gem(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	return _exact_keys(value, GEM_FIELDS) and value.uid is String and not value.uid.is_empty() \
		and value.definition_id is String and not value.definition_id.is_empty() and value.icon is Texture2D


func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true
