extends SceneTree
## Run only under isolated XDG roots: this uses the real scene and its autosave.
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")

var checks: int = 0
var failures: int = 0
var arena: Node
var support_panel: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var fresh = Model.new()
	_expect(fresh.save_build() == OK, "Fresh UI fixture saves in isolated root")
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await process_frame
	arena.hud.open_panel("skills")
	support_panel = arena.hud.find_child("SkillSupportPanel", true, false)
	_expect(support_panel != null, "K panel includes dedicated support inspector")
	if support_panel == null:
		_finish()
		return
	_expect(arena.hud.is_blocking(), "Support editor keeps parent modal pause")
	var elapsed: float = arena.elapsed
	arena._process(1.0)
	_expect(arena.elapsed == elapsed, "Support editor freezes combat simulation")
	_expect(support_panel.selected_skill_id == "bolt", "Initial inspector targets actual slot-one skill")
	_expect(support_panel.find_child("SupportSlots", true, false).get_child_count() == 2, "Exactly two support slots are visible")
	for skill_id: String in Data.SKILLS:
		_expect(_button("SelectSkill_" + skill_id) != null, "Existing eight-skill action preserved: " + skill_id)
	for index: int in range(1, 6):
		_expect(_button("SlotButton%d" % index) != null and _button("SkillButton%d" % index) != null, "Existing slot/hotbar stable names preserved")
	_test_attach_reject_remove()
	_test_identity_and_persistence()
	_test_previews_and_affordability()
	_test_incompatible_skills()
	_test_invalid_compiler()
	await _test_layout_and_panels()
	arena.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _button(stable_name: String) -> Button:
	return arena.hud.find_child(stable_name, true, false) as Button


func _press(stable_name: String) -> void:
	var button: Button = _button(stable_name)
	_expect(button != null, "Action exists: " + stable_name)
	if button != null:
		button.pressed.emit()


func _label(stable_name: String) -> Label:
	return arena.hud.find_child(stable_name, true, false) as Label


func _test_attach_reject_remove() -> void:
	arena.cooldowns.bolt = 0.61
	var original_inventory: Array = arena.state.inventory.duplicate()
	var original_jewels: Dictionary = arena.state.jewels.duplicate(true)
	_press("AddSupport_volley")
	_expect(arena.state.get_skill_supports("bolt") == ["volley"], "Add button links support to selected skill")
	_expect(_button("AddSupport_volley").disabled, "Linked support displays disabled add action")
	var configured: Dictionary = arena.state._snapshot()
	_press("AddSupport_volley")
	_expect(arena.state._snapshot() == configured, "Repeated add cannot duplicate support")
	_expect(not _label("SupportReason_volley").text.is_empty(), "Duplicate rejection has a visible reason")
	_press("AddSupport_focus")
	_expect(arena.state.get_skill_supports("bolt").size() == 2, "Both originals fit independent two-slot bound")
	_expect(_label("SupportSlotCaption").text.contains("2 / 2"), "Full support slots are clearly labelled")
	configured = arena.state._snapshot()
	_press("AddSupport_focus")
	_press("AddSupport_volley")
	_expect(arena.state._snapshot() == configured, "Full/repeated UI actions never mutate configured build")
	_expect(not arena.state.set_skill_supports("bolt", ["volley", "focus", "volley"]), "Three-support request is rejected by same state boundary")
	_expect(arena.state.inventory == original_inventory and arena.state.jewels == original_jewels, "Virtual supports never consume physical inventory or jewels")
	var removed_id: String = arena.state.get_skill_supports("bolt")[0]
	var stale_remove: Button = _button("RemoveSupport1")
	stale_remove.pressed.emit()
	_expect(not arena.state.get_skill_supports("bolt").has(removed_id), "Slot action removes displayed support")
	configured = arena.state._snapshot()
	stale_remove.pressed.emit()
	_expect(arena.state._snapshot() == configured and arena.state.get_skill_supports("bolt").size() == 1, "Repeated stale remove cannot remove the shifted remaining support")
	_expect(is_equal_approx(arena.cooldowns.bolt, 0.61), "Support additions/removals never reset existing cooldown")
	_press("AddSupport_" + removed_id)


func _test_identity_and_persistence() -> void:
	var configured: Array = arena.state.get_skill_supports("bolt")
	_expect(arena.state.slot_skill(1, "bolt"), "External hotbar swap fixture accepted")
	_expect(arena.state.skill_slots[1] == "bolt" and arena.state.get_skill_supports("bolt") == configured, "Supports follow skill across hotbar swap")
	_expect(support_panel.selected_skill_id == "bolt" and _label("SelectedSupportSkill").text.contains("快捷栏 2"), "Inspector selection follows actual skill identity and updates location")
	_expect(arena.hud._selected_skill_slot == 1, "Hotbar target selection follows externally moved skill")
	_press("SlotButton1")
	_expect(support_panel.selected_skill_id == "frost" and arena.state.get_skill_supports("frost").is_empty(), "Selecting another slot never borrows previous skill supports")
	_press("AddSupport_focus")
	_press("SelectSkill_bolt")
	_expect(arena.state.skill_slots[0] == "bolt" and arena.state.get_skill_supports("bolt") == configured, "Existing skill library swaps supported skill without overwriting its links")
	_expect(arena.state.get_skill_supports("frost") == ["focus"], "Displaced skill retains its own independent links")
	var before: Dictionary = arena.state._snapshot()
	for index: int in range(3):
		arena.hud.close_panel()
		_expect(not arena.hud.is_blocking(), "Close resumes combat without altering links")
		arena.hud.open_panel("skills")
		_expect(arena.hud.find_child("SkillSupportPanel", true, false) == support_panel, "Reopening reuses inspector")
		_expect(support_panel.selected_skill_id == "bolt" and arena.state._snapshot() == before, "Reopening keeps selection and configured links")
	_expect(is_equal_approx(arena.cooldowns.bolt, 0.61), "Swap and modal reopen preserve running cooldown")
	var loaded = Model.new()
	_expect(loaded.load_build() and loaded.get_skill_supports("bolt") == configured and loaded.get_skill_supports("frost") == ["focus"], "Actual scene autosave persists independent skill support transactions")


func _test_previews_and_affordability() -> void:
	for skill_id: String in ["tornado", "bolt", "frost"]:
		arena.hud._slot_skill(skill_id)
		for support_id: String in Supports.SUPPORTS:
			if not arena.state.get_skill_supports(skill_id).has(support_id):
				_press("AddSupport_" + support_id)
		var cast: Dictionary = arena.state.get_skill_cast(skill_id)
		var expected: float = float(Data.SKILLS[skill_id].mana) * 1.56
		_expect(bool(cast.ok) and is_equal_approx(float(cast.mana), expected), "Both support mana factors compile exactly: " + skill_id)
		_expect(_label("SupportCastPreview").text.contains("%.2f 法力" % expected), "Inspector displays exact two-decimal effective mana: " + skill_id)
		_expect(_label("SupportCastPreview").text.contains("初始投射物 %d 枚" % int(cast.initial_count)), "Inspector uses compiler initial volley count: " + skill_id)
		var position: int = arena.state.skill_slots.find(skill_id)
		arena.hud.close_panel()
		arena.cooldowns[skill_id] = 0.0
		arena.mana = expected - 0.001
		arena.hud._update_live()
		var hotbar: Button = _button("SkillButton%d" % (position + 1))
		_expect(hotbar.text.contains("法力不足"), "Fraction below effective cost is never shown affordable: " + skill_id)
		_expect(hotbar.tooltip_text.contains("%.2f 法力" % expected) and hotbar.tooltip_text.contains("冷却 %.2f 秒" % float(cast.cooldown)), "Hotbar tooltip exactly matches compiled mana/cooldown: " + skill_id)
		arena.mana = float(cast.mana)
		arena.hud._update_live()
		_expect(hotbar.text.contains("就绪"), "Exact compiled mana is shown affordable: " + skill_id)
		arena.hud.open_panel("skills")


func _test_incompatible_skills() -> void:
	for skill_id: String in ["nova", "dash", "ward", "meteor", "chain"]:
		arena.hud._slot_skill(skill_id)
		_expect(support_panel.selected_skill_id == skill_id, "Unsupported selection is explicit: " + skill_id)
		_expect(bool(arena.state.get_skill_cast(skill_id).ok), "Unsupported skill remains castable without supports: " + skill_id)
		var before: Dictionary = arena.state._snapshot()
		for support_id: String in Supports.SUPPORTS:
			var reason: String = arena.state.support_reason(skill_id, support_id)
			_expect(not reason.is_empty() and _label("SupportReason_" + support_id).text == reason, "Incompatibility reason shown verbatim: " + skill_id + "/" + support_id)
			_expect(_button("AddSupport_" + support_id).disabled, "Incompatible action is disabled")
			_press("AddSupport_" + support_id)
		_expect(arena.state._snapshot() == before, "Programmatic disabled clicks cannot attach incompatible support: " + skill_id)


func _test_invalid_compiler() -> void:
	arena.hud._slot_skill("bolt")
	var original: Array = arena.state.get_skill_supports("bolt")
	# Deliberate corruption is isolated to this fixture; UI never writes state maps.
	arena.state.skill_supports["bolt"] = ["unknown_support"]
	arena.hud.refresh_build()
	_expect(_label("SupportCastPreview").text.begins_with("无法施放："), "Compiler errors remain visible in support preview")
	var corrupted: Dictionary = arena.state.skill_supports.duplicate(true)
	_press("AddSupport_focus")
	_expect(arena.state.skill_supports == corrupted, "Invalid compiler result rejects a forced disabled add action")
	var position: int = arena.state.skill_slots.find("bolt")
	arena.hud.close_panel()
	arena.hud._update_live()
	var hotbar: Button = _button("SkillButton%d" % (position + 1))
	_expect(hotbar.disabled and hotbar.text.contains("配置无效") and hotbar.tooltip_text.contains("无法施放"), "Invalid compiler result fails closed instead of showing a zero-cost cast")
	arena.state.skill_supports["bolt"] = original
	arena.hud.open_panel("skills")
	arena.hud.refresh_build()


func _test_layout_and_panels() -> void:
	arena.visual_settings.ui_scale = 1.1
	arena.visual_settings.font_scale = 1.2
	arena.hud._apply_presentation()
	var before: Dictionary = arena.state._snapshot()
	for panel: String in ["inventory", "talents", "skills", "combat", "monsters", "settings", "pause"]:
		arena.hud.open_panel(panel)
		for frame: int in range(5):
			await process_frame
		var scroll: Control = arena.hud.find_child("PanelScroll", true, false)
		var body: Control = arena.hud.find_child("PanelBody", true, false)
		var modal: Control = arena.hud.find_child("BuildPanel", true, false)
		var hud_root: Control = arena.hud.get_node("HUDRoot")
		_expect(body.size.x <= scroll.size.x + 1.0, "Maximum UI/font avoids horizontal overflow: " + panel)
		_expect(modal.get_rect().end.y <= hud_root.size.y + 1.0, "Maximum UI/font frame remains within viewport: " + panel)
		_expect(arena.hud.is_blocking(), "Original panel retains pause: " + panel)
		if panel == "skills":
			_expect(support_panel.size.x <= scroll.size.x + 1.0, "Support editor fits available width")
			_check_support_children(support_panel)
			_press("RemoveSupport1")
			_expect(_label("SupportSlotName1").get_theme_font_size("font_size") == 19, "Live support refresh preserves maximum font setting")
			_press("AddSupport_focus")
	_expect(arena.state._snapshot() == before, "Panel regressions and remove/re-add preserve build")


func _check_support_children(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control and child.visible:
			var control: Control = child
			_expect(control.get_global_rect().end.x <= support_panel.get_global_rect().end.x + 1.0, "Support control has no horizontal clipping: " + str(child.name))
		_check_support_children(child)


func _finish() -> void:
	print("Skill support UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
