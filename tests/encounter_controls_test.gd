extends SceneTree
## Isolated standalone UI acceptance; never installs the component in main.tscn.
const Controls = preload("res://scripts/ui/encounter_controls.gd")
const Catalog = preload("res://scripts/encounters/encounter_catalog.gd")
const Compiler = preload("res://scripts/encounters/encounter_compiler.gd")
const Design = preload("res://scripts/visuals/visual_theme.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const Model = preload("res://scripts/build_state.gd")

var checks: int = 0
var failures: int = 0
var panel: Control
var host: ScrollContainer
var events: Array = []
var mutate_event: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(70.0).timeout.connect(func() -> void:
		push_error("Encounter controls timed out before completing acceptance")
		quit(2))
	root.size = Vector2i(720, 720)
	root.content_scale_size = Vector2i(720, 720)
	var state := Model.new()
	_expect(state.save_build() == OK, "Real save fixture created only in isolated XDG root")
	var state_before: Dictionary = state._snapshot().duplicate(true)
	var save_before: PackedByteArray = FileAccess.get_file_as_bytes("user://build_save.json")
	_expect(not save_before.is_empty(), "Save guard observes actual existing save bytes")
	var catalog_before: Dictionary = Catalog.metadata()
	seed(93715)
	var next_random: int = randi()
	seed(93715)
	panel = Controls.new()
	var ids: Array[String] = ["enemy_max_health_120","enemy_move_speed_110"]
	_expect(panel.set_context([ids[0]]), "Context can be supplied before embedding")
	host = ScrollContainer.new()
	host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	host.follow_focus = true
	host.position = Vector2(24, 24)
	host.size = Vector2(280, 650)
	root.add_child(host)
	host.add_child(panel)
	panel.encounter_requested.connect(_capture)
	await _settle()
	_expect(_label("EncounterIntegration").text.contains("未集成"), "Visible standalone status never claims playable integration")
	_expect(panel.theme.default_font == Design.create_theme().default_font, "Existing presentation font is reused")
	_expect(panel.get_theme_stylebox("panel").get_script() == Design.Frame, "Existing paper material is reused")
	_test_selections(ids)
	_test_all_previews()
	_test_copies(ids)
	_test_invalid(ids)
	_test_disabled(ids)
	_test_metadata(ids)
	await _test_layout(ids)
	await _test_real_clicks(ids)
	await _test_keyboard(ids)
	await _test_context_updates(ids)
	_expect(state._snapshot() == state_before, "Selection and confirmation leave build/reward state equal")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json") == save_before, "Selection and confirmation leave save bytes equal")
	_expect(Catalog.metadata() == catalog_before, "UI never changes the definition source")
	_expect(randi() == next_random, "Construction, selection and all confirmations preserve global RNG")
	host.queue_free()
	await process_frame
	print("Encounter controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)


func _label(stable_name: String) -> Label:
	return panel.find_child(stable_name, true, false) as Label


func _option(id: String) -> CheckBox:
	return panel.find_child("EncounterOption_" + id, true, false) as CheckBox


func _confirm() -> Button:
	return panel.find_child("EncounterConfirm", true, false) as Button


func _capture(ids_copy: Array[String]) -> void:
	events.append(ids_copy)
	if mutate_event:
		ids_copy.clear()
		ids_copy.append("receiver_edit")


func _test_selections(ids: Array[String]) -> void:
	for selection: Array in [[], [ids[0]], [ids[1]], ids, [ids[1], ids[0]]]:
		var before: Array = selection.duplicate(true)
		_expect(panel.set_context(selection), "Empty, either single and both orders are valid")
		var profile: Dictionary = Compiler.compile(selection).profile
		_expect(selection == before and panel.get_selected_ids() == profile.modifier_ids, "Context is detached and canonically ordered")
		for id: String in ids:
			_expect(_option(id).button_pressed == selection.has(id), "Checkbox reflects actual selected identity: " + id)
		var preview: String = _label("EncounterPreview").text
		_expect_preview(selection)
		_expect(preview.contains("普通遭遇") == selection.is_empty(), "Only empty selection is labelled ordinary")
		var count: int = events.size()
		_confirm().pressed.emit()
		_confirm().pressed.emit()
		_expect(events.size() == count + 2, "Every confirmation emits exactly once without self-locking")
		_expect(events[count] == profile.modifier_ids and events[count + 1] == profile.modifier_ids, "Both requests contain exact current IDs")
		_expect(panel.get_selected_ids() == profile.modifier_ids, "Confirming only emits; it does not consume selection")
	panel.set_context([])
	for id: String in ids:
		_option(id).button_pressed = true
	_expect(panel.get_selected_ids() == ids, "Checking both options compiles the bounded draft")
	for id: String in ids:
		_option(id).button_pressed = false
	_expect(panel.get_selected_ids().is_empty(), "Unchecking both restores ordinary draft")
	_expect(not _confirm().disabled, "Ordinary request remains confirmable")


func _expect_preview(selection: Array) -> void:
	var compiled: Dictionary = Compiler.compile(selection)
	_expect(compiled.ok, "Preview fixture is a valid catalog selection")
	if not compiled.ok:
		return
	var canonical: Array = compiled.profile.modifier_ids
	var expected: String = "普通遭遇（无挑战）" if canonical.is_empty() else \
		"已选择 %d / %d 条" % [canonical.size(), Catalog.MAX_MODIFIERS]
	# Independently assemble the public contract; never call the UI summary helper.
	for definition: Dictionary in compiled.profile.definitions:
		expected += "\n" + str(definition.description)
	_expect(_label("EncounterPreview").text == expected,
		"Exact heading and ordered canonical descriptions: " + str(selection))


func _test_all_previews() -> void:
	var all_ids: Array[String] = Catalog.get_ids()
	_expect(all_ids.size() == 6, "Current encounter catalog has six independently covered options")
	panel.set_context([])
	_expect_preview([])
	for first: String in all_ids:
		panel.set_context([first])
		_expect_preview([first])
		for second: String in all_ids:
			if first == second:
				continue
			panel.set_context([first, second])
			_expect_preview([first, second])
			var canonical: Array[String] = [first, second]
			canonical.sort()
			_expect(panel.get_selected_ids() == canonical, "Every pair input order resolves canonical IDs")
	# These units cannot be reconstructed from multiplier-only aggregate fields.
	panel.set_context(["enemy_shield_from_health_20", "enemy_armour_80"])
	var preview: String = _label("EncounterPreview").text
	_expect(preview.contains("怪物护甲 +80") and preview.contains("未附本轮普通词缀前最大生命的20%"),
		"Armour/shield preview retains flat armour and unmodified-health shield units")
	panel.set_context(["enemy_shield_from_health_20", "enemy_max_health_120"])
	preview = _label("EncounterPreview").text
	_expect(preview.contains("怪物最大生命 ×1.20") and preview.contains("与强健顺序无关"),
		"Health/shield preview retains the independent shield base rule")


func _test_copies(ids: Array[String]) -> void:
	var supplied: Array = [ids[0]]
	panel.set_context(supplied)
	supplied[0] = "caller_edit"
	supplied.append(ids[1])
	_expect(panel.get_selected_ids() == [ids[0]], "Caller edits cannot change the accepted context")
	var returned: Array = panel.get_selected_ids()
	returned.clear()
	_expect(panel.get_selected_ids() == [ids[0]], "Getter returns a fresh independent copy")
	_confirm().pressed.emit()
	var retained: Array = events.back()
	retained.clear()
	retained.append("retained_edit")
	_confirm().pressed.emit()
	_expect(events.back() == [ids[0]] and retained == ["retained_edit"], "Later clicks cannot reuse or change an earlier payload")
	mutate_event = true
	_confirm().pressed.emit()
	mutate_event = false
	_expect(panel.get_selected_ids() == [ids[0]], "Immediate receiver edits cannot mutate the draft")
	_confirm().pressed.emit()
	_expect(events.back() == [ids[0]], "Click after a mutating receiver still emits a fresh valid copy")
	var frozen: Array = [ids[1], ids[0]]
	frozen.make_read_only()
	_expect(panel.set_context(frozen) and panel.get_selected_ids() == ids, "Read-only caller arrays are accepted without modification")


func _test_invalid(ids: Array[String]) -> void:
	for selection: Variant in [[ids[0], ids[0]], [ids[1], ids[1]], ["unknown"],
		[ids[0], "unknown"], [ids[0], ids[1], ids[0]], null, {}, ids[0],
		PackedStringArray(ids), [1], [true], [[]], [""]]:
		panel.set_context([ids[0]])
		var rejected: Dictionary = Compiler.compile(selection)
		var count: int = events.size()
		_expect(not panel.set_context(selection), "Invalid context is rejected as one transaction")
		_expect(_label("EncounterStatus").visible and _label("EncounterStatus").text == rejected.error, "Exact compiler rejection stays visible")
		_expect(_confirm().disabled and panel.get_selected_ids().is_empty(), "Invalid input cannot leave an actionable partial draft")
		_expect(not _label("EncounterPreview").text.contains("普通遭遇"), "Invalid input cannot masquerade as an ordinary request")
		for id: String in ids:
			_expect(_option(id).disabled, "Invalid context blocks option callbacks")
			_option(id).set_pressed_no_signal(true)
			_option(id).toggled.emit(true)
			_expect(not _option(id).button_pressed, "Forced toggle is restored after rejection")
		_confirm().pressed.emit()
		_expect(events.size() == count, "Forced invalid confirmation emits nothing")
	_expect(panel.set_context(ids) and not _confirm().disabled, "A later valid context explicitly recovers the control")


func _test_disabled(ids: Array[String]) -> void:
	var reason: String = "遭遇进行中，结束后才能确认新的挑战选择。"
	for selection: Array in [[], [ids[0]], ids]:
		var count: int = events.size()
		_expect(panel.set_context(selection, reason), "Owner lock is separate from valid selection")
		_expect(_confirm().disabled and _label("EncounterStatus").text == reason, "Owner reason is displayed verbatim")
		for id: String in ids:
			_expect(_option(id).disabled and _option(id).tooltip_text == reason, "Owner lock disables every checkbox")
			_option(id).set_pressed_no_signal(not selection.has(id))
			_option(id).toggled.emit(not selection.has(id))
			_expect(_option(id).button_pressed == selection.has(id), "Forced locked toggle restores the accepted draft")
		_confirm().pressed.emit()
		_expect(events.size() == count and panel.get_selected_ids() == selection, "Disabled actions cannot emit or change IDs")
	panel.set_context(["unknown"], reason)
	_expect(_label("EncounterStatus").text.contains(reason) and _label("EncounterStatus").text.contains(Compiler.compile(["unknown"]).error), "Owner lock and invalid selection both remain visible")
	panel.set_context(ids)
	_expect(not _confirm().disabled and not _label("EncounterStatus").visible, "Clearing the owner reason restores normal controls")
	var count: int = events.size()
	panel.encounter_requested.connect(func(_ids_copy: Array[String]) -> void:
		panel.set_context(ids, "上层已经开始遭遇"), CONNECT_ONE_SHOT)
	_confirm().pressed.emit()
	_confirm().pressed.emit()
	_expect(events.size() == count + 1 and _confirm().disabled, "A synchronous owner lock immediately blocks the next click")
	panel.set_context(ids)


func _test_metadata(ids: Array[String]) -> void:
	var metadata: Dictionary = Catalog.metadata()
	_expect(panel.find_children("EncounterOption_*", "CheckBox", true, false).size() == metadata.definitions.size(), "Exactly the actual catalog options are generated")
	for definition: Dictionary in metadata.definitions:
		var profile: Dictionary = Compiler.compile([definition.id]).profile
		var expected: String = str(profile.definitions[0].description)
		_expect(_option(str(definition.id)).text == definition.name, "Option name uses catalog metadata")
		_expect(_label("EncounterDescription_" + str(definition.id)).text == expected, "Description and risk use the compiler's same-source snapshot")
	_expect(_label("EncounterRisk").text.contains("尚未评估"), "Parameter-only risk never implies a balanced difficulty score")
	metadata.definitions[0].multiplier = 900.0
	metadata.definitions[0].name = "external_edit"
	panel.set_context(ids)
	_expect(not _label("EncounterPreview").text.contains("900") and _option(ids[0]).text != "external_edit", "Detached metadata edits cannot corrupt presentation")


func _test_layout(ids: Array[String]) -> void:
	_expect(root.get_visible_rect().size == Vector2(720, 720), "Fixture uses verified logical viewport dimensions")
	for width: int in [220, 280]:
		for scale: float in Settings.FONT_SCALES:
			host.size = Vector2(width, 480)
			panel.font_scale = scale
			for selection: Array in [[], [ids[0]], ids,
				["enemy_armour_80", "enemy_shield_from_health_20"],
				["enemy_max_health_120", "enemy_shield_from_health_20"]]:
				panel.set_context(selection)
				await _settle()
				_expect(panel.size.x <= width + 1.0, "Component fits %d logical px / %.0f%% font" % [width, scale * 100.0])
				_check_bounds(panel)
				_expect_preview(selection)
				_expect(_label("EncounterPreview").get_theme_font_size("font_size") == roundi(14 * scale), "Font scale survives selection refresh")
				await _reveal_all()
			panel.set_context(ids, "遭遇进行中，当前无法改变选择。请在本次遭遇结束后再次确认。")
			await _settle()
			_check_bounds(panel)
			_expect(panel.size.y > host.size.y and host.get_v_scroll_bar().visible,
				"Six-option wrapped content overflows into a real vertical scrollbar")
			await _reveal_all()
			panel.set_context(["unknown"])
			await _settle()
			_check_bounds(panel)
			await _reveal_all()
	panel.font_scale = 1.0
	host.size = Vector2(280, 480)
	panel.set_context(ids)
	await _settle()
	_expect(_label("EncounterPreview").get_theme_font_size("font_size") == 14, "Scaling back to 100 percent has no cumulative enlargement")


func _reveal_all() -> void:
	for stable_name: String in ["EncounterTitle", "EncounterIntegration", "EncounterRisk",
		"EncounterPreview", "EncounterStatus", "EncounterConfirm"]:
		var widget: Control = panel.find_child(stable_name, true, false) as Control
		if widget.visible:
			await _reveal(widget)
	for id: String in Catalog.get_ids():
		await _reveal(_option(id))
		await _reveal(_label("EncounterDescription_" + id))


func _reveal(widget: Control) -> void:
	host.ensure_control_visible(widget)
	await _settle()
	var visible_rect: Rect2 = host.get_global_rect()
	visible_rect.size.x -= host.get_v_scroll_bar().size.x if host.get_v_scroll_bar().visible else 0.0
	# Scroll offsets are integral; theme layout positions can be fractional.
	_expect(visible_rect.grow(1.0).encloses(widget.get_global_rect()),
		"Scrolling fully reveals " + str(widget.name))
	_expect(root.get_visible_rect().grow(1.0).encloses(widget.get_global_rect()),
		"Revealed control fits the actual logical viewport: " + str(widget.name))


func _check_bounds(node: Node) -> void:
	var bounds: Rect2 = panel.get_global_rect()
	for child: Node in node.get_children():
		if child is Control and child.visible:
			var rect: Rect2 = child.get_global_rect()
			_expect(rect.position.x >= bounds.position.x - 1.0 and rect.end.x <= bounds.end.x + 1.0,
				"No horizontal clipping: " + str(child.name))
			_expect(rect.position.y >= bounds.position.y - 1.0 and rect.end.y <= bounds.end.y + 1.0,
				"No vertical clipping: " + str(child.name))
			if child is Label:
				_expect(child.get_line_count() == child.get_visible_line_count(), "Every wrapped line remains visible: " + str(child.name))
		_check_bounds(child)


func _test_real_clicks(ids: Array[String]) -> void:
	panel.set_context([])
	await _settle()
	await _click(_option(ids[0]))
	_expect(panel.get_selected_ids() == [ids[0]], "Actual viewport mouse click checks the selected option")
	var count: int = events.size()
	await _click(_confirm())
	_expect(events.size() == count + 1 and events.back() == [ids[0]], "First actual mouse activation emits exactly one current request")
	await _click(_confirm())
	_expect(events.size() == count + 2 and events.back() == [ids[0]], "Two actual mouse clicks send two exact requests")
	panel.set_context(ids, "运行中")
	await _settle()
	count = events.size()
	await _click(_confirm())
	await _click(_option(ids[0]))
	_expect(events.size() == count and panel.get_selected_ids() == ids, "Actual disabled mouse input is ignored")


func _test_keyboard(ids: Array[String]) -> void:
	panel.set_context([])
	await _settle()
	var count: int = events.size()
	_option(ids[0]).grab_focus()
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, true, true)
	await _key(KEY_SPACE, false)
	_expect(panel.get_selected_ids() == [ids[0]] and events.size() == count, "Keyboard option activation changes only the draft")
	_confirm().grab_focus()
	for keycode: int in [KEY_SPACE, KEY_ENTER]:
		for activation: int in range(2):
			count = events.size()
			await _key(keycode, true)
			await _key(keycode, true, true)
			await _key(keycode, true, true)
			await _key(keycode, false)
			_expect(events.size() == count + 1 and events.back() == [ids[0]], "Each keyboard activation emits once despite key-repeat echoes")
	panel.set_context(ids, "运行中")
	count = events.size()
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false)
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	_expect(events.size() == count and panel.get_selected_ids() == ids, "Disabled keyboard confirmation cannot emit or change the draft")


func _test_context_updates(ids: Array[String]) -> void:
	for selection: Array in [[ids[1]], []]:
		panel.set_context([ids[0]])
		_confirm().grab_focus()
		var count: int = events.size()
		await _key(KEY_SPACE, true)
		_expect(panel.set_context(selection), "Owner can replace context during an in-flight activation")
		_expect(events.size() == count, "Context replacement emits no request")
		for id: String in ids:
			_expect(_option(id).button_pressed == selection.has(id), "Replacement removes stale checkbox state: " + id)
		await _key(KEY_SPACE, false)
		_expect(events.size() == count + 1 and events.back() == selection, "Activation release submits the latest context, including ordinary empty selection")
		_expect(panel.get_selected_ids() == selection, "Activation never restores a stale draft")
	panel.set_context([ids[0]])
	_confirm().grab_focus()
	var count: int = events.size()
	await _key(KEY_SPACE, true)
	panel.set_context(ids, "上层已经开始遭遇")
	await _key(KEY_SPACE, false)
	_expect(events.size() == count and panel.get_selected_ids() == ids, "Owner lock during activation blocks its release")
	panel.set_context([ids[0]])
	_confirm().grab_focus()
	await _key(KEY_ENTER, true)
	panel.set_context([ids[1], "unknown"])
	await _key(KEY_ENTER, false)
	_expect(events.size() == count and panel.get_selected_ids().is_empty(), "Invalid replacement during activation cannot submit stale IDs")
	panel.set_context([])
	await _click(_confirm())
	_expect(events.size() == count + 1 and events.back().is_empty(), "Explicit recovery submits ordinary empty selection without stale IDs")


func _key(keycode: int, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)
	await process_frame


func _click(button: Button) -> void:
	await _reveal(button)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _settle() -> void:
	for frame: int in range(5):
		await process_frame
