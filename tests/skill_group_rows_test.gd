extends SceneTree

const RowsView = preload("res://scripts/ui/skill_group_rows.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")

var checks: int = 0
var failures: int = 0
var rows_view: Variant
var move_events: Array[Dictionary] = []
var return_events: Array[Dictionary] = []
var hover_events: Array[Dictionary] = []
var hover_left_events: int = 0
var binding_events: Array[Dictionary] = []
var validator_calls: int = 0
var validator_result: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	rows_view = RowsView.new()
	rows_view.name = "SkillGroupRowsTest"
	rows_view.theme = PresentationTheme.create_theme()
	rows_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(rows_view)
	rows_view.move_requested.connect(func(uid: String, destination: Dictionary, revision: int):
		move_events.append({"uid": uid, "destination": destination, "revision": revision}))
	rows_view.return_requested.connect(func(uid: String, revision: int):
		return_events.append({"uid": uid, "revision": revision}))
	rows_view.item_hovered.connect(func(uid: String, anchor: Rect2):
		hover_events.append({"uid": uid, "anchor": anchor}))
	rows_view.hover_left.connect(func():
		hover_left_events += 1)
	rows_view.binding_requested.connect(func(group_id: String, keycode: int, revision: int):
		binding_events.append({"group_id": group_id, "keycode": keycode, "revision": revision}))
	rows_view.set_drop_validator(_validate_drop)

	var input_rows: Array = [_row("group_a", "同名技能", true, "active_a", KEY_1),
		_row("group_b", "同名技能", false, "active_b", KEY_0)]
	rows_view.set_rows(input_rows, 7)
	await process_frame
	await _test_deep_snapshot_and_identity(input_rows)
	_test_drag_contract()
	await _test_drop_destinations_and_revisions()
	_test_right_click_and_hover()
	await _test_binding_options()
	await _test_layout_and_capacity()
	rows_view.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _texture() -> Texture2D:
	return GradientTexture2D.new()


func _gem(uid: String, definition_id: String) -> Dictionary:
	return {"uid": uid, "definition_id": definition_id, "icon": _texture()}


func _row(group_id: String, display_name: String, active: bool, main_uid: String, binding_keycode: int) -> Dictionary:
	var supports: Array = [{}, {}, {}, {}, {}]
	supports[0] = _gem("support_%s_0" % group_id, "support:focus")
	supports[4] = _gem("support_%s_4" % group_id, "support:volley")
	return {
		"group_id": group_id,
		"name": display_name,
		"active": active,
		"main": _gem(main_uid, "skill:bolt"),
		"supports": supports,
		"preview": "一次紧凑预览 · 1.25 秒",
		"preview_tooltip": "完整说明仅在此处的悬停提示显示。".repeat(8),
		"binding_keycode": binding_keycode,
	}


func _test_deep_snapshot_and_identity(input_rows: Array) -> void:
	var main: Variant = _slot(0, "main")
	var support: Variant = _slot(0, "support", 0)
	_expect(main.gem_uid == "active_a" and support.gem_uid == "support_group_a_0", "Nested main/support gem identity is copied into controls")
	var main_icon: Control = main.get_node_or_null("GemIcon") as Control
	var support_icon: Control = support.get_node_or_null("GemIcon") as Control
	_expect(main_icon != null and main_icon.get("gem_role") == "active"
		and support_icon != null and support_icon.get("gem_role") == "support", "Active and support slots use the shared centered GemIcon view")
	_expect(main_icon.mouse_filter == Control.MOUSE_FILTER_IGNORE and support_icon.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"GemIcon children leave their parent slot drag and hover input intact")
	input_rows[0].main.uid = "mutated_after_set_rows"
	input_rows[0].supports[0].definition_id = "support:mutated"
	_expect(main.gem_uid == "active_a" and support.gem_definition_id == "support:focus", "Deep snapshot isolates nested Dictionary and Array mutations")
	_expect(rows_view.find_child("SkillGroupRow_00", true, false) != null and rows_view.find_child("SkillGroupRow_01", true, false) != null,
		"Two rows with the same display name retain separate stable identities")
	_expect(_slot(0, "main").gem_uid != _slot(1, "main").gem_uid, "Same-name rows keep different item UIDs")
	_expect(rows_view.find_child("SkillPreview_00", true, false) == null
		and rows_view.find_child("SkillGroupName_00", true, false).tooltip_text.contains(_row("x", "x", true, "x", KEY_1).preview_tooltip),
		"Long preview detail stays on the named group hover without taking a wide row column")
	_expect(rows_view.find_children("SkillSlotColumn_00_*", "VBoxContainer", true, false).size() == 6,
		"Each skill row labels and shows its main slot plus all five support slots")
	rows_view.set_rows([_row("group_a", "同名技能", true, "active_a", KEY_1), _row("group_b", "同名技能", false, "active_b", KEY_0)], 7)
	await process_frame
	_expect(rows_view.find_child("SkillGroupRows", true, false).get_child_count() == 2, "Repeated set_rows replaces controls instead of duplicating rows")
	var inactive_panel: PanelContainer = rows_view.find_child("SkillGroupRow_01", true, false) as PanelContainer
	var inactive_slot: Variant = _slot(1, "support", 4)
	_expect(inactive_panel.modulate.r < 1.0 and not inactive_slot.disabled, "Inactive row is grey while its configured gem remains interactive")


func _test_drag_contract() -> void:
	var slot: Variant = _slot(0, "main")
	var payload: Variant = slot._get_drag_data(Vector2.ZERO)
	_expect(payload is Dictionary and payload.size() == 4, "Drag payload contains exactly four canonical fields")
	_expect(payload.type == "unified_item" and payload.uid == "active_a" and payload.revision == 7 \
		and payload.grab_offset is Vector2i, "Drag payload carries type, UID, current revision, and logical grab offset")
	_expect(_slot(0, "support", 1)._get_drag_data(Vector2.ZERO) == null, "Empty slots do not become drag sources")
	var extra_key: Dictionary = payload.duplicate()
	extra_key["group_id"] = "group_a"
	_expect(not _slot(0, "support", 4)._can_drop_data(Vector2.ZERO, extra_key), "Drop rejects payloads with extra fields")


func _test_drop_destinations_and_revisions() -> void:
	var payload: Dictionary = {"type": "unified_item", "uid": "bag_gem", "revision": 7, "grab_offset": Vector2i.ZERO}
	validator_calls = 0
	var fifth_support: Variant = _slot(0, "support", 4)
	_expect(fifth_support._can_drop_data(Vector2.ZERO, payload), "Fifth support position is a valid target")
	fifth_support._drop_data(Vector2.ZERO, payload)
	_expect(validator_calls == 2 and move_events.size() == 1, "Drop event emits only after parent validator accepts the request")
	_expect(move_events[0] == {"uid": "bag_gem", "destination": {"kind": "skill_support", "group_id": "group_a", "index": 4}, "revision": 7},
		"Fifth support emits the exact canonical destination")
	var main_target: Variant = _slot(0, "main")
	main_target._drop_data(Vector2.ZERO, payload)
	_expect(move_events.size() == 2 and move_events[1].destination == {"kind": "skill_main", "group_id": "group_a"},
		"Main target emits the exact canonical destination")
	validator_result = false
	main_target._drop_data(Vector2.ZERO, payload)
	_expect(move_events.size() == 2, "Rejected parent validation emits no move request")
	validator_result = true
	var stale_payload: Dictionary = payload.duplicate()
	stale_payload.revision = 6
	_expect(not fifth_support._can_drop_data(Vector2.ZERO, stale_payload), "Stale drag revision cannot target a current row")
	var invalid_index: Dictionary = {"type": "unified_item", "uid": "bag_gem", "revision": 7, "grab_offset": Vector2i.ZERO, "junk": 1}
	_expect(not fifth_support._can_drop_data(Vector2.ZERO, invalid_index), "Malformed drag data is rejected before calling the validator")
	var old_target: Variant = fifth_support
	rows_view.set_rows([_row("group_a", "同名技能", true, "active_a", KEY_1)], 8)
	_expect(not old_target._can_drop_data(Vector2.ZERO, payload), "Old row controls cannot accept drops after a refresh")
	_expect(old_target._get_drag_data(Vector2.ZERO) == null, "Old row controls cannot create stale drags after a refresh")
	rows_view.set_rows([_row("group_a", "同名技能", true, "active_a", KEY_1), _row("group_b", "同名技能", false, "active_b", KEY_0)], 7)
	await process_frame


func _test_right_click_and_hover() -> void:
	var target: Variant = _slot(0, "main")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	target._gui_input(right_click)
	_expect(return_events.size() == 1 and return_events[0] == {"uid": "active_a", "revision": 7}, "Right-click requests return for the exact UID and snapshot revision")
	var empty_slot: Variant = _slot(0, "support", 1)
	empty_slot._gui_input(right_click)
	_expect(return_events.size() == 1, "Right-click on an empty slot emits no return request")
	rows_view._on_slot_entered(target)
	_expect(hover_events.size() == 1 and hover_events[0].uid == "active_a", "Gem hover reports UID")
	var expected_anchor: Rect2 = target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)
	_expect(hover_events[0].anchor == expected_anchor, "Hover anchor uses canvas logical coordinates")
	rows_view._on_slot_exited(target)
	_expect(hover_left_events == 1, "Leaving a hovered gem reports hover_left")
	var before_hover_left: int = hover_events.size()
	rows_view._on_slot_entered(empty_slot)
	_expect(hover_events.size() == before_hover_left, "Empty slots do not claim an item hover")


func _test_binding_options() -> void:
	var active_picker: OptionButton = rows_view.find_child("SkillBinding_00", true, false) as OptionButton
	var inactive_picker: OptionButton = rows_view.find_child("SkillBinding_01", true, false) as OptionButton
	_expect(active_picker.get_item_count() == 32, "Binding menu includes unbound, digits, approved function keys, and letters")
	_expect(active_picker.get_item_id(0) == 0 and active_picker.get_item_text(0) == "未绑定", "Unbound keycode zero has a distinct menu entry")
	var digit_zero_index: int = active_picker.get_item_index(KEY_0)
	_expect(digit_zero_index > 0 and active_picker.get_item_text(digit_zero_index) == "0" and KEY_0 != 0,
		"Digit zero keycode remains distinct from the unbound zero value")
	_expect(active_picker.get_item_index(KEY_F6) == -1 and active_picker.get_item_index(KEY_F7) == -1 and active_picker.get_item_index(KEY_F8) == -1,
		"Function keys F6-F8 are absent")
	_expect(inactive_picker.selected == active_picker.get_item_index(KEY_0), "Displayed selection retains numeric zero binding")
	var key_two_index: int = active_picker.get_item_index(KEY_2)
	active_picker.item_selected.emit(key_two_index)
	active_picker.item_selected.emit(key_two_index)
	active_picker.item_selected.emit(active_picker.get_item_index(KEY_1))
	_expect(binding_events.size() == 1 and binding_events[0] == {"group_id": "group_a", "keycode": KEY_2, "revision": 7},
		"Repeated selection emits one revisioned request; selecting the snapshot binding emits none")
	_expect(active_picker.selected == active_picker.get_item_index(KEY_1), "Picker stays read-only until a new row snapshot arrives")
	var unbound_index: int = inactive_picker.get_item_index(0)
	inactive_picker.item_selected.emit(unbound_index)
	_expect(binding_events.size() == 2 and binding_events[1].keycode == 0 and binding_events[1].group_id == "group_b",
		"Inactive row can request explicit unbinding")
	rows_view.set_rows([_row("group_a", "同名技能", true, "active_a", KEY_2), _row("group_b", "同名技能", false, "active_b", 0)], 8)
	await process_frame
	active_picker = rows_view.find_child("SkillBinding_00", true, false) as OptionButton
	_expect(active_picker.get_item_id(active_picker.selected) == KEY_2,
		"Accepted binding appears only in the newer supplied snapshot (selection=%d, key=%d)" % [active_picker.selected, active_picker.get_item_id(active_picker.selected)])


func _test_layout_and_capacity() -> void:
	rows_view.size = Vector2(480, 460)
	rows_view.font_scale = 1.2
	rows_view.set_rows([_row("group_a", "同名技能", true, "active_a", KEY_1), _row("group_b", "同名技能", false, "active_b", KEY_0)], 9)
	await process_frame
	await process_frame
	var row_controls: Array = rows_view.find_children("SkillGroupRow_*", "PanelContainer", true, false)
	_expect(row_controls.size() == 2, "Rows remain vertically scrollable in a narrow 120-percent-font layout")
	for candidate: Node in row_controls:
		var row_control: Control = candidate as Control
		_expect(row_control.size.x <= rows_view.size.x + 1.0, "Narrow layout keeps each row within the scroll viewport")
	var slot_row: HBoxContainer = rows_view.find_child("SkillGroupSlots_00", true, false) as HBoxContainer
	for child: Node in slot_row.get_children():
		var column: Control = child as Control
		_expect(column.position.x >= -1.0 and column.position.x + column.size.x <= slot_row.size.x + 1.0,
			"Every gem slot column fits within the narrow row: " + str(child.name))
		var slot: Control = column.get_child(1) as Control
		_expect(slot.size.x > 0.0 and slot.size.x <= column.size.x + 1.0,
			"Main and support drop targets retain visible hit areas: " + str(slot.name))
	var title: Label = rows_view.find_child("SkillGroupName_00", true, false) as Label
	var binding: OptionButton = rows_view.find_child("SkillBinding_00", true, false) as OptionButton
	_expect(title.get_theme_font_size("font_size") == roundi(13.0 * 1.2)
		and binding.get_theme_font_size("font_size") == roundi(12.0 * 1.2),
		"Group name and key binding typography follow the requested font scale")
	var too_many: Array = []
	for index: int in range(70):
		too_many.append(_row("group_%02d" % index, "技能 %d" % index, true, "main_%02d" % index, 0))
	rows_view.set_rows(too_many, 10)
	await process_frame
	_expect(rows_view.find_children("SkillGroupRow_*", "PanelContainer", true, false).size() == 64,
		"Rows are capped at 64 while preserving scroll behavior")


func _validate_drop(_uid: String, _destination: Dictionary, _revision: int) -> bool:
	validator_calls += 1
	return validator_result


func _slot(row_index: int, role: String, support_index: int = -1) -> Variant:
	var node_name: String = "MainGem_%02d" % row_index if role == "main" else "SupportGem_%02d_%d" % [row_index, support_index]
	return rows_view.find_child(node_name, true, false)


func _finish() -> void:
	print("Skill group rows: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
