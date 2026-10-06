extends SceneTree
## External bounded probe for the final Windows PCK, executed by Linux Godot.
## Source invocation only validates parsing and must exit78 at the guard.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const ROUTE = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "44202", "23027", "60472", "26270", "64210", "7444", "63425"]
const REGEN_BRANCH = ["55649", "22285", "53793", "37884", "32482", "31033"]
const ES_BRANCH = "38906"
const ENTRY = "Life Regeneration is applied to Energy Shield instead"
const CHINESE = "生命再生改为作用于能量护盾"
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


func same_json(left: Variant, right: Variant) -> bool:
	# Both sides cross the same JSON boundary before the strict typed comparison.
	return Same._same_data(JSON.parse_string(JSON.stringify(left)), JSON.parse_string(JSON.stringify(right)))


func save_report() -> bool:
	if output.is_empty(): return false
	var report := {
		"ok": completed and failures == 0, "completed": completed,
		"checks": rows.size(), "failures": failures, "results": rows,
		"source_commit": OS.get_environment("V065_SOURCE"),
		"pck_sha256": evidence.get("pck_sha256", ""),
		"schema": 41, "source_policy": 41, "gear_vocabulary": 39, "evidence": evidence,
		"scope": "One bounded Linux same-Windows-PCK migration/equipment/ZealotsOath/main-consumer probe; no source-suite rerun, new golden, performance, screenshot or Windows hardware claim"
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
		label = "Packed ZealotsOath probe exceeded30seconds: " + label
	rows.append({"ok": ok, "label": label})
	if not ok:
		failures += 1
		push_error(label)
		save_report()
		quit(1)
	return ok


func require(ok: bool, label: String) -> bool:
	# Repeated preparation is one narrow check; fail at the exact bad step.
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
		if not transaction(model.move_item(uid, destination, model.revision(), arena.build_save_path), "Restore original recovery UID " + uid, false): return false
	evidence.recovered_items = pending.size()
	return check(model.pending_items().is_empty(), "All original recovery items move through real transactions")


func resources() -> Array:
	return [arena.health, arena.mana, arena.shield]


func clean_resources() -> bool:
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.pickups.clear()
	arena.damage_trace.clear()
	arena.burn_trace.clear()
	arena.monster_runtime.reset()
	arena.telegraphs.reset()
	arena.burn_runtime.reset()
	arena.shock_runtime.reset()
	arena.leech_runtime.clear()
	arena.flask_runtime.clear_effects()
	arena.feedback_runtime = arena.FeedbackRuntime.new()
	arena.alive = true
	arena.invulnerable = 0.0
	arena.elapsed = 0.0
	arena.wave = 1
	arena._burn_immunity_until = 0.0
	arena._burn_step_active = false
	arena._burn_incoming_time = -1.0
	arena.spawn_timer = 10000.0
	arena.boss_wave_pending = 0
	arena._autosave_timer = 0.0
	arena._simulation_accumulator = 0.0
	arena._stats = arena.state.get_stats()
	arena.health = float(arena._stats.max_health) * 0.4
	arena.mana = float(arena._stats.max_mana)
	arena.shield = 0.0
	arena.damage_delay = float(arena._stats.shield_recharge_delay)
	arena.player_pos = arena.ARENA.get_center()
	arena._player_evasion_entropy = 37.0
	arena.hud._process(0.0)
	for unused: int in range(3):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	return require(not arena.hud.is_blocking(), "Actual alive fixture has no blocking menu")


func run() -> void:
	output = OS.get_environment("V065_PACK_QA")
	var fixture := OS.get_environment("V065_OLD_SAVE")
	var pack := OS.get_environment("V065_MAIN_PACK")
	var isolated := OS.get_environment("XDG_DATA_HOME")
	# Godot consumes --main-pack before OS.get_cmdline_args(); an empty
	# globalized res root is the established packed-runtime boundary.
	if output.is_empty() or fixture.is_empty() or pack.is_empty() or OS.get_environment("V065_SOURCE").is_empty() or OS.get_environment("V065_PACK_FONT_SHA256").is_empty() \
		or not ProjectSettings.globalize_path("res://").is_empty() or not pack.is_absolute_path() or not FileAccess.file_exists(pack) \
		or not isolated.begins_with("/tmp/godot-m1-v065-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		print("V065_PACK_GUARD: expected a loaded PCK, complete V065 environment and isolated user data; no runtime checks executed")
		quit(78)
		return
	started_msec = Time.get_ticks_msec()
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create V065_PACK_QA directory")
		quit(1)
		return
	create_timer(30.0).timeout.connect(func() -> void: check(false, "Packed ZealotsOath probe stalled"))
	evidence.pck_sha256 = sha(FileAccess.get_file_as_bytes(pack))
	evidence.resource_root = ProjectSettings.globalize_path("res://")
	var original := FileAccess.get_file_as_bytes(fixture)
	var expected: Variant = JSON.parse_string(original.get_string_from_utf8())
	if not check(expected is Dictionary and expected.get("version") == 40 and expected.get("progress", {}).get("level") == 37 and expected.get("talents", {}).get("allocated", []).has("10661"), "Real frozen-v64 fixture is schema40/level37 with existing Iron Reflexes"): return
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
	if not check(str(ProjectSettings.get_setting("application/config/version")) == "0.65.0" and model.snapshot().version == 41 and Source.CURRENT_SAVE_VERSION == 41 and Gear.CURRENT_VOCABULARY == 39, "Actual packed version0.65/schema41/source41 retains gear39"): return
	expected.version = 41
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path + ".v40-backup.json") == original and same_json(model.snapshot(), expected), "Migration preserves original40 backup bytes and changes only schema across equal JSON boundaries"): return
	var localized: Dictionary = Localization.line_status(ENTRY)
	if not check(Source.node_effect("63425").status == "full" and Localization.node_name("63425") == "狂信者的誓约" and localized.implemented and localized.parser_supported and localized.missing_consumers.is_empty() and Localization.display_line(ENTRY) == CHINESE, "63425 is dynamically full with its exact complete Chinese regeneration rule"): return
	if not check(Source._execution_policy(40) == 40 and Source.node_effect("63425", 0, 40).status != "full" and not Source.line_effect(ENTRY, 40).supported, "Historical schema40 retains source40 and cannot execute the new keystone"): return
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	if not require(font != null, "Load actual packaged font"): return
	font.allow_system_fallback = false
	var glyphs_ok := true
	for character: String in ("狂信者的誓约生命再生能量护盾充能药剂" + CHINESE).split(""):
		glyphs_ok = glyphs_ok and font.has_char(character.unicode_at(0))
	if not check(sha(font.data) == OS.get_environment("V065_PACK_FONT_SHA256") and glyphs_ok, "Actual original-font hash and required Chinese glyphs match without fallback"): return
	evidence.font_sha256 = sha(font.data)
	if not prepare_recovery(model): return
	if not transaction(model.reset_all_passives(model.revision(), arena.build_save_path), "Real full refund removes the original Iron Reflexes route"): return
	if int(model.snapshot().talents.class_id) != 1:
		if not transaction(model.select_class(1, model.revision(), arena.build_save_path), "Real class switch selects Marauder", false): return
	if not check(model.talent_points == 41 and model.snapshot().talents.class_id == 1 and model.snapshot().talents.allocated == [ROUTE[0]], "Real level37 keeps41 earned points at the Marauder root"): return
	var robe: Dictionary = model.snapshot().items.get("guardian_robe", {})
	if not check(Items.validate_instance(robe) and robe.definition_id == "equipment:guardian_robe" and near(Items.definition_for_instance(robe).stats.max_shield, 30.0) and near(Items.definition_for_instance(robe).stats.shield_regen, 3.0), "Original owned legal guardian robe supplies30shield and3existing recharge"): return
	if not transaction(model.move_item("guardian_robe", {"kind": "equipment", "slot_id": "body_armour"}, model.revision(), arena.build_save_path), "Real body-slot transaction equips the existing guardian robe"): return
	for id: String in ROUTE.slice(1, ROUTE.size() - 1) + REGEN_BRANCH + [ES_BRANCH]:
		if not require(model.available_passives().has(id), "Real connected source node available: " + id): return
		if not transaction(model.allocate_passive(id, 0, model.revision(), arena.build_save_path), "Real earned allocation " + id, false): return
	if not check(model.talent_points == 19 and model.available_passives().has("63425") and model.snapshot().talents.allocated.has("31033") and model.snapshot().talents.allocated.has("32482") and model.snapshot().talents.allocated.has(ES_BRANCH), "22actual allocations prepare flat10/percent1.8/shield4percent and the connected keystone"): return
	var off: Dictionary = model.get_stats()
	if not check(off.max_shield > 0.0 and near(off.life_regen_percent, 0.018) and near(off.life_regen, 10.0 + 0.018 * off.max_health) and not off.has("zealots_oath") and not off.has("shield_regeneration_rate") and model.get_regeneration_profile() == {"enabled": false, "life_rate": off.life_regen, "shield_rate": 0.0}, "Inactive actual build regenerates life from final life and has no active-only stat keys"): return
	evidence.route = ROUTE
	evidence.regeneration_branch = REGEN_BRANCH
	evidence.shield_branch = ES_BRANCH
	evidence.equipment_uid = "guardian_robe"
	evidence.off_stats = off
	if not transaction(arena.leave_normal_town(arena.world_context().revision), "Enter actual normal practice"): return
	if not clean_resources(): return
	var pools := resources()
	var delay: float = arena.damage_delay
	var rng_state: int = arena.rng.state
	if not transaction(model.allocate_passive("63425", 0, model.revision(), arena.build_save_path), "Actual23rd earned point allocates ZealotsOath"): return
	var on: Dictionary = model.get_stats()
	var profile: Dictionary = model.get_regeneration_profile()
	var rate: float = 10.0 + 0.018 * float(on.max_shield)
	if not check(near(on.zealots_oath, 1.0) and near(on.life_regen, 0.0) and near(on.shield_regeneration_rate, rate) and profile == {"enabled": true, "life_rate": 0.0, "shield_rate": on.shield_regeneration_rate} and model.talent_points == 18, "Active authoritative profile uses life0 and flat10 plus1.8percent of final maximum shield"): return
	var other_on := on.duplicate(true)
	other_on.erase("zealots_oath")
	other_on.erase("shield_regeneration_rate")
	other_on.life_regen = off.life_regen
	if not check(other_on == off and near(on.shield_recharge_rate, off.shield_recharge_rate) and near(on.shield_recharge_delay, off.shield_recharge_delay), "All other actual stats remain equal and delayed recharge stays independent"): return
	if not check(arena._stats == on and resources() == pools and near(arena.damage_delay, delay) and arena.rng.state == rng_state, "Actual main refresh neither refills pools nor resets recharge wait or RNG"): return
	var hp: float = arena.health
	arena.tick(0.5)
	if not check(near(arena.health, hp) and near(arena.shield, rate * 0.5) and near(arena.damage_delay, delay - 0.5), "Actual tick regenerates shield during recharge wait and restores no life"): return
	evidence.delayed_tick = {"health": arena.health, "shield": arena.shield, "damage_delay": arena.damage_delay}
	if not clean_resources(): return
	arena.damage_delay = 0.0
	hp = arena.health
	arena.tick(0.5)
	if not check(near(arena.shield, (rate + float(on.shield_recharge_rate)) * 0.5) and near(arena.health, hp), "Actual tick adds continuous regeneration to existing recharge exactly once"): return
	evidence.combined_tick = {"health": arena.health, "shield": arena.shield}
	if not clean_resources(): return
	arena.damage_delay = 0.25
	hp = arena.health
	arena.tick(0.5)
	if not check(near(arena.shield, rate * 0.5 + float(on.shield_recharge_rate) * 0.25) and near(arena.health, hp), "Crossing the wait threshold keeps full regeneration and only post-wait recharge time"): return
	if not clean_resources(): return
	arena.shield = float(on.max_shield) - 0.01
	hp = arena.health
	arena.tick(0.5)
	if not check(near(arena.shield, on.max_shield) and near(arena.health, hp), "Actual regeneration clamps at the real maximum shield without spilling into life"): return
	arena.tick(0.5)
	if not check(near(arena.shield, on.max_shield) and near(arena.health, hp), "Already-full shield never redirects surplus regeneration back to life"): return
	if not clean_resources(): return
	hp = arena.health
	if not transaction(arena.use_flask("flask_1"), "Actual life flask admitted with the keystone", false): return
	var flask_rate: float = arena.flask_runtime.snapshot().active_by_resource.health.rate
	arena.tick(0.5)
	if not check(flask_rate > 0.0 and near(arena.health, minf(float(on.max_health), hp + flask_rate * 0.5)) and near(arena.shield, rate * 0.5), "Actual life flask still restores life and adds no converted shield recovery"): return
	evidence.flask_tick = {"health_before": hp, "health": arena.health, "shield": arena.shield, "flask_rate": flask_rate}
	var loaded := Model.new()
	if not check(model.save_build(arena.build_save_path) == OK and loaded.load_build(arena.build_save_path) and same_json(loaded.snapshot(), model.snapshot()) and loaded.get_stats() == on and loaded.get_regeneration_profile() == profile, "Actual schema41 save/reload preserves complete build, final stats and regeneration profile"): return
	if not transaction(model.refund_passive("63425", model.revision(), arena.build_save_path), "Real ZealotsOath refund"): return
	var refunded: Dictionary = model.get_regeneration_profile()
	if not check(model.get_stats() == off and arena._stats == off and refunded == {"enabled": false, "life_rate": off.life_regen, "shield_rate": 0.0} and model.talent_points == 19, "Refund restores exact inactive stats, original life regeneration and the earned point"): return
	if not clean_resources(): return
	hp = arena.health
	arena.tick(0.5)
	if not check(near(arena.health, minf(float(off.max_health), hp + float(off.life_regen) * 0.5)) and near(arena.shield, 0.0), "Actual refunded tick restores life while shield still waits for recharge"): return
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path + ".v40-backup.json") == original, "Original40 backup bytes survive equipment/allocation/save/refund unchanged"): return
	evidence.on_stats = on
	evidence.on_profile = profile
	evidence.refunded_profile = refunded
	completed = true
	if not save_report():
		quit(1)
		return
	print("Packed v65 ZealotsOath probe: %d checks, %d failures" % [rows.size(), failures])
	arena.queue_free()
	await process_frame
	quit(0)
