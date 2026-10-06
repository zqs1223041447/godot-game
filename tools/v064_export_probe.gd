extends SceneTree
## External probe for the final Windows PCK, executed by Linux Godot.
## Source invocation only validates parsing and must exit78 at the guard.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const ROUTE = ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544", "10661"]
const HYBRID_BRANCH = ["24377", "35568"]
const SIX = ["ironhide", "mistweave", "rootwell", "emberward", "rimeward", "stormward"]
const ENTRY = "Converts all Evasion Rating to Armour. Dexterity provides no bonus to Evasion Rating"
const CHINESE = "将全部闪避值转化为护甲；敏捷不再提供闪避值加成"
var arena: Node
var output := ""
var rows: Array[Dictionary] = []
var failures := 0
var completed := false
var evidence: Dictionary = {}
var started_msec := 0


func _initialize() -> void:
	call_deferred("run")


func sha(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func near(actual: float, expected: float) -> bool:
	return is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9)


func save_report() -> bool:
	if output.is_empty(): return false
	var report := {
		"ok": completed and failures == 0, "completed": completed,
		"checks": rows.size(), "failures": failures, "results": rows,
		"source_commit": OS.get_environment("V064_SOURCE"),
		"pck_sha256": evidence.get("pck_sha256", ""),
		"schema": 40, "source_policy": 40, "evidence": evidence,
		"scope": "One bounded Linux same-Windows-PCK migration/equipment/Iron Reflexes/main-consumer probe; no source-suite rerun, new golden, performance, screenshot or Windows hardware claim"
	}
	var file := FileAccess.open(output.path_join("packed-runtime-probe.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write packed-runtime-probe.json")
		return false
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	return true


func check(ok: bool, label: String) -> bool:
	if failures > 0: return false
	if Time.get_ticks_msec() - started_msec >= 30000:
		ok = false
		label = "Packed Iron Reflexes probe exceeded30seconds: " + label
	rows.append({"ok": ok, "label": label})
	if not ok:
		failures += 1
		push_error(label)
		save_report()
		quit(1)
	return ok


func require(ok: bool, label: String) -> bool:
	# Repeated preparation steps belong to one narrow check; fail immediately
	# at the exact offending step rather than inflating successful check counts.
	if not ok: return check(false, label)
	return failures == 0


func transaction(result: Dictionary, label: String, record: bool = true) -> bool:
	var ok: bool = bool(result.get("ok", false))
	if record: return check(ok, label + ": " + str(result.get("reason", "")))
	return require(ok, label + ": " + str(result.get("reason", "")))


func prepare_recovery(model: RefCounted) -> bool:
	var pending: Array = model.pending_items()
	for uid: String in pending:
		var destination: Dictionary = model.first_bag_position(uid)
		if not require(not destination.is_empty(), "Original recovery UID has lawful bag space: " + uid): return false
		var result: Dictionary = model.move_item(uid, destination, model.revision(), arena.build_save_path)
		if not transaction(result, "Restore original recovery UID " + uid, false): return false
	evidence.recovered_items = pending.size()
	return check(model.pending_items().is_empty(), "All original recovery items move through real transactions before acquisition")


func full_vest(uid: String) -> Dictionary:
	var affixes: Array = []
	for id: String in SIX:
		affixes.append({"id": id, "tier": 3, "value": int(Gear.affix_definition(id).tiers[2].max)})
	return {"id": uid, "base_id": "emberhide_vest", "rarity": "rare", "item_level": 16, "affixes": affixes}


func reset_resources() -> void:
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.incoming_damage_trace.clear()
	arena.attack_admission_trace.clear()
	arena.burn_trace.clear()
	arena.burn_runtime.reset()
	arena.shock_runtime.reset()
	arena.leech_runtime.clear()
	arena.feedback_runtime.reset()
	arena.alive = true
	arena.health = float(arena._stats.max_health)
	arena.shield = 0.0
	arena.mana = float(arena._stats.max_mana)
	arena.invulnerable = 0.0
	arena.damage_delay = 0.0
	arena._player_evasion_entropy = 37.0
	arena._burn_immunity_until = 0.0
	arena._burn_step_active = false
	arena._burn_incoming_time = -1.0
	arena.elapsed = 0.0


func spell_hits() -> Dictionary:
	var outcomes: Dictionary = {}
	for element: String in ["physical", "fire", "cold", "lightning"]:
		reset_resources()
		if not require(arena.hit_player_components({element: 40.0}, 0, ["hit", "spell"]), "Actual nonattack hit admitted: " + element): return {}
		if not require(not arena.incoming_damage_trace.is_empty(), "Actual nonattack receipt exists: " + element): return {}
		if not require(arena.attack_admission_trace.is_empty() and near(arena._player_evasion_entropy, 37.0), "Nonattack bypasses attack entropy: " + element): return {}
		outcomes[element] = arena.incoming_damage_trace.back().duplicate(true)
	return outcomes


func burn_receipt() -> Dictionary:
	reset_resources()
	if not transaction(arena.burn_runtime.apply("player", 0, 71, 20.0, 3.0, 0.0), "Attach actual persistent burn", false): return {}
	arena.elapsed = 1.0
	arena._advance_player_burn(1.0)
	if not require(not arena.burn_trace.is_empty(), "Actual persistent burn has settlement"): return {}
	if not require(arena.attack_admission_trace.is_empty() and near(arena._player_evasion_entropy, 37.0), "Burn consumes no attack entropy"): return {}
	return arena.burn_trace.back().settlement.duplicate(true)


func run() -> void:
	output = OS.get_environment("V064_PACK_QA")
	var fixture := OS.get_environment("V064_OLD_SAVE")
	var pack := OS.get_environment("V064_MAIN_PACK")
	var isolated := OS.get_environment("XDG_DATA_HOME")
	# Godot consumes --main-pack before OS.get_cmdline_args(); an empty
	# globalized res root is the established packed-runtime boundary.
	if output.is_empty() or fixture.is_empty() or pack.is_empty() or OS.get_environment("V064_SOURCE").is_empty() or OS.get_environment("V064_PACK_FONT_SHA256").is_empty() \
		or not ProjectSettings.globalize_path("res://").is_empty() or not pack.is_absolute_path() or not FileAccess.file_exists(pack) \
		or not isolated.begins_with("/tmp/godot-m1-v064-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		print("V064_PACK_GUARD: expected a loaded PCK, complete V064 environment and isolated user data; no runtime checks executed")
		quit(78)
		return
	started_msec = Time.get_ticks_msec()
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create V064_PACK_QA directory")
		quit(1)
		return
	create_timer(30.0).timeout.connect(func() -> void: check(false, "Packed Iron Reflexes probe stalled"))
	evidence.pck_sha256 = sha(FileAccess.get_file_as_bytes(pack))
	evidence.resource_root = ProjectSettings.globalize_path("res://")
	var original := FileAccess.get_file_as_bytes(fixture)
	var expected: Variant = JSON.parse_string(original.get_string_from_utf8())
	if not check(expected is Dictionary and expected.get("version") == 39 and expected.get("progress", {}).get("level") == 37 and expected.get("talents", {}).get("class_id") == 1, "Real frozen-v63 fixture is schema39/level37/class1"): return
	evidence.old_save_sha256 = sha(original)
	var file := FileAccess.open("user://build_save.json", FileAccess.WRITE)
	if not require(file != null, "Open isolated original-save destination"): return
	file.store_buffer(original)
	file.close()
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not require(scene != null, "Load actual packed main scene"): return
	arena = scene.instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	arena.hud.close_panel()
	var model: RefCounted = arena.state
	if not check(str(ProjectSettings.get_setting("application/config/version")) == "0.64.0" and model.snapshot().version == 40 and Source.CURRENT_SAVE_VERSION == 40, "Actual packed version0.64/schema40/source40"): return
	expected.version = 40
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path + ".v39-backup.json") == original and Same._same_data(JSON.parse_string(JSON.stringify(model.snapshot())), JSON.parse_string(JSON.stringify(expected))), "Migration keeps original39 backup bytes and changes only schema"): return
	var localized: Dictionary = Localization.line_status(ENTRY)
	if not check(Source.node_effect("10661").status == "full" and Localization.node_name("10661") == "铁反射" and localized.implemented and localized.parser_supported and localized.missing_consumers.is_empty() and Localization.display_line(ENTRY) == CHINESE, "10661 is dynamically full with complete implemented Chinese rule"): return
	var historical_locked := true
	for version: int in range(14, 40):
		historical_locked = historical_locked and Source.node_effect("10661", 0, version).status != "full" and not Source.line_effect(ENTRY, version).supported
	if not check(historical_locked and Source._execution_policy(39) == 38, "Every historical schema14through39 keeps10661 unavailable and39 retains source38"): return
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	if not require(font != null, "Load actual packaged font"): return
	font.allow_system_fallback = false
	var glyphs_ok := true
	for character: String in ("铁反射护甲闪避敏捷命中雾织" + CHINESE).split(""):
		glyphs_ok = glyphs_ok and font.has_char(character.unicode_at(0))
	if not check(sha(font.data) == OS.get_environment("V064_PACK_FONT_SHA256") and glyphs_ok, "Actual original-font hash and required Chinese glyphs match without fallback"): return
	evidence.font_sha256 = sha(font.data)
	if not prepare_recovery(model): return
	if not transaction(model.reset_all_passives(model.revision(), arena.build_save_path), "Real full refund removes old Resolute Technique route"): return
	if not transaction(model.select_class(4, model.revision(), arena.build_save_path), "Real class switch selects Duelist root"): return
	if not require(model.talent_points == 41 and model.snapshot().talents.allocated == [ROUTE[0]], "Real level37 retains41 earned points at Duelist root"): return
	var uid := "gear_%06d" % int(model.snapshot().next_item_serial)
	var vest := full_vest(uid)
	var flat: Dictionary = Gear.get_stats(vest)
	if not check(Gear.validate_instance(vest) and Gear.validate_instance_for_version(vest, 39) and near(flat.armour, 120.0) and near(flat.evasion, 450.0), "Existing legal six-affix chest supplies exact flat armour120/evasion450"): return
	if not check(model._admit_reward_item(Items.wrap_equipment(vest)) and model.save_build(arena.build_save_path) == OK, "Real reward admission owns selected UID and persists"): return
	if not transaction(model.move_item(uid, {"kind": "equipment", "slot_id": "body_armour"}, model.revision(), arena.build_save_path), "Real body-slot equipment transaction"): return
	for id: String in ROUTE.slice(1, ROUTE.size() - 1) + HYBRID_BRANCH:
		if not require(model.available_passives().has(id), "Real connected source node available: " + id): return
		if not transaction(model.allocate_passive(id, 0, model.revision(), arena.build_save_path), "Real earned allocation " + id, false): return
	if not check(model.talent_points == 28 and model.available_passives().has("10661") and model.snapshot().talents.allocated.has("35568"), "Real12-point route is prepared with separate35568 hybrid6percent branch"): return
	var off: Dictionary = model.get_stats()
	if not check(near(off.armour, 127.2) and near(off.evasion, 604.5) and near(off.armour_increased, 0.06) and near(off.evasion_increased, 0.06) and near(off.dexterity, 123.0) and near(off.accuracy, 371.0) and not off.has("iron_reflexes") and not off.has("evasion_converted_to_armour"), "Inactive real build retains armour127.2/evasion604.5/Dexterity123/accuracy371"): return
	evidence.route = ROUTE
	evidence.hybrid_branch = HYBRID_BRANCH
	evidence.item = vest
	evidence.off_stats = off
	if not transaction(arena.leave_normal_town(arena.world_context().revision), "Enter actual normal practice"): return
	var off_hits := spell_hits()
	if failures > 0: return
	var off_burn := burn_receipt()
	if failures > 0: return
	if not check(off_hits.size() == 4 and near(off_hits.physical.damage_total, 40.0 * (1.0 - off.armour / (off.armour + 200.0))) and near(off_hits.fire.damage_total, 24.0) and near(off_hits.cold.damage_total, 30.0) and near(off_hits.lightning.damage_total, 30.0) and near(off_burn.damage_total, 12.0), "Actual inactive physical/elemental hits and burn establish existing definitions"): return
	var pools := [arena.health, arena.mana, arena.shield]
	var entropy: float = arena._player_evasion_entropy
	if not transaction(model.allocate_passive("10661", 0, model.revision(), arena.build_save_path), "Real12th route point allocates Iron Reflexes"): return
	var on: Dictionary = model.get_stats()
	if not check(near(on.armour, 620.1) and near(on.evasion, 0.0) and near(on.evasion_converted_to_armour, 492.9) and near(on.iron_reflexes, 1.0) and model.talent_points == 27, "Actual conversion produces armour620.1/evasion0/converted492.9 with hybrid counted once"): return
	var other_on := on.duplicate(true)
	var other_off := off.duplicate(true)
	for key: String in ["armour", "evasion", "iron_reflexes", "evasion_converted_to_armour"]: other_on.erase(key)
	for key: String in ["armour", "evasion"]: other_off.erase(key)
	if not check(other_on == other_off and near(on.accuracy, 371.0) and arena._stats == on and pools == [arena.health, arena.mana, arena.shield] and near(arena._player_evasion_entropy, entropy), "Accuracy and all other stats stay identical; real main refresh neither refills pools nor changes entropy"): return
	var profile: Dictionary = model.get_defense_conversion_profile()
	if not check(profile == {"enabled": true, "armour": on.armour, "evasion": 0.0, "converted_armour": on.evasion_converted_to_armour, "dexterity_evasion_disabled": true}, "Actual defense profile exposes the same final authoritative values"): return
	var on_hits := spell_hits()
	if failures > 0: return
	if not check(near(on_hits.physical.damage_total, 40.0 * (1.0 - on.armour / (on.armour + 200.0))) and on_hits.physical.damage_total < off_hits.physical.damage_total, "Actual converted armour reduces physical hit damage"): return
	if not check(near(on_hits.fire.damage_total, off_hits.fire.damage_total) and near(on_hits.cold.damage_total, off_hits.cold.damage_total) and near(on_hits.lightning.damage_total, off_hits.lightning.damage_total), "Actual fire/cold/lightning hit damage remains unchanged"): return
	var on_burn := burn_receipt()
	if failures > 0: return
	if not check(on_burn == off_burn and near(on_burn.damage_total, 12.0), "Actual burn keeps complete original settlement and40percent fire resistance"): return
	reset_resources()
	var attack_hit: bool = arena.hit_player_components({"lightning": 40.0}, 0, ["hit", "attack"])
	if not check(attack_hit and arena.attack_admission_trace.size() == 1 and near(arena.attack_admission_trace.back().chance, 1.0) and near(arena._player_evasion_entropy, 37.0) and near(arena.incoming_damage_trace.back().damage_total, 30.0), "Actual zero-evasion attack uses existing100percent hit cap without reducing elemental damage"): return
	var loaded := Model.new()
	if not check(model.save_build(arena.build_save_path) == OK and loaded.load_build(arena.build_save_path) and Same._same_data(loaded.snapshot(), model.snapshot()) and loaded.get_stats() == on and loaded.get_defense_conversion_profile() == profile, "Actual schema40 save/reload preserves complete build, final stats and conversion profile"): return
	if not transaction(model.refund_passive("10661", model.revision(), arena.build_save_path), "Real Iron Reflexes refund"): return
	var refunded: Dictionary = model.get_defense_conversion_profile()
	if not check(model.get_stats() == off and arena._stats == off and not refunded.enabled and not refunded.dexterity_evasion_disabled and near(refunded.converted_armour, 0.0) and model.talent_points == 28, "Refund restores exact prior ratings/accuracy/profile and earned point"): return
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path + ".v39-backup.json") == original, "Original39 backup bytes remain intact after equipment/allocation/save/refund"): return
	evidence.on_stats = on
	evidence.on_profile = profile
	evidence.off_hits = off_hits
	evidence.on_hits = on_hits
	evidence.off_burn = off_burn
	evidence.on_burn = on_burn
	evidence.refunded_profile = refunded
	completed = true
	if not save_report():
		quit(1)
		return
	print("Packed v64 Iron Reflexes probe: %d checks, %d failures" % [rows.size(), failures])
	arena.queue_free()
	await process_frame
	quit(0)
