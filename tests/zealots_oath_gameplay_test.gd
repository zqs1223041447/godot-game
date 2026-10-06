extends SceneTree
## Bounded actual-model/main coverage for v065. No production test hooks.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const CharacterSheet = preload("res://scripts/ui/canonical_character_panel.gd")
const ROUTE = ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "44202", "23027", "60472", "26270", "64210", "7444", "63425"]
const REGEN = ["55649", "22285", "53793", "37884", "32482", "31033"]
const ES = "38906"
class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
var arena: Node
var checks := 0
var failures := 0
var finished := false
var changes := 0
var sections := {}
var report := {}
var robe_uid := ""
var coat_uid := ""
var charm_uid := ""
var off_stats := {}
var on_stats := {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9), "%s got=%s expected=%s" % [label, actual, expected])
func accepted(result: Variant, label: String) -> bool:
	return check(result is Dictionary and result.get("ok", false), label + ": " + JSON.stringify(result))
func section(test: Callable) -> bool:
	var start := checks; finished = false
	test.call()
	check(finished, "Section completed: " + test.get_method())
	sections[test.get_method()] = checks - start
	return finished and failures == 0
func resources() -> Array: return [arena.health, arena.mana, arena.shield]
func readonly() -> Dictionary:
	return {"model":var_to_bytes(arena.state.snapshot()), "disk":FileAccess.get_file_as_bytes(arena.build_save_path),
		"saves":arena.state.successful_saves, "rng":arena.rng.state, "critical":arena.critical_runtime.checkpoint()}
func runtime() -> Dictionary:
	return {"resources":resources(), "delay":arena.damage_delay, "elapsed":arena.elapsed,
		"flasks":arena.flask_runtime.snapshot(), "leech":arena.leech_runtime.snapshot(),
		"burns":arena.burn_runtime.statuses(), "entropy":arena._player_evasion_entropy}
func transaction_mark() -> Dictionary:
	return {"readonly":readonly(), "runtime":runtime(), "stats":arena._stats.duplicate(true),
		"cache":arena.state.cache_diagnostics(), "changes":changes, "attempts":arena.state.save_attempts}
func unchanged(before: Dictionary, label: String, attempts: int = 0) -> void:
	check(readonly() == before.readonly, label + " preserves exact build/disk/RNG/critical/successful saves")
	check(runtime() == before.runtime, label + " preserves current pools, recovery clocks and attack entropy")
	check(arena._stats == before.stats and arena.state.get_stats() == before.stats, label + " preserves actual-main and model stats")
	check(arena.state.cache_diagnostics() == before.cache and changes == before.changes, label + " emits no signal or cache invalidation")
	check(arena.state.save_attempts == before.attempts + attempts, label + " has exact save attempt accounting")
func roll(id: String) -> Dictionary:
	return {"id":id, "tier":3, "value":int(Gear.affix_definition(id).tiers[2].max)}
func admit(base: String, rarity: String, affixes: Array) -> String:
	var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	var item := {"id":uid, "base_id":base, "rarity":rarity, "item_level":16, "affixes":affixes}
	if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Admit legal owned equipment " + base): return ""
	return uid
func equip(uid: String, slot: String = "body_armour") -> bool:
	return accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":slot}, arena.state.revision(), arena.build_save_path), "Actual equipment transaction " + uid)
func set_oath(enabled: bool) -> bool:
	if bool(arena.state.get_regeneration_profile().enabled) == enabled: return true
	var pools := resources(); var old_rng: int = arena.rng.state; var delay: float = arena.damage_delay
	var result: Dictionary = arena.state.allocate_passive("63425", 0, arena.state.revision(), arena.build_save_path) if enabled else arena.state.refund_passive("63425", arena.state.revision(), arena.build_save_path)
	if not accepted(result, "Actual Zealot's Oath " + ("allocation" if enabled else "refund")): return false
	check(resources() == pools and arena.rng.state == old_rng and arena.damage_delay == delay, "Keystone transaction never refills current pools, resets recharge wait or draws RNG")
	return true
func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear(); arena.damage_trace.clear(); arena.burn_trace.clear()
	arena.monster_runtime.reset(); arena.telegraphs.reset(); arena.burn_runtime.reset(); arena.shock_runtime.reset()
	arena.leech_runtime.clear(); arena.flask_runtime.clear_effects(); arena.feedback_runtime = arena.FeedbackRuntime.new()
	arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 5.0; arena.elapsed = 0.0; arena.wave = 1
	arena._burn_immunity_until = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena.spawn_timer = 10000.0; arena.boss_wave_pending = 0; arena._autosave_timer = 0.0; arena._simulation_accumulator = 0.0
	arena._stats = arena.state.get_stats(); arena.health = arena._stats.max_health * 0.4; arena.mana = arena._stats.max_mana; arena.shield = 20.0
	arena.player_pos = arena.ARENA.get_center(); arena._player_evasion_entropy = 37.0
	arena.hud._process(0.0)
	for unused: int in range(3):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	check(not arena.hud.is_blocking(), "Clean fixture closes the current menu after death-latch refresh")
func prepare_real_model() -> void:
	for uid: String in arena.state.pending_items():
		var place: Dictionary = arena.state.first_bag_position(uid)
		if not check(not place.is_empty(), "Recovery item has lawful bag position " + uid): return
		if not accepted(arena.state.move_item(uid, place, arena.state.revision(), arena.build_save_path), "Resolve recovery " + uid): return
	if not check(arena.state.pending_items().is_empty(), "Resolve recovery before reward admission"): return
	robe_uid = "gear_%06d" % int(arena.state.snapshot().next_item_serial)
	if not check(arena.state._admit_reward_item(Items.fixed_equipment(robe_uid, "guardian_robe")), "Admit existing guardian robe with30shield and3recharge"): return
	if not equip(robe_uid): return
	coat_uid = admit("tidebound_coat", "magic", [roll("lanternveil")])
	charm_uid = admit("wayglass_token", "rare", [roll("lanternveil"), roll("attack_life_leech"), roll("coalglow"), roll("rimeecho")])
	if coat_uid.is_empty() or charm_uid.is_empty() or not equip(charm_uid, "amulet"): return
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":19, "xp":0}; candidate.talents.class_id = 1
	candidate.talents.allocated = [ROUTE[0]]; candidate.talents.normal_points = 23; candidate.revision += 1
	if not check(candidate.version == 41 and Model.Rules.reason(candidate).is_empty(), "Store fixture is legal schema41 Marauder level19 with23earned points"): return
	var path := "user://zealots-oath-gameplay.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Open isolated legal fixture"): return
	file.store_string(JSON.stringify(candidate, "\t", true, true)); file.close()
	var model := FaultModel.new()
	if not check(model.load_build(path), "Actual store loads fixture after recovery/admission/equipment"): return
	arena._replace_build(model, path); model.changed.connect(func() -> void: changes += 1)
	for id: String in ROUTE.slice(1, ROUTE.size() - 1) + REGEN + [ES]:
		if not check(model.available_passives().has(id), "Connected source node available " + id): return
		if not accepted(model.allocate_passive(id, 0, model.revision(), path), "Spend actual earned point " + id): return
	if not check(model.talent_points == 1 and model.available_passives().has("63425"), "22real allocations leave one connected keystone point"): return
	off_stats = model.get_stats()
	check(not off_stats.has("zealots_oath") and not off_stats.has("shield_regeneration_rate"), "Inactive build has no added regeneration stats keys")
	near(off_stats.life_regen_percent, 0.018, "Supported regeneration branch totals1.8percent")
	near(off_stats.life_regen, 10.0 + 0.018 * off_stats.max_health, "Inactive regeneration uses final maximum life")
	near(off_stats.max_shield, (float(Model.Legacy.BASE_STATS.max_shield) + 30.0 + 22.0) * (1.04 + floorf(off_stats.intelligence / 10.0) * 0.01), "Final ES includes legal gear,4percent source and Intelligence")
	check(model.get_regeneration_profile() == {"enabled":false, "life_rate":off_stats.life_regen, "shield_rate":0.0}, "Actual inactive profile is final and complete")
	report.route = ROUTE; report.regeneration_branch = REGEN; report.shield_branch = ES; report.off_stats = off_stats
	finished = true
func failed_and_successful_transactions() -> void:
	clean(); var model: FaultModel = arena.state
	var before := transaction_mark(); model.fail_save = true
	seed(650101); var expected_rng := randi(); seed(650101)
	var result := model.allocate_passive("63425", 0, model.revision(), arena.build_save_path)
	check(not result.ok and result.error_code == "save_failed", "Failed save rejects allocation")
	unchanged(before, "Failed allocation", 1); check(randi() == expected_rng, "Failed allocation uses no global RNG")
	model.fail_save = false
	if not set_oath(true): return
	on_stats = model.get_stats()
	near(on_stats.life_regen, 0.0, "Active model disables all life regeneration")
	near(on_stats.shield_regeneration_rate, 10.0 + 0.018 * on_stats.max_shield, "Active model applies raw10 plus1.8percent of final ES")
	check(model.get_regeneration_profile() == {"enabled":true, "life_rate":0.0, "shield_rate":on_stats.shield_regeneration_rate}, "Actual active profile uses authoritative final rates")
	check(arena._stats == on_stats and model.talent_points == 0 and changes == before.changes + 1, "One commit updates main signal/cache and spends final point")
	var same := on_stats.duplicate(true); same.erase("zealots_oath"); same.erase("shield_regeneration_rate"); same.life_regen = off_stats.life_regen
	check(same == off_stats, "Only redirected regeneration and active metadata differ; recharge remains exact")
	before = transaction_mark(); model.fail_save = true
	seed(650102); expected_rng = randi(); seed(650102)
	result = model.refund_passive("63425", model.revision(), arena.build_save_path)
	check(not result.ok and result.error_code == "save_failed", "Failed save rejects refund")
	unchanged(before, "Failed refund", 1); check(randi() == expected_rng, "Failed refund uses no global RNG")
	model.fail_save = false
	if not set_oath(false): return
	check(model.get_stats() == off_stats, "Actual refund restores exact inactive stats and key set")
	if not set_oath(true): return
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and loaded.snapshot() == model.snapshot() and loaded.get_regeneration_profile() == model.get_regeneration_profile(), "Schema41save reload reproduces allocation and rates")
	report.on_stats = on_stats; finished = true
func actual_resource_stage() -> void:
	var outcomes := {}
	for enabled: bool in [false, true]:
		if not set_oath(enabled): return
		clean(); var before := readonly(); var hp: float = arena.health; var shield: float = arena.shield
		if not accepted(arena.burn_runtime.apply("player", 0, 65, 20.0, 3.0, 0.0), "Attach actual ongoing player burn"): return
		arena.tick(0.5)
		var burned: float = 20.0 * 0.5 * (1.0 - arena._stats.fire_resistance)
		near(arena.health, hp + (0.0 if enabled else off_stats.life_regen * 0.5), "Life regeneration switches in actual tick during burn " + str(enabled))
		near(arena.shield, shield + (on_stats.shield_regeneration_rate * 0.5 if enabled else 0.0) - burned, "ES regeneration continues before actual burn despite recharge delay " + str(enabled))
		near(arena.damage_delay, arena._stats.shield_recharge_delay, "Ongoing burn still restarts only the existing recharge delay")
		near(arena.burn_runtime.status_for("player", 0).remaining, 2.5, "Burn clock continues at original rate")
		check(readonly() == before, "Resource/burn tick has no persistent/RNG/critical changes " + str(enabled))
		outcomes["on" if enabled else "off"] = {"health":arena.health, "shield":arena.shield, "burned":burned}
	clean(); arena.shield = 0.0; arena.damage_delay = 0.0
	var hp: float = arena.health; var before := readonly(); var regen: float = arena._stats.shield_regeneration_rate
	arena.tick(0.5)
	near(arena.shield, (regen + on_stats.shield_recharge_rate) * 0.5, "Regeneration adds independently to existing recharge without multiplying either")
	near(arena.health, hp, "Active regeneration never restores life")
	check(readonly() == before, "Combined recovery adds no save or random draw")
	clean(); arena.shield = 0.0; arena.damage_delay = 0.25; arena.tick(0.5)
	near(arena.shield, regen * 0.5 + on_stats.shield_recharge_rate * 0.25, "Crossing wait threshold gives full regeneration and only remaining recharge time")
	clean(); arena.shield = arena._stats.max_shield - 0.01; hp = arena.health; arena.tick(0.5)
	near(arena.shield, on_stats.max_shield, "Actual regeneration clamps at maximum ES")
	near(arena.health, hp, "Clamped regeneration never spills into life")
	arena.tick(0.5); near(arena.health, hp, "Already-full ES does not restore life")
	report.resource_stage = outcomes; finished = true
func other_recovery_and_lifecycle() -> void:
	clean(); arena.shield = 0.0
	var hp: float = arena.health; var regen: float = arena._stats.shield_regeneration_rate
	if not accepted(arena.use_flask("flask_1"), "Actual life flask works with Zealot's Oath"): return
	var flask_rate: float = arena.flask_runtime.snapshot().active_by_resource.health.rate
	var before := readonly(); arena.tick(0.5)
	near(arena.health, hp + flask_rate * 0.5, "Life flask still restores life through original main resource stage")
	near(arena.shield, regen * 0.5, "Life flask does not add ES recovery")
	check(readonly() == before, "Flask/recovery tick does not persist or draw RNG")
	clean(); hp = arena.health; var shield: float = arena.shield
	arena.pickups.append({"pos":arena.player_pos, "life":3.0}); arena._update_pickups(0.0)
	near(arena.health, hp + 18.0, "Existing pickup still heals exactly18life")
	near(arena.shield, shield, "Pickup healing is not converted")
	clean(); arena.shield = 0.0; hp = arena.health
	var cast: Dictionary = arena.state.get_basic_cast()
	if not check(cast.ok and cast.has("leech") and cast.leech.health.attack_fraction == 0.006, "Legal equipped leech affix reaches actual basic cast"): return
	var target: Dictionary = arena._spawn_monster("crawler", arena.player_pos + Vector2(60, 0), "ordinary", "", [], false)
	target.spawn = 0.0; target.health = 10000.0; target.max_health = 10000.0; target.shield = 0.0; target.armour = 0.0; target.evasion = 0.0
	arena._apply_damage_packet(target, arena.Damage.packet({"physical":100.0}, ["hit", "attack"], "zealot_leech_control"), cast.snapshot, Color.WHITE)
	if not check(not arena.damage_trace.is_empty() and arena.damage_trace.back().has("leech") and not arena.leech_runtime.is_empty(), "Actual attack hit creates existing life leech"): return
	var leech_amount: float = arena.damage_trace.back().leech.health
	arena.enemies.clear(); before = readonly(); arena.tick(0.5)
	near(arena.health, hp + leech_amount, "Existing life leech remains life while keystone is active")
	near(arena.shield, regen * 0.5, "Life leech does not add ES recovery")
	check(readonly() == before, "Leech/recovery tick does not persist or draw RNG")
	clean(); arena.hud.open_panel("inventory"); var paused := runtime(); before = readonly(); arena._process(0.5)
	check(runtime() == paused and readonly() == before, "Actual paused process freezes all resource and recovery clocks")
	arena.hud.close_panel(); arena.invulnerable = 0.0
	if not check(arena.hit_player_components({"chaos":1000000.0}, 0, ["hit", "spell"]) and not arena.alive, "Actual lethal hit enters existing death lifecycle"): return
	var dead := runtime(); before = readonly(); arena._process(0.5)
	check(not arena.alive and arena.health == 0.0 and runtime() == dead and readonly() == before, "Actual dead process cannot regenerate shield/life or revive")
	finished = true
func equipment_readonly_and_zero_sources() -> void:
	clean(); var before := transaction_mark(); var model: FaultModel = arena.state
	model.fail_save = true
	var result := model.move_item(coat_uid, {"kind":"equipment", "slot_id":"body_armour"}, model.revision(), arena.build_save_path)
	check(not result.ok and result.error_code == "save_failed", "Failed equipment save rejects changed regeneration basis")
	unchanged(before, "Failed equipment", 1); model.fail_save = false
	var pools := resources(); var rng: int = arena.rng.state; var delay: float = arena.damage_delay
	if not equip(coat_uid): return
	check(resources() == pools and arena.rng.state == rng and arena.damage_delay == delay, "Actual higher-ES equipment never refills current resources or resets wait/RNG")
	var changed: Dictionary = model.get_stats()
	near(changed.max_shield - on_stats.max_shield, 2.0 * (1.04 + floorf(changed.intelligence / 10.0) * 0.01), "Replacement changes final ES through original capacity rules")
	near(changed.shield_regeneration_rate, 10.0 + 0.018 * changed.max_shield, "Equipment immediately changes percentage regeneration basis")
	near(changed.shield_recharge_rate, on_stats.shield_recharge_rate - 2.4, "Equipment recharge contribution remains independently additive")
	if not equip(robe_uid): return
	check(resources() == pools and arena.rng.state == rng, "Restoring gear preserves pools below both maxima")
	model.get_basic_cast(); before = transaction_mark()
	var panel := CharacterSheet.new(); panel.setup(model)
	check(panel.find_child("Value_life_regen", true, false).text == "0.00" and panel.find_child("Value_shield_regeneration_rate", true, false).text == "%.2f" % on_stats.shield_regeneration_rate, "Actual C panel uses real-model final regeneration profile")
	check(panel.find_child("Value_shield_recharge_rate", true, false).text == "%.2f" % on_stats.shield_recharge_rate, "Actual C panel keeps recharge separate")
	for unused: int in range(3): model.get_regeneration_profile(); panel.refresh()
	panel.free(); unchanged(before, "Repeated C/profile reads")
	for id: String in ["31033", "32482"]:
		if not accepted(model.refund_passive(id, model.revision(), arena.build_save_path), "Actual refund of regeneration source " + id): return
	near(model.get_stats().life_regen_percent, 0.0, "All actual regeneration sources removed")
	check(model.get_regeneration_profile() == {"enabled":true, "life_rate":0.0, "shield_rate":0.0}, "Active keystone without sources grants zero regeneration")
	clean(); pools = resources(); arena.tick(0.5)
	check(resources() == pools, "Zero-source active keystone cannot restore resources during recharge wait")
	if not set_oath(false): return
	check(not model.get_stats().has("zealots_oath") and not model.get_stats().has("shield_regeneration_rate"), "Final refund removes active-only stats keys")
	finished = true
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v065-gameplay-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	if check(arena.save_build(), "Save initial actual-main fixture") and accepted(arena.leave_normal_town(arena.world_context().revision), "Enter actual normal practice"):
		for test: Callable in [prepare_real_model, failed_and_successful_transactions, actual_resource_stage, other_recovery_and_lifecycle, equipment_readonly_and_zero_sources]:
			if not section(test): break
	report.merge({"checks":checks, "failures":failures, "sections":sections, "scope":"Bounded actual main/model resource-stage, equipment, source allocation/refund, persistence atomicity and read-only C consumer. Lawful level19 budget loaded through store; no screenshots or historical full simulation."})
	var output := OS.get_environment("ZEALOTS_OATH_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("ZEALOTS_OATH_GAMEPLAY ", JSON.stringify({"checks":checks, "failures":failures, "sections":sections}))
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
