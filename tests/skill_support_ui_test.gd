extends SceneTree
## Legacy component contracts plus current canonical Main panel integration.
## The legacy virtual-support component is not the current product skills editor.
const CanonicalModel = preload("res://scripts/canonical_game_state.gd")
const CanonicalPanel = preload("res://scripts/ui/canonical_skill_panel.gd")
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")

# Fault injection only for the final fail-closed hotbar probe. All other calls
# use the production compiler and canonical transactions unchanged.
class CompilerFaultModel extends CanonicalModel:
	var reject_casts := false
	func get_group_cast(group_id: String) -> Dictionary:
		if reject_casts: return {"ok":false,"error":"fixture compiler failure"}
		return super.get_group_cast(group_id)

var checks: int = 0
var failures: int = 0
var arena: Node
var support_panel: Control
var legacy: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	create_timer(45.0).timeout.connect(func(): push_error("Support UI watchdog expired"); quit(1))
	root.size = Vector2i(1280, 720)
	# Legacy-only component contract: never inject BuildState into current Main.
	legacy = Model.new()
	support_panel = preload("res://scripts/skill_support_panel.gd").new()
	root.add_child(support_panel)
	support_panel.size = Vector2(1200, 700)
	support_panel.setup(legacy)
	legacy.changed.connect(func(): support_panel.refresh(); _expect(legacy.save_build("user://legacy-support.json") == OK,"Legacy component transaction persists"))
	support_panel.select_skill("bolt")
	_expect(support_panel.selected_skill_id == "bolt", "Legacy inspector targets selected skill")
	_expect(support_panel.find_child("SupportSlots", true, false).get_child_count() == 2, "Legacy component exposes two support slots")
	_test_attach_reject_remove()
	_test_identity_and_persistence()
	_test_legacy_previews()
	_test_incompatible_skills()
	_test_invalid_compiler()
	support_panel.font_scale = 1.2
	support_panel.refresh()
	for frame: int in range(5): await process_frame
	_check_support_children(support_panel)
	_press("RemoveSupport1")
	_expect(_label("SupportSlotName1").get_theme_font_size("font_size") == 19, "Legacy refresh preserves maximum font setting")
	_press("AddSupport_focus")
	support_panel.queue_free()
	await process_frame
	# Current product integration uses the unmodified canonical Main/model/HUD.
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = CompilerFaultModel.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await process_frame
	_expect(arena.state is CanonicalModel, "Current Main uses canonical model")
	_expect(arena.world_context().mode == "town", "Current Main starts in formal town")
	_expect(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).ok, "Current formal map draft accepted")
	_expect(arena.start_map(arena.map_draft().revision).ok, "Current formal map entered")
	if arena.world_context().mode != "map": _finish(); return
	arena.hud.close_panel()
	var advancing: float = arena.elapsed
	arena._process(0.1)
	_expect(arena.elapsed > advancing, "Positive control: closed panels advance actual combat")
	arena.hud.open_panel("skills")
	_expect(arena.hud._skill_support_panel is CanonicalPanel, "Current skills dock uses canonical physical-gem editor")
	var elapsed: float = arena.elapsed
	arena._process(1.0)
	_expect(arena.elapsed == elapsed and arena.hud.is_blocking(), "Current skills dock freezes simulation")
	_test_canonical_hotbar()
	_test_canonical_support_edit()
	await _test_layout_and_panels()
	arena.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		quit(1)


func _button(stable_name: String) -> Button:
	var found := support_panel.find_child(stable_name, true, false) as Button
	if found == null: _expect(false, "Required legacy button missing: " + stable_name)
	return found


func _press(stable_name: String) -> void:
	var button: Button = _button(stable_name)
	_expect(button != null, "Action exists: " + stable_name)
	if button != null:
		button.pressed.emit()


func _label(stable_name: String) -> Label:
	var found := support_panel.find_child(stable_name, true, false) as Label
	if found == null: _expect(false, "Required legacy label missing: " + stable_name)
	return found


func _test_attach_reject_remove() -> void:
	var original_inventory: Array = legacy.inventory.duplicate()
	var original_jewels: Dictionary = legacy.jewels.duplicate(true)
	_press("AddSupport_volley")
	_expect(legacy.get_skill_supports("bolt") == ["volley"], "Add button links support to selected skill")
	_expect(_button("AddSupport_volley").disabled, "Linked support displays disabled add action")
	var configured: Dictionary = legacy._snapshot()
	_press("AddSupport_volley")
	_expect(legacy._snapshot() == configured, "Repeated add cannot duplicate support")
	_expect(not _label("SupportReason_volley").text.is_empty(), "Duplicate rejection has a visible reason")
	_press("AddSupport_focus")
	_expect(legacy.get_skill_supports("bolt").size() == 2, "Both originals fit independent two-slot bound")
	_expect(_label("SupportSlotCaption").text.contains("2 / 2"), "Full support slots are clearly labelled")
	configured = legacy._snapshot()
	_press("AddSupport_focus")
	_press("AddSupport_volley")
	_expect(legacy._snapshot() == configured, "Full/repeated UI actions never mutate configured build")
	_expect(not legacy.set_skill_supports("bolt", ["volley", "focus", "volley"]), "Three-support request is rejected by same state boundary")
	_expect(legacy.inventory == original_inventory and legacy.jewels == original_jewels, "Virtual supports never consume physical inventory or jewels")
	if legacy.get_skill_supports("bolt").is_empty():
		_expect(false, "Required installed legacy support missing")
		return
	var removed_id: String = legacy.get_skill_supports("bolt")[0]
	var stale_remove: Button = _button("RemoveSupport1")
	stale_remove.pressed.emit()
	_expect(not legacy.get_skill_supports("bolt").has(removed_id), "Slot action removes displayed support")
	configured = legacy._snapshot()
	stale_remove.pressed.emit()
	_expect(legacy._snapshot() == configured and legacy.get_skill_supports("bolt").size() == 1, "Repeated stale remove cannot remove the shifted remaining support")
	_press("AddSupport_" + removed_id)


func _test_identity_and_persistence() -> void:
	var configured: Array = legacy.get_skill_supports("bolt")
	_expect(legacy.slot_skill(1, "bolt"), "Legacy hotbar swap accepted")
	_expect(legacy.skill_slots[1] == "bolt" and legacy.get_skill_supports("bolt") == configured, "Supports follow skill across hotbar swap")
	_expect(support_panel.selected_skill_id == "bolt" and _label("SelectedSupportSkill").text.contains("快捷栏 2"), "Inspector follows skill identity and location")
	support_panel.select_skill("frost")
	_expect(legacy.get_skill_supports("frost").is_empty(), "Another skill never borrows previous links")
	_press("AddSupport_focus")
	_expect(legacy.slot_skill(0, "bolt"), "Legacy supported skill swaps back")
	support_panel.select_skill("bolt")
	_expect(legacy.get_skill_supports("bolt") == configured and legacy.get_skill_supports("frost") == ["focus"], "Swapped and displaced skills retain independent links")
	var before: Dictionary = legacy._snapshot()
	for index: int in range(3):
		support_panel.hide()
		support_panel.show()
		support_panel.refresh()
		_expect(support_panel.selected_skill_id == "bolt" and legacy._snapshot() == before, "Component reopen preserves selected identity and build")
	var loaded = Model.new()
	_expect(loaded.load_build("user://legacy-support.json") and loaded.get_skill_supports("bolt") == configured and loaded.get_skill_supports("frost") == ["focus"], "Legacy component transactions persist independent supports")


func _test_legacy_previews() -> void:
	for skill_id: String in ["tornado", "bolt", "frost"]:
		support_panel.select_skill(skill_id)
		for support_id: String in Supports.SUPPORTS:
			if not legacy.get_skill_supports(skill_id).has(support_id):
				_press("AddSupport_" + support_id)
		var cast: Dictionary = legacy.get_skill_cast(skill_id)
		var expected: float = float(Data.SKILLS[skill_id].mana) * 1.56
		_expect(bool(cast.ok) and is_equal_approx(float(cast.mana), expected), "Both support mana factors compile exactly: " + skill_id)
		_expect(_label("SupportCastPreview").text.contains("%.2f 法力" % expected), "Inspector displays exact two-decimal effective mana: " + skill_id)
		_expect(_label("SupportCastPreview").text.contains("初始投射物 %d 枚" % int(cast.initial_count)), "Inspector uses compiler initial volley count: " + skill_id)


func _test_incompatible_skills() -> void:
	for skill_id: String in ["nova", "dash", "ward", "meteor", "chain"]:
		support_panel.select_skill(skill_id)
		_expect(support_panel.selected_skill_id == skill_id, "Unsupported selection is explicit: " + skill_id)
		_expect(bool(legacy.get_skill_cast(skill_id).ok), "Unsupported skill remains castable without supports: " + skill_id)
		var before: Dictionary = legacy._snapshot()
		for support_id: String in Supports.SUPPORTS:
			var reason: String = legacy.support_reason(skill_id, support_id)
			_expect(not reason.is_empty() and _label("SupportReason_" + support_id).text == reason, "Incompatibility reason shown verbatim: " + skill_id + "/" + support_id)
			_expect(_button("AddSupport_" + support_id).disabled, "Incompatible action is disabled")
			_press("AddSupport_" + support_id)
		_expect(legacy._snapshot() == before, "Programmatic disabled clicks cannot attach incompatible support: " + skill_id)


func _test_invalid_compiler() -> void:
	support_panel.select_skill("bolt")
	var original: Array = legacy.get_skill_supports("bolt")
	# Deliberate corruption is isolated to this fixture; UI never writes state maps.
	legacy.skill_supports["bolt"] = ["unknown_support"]
	support_panel.refresh()
	_expect(_label("SupportCastPreview").text.begins_with("无法施放："), "Compiler errors remain visible in support preview")
	var corrupted: Dictionary = legacy.skill_supports.duplicate(true)
	_press("AddSupport_focus")
	_expect(legacy.skill_supports == corrupted, "Invalid compiler result rejects a forced disabled add action")
	legacy.skill_supports["bolt"] = original
	support_panel.refresh()


func _test_canonical_hotbar() -> void:
	arena.hud.close_panel()
	for index: int in range(5):
		var group_id: String = arena.state.group_for_key(KEY_1 + index)
		var button := arena.hud.find_child("SkillButton%d" % (index + 1), true, false) as Button
		_expect(button != null, "Current hotbar stable button exists")
		if button == null: return
		if group_id.is_empty(): continue
		var cast: Dictionary = arena.state.get_group_cast(group_id)
		_expect(bool(cast.get("ok", false)), "Current bound group compiles")
		if not cast.get("ok", false): return
		arena.mana = float(cast.mana) - 0.001
		arena.hud._update_live()
		_expect(button.text.contains("法力不足"), "Current hotbar rejects fractional mana shortfall")
		_expect(button.tooltip_text.contains("%.2f 法力" % float(cast.mana)) and button.tooltip_text.contains("冷却 %.2f 秒" % float(cast.cooldown)), "Current tooltip matches canonical compiled mana and cooldown")
		arena.mana = float(cast.mana)
		arena.hud._update_live()
		_expect(button.text.contains("就绪"), "Current hotbar admits exact compiled mana")
	var before: Dictionary = arena.state.snapshot()
	var current_panel: Control = arena.hud._skill_support_panel
	for index: int in range(3):
		arena.hud.open_panel("skills")
		_expect(arena.hud._skill_support_panel == current_panel, "Current skills dock reuses canonical editor")
		arena.hud.close_panel()
		_expect(not arena.hud.is_blocking() and arena.state.snapshot() == before, "Current reopen and close preserve build and resume simulation")


func _test_canonical_support_edit() -> void:
	var group_id := "group_000002"
	var panel: Control = arena.hud._skill_support_panel
	arena.hud.close_panel()
	arena.mana = arena.get_stats().max_mana
	_expect(arena.cast_group(group_id), "Current real cast establishes cooldown before edits")
	var debt: Dictionary = arena.group_cooldowns.snapshot()
	var uid := ""
	var source: Dictionary = arena.state.snapshot()
	for item_uid: String in source.items:
		if source.items[item_uid].definition_id == "support:quickcast": uid = item_uid
	_expect(not uid.is_empty(), "Owned compatible physical support exists")
	if uid.is_empty(): return
	arena.hud.open_panel("skills")
	panel._rows.move_requested.emit(uid, {"kind":"skill_support", "group_id":group_id, "index":0}, arena.state.revision())
	_expect(arena.state.skill_group(group_id).support_uids.has(uid), "Current editor input attaches physical support")
	_expect(arena.group_cooldowns.snapshot() == debt, "Current support addition preserves real cooldown debt")
	var loaded = CanonicalModel.new()
	_expect(loaded.load_build(arena.build_save_path) and loaded.skill_group(group_id).support_uids.has(uid), "Current editor transaction persists physical support")
	panel._rows.return_requested.emit(uid, arena.state.revision())
	_expect(not arena.state.skill_group(group_id).support_uids.has(uid), "Current editor input removes physical support")
	_expect(arena.group_cooldowns.snapshot() == debt, "Current support removal preserves real cooldown debt")
	for index: int in range(3):
		arena.hud.close_panel()
		arena.hud.open_panel("skills")
	_expect(arena.group_cooldowns.snapshot() == debt, "Current modal reopen preserves running cooldown")
	arena.hud.close_panel()
	arena.state.reject_casts = true
	arena.hud._skill_views.clear()
	arena.hud._update_live()
	var button := arena.hud.find_child("SkillButton2", true, false) as Button
	_expect(button != null, "Current invalid-cast hotbar exists")
	if button != null:
		_expect(button.disabled and button.text.contains("配置无效") and button.tooltip_text.contains("无法施放"), "Current compiler rejection fails closed in hotbar")
	arena.state.reject_casts = false
	arena.hud._skill_views.clear()
	arena.hud._update_live()


func _test_layout_and_panels() -> void:
	arena.visual_settings.ui_scale = 1.1
	arena.visual_settings.font_scale = 1.2
	arena.hud._apply_presentation()
	var before: Dictionary = arena.state.snapshot()
	for panel: String in ["inventory", "talents", "skills", "combat", "monsters", "settings", "pause"]:
		arena.hud.open_panel(panel)
		for frame: int in range(5):
			await process_frame
		var scroll: Control = arena.hud._panel_scroll
		var body: Control = arena.hud._panel_body
		var modal: Control = arena.hud._modal.find_child("BuildPanel",true,false)
		# Skills/inventory now live in independent one-third docks. Validate the
		# visible dock's actual body, scroll and frame instead of stale modal state.
		if panel in ["inventory", "skills"]:
			var side: String = "right" if panel == "inventory" else "left"
			scroll = arena.hud._dock_scrolls[side]
			body = arena.hud._dock_bodies[side]
			modal = arena.hud._dock_roots[side].get_child(0)
		var hud_root: Control = arena.hud.get_node("HUDRoot")
		_expect(body.size.x <= scroll.size.x + 1.0, "Maximum UI/font avoids horizontal overflow: " + panel)
		_expect(modal.get_rect().end.y <= hud_root.size.y + 1.0, "Maximum UI/font frame remains within viewport: " + panel)
		_expect(arena.hud.is_blocking(), "Original panel retains pause: " + panel)

	_expect(arena.state.snapshot() == before, "All current panels preserve canonical build")


func _check_support_children(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control and child.visible:
			var control: Control = child
			_expect(control.get_global_rect().end.x <= support_panel.get_global_rect().end.x + 1.0, "Support control has no horizontal clipping: " + str(child.name))
		_check_support_children(child)


func _finish() -> void:
	print("Skill support UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
