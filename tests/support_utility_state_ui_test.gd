extends SceneTree
## Focused real-scene utility casts, literal schema migration and connected HUD actions.
## Every write, including scene autosave/settings, is gated by disposable Linux XDG roots.
const Model = preload("res://scripts/build_state.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const Data = preload("res://scripts/game_data.gd")
const Fixture = preload("res://tests/windows/save_fixture.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const FRESH: String = "user://support_utility_fresh.json"
const NEW_IDS: Dictionary = {
	"efficiency": "dash", "quickcast": "ward", "concentrate": "nova",
	"physical_focus": "tornado", "fire_focus": "meteor", "cold_focus": "frost",
	"lightning_focus": "bolt", "swift_projectiles": "bolt", "heavy_projectiles": "bolt",
	"lingering_chill": "frost", "chain_extension": "chain", "chain_reach": "chain",
}
var arena: Node
var checks: int = 0
var failures: int = 0
var utility_rows: int = 0
var completed: bool = false
var writes_allowed: bool = false
var baseline: Dictionary
var settings_bytes: PackedByteArray


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func near(actual: float, expected: float, label: String) -> void:
	expect(absf(actual - expected) < 0.000001, "%s: %.10f / %.10f" % [label, actual, expected])


func isolated_userdata() -> bool:
	if OS.get_name() != "Linux":
		return false
	for key: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var location: String = OS.get_environment(key).simplify_path()
		if not location.begins_with("/tmp/godot-"):
			return false
	var data: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	return OS.get_user_data_dir().simplify_path().begins_with(data + "/")


func write_bytes(path: String, bytes: PackedByteArray) -> void:
	expect(writes_allowed and isolated_userdata() and path.begins_with("user://"), "Fixture write remains in proven disposable userdata")
	if not writes_allowed or not isolated_userdata() or not path.begins_with("user://"):
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	expect(file != null, "Open isolated fixture: " + path)
	if file != null:
		file.store_buffer(bytes)
		file.close()


func run() -> void:
	if not isolated_userdata():
		printerr("Support utility/state/UI writes require isolated Linux /tmp/godot-* XDG data, config and cache roots")
		quit(78)
		return
	writes_allowed = true
	print("SUPPORT_UTILITY_ISOLATION " + OS.get_user_data_dir())
	_migration_and_guards()
	expect(completed, "Migration and guard cases returned normally")
	var fresh := Model.new()
	var original: String = "user://support_utility_source_v12.json"
	write_bytes(original, FileAccess.get_file_as_bytes("res://tests/fixtures/area_v12_build.json"))
	expect(fresh.load_build(original), "Prepare actual rich model from literal v12 build")
	baseline = fresh._snapshot()
	expect(fresh.save_build(FRESH) == OK and fresh.save_build() == OK, "Save actual model for real scene fixture")
	var preferences := Settings.new()
	preferences.ui_scale = 1.1
	preferences.font_scale = 1.2
	preferences.effects_level = 1
	preferences.motion = false
	expect(preferences.save_settings() == OK, "Stage actual isolated presentation preferences")
	settings_bytes = FileAccess.get_file_as_bytes(Settings.PATH)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	expect(arena.start_encounter(["enemy_max_health_120", "enemy_move_speed_110"], arena.run_revision), "Stage real encounter settings through actual scene transaction")
	for test: Callable in [_utility_matrix, _utility_rejections, _state_transactions]:
		completed = false
		test.call()
		expect(completed, "Case returned normally: " + test.get_method())
	completed = false
	await _ui_actions_and_layout()
	expect(completed, "UI actions and layout cases returned normally")
	expect(utility_rows == 8, "Exactly dash4 plus ward4 real-scene legal rows")
	expect(FileAccess.get_file_as_bytes(Settings.PATH) == settings_bytes, "Utility and support UI never rewrite presentation settings")
	print("SUPPORT_UTILITY_ROWS " + str(utility_rows))
	print("Support utility/state/UI: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _migration_and_guards() -> void:
	expect(Model.SAVE_VERSION == 13 and Registry.SUPPORTS.size() == 16 and NEW_IDS.size() == 12, "Schema13 contains sixteen supports with twelve batch additions")
	for version: int in [11, 12]:
		var source: String = FileAccess.get_file_as_string("res://tests/fixtures/area_v%d_build.json" % version)
		var expected: Dictionary = JSON.parse_string(source)
		expect(expected.size() == 17, "Literal historical fixture has all seventeen fields")
		expected.version = 13
		var raw: PackedByteArray = PackedByteArray([239, 187, 191])
		raw.append_array(("\r\n" + source.replace("\n", "\r\n") + "\r\n").to_utf8_buffer())
		var path: String = "user://support_migrate_v%d.json" % version
		write_bytes(path, raw)
		var state := Model.new()
		expect(state.load_build(path), "Literal BOM/CRLF v%d loads" % version)
		expect(state.migrated_from_v12 if version == 12 else state.migrated_from_v11, "Correct historical migration flag")
		expect(Fixture.equivalent(state._snapshot(), expected), "Migration preserves all seventeen independently authored fields")
		expect(state.crafting_balance() == (23 if version == 12 else 17) and state.crafting.revision == (9 if version == 12 else 7), "Wallet and crafting revision are not reset or granted")
		expect(FileAccess.get_file_as_bytes(path) == raw and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Load alone does not overwrite source or create premature backup")
		expect(state.save_build(path) == OK, "First migrated save commits")
		var backup: String = path + ".v%d-backup.json" % version
		expect(FileAccess.get_file_as_bytes(backup) == raw, "First overwrite preserves raw BOM/CRLF source byte for byte")
		var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		expect(Fixture.equivalent(current, expected), "Saved schema13 matches independent historical expectation")
		var reloaded := Model.new()
		expect(reloaded.load_build(path) and not reloaded.migrated_from_v11 and not reloaded.migrated_from_v12 and Fixture.equivalent(reloaded._snapshot(), expected), "Current roundtrip retains gear, jewels, remote graph, positions and old links")
		expect(reloaded.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == raw, "Later save leaves original backup immutable")
		expect(reloaded.unequip("weapon"), "Stage existing rare weapon through actual unequip transaction")
		var quote: Dictionary = reloaded.crafting_quote("salvage", "gear_000042", path)
		expect(quote.ok and reloaded._craft_quotes.size() == 1, "Existing rare weapon issues actual ephemeral quote without granting items")
		expect(reloaded.load_build(path) and reloaded._craft_quotes.is_empty(), "Successful load clears genuinely issued quote")
		var before: Dictionary = reloaded._snapshot()
		var stale: Dictionary = reloaded.execute_crafting(quote.get("handle", ""), quote.get("source_instance", {}))
		expect(not stale.ok and stale.code == "unknown_quote" and reloaded._snapshot() == before, "Cleared quote cannot spend wallet or destroy equipment")
	var literal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/area_v12_build.json"))
	expect(literal.skill_supports.nova == ["breadth"] and literal.skill_supports.meteor == ["breadth"], "v12 fixture contains original area links")
	for id: String in NEW_IDS:
		var skill: String = NEW_IDS[id]
		expect(not Registry.saved_links_reason(skill, [id], 12).is_empty() and Registry.saved_links_reason(skill, [id], 13).is_empty(), "New ID requires schema13: " + id)
		var injected: Dictionary = literal.duplicate(true)
		injected.skill_supports[skill] = [id]
		_rejected_save(injected, "v12_" + id)
		injected.version = 13
		var current_path: String = "user://support_accept_v13_%s.json" % id
		write_bytes(current_path, JSON.stringify(injected, "\t", true, true).to_utf8_buffer())
		var admitted := Model.new()
		expect(admitted.load_build(current_path) and Fixture.equivalent(admitted._snapshot(), injected), "Schema13 accepts exact new link and preserves other sixteen fields: " + id)
	expect(not Registry.saved_links_reason("nova", ["breadth"], 11).is_empty() and Registry.saved_links_reason("nova", ["breadth"], 12).is_empty(), "Existing breadth keeps minimum schema12")
	expect(not Registry.saved_links_reason("bolt", ["pierce"], 9).is_empty() and Registry.saved_links_reason("bolt", ["pierce"], 10).is_empty(), "Existing pierce keeps minimum schema10")
	for mutation: String in ["future14", "duplicate", "unknown", "illegal_skill", "unknown_skill", "third_slot", "v11_breadth"]:
		var invalid: Dictionary = literal.duplicate(true)
		invalid.version = 13
		match mutation:
			"future14": invalid.version = 14
			"duplicate": invalid.skill_supports.dash = ["efficiency", "efficiency"]
			"unknown": invalid.skill_supports.dash = ["unknown_support"]
			"illegal_skill": invalid.skill_supports.dash = ["concentrate"]
			"unknown_skill": invalid.skill_supports["future_skill"] = ["efficiency"]
			"third_slot": invalid.skill_supports.bolt = ["focus", "efficiency", "lightning_focus"]
			"v11_breadth": invalid.version = 11
		_rejected_save(invalid, mutation)
	completed = true


func _rejected_save(candidate: Dictionary, tag: String) -> void:
	var path: String = "user://support_reject_%s.json" % tag
	var raw: PackedByteArray = JSON.stringify(candidate, "\t", true, true).to_utf8_buffer()
	write_bytes(path, raw)
	var state := Model.new()
	var valid: String = "user://support_migrate_v12.json"
	expect(state.load_build(valid), "Load valid rich baseline before rejected candidate")
	expect(state.unequip("weapon"), "Stage existing rare weapon for genuine quote before invalid load")
	var quote: Dictionary = state.crafting_quote("salvage", "gear_000042", valid)
	expect(quote.ok, "Issue actual quote before rejected load")
	var before: Dictionary = state._snapshot()
	expect(not state.load_build(path) and state._snapshot() == before, "Whole invalid candidate rejects without partial mutation: " + tag)
	expect(state._craft_quotes.is_empty(), "Rejected load also invalidates issued quote: " + tag)
	expect(not state.save_block_reason(path).is_empty() and state.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == raw, "Rejected source remains byte-exact and write-protected: " + tag)


func prepare(skill: String, links: Array) -> void:
	expect(arena.state.load_build(FRESH), "Restore complete actual model")
	arena.restart_run()
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.player_pos = Vector2(700, 350)
	arena.player_facing = Vector2.RIGHT
	arena.hud.close_panel()
	if arena.state.skill_slots[0] != skill:
		expect(arena.state.slot_skill(0, skill), "Slot actual utility skill")
	if arena.state.get_skill_supports(skill) != links:
		expect(arena.state.set_skill_supports(skill, links), "Configure valid utility support transaction")
	expect(arena.state.get_skill_supports(skill) == links, "Prepared links are exact")
	arena.mana = 100.0
	arena.cooldowns[skill] = 0.0
	arena.invulnerable = 0.0
	arena.damage_delay = 7.0
	arena.shield = 0.0
	arena.visual_cues.reset()


func stable_build(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	result.erase("skill_slots")
	result.erase("skill_supports")
	return result


func outcome() -> Dictionary:
	return {"mana": arena.mana, "cooldowns": arena.cooldowns.duplicate(true), "position": arena.player_pos,
		"shield": arena.shield, "invulnerable": arena.invulnerable, "damage_delay": arena.damage_delay,
		"enemies": arena.enemies.duplicate(true), "projectiles": arena.projectiles.duplicate(true),
		"cues": arena.visual_cues.cues.duplicate(true), "particles": arena.particles.duplicate(true),
		"floating_text": arena.floating_text.duplicate(true), "damage": arena.total_damage,
		"trace": arena.damage_trace.duplicate(true), "events": arena.event_counts.duplicate(true)}


func stage_context() -> Dictionary:
	return {"selection": arena.encounter_selection(), "profile": arena._encounter_profile.duplicate(true),
		"run_revision": arena.run_revision, "wave": arena.wave, "elapsed": arena.elapsed,
		"ui_scale": arena.visual_settings.ui_scale, "font_scale": arena.visual_settings.font_scale,
		"effects_level": arena.visual_settings.effects_level, "motion": arena.visual_settings.motion,
		"damage_numbers": arena.visual_settings.damage_numbers}


func _utility_matrix() -> void:
	var selections: Array = [[], ["efficiency"], ["quickcast"], ["efficiency", "quickcast"]]
	var mana_factors: Array[float] = [1.0, 0.8, 1.4, 1.12]
	var cooldown_factors: Array[float] = [1.0, 1.15, 0.8, 0.92]
	for skill: String in ["dash", "ward"]:
		for index: int in range(selections.size()):
			prepare(skill, selections[index])
			utility_rows += 1
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			var base_snapshot: Dictionary = arena.state.get_combat_snapshot()
			near(cast.mana, (12.0 if skill == "dash" else 20.0) * mana_factors[index], "Independent utility mana factors")
			near(cast.cooldown, (3.0 if skill == "dash" else 7.0) * cooldown_factors[index], "Independent utility cooldown factors")
			expect(cast.packets.is_empty() and cast.recipe.is_empty() and cast.initial_count == 0, "Resources never create utility hit packet, carrier or recipe")
			expect(cast.snapshot.effects == base_snapshot.effects and cast.snapshot.modifiers == base_snapshot.modifiers, "Resources never add effects or damage modifiers")
			for distance: float in [50.0, 100.0, 300.0]:
				var enemy: Dictionary = arena._spawn_monster("crawler", arena.player_pos + Vector2(distance, 0), "ordinary", "normal", [])
				expect(not enemy.is_empty(), "Real catalog target admitted")
				enemy.spawn = 0.0
			var enemies_before: Array = arena.enemies.duplicate(true)
			var build_before: Dictionary = arena.state._snapshot()
			var from: Vector2 = arena.player_pos
			var health: float = arena.health
			var max_shield: float = arena.get_stats().max_shield
			var stage_before: Dictionary = stage_context()
			expect(arena.cast_skill(0), "Real utility cast accepted: %s/%s" % [skill, str(selections[index])])
			near(arena.mana, 100.0 - cast.mana, "Real cast pays compiled mana exactly once")
			near(arena.cooldowns[skill], cast.cooldown, "Real cast starts exact compiled cooldown")
			near(arena.invulnerable, 0.6 if skill == "dash" else 0.8, "Original invulnerability duration preserved")
			near(arena.shield, 0.0 if skill == "dash" else max_shield * 0.75, "Ward restores 75 percent of actual maximum; dash grants no shield")
			near(arena.damage_delay, 7.0 if skill == "dash" else 0.0, "Original shield recharge delay behavior preserved")
			expect(arena.player_pos.is_equal_approx(from + Vector2(175, 0) if skill == "dash" else from), "Dash175 and stationary ward retain original movement")
			expect(arena.enemies == enemies_before and arena.projectiles.is_empty() and arena.damage_trace.is_empty() and arena.total_damage == 0.0, "Utility resources never hit, slow, knock back or explode on real nearby targets")
			expect(arena.health == health and arena.state._snapshot() == build_before and stable_build(build_before) == stable_build(baseline), "Utility cast preserves actual build, wallet, gear, graph and health")
			expect(stage_context() == stage_before, "Utility helpers preserve actual encounter selection, run state and presentation settings")
			expect(arena.visual_cues.cues.size() == 1 and arena.visual_cues.cues[0].kind == skill, "Only original utility cue emitted")
			var after: Dictionary = outcome()
			expect(not arena.cast_skill(0) and outcome() == after, "Repeated cooling utility cast is entirely inert")
			arena.cooldowns[skill] = 0.0
			arena.mana = cast.mana
			if skill == "ward":
				arena.shield = max_shield * 0.9
				expect(arena.cast_skill(0), "Exact compiled cost accepts ward near shield cap")
				near(arena.shield, max_shield, "Ward never exceeds actual maximum shield")
				near(arena.mana, 0.0, "Exact utility mana is spent without rounded residue")
			else:
				arena.player_pos = arena.ARENA.end - Vector2(arena.PLAYER_RADIUS + 10.0, arena.PLAYER_RADIUS + 10.0)
				var edge: Vector2 = arena.player_pos
				Input.action_press("move_right")
				expect(arena.cast_skill(0), "Exact compiled cost accepts edge dash")
				Input.action_release("move_right")
				expect(arena.player_pos.is_equal_approx(Vector2(arena.ARENA.end.x - arena.PLAYER_RADIUS, edge.y)), "Dash clamps to world boundary using player radius")
				near(arena.mana, 0.0, "Exact dash mana is spent without rounded residue")
	completed = true


func _utility_rejections() -> void:
	for skill: String in ["dash", "ward"]:
		for links: Array in [[], ["efficiency"], ["quickcast"], ["efficiency", "quickcast"]]:
			prepare(skill, links)
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			arena.mana = cast.mana - 0.00001
			var before: Dictionary = outcome()
			expect(not arena.cast_skill(0) and outcome() == before, "Fractionally insufficient mana rejects before every utility effect")
		for invalid: Array in [["efficiency", "efficiency"], ["unknown_support"], ["efficiency", "quickcast", "focus"], ["concentrate"]]:
			prepare(skill, [])
			var before_state: Dictionary = arena.state._snapshot()
			expect(not arena.state.set_skill_supports(skill, invalid) and arena.state._snapshot() == before_state, "Model rejects duplicate, unknown, excess or illegal utility support atomically")
			# Deliberate corruption proves main.cast_skill independently fails closed.
			arena.state.skill_supports[skill] = invalid.duplicate()
			var before: Dictionary = outcome()
			expect(not arena.cast_skill(0) and outcome() == before, "Real runtime rejects corrupted utility links before payment or effects")
			arena.state.skill_supports.erase(skill)
	completed = true


func _state_transactions() -> void:
	var model := Model.new()
	expect(model.load_build(FRESH), "Load rich baseline for cross-provider transactions")
	for links: Array in [["focus", "efficiency"], ["efficiency", "lightning_focus"], ["pierce", "heavy_projectiles"]]:
		expect(model.set_skill_supports("bolt", links), "Two slots work across distinct providers")
		var before: Dictionary = model._snapshot()
		var third: Array = links.duplicate()
		third.append("quickcast")
		expect(not model.set_skill_supports("bolt", third) and model._snapshot() == before, "Global maximum two applies across providers")
	expect(stable_build(model._snapshot()) == stable_build(baseline), "Support state transactions cannot reset wallet, gear, jewel or remote graph grants")
	completed = true


func button(id: String) -> Button:
	return arena.hud.find_child(id, true, false) as Button


func label(id: String) -> Label:
	return arena.hud.find_child(id, true, false) as Label


func panel() -> Control:
	return arena.hud.find_child("SkillSupportPanel", true, false) as Control


func press(id: String) -> void:
	var action: Button = button(id)
	expect(action != null, "Connected HUD action exists: " + id)
	if action != null:
		action.pressed.emit()


func select_skill(skill: String) -> void:
	var index: int = arena.state.skill_slots.find(skill)
	press("SlotButton%d" % (index + 1) if index >= 0 else "SelectSkill_" + skill)
	expect(panel().selected_skill_id == skill and arena.hud._selected_support_skill_id == skill, "Actual slot/library callbacks keep HUD and inspector selection aligned")


func clear_selected_links() -> void:
	while not arena.state.get_skill_supports(panel().selected_skill_id).is_empty():
		press("RemoveSupport1")


func settle() -> void:
	for frame: int in range(4):
		await process_frame


func visible_cards_match(skill: String) -> void:
	var visible: Array[String] = []
	for id: String in Registry.SUPPORTS:
		var card: Control = arena.hud.find_child("SupportOption_" + id, true, false)
		expect(card != null, "Stable support card retained: " + id)
		if card != null and card.visible:
			visible.append(id)
		if not Registry.supports_for_skill(skill).has(id):
			expect(button("AddSupport_" + id).disabled, "Hidden incompatible action remains disabled")
	visible.sort()
	var expected: Array[String] = Registry.supports_for_skill(skill)
	expected.sort()
	expect(visible == expected, "Visible cards exactly equal registry compatibility: " + skill)


func _ui_actions_and_layout() -> void:
	expect(arena.state.load_build(FRESH), "Restore actual rich model before UI callbacks")
	arena.restart_run()
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	arena.hud.close_panel()
	root.size = Vector2i(1280, 720)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.pressed = true
	arena._unhandled_key_input(key)
	await settle()
	expect(arena.hud.is_blocking() and panel() != null, "Actual K key handler opens support UI")
	var elapsed: float = arena.elapsed
	var stage_before: Dictionary = stage_context()
	arena._process(1.0)
	expect(arena.elapsed == elapsed, "Open skills panel pauses actual simulation")
	for skill: String in Data.SKILLS:
		select_skill(skill)
		visible_cards_match(skill)
	select_skill("nova")
	clear_selected_links()
	arena.cooldowns.nova = 2.345
	press("AddSupport_breadth")
	press("AddSupport_efficiency")
	expect(arena.state.get_skill_supports("nova") == ["breadth", "efficiency"] and label("SupportSlotCaption").text.contains("2 / 2"), "Connected adds share two slots across area and resource providers")
	var full: Dictionary = arena.state._snapshot()
	var saved: PackedByteArray = FileAccess.get_file_as_bytes("user://build_save.json")
	for id: String in ["breadth", "efficiency", "concentrate", "lightning_focus"]:
		expect(button("AddSupport_" + id).disabled, "Full or duplicate callback visibly unavailable")
		press("AddSupport_" + id)
	expect(arena.state._snapshot() == full and FileAccess.get_file_as_bytes("user://build_save.json") == saved, "Repeated adds and forced third-provider callbacks are save-inert")
	var stale_remove: Button = button("RemoveSupport1")
	stale_remove.pressed.emit()
	expect(arena.state.get_skill_supports("nova") == ["efficiency"], "Remove callback detaches displayed support")
	var after_remove: Dictionary = arena.state._snapshot()
	saved = FileAccess.get_file_as_bytes("user://build_save.json")
	stale_remove.pressed.emit()
	expect(arena.state._snapshot() == after_remove and FileAccess.get_file_as_bytes("user://build_save.json") == saved, "Repeated stale remove never removes shifted support or saves")
	press("AddSupport_breadth")
	press("RemoveSupport2")
	press("AddSupport_concentrate")
	var cast: Dictionary = arena.state.get_skill_cast("nova")
	near(cast.recipe.radius, 148.8, "Opposed area helpers preserve full precision radius")
	near(cast.recipe.area_multiplier, 0.9216, "Opposed area helpers multiply area before square root")
	expect(label("SupportCastPreview").text.contains("半径 148.8") and label("SupportCastPreview").text.contains("面积 ×0.9216"), "Nova preview shows composed radius and all four area decimals")
	expect(label("SupportCastPreview").tooltip_text.contains("平方根") and label("SupportCastPreview").tooltip_text.contains("0.9216"), "Area detail exposes precise geometry contract")
	near(arena.cooldowns.nova, 2.345, "All UI adds/removes preserve existing cooldown")
	var stale_other_skill: Button = button("RemoveSupport1")
	select_skill("chain")
	var switched: Dictionary = arena.state._snapshot()
	stale_other_skill.pressed.emit()
	expect(arena.state._snapshot() == switched, "Old remove callback cannot affect newly selected skill")
	clear_selected_links()
	press("AddSupport_chain_extension")
	press("AddSupport_chain_reach")
	expect(label("SupportCastPreview").text.contains("最多 7 个目标") and label("SupportCastPreview").text.contains("续跳 286"), "Chain preview means seven total targets and286 follow-up range")
	expect(label("SupportCastPreview").tooltip_text.contains("含首个") and label("SupportCastPreview").tooltip_text.contains("首段 600.00"), "Chain detail keeps first target included and original first range")
	for skill: String in ["dash", "ward"]:
		select_skill(skill)
		clear_selected_links()
		press("AddSupport_efficiency")
		press("AddSupport_quickcast")
		cast = arena.state.get_skill_cast(skill)
		var preview: String = label("SupportCastPreview").text
		expect(preview.contains("%.2f 法力" % cast.mana) and preview.contains("%.2f 秒冷却" % cast.cooldown) and preview.contains("功能效果不变") and preview.contains("不直接造成命中伤害") and not preview.contains("初始投射物"), "Utility preview reports compiled resources and no invented projectile count")
		var incompatible_before: Dictionary = arena.state._snapshot()
		press("AddSupport_concentrate")
		expect(arena.state._snapshot() == incompatible_before, "Forced hidden incompatible callback remains harmless")
	# Swap two already slotted identities through the real library button.
	var ward_index: int = arena.state.skill_slots.find("ward")
	var nova_index: int = arena.state.skill_slots.find("nova")
	if nova_index < 0:
		select_skill("nova")
		nova_index = arena.state.skill_slots.find("nova")
		select_skill("ward")
		ward_index = arena.state.skill_slots.find("ward")
	var links_before_swap: Dictionary = arena.state.skill_supports.duplicate(true)
	press("SlotButton%d" % (nova_index + 1))
	press("SelectSkill_ward")
	expect(arena.state.skill_slots[nova_index] == "ward" and arena.state.skill_slots[ward_index] == "nova" and arena.state.skill_supports == links_before_swap, "Actual library action swaps existing slots and retains both skill-owned links")
	expect(panel().selected_skill_id == "ward" and label("SelectedSupportSkill").text.contains("快捷栏 %d" % (nova_index + 1)), "HUD refresh preserves moved skill identity")
	var before_reopen: Dictionary = arena.state._snapshot()
	for repetition: int in range(2):
		arena.hud.close_panel()
		expect(not arena.hud.is_blocking(), "Closing skills releases modal pause")
		arena._unhandled_key_input(key)
		await settle()
		expect(panel().selected_skill_id == "ward" and arena.state._snapshot() == before_reopen, "K reopen retains selected identity and all links")
	var loaded := Model.new()
	expect(loaded.load_build() and Fixture.equivalent(loaded._snapshot(), arena.state._snapshot()), "Actual HUD autosave reloads complete seventeen-field build")
	expect(stable_build(loaded._snapshot()) == stable_build(baseline), "UI autosave never resets wallet23/revision9, gear, jewels, remote nodes or grants")
	expect(stage_context() == stage_before, "Support UI callbacks preserve staged encounter profile, run state and active preferences")
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = dimensions
		arena.visual_settings.ui_scale = 1.1
		arena.visual_settings.font_scale = 1.2
		arena.hud._apply_presentation()
		for skill: String in Data.SKILLS:
			select_skill(skill)
			await settle()
			visible_cards_match(skill)
			var bounds: Rect2 = panel().get_global_rect()
			var preview: Control = label("SupportCastPreview")
			fits_width(preview, bounds, "Preview fits support panel")
			for id: String in Registry.supports_for_skill(skill):
				var card: Control = arena.hud.find_child("SupportOption_" + id, true, false)
				fits_width(card, bounds, "Compatible card fits panel at720p/2K UI110 font120")
				for control: Control in [button("AddSupport_" + id), label("SupportDescription_" + id), label("SupportReason_" + id)]:
					fits_width(control, card.get_global_rect(), "Support content fits card at720p/2K UI110 font120")
				arena.hud._panel_scroll.ensure_control_visible(button("AddSupport_" + id))
				await settle()
				var viewport: Rect2 = arena.hud._panel_scroll.get_global_rect()
				var action: Rect2 = button("AddSupport_" + id).get_global_rect()
				expect(action.position.y >= viewport.position.y - 1.0 and action.end.y <= viewport.end.y + 1.0, "Compatible add button remains reachable through actual panel scrolling")
	completed = true


func fits_width(control: Control, bounds: Rect2, message: String) -> void:
	var rect: Rect2 = control.get_global_rect()
	expect(rect.position.x >= bounds.position.x - 0.1 and rect.end.x <= bounds.end.x + 0.1, message)
