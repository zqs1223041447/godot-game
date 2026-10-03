extends SceneTree
## Headless functional UI acceptance: real K handler and connected button signals.
## Rendered mouse/keyboard, painting, hover and screenshots are separate acceptance.
const Model = preload("res://scripts/build_state.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const Emblem = preload("res://scripts/visuals/skill_emblem.gd")

var arena: Node
var support_panel: Control
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _prove_isolation():
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--probe-only"):
		quit(0)
		return
	root.size = Vector2i(1280, 720)
	var fresh = Model.new()
	_expect(fresh.save_build() == OK, "Fresh UI fixture writes only after isolation proof")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await process_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.pressed = true
	arena._unhandled_key_input(key)
	await process_frame
	support_panel = arena.hud.find_child("SkillSupportPanel", true, false)
	_expect(support_panel != null and arena.hud.is_blocking(), "Actual K key handler opens modal support inspector")
	if support_panel == null:
		_finish()
		return
	_expect(_label("SupportCastPreview").mouse_filter == Control.MOUSE_FILTER_PASS, "Cast detail label receives hover and passes wheel input to the existing scroll")
	for test: Callable in [_modal_and_catalog, _attach_remove_and_bound, _ineligible,
		_identity_and_autosave, _preview_and_affordability, _invalid_configuration]:
		completed = false
		test.call()
		_expect(completed, "UI case completed without a script exception: " + test.get_method())
	completed = false
	await _maximum_font_layout()
	_expect(completed, "Maximum-font layout case completed without a script exception")
	arena.queue_free()
	await process_frame
	_finish()


func _prove_isolation() -> bool:
	var expected: String = OS.get_environment("PIERCE_QA_ROOT").simplify_path()
	var actual: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = expected.begins_with("/tmp/godot-pierce-acceptance-") \
		and expected == OS.get_environment("XDG_DATA_HOME").simplify_path() \
		and actual.begins_with(expected + "/") and actual == OS.get_user_data_dir().simplify_path()
	_expect(safe, "Disposable Linux userdata path must match explicit XDG_DATA_HOME and PIERCE_QA_ROOT")
	if not safe:
		return false
	print("ISOLATION PROVED: user://=" + actual)
	var fresh: bool = not FileAccess.file_exists("user://build_save.json") and not FileAccess.file_exists(Settings.PATH)
	_expect(fresh, "Refuse existing default build or display settings, even within claimed QA directory")
	return fresh


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _near(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.0001, "%s (actual %.7f, expected %.7f)" % [message, actual, expected])


func _button(stable_name: String) -> Button:
	return arena.hud.find_child(stable_name, true, false) as Button


func _label(stable_name: String) -> Label:
	return arena.hud.find_child(stable_name, true, false) as Label


func _press(stable_name: String) -> void:
	var button: Button = _button(stable_name)
	_expect(button != null, "Connected UI action exists: " + stable_name)
	if button != null:
		button.pressed.emit() # Forced disabled signals exercise handler-side rejection too.


func _select(skill: String) -> void:
	var position: int = arena.state.skill_slots.find(skill)
	_press("SlotButton%d" % (position + 1) if position >= 0 else "SelectSkill_" + skill)
	_expect(support_panel.selected_skill_id == skill, "Real slot/library action selects support target: " + skill)


func _clear(skill: String) -> void:
	if not arena.state.get_skill_supports(skill).is_empty():
		_expect(arena.state.set_skill_supports(skill, []), "State transaction clears previous UI fixture links")


func _modal_and_catalog() -> void:
	_expect(support_panel.selected_skill_id == "bolt", "Initial K support target is actual slot-one bolt")
	_expect(support_panel.find_child("SupportSlots", true, false).get_child_count() == 2, "K shows exactly two independent support slots")
	_expect(_label("SupportName_pierce").text == Registry.get_definition("pierce").name and _label("SupportDescription_pierce").text == Registry.get_definition("pierce").description, "K name/description come from unified metadata")
	_expect(Emblem.ICONS.has("pierce") and Emblem.ICONS.pierce.get_width() >= 256, "Actual pierce option has an imported production-size icon")
	_expect(_button("AddSupport_pierce") != null and _button("AddSupport_volley") != null and _button("AddSupport_focus") != null, "K includes all three support options")
	var elapsed: float = arena.elapsed
	var mana: float = arena.mana
	var before: Dictionary = arena.state._snapshot()
	arena._process(1.0)
	_expect(arena.elapsed == elapsed and arena.mana == mana and arena.state._snapshot() == before, "K modal freezes simulation/resources and does not mutate build")
	_expect(not arena.cast_skill(0) and arena.mana == mana and arena.projectiles.is_empty(), "Actual skill cast is blocked while K editor is open")
	completed = true


func _attach_remove_and_bound() -> void:
	for skill: String in ["bolt", "frost"]:
		_clear(skill)
		_select(skill)
		arena.cooldowns[skill] = 0.61
		var inventory: Array = arena.state.inventory.duplicate()
		var jewels: Dictionary = arena.state.jewels.duplicate(true)
		_expect(not _button("AddSupport_pierce").disabled, "Eligible empty skill enables real pierce action: " + skill)
		_press("AddSupport_pierce")
		_expect(arena.state.get_skill_supports(skill) == ["pierce"] and _button("AddSupport_pierce").disabled and _button("AddSupport_pierce").text == "已装配", "Real add attaches pierce and disables duplicate action")
		var before: Dictionary = arena.state._snapshot()
		var saved: PackedByteArray = FileAccess.get_file_as_bytes("user://build_save.json")
		_press("AddSupport_pierce")
		_expect(arena.state._snapshot() == before and FileAccess.get_file_as_bytes("user://build_save.json") == saved, "Forced duplicate add leaves state and autosave unchanged")
		_expect(_label("SupportReason_pierce").text == arena.state.support_reason(skill, "pierce") and not _label("SupportReason_pierce").text.is_empty(), "Disabled duplicate shows exact state reason")
		_press("AddSupport_focus")
		_expect(arena.state.get_skill_supports(skill) == ["focus", "pierce"] and _label("SupportSlotCaption").text.contains("2 / 2"), "Legacy focus and pierce share the real two-slot bound")
		_expect(_button("AddSupport_volley").disabled and not _label("SupportReason_volley").text.is_empty(), "Third distinct support is visibly disabled with a reason")
		before = arena.state._snapshot()
		saved = FileAccess.get_file_as_bytes("user://build_save.json")
		_press("AddSupport_volley")
		_expect(arena.state._snapshot() == before and FileAccess.get_file_as_bytes("user://build_save.json") == saved, "Forced third-slot action cannot partially attach or autosave")
		var stale: Button = _button("RemoveSupport1")
		stale.pressed.emit()
		_expect(arena.state.get_skill_supports(skill) == ["pierce"], "Removal takes displayed focus identity and keeps pierce")
		before = arena.state._snapshot()
		stale.pressed.emit()
		_expect(arena.state._snapshot() == before and arena.state.get_skill_supports(skill) == ["pierce"], "Repeated stale remove cannot take shifted pierce identity")
		_press("RemoveSupport1")
		_expect(arena.state.get_skill_supports(skill).is_empty() and not _button("AddSupport_pierce").disabled, "Real pierce removal restores empty slot and eligible add action")
		_near(arena.cooldowns[skill], 0.61, "UI add/remove does not reset an existing skill cooldown")
		_expect(arena.state.inventory == inventory and arena.state.jewels == jewels, "Virtual support choices consume no physical items or jewels")
	completed = true


func _ineligible() -> void:
	for skill: String in ["tornado", "nova", "dash", "ward", "meteor", "chain"]:
		_select(skill)
		var before: Dictionary = arena.state._snapshot()
		var saved: PackedByteArray = FileAccess.get_file_as_bytes("user://build_save.json")
		var reason: String = arena.state.support_reason(skill, "pierce")
		_expect(_button("AddSupport_pierce").disabled and not reason.is_empty(), "Ineligible actual K selection disables pierce: " + skill)
		_expect(_label("SupportReason_pierce").text == reason and _button("AddSupport_pierce").tooltip_text == reason, "Visible reason and tooltip match actual state validation")
		_press("AddSupport_pierce")
		_expect(arena.state._snapshot() == before and FileAccess.get_file_as_bytes("user://build_save.json") == saved, "Forced disabled action preserves full build and saved bytes: " + skill)
		_expect(arena.state.get_skill_cast(skill).ok, "Ineligible skill remains usable without pierce")
	completed = true


func _identity_and_autosave() -> void:
	_clear("bolt")
	_clear("frost")
	_expect(arena.state.set_skill_supports("bolt", ["pierce", "focus"]) and arena.state.set_skill_supports("frost", ["volley", "pierce"]), "Independent eligible skills accept different real two-support combinations")
	_select("bolt")
	arena.cooldowns.bolt = 0.61
	var position: int = arena.state.skill_slots.find("bolt")
	var destination: int = (position + 1) % 5
	_expect(arena.state.slot_skill(destination, "bolt"), "Actual hotbar swap moves the supported skill")
	_expect(support_panel.selected_skill_id == "bolt" and _label("SelectedSupportSkill").text.contains("快捷栏 %d" % (destination + 1)), "Inspector follows skill identity and shows new actual hotbar position")
	_expect(arena.state.get_skill_supports("bolt") == ["focus", "pierce"] and arena.state.get_skill_supports("frost") == ["pierce", "volley"], "Swap does not lend one skill's support list to another")
	_near(arena.cooldowns.bolt, 0.61, "Hotbar swap retains existing cooldown")
	var loaded = Model.new()
	_expect(loaded.load_build() and loaded._snapshot() == arena.state._snapshot(), "Actual scene autosave reloads complete schema10 support build")
	var before: Dictionary = arena.state._snapshot()
	var saved: PackedByteArray = FileAccess.get_file_as_bytes("user://build_save.json")
	for index: int in range(2):
		arena.hud.close_panel()
		_expect(not arena.hud.is_blocking(), "Closing K restores gameplay admission")
		arena.hud.open_panel("skills")
		_expect(arena.hud.find_child("SkillSupportPanel", true, false) == support_panel and support_panel.selected_skill_id == "bolt", "Reopening K reuses inspector with same skill identity")
		_expect(arena.state._snapshot() == before and FileAccess.get_file_as_bytes("user://build_save.json") == saved, "Opening/closing K neither alters nor resaves build")
	completed = true


func _preview_and_affordability() -> void:
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	for skill: String in ["bolt", "frost"]:
		_select(skill)
		for links: Array in [["pierce"], ["focus", "pierce"], ["volley", "pierce"]]:
			_clear(skill)
			_expect(arena.state.set_skill_supports(skill, links), "Preview fixture uses validated state transaction")
			var expected_mana: float = (7.0 if skill == "bolt" else 16.0) * 1.2 * (1.3 if links.has("volley") else 1.2 if links.has("focus") else 1.0)
			var damage: float = 18.0 * (1.6 if skill == "bolt" else 0.85) * 0.85 * (0.8 if links.has("volley") else 1.25 if links.has("focus") else 1.0)
			var count: int = (3 if skill == "bolt" else 5) + (2 if links.has("volley") else 0)
			var pierce: int = 3 if skill == "bolt" else 4
			var preview: Label = _label("SupportCastPreview")
			_expect(preview.text.contains("%.2f 法力" % expected_mana) and preview.text.contains("初始投射物 %d 枚" % count) and preview.text.contains("每枚投射物 %.2f" % damage), "K preview matches independent exact mana/count/damage algebra")
			_expect(preview.tooltip_text.contains("穿透 %d 次，最多命中 %d 次" % [pierce, pierce + 1]) and preview.tooltip_text.contains("去返共享剩余次数") and preview.tooltip_text.contains("同相位同目标至多命中一次"), "K tooltip distinguishes remaining pierce from total target capacity and shared phase rules")
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			_near(cast.mana, expected_mana, "Actual compiler cost agrees with independent UI expected cost")
			var position: int = arena.state.skill_slots.find(skill)
			arena.hud.close_panel()
			arena.cooldowns[skill] = 0.0
			arena.mana = float(cast.mana) - 0.001
			arena.hud._update_live()
			var hotbar: Button = _button("SkillButton%d" % (position + 1))
			_expect(hotbar.text.contains("法力不足"), "Hotbar detects a fraction below exact supported cost")
			_expect(hotbar.tooltip_text.contains("%.2f 法力" % expected_mana) and hotbar.tooltip_text.contains("初始投射物：%d 枚" % count) and hotbar.tooltip_text.contains("最多命中 %d 次" % (pierce + 1)), "Hotbar reports the same actual supported cost/count/finite capacity")
			arena.mana = float(cast.mana)
			arena.hud._update_live()
			_expect(hotbar.text.contains("就绪"), "Hotbar shows exact supported mana affordable")
			arena.hud.open_panel("skills")
	completed = true


func _invalid_configuration() -> void:
	_select("bolt")
	var original: Dictionary = arena.state.skill_supports.duplicate(true)
	arena.state.skill_supports.bolt = ["volley", "focus", "pierce"] # Intentional fixture corruption only.
	arena.hud.refresh_build()
	_expect(_label("SupportCastPreview").text.begins_with("无法施放："), "Overbound runtime configuration makes K preview fail closed")
	var before: Dictionary = arena.state._snapshot()
	for id: String in ["pierce", "focus", "volley"]:
		_expect(_button("AddSupport_" + id).disabled, "Invalid compiler state disables every add action")
		_press("AddSupport_" + id)
	_expect(arena.state._snapshot() == before, "Forced add cannot mutate a failed compiled configuration")
	arena.hud.close_panel()
	arena.hud._update_live()
	var position: int = arena.state.skill_slots.find("bolt")
	var hotbar: Button = _button("SkillButton%d" % (position + 1))
	_expect(hotbar.disabled and hotbar.text.contains("配置无效") and hotbar.tooltip_text.contains("无法施放"), "Invalid supports never appear as free/ready hotbar cast")
	arena.state.skill_supports = original
	arena.hud.open_panel("skills")
	arena.hud.refresh_build()
	completed = true


func _maximum_font_layout() -> void:
	_clear("frost")
	_select("frost")
	_expect(arena.state.set_skill_supports("frost", ["pierce", "focus"]), "Maximum-font layout includes two occupied slots and all three option cards")
	var before: Dictionary = arena.state._snapshot()
	var saved: PackedByteArray = FileAccess.get_file_as_bytes("user://build_save.json")
	arena.hud._set_ui_scale(Settings.UI_SCALES.size() - 1)
	arena.hud._set_font_scale(Settings.FONT_SCALES.size() - 1)
	arena.hud.refresh_build()
	for frame: int in range(6):
		await process_frame
	_expect(root.get_visible_rect().size == Vector2(1280, 720) and arena.visual_settings.ui_scale == 1.1 and arena.visual_settings.font_scale == 1.2, "Layout really runs at 720p and both maximum supported scales")
	var modal: Control = arena.hud._modal.find_child("BuildPanel",true,false)
	var scroll: ScrollContainer = arena.hud._panel_scroll as ScrollContainer
	var body: Control = arena.hud._panel_body
	var viewport: Rect2 = root.get_visible_rect()
	var bounds: Rect2 = modal.get_global_rect()
	_expect(bounds.position.x >= -1.0 and bounds.position.y >= -1.0 and bounds.end.x <= viewport.end.x + 1.0 and bounds.end.y <= viewport.end.y + 1.0, "Maximum-size K frame remains inside actual 720p viewport")
	_expect(body.size.x <= scroll.size.x + 1.0 and support_panel.size.x <= scroll.size.x + 1.0, "Maximum-font K body/inspector have no horizontal overflow")
	_check_horizontal(support_panel, support_panel.get_global_rect())
	_expect(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "Tall three-option inspector is reachable through real vertical scrolling")
	_expect(_label("SupportDescription_pierce").get_theme_font_size("font_size") == 17 and _label("SupportCastPreview").get_theme_font_size("font_size") == 19, "Pierce description and preview receive maximum font scaling")
	_press("RemoveSupport1")
	_expect(_label("SupportSlotName1").get_theme_font_size("font_size") == 19, "Live removal rebuild retains maximum font size")
	_press("AddSupport_focus")
	for frame: int in range(4):
		await process_frame
	_expect(support_panel.find_child("SupportSlots", true, false).get_child_count() == 2, "Live refresh retains exactly two support slots")
	_expect(arena.state._snapshot() == before and FileAccess.get_file_as_bytes("user://build_save.json") == saved, "Presentation changes and remove/re-add preserve final exact build/save")
	_clear("frost")
	for frame: int in range(4):
		await process_frame
	scroll.ensure_control_visible(_button("AddSupport_pierce"))
	for frame: int in range(3):
		await process_frame
	var button_rect: Rect2 = _button("AddSupport_pierce").get_global_rect()
	var scroll_rect: Rect2 = scroll.get_global_rect()
	_expect(button_rect.position.y >= scroll_rect.position.y - 1.0 and button_rect.end.y <= scroll_rect.end.y + 1.0 and not _button("AddSupport_pierce").disabled, "At maximum font, scrolling makes entire eligible pierce add action accessible")
	_press("AddSupport_pierce")
	_expect(arena.state.get_skill_supports("frost") == ["pierce"] and _label("SupportDescription_pierce").get_theme_font_size("font_size") == 17, "Scrolled live add still uses real transaction and maximum-size description")
	completed = true


func _check_horizontal(node: Node, bounds: Rect2) -> void:
	for child: Node in node.get_children():
		if child is Control and child.is_visible_in_tree():
			var rect: Rect2 = child.get_global_rect()
			_expect(rect.position.x >= bounds.position.x - 1.0 and rect.end.x <= bounds.end.x + 1.0, "Maximum-font support child stays inside horizontal bounds: " + str(child.name))
		_check_horizontal(child, bounds)


func _finish() -> void:
	print("Pierce UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
