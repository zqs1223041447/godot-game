extends SceneTree
## Bounded v064 actual canonical-model/main consumers. No production test hooks.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
const CharacterSheet = preload("res://scripts/ui/canonical_character_panel.gd")
const ROUTE = ["50986", "39725", "63649", "49806", "6580", "19711", "20010", "23471", "5237", "6363", "29937", "8544", "10661"]
const HYBRID_BRANCH = ["24377", "35568"]
const OLD = ["rootwell", "emberward", "rimeward", "stormward"]
const NEW = ["ironhide", "mistweave", "rootwell", "emberward", "rimeward", "stormward"]
class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
var arena: Node
var checks := 0
var failures := 0
var finished := false
var sections := {}
var report := {}
var old_uid := ""
var new_uid := ""
var off_stats := {}
var on_stats := {}
var changes := 0
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
func roll(id: String) -> Dictionary:
	return {"id":id, "tier":3, "value":int(Gear.affix_definition(id).tiers[2].max)}
func vest(uid: String, ids: Array) -> Dictionary:
	var affixes: Array = []
	for id: String in ids: affixes.append(roll(id))
	return {"id":uid, "base_id":"emberhide_vest", "rarity":"rare", "item_level":16, "affixes":affixes}
func equip(uid: String) -> bool:
	return accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":"body_armour"}, arena.state.revision(), arena.build_save_path), "Actual body armour transaction " + uid)
func resources() -> Array: return [arena.health, arena.mana, arena.shield]
func readonly() -> Dictionary:
	return {"model":var_to_bytes(arena.state.snapshot()), "disk":FileAccess.get_file_as_bytes(arena.build_save_path),
		"saves":arena.state.successful_saves, "rng":arena.rng.state, "critical":arena.critical_runtime.checkpoint()}
func transactional_mark() -> Dictionary:
	return {"readonly":readonly(), "resources":resources(), "entropy":arena._player_evasion_entropy,
		"stats":arena._stats.duplicate(true), "cache":arena.state.cache_diagnostics(), "changes":changes,
		"attempts":arena.state.save_attempts}
func unchanged(before: Dictionary, label: String, attempts: int = 0) -> void:
	check(readonly() == before.readonly, label + " preserves exact build/disk/RNG/critical state and successful saves")
	check(resources() == before.resources and arena._player_evasion_entropy == before.entropy, label + " preserves current resources and attack entropy")
	check(arena._stats == before.stats and arena.state.get_stats() == before.stats, label + " preserves authoritative and actual-main projections")
	check(arena.state.cache_diagnostics() == before.cache and changes == before.changes, label + " emits no build signal and does not invalidate caches")
	check(arena.state.save_attempts == before.attempts + attempts, label + " exact save-attempt accounting")
func set_ir(enabled: bool) -> bool:
	if bool(arena.state.get_defense_conversion_profile().enabled) == enabled: return true
	var before := resources(); var entropy: float = arena._player_evasion_entropy
	var result: Dictionary = arena.state.allocate_passive("10661", 0, arena.state.revision(), arena.build_save_path) if enabled else arena.state.refund_passive("10661", arena.state.revision(), arena.build_save_path)
	if not accepted(result, "Actual Iron Reflexes " + ("allocate" if enabled else "refund")): return false
	check(resources() == before and arena._player_evasion_entropy == entropy, "Keystone transaction neither refills current resources nor changes entropy")
	return true
func casts() -> Dictionary:
	var result := {"basic":arena.state.get_basic_cast()}
	for group: Dictionary in arena.state.snapshot().skill_groups:
		var cast: Dictionary = arena.state.get_group_cast(group.id)
		if cast.get("ok", false): result[group.id] = cast
	return result
func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.incoming_damage_trace.clear(); arena.attack_admission_trace.clear(); arena.burn_trace.clear()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.leech_runtime.clear(); arena.feedback_runtime = arena.FeedbackRuntime.new()
	arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0; arena.elapsed = 0.0
	arena._burn_immunity_until = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._stats = arena.state.get_stats(); arena.health = arena._stats.max_health; arena.shield = 0.0; arena.mana = arena._stats.max_mana
	arena._player_evasion_entropy = 37.0; arena.hud._process(0.0); arena.hud.close_panel()
func prepare_real_model() -> void:
	for uid: String in arena.state.pending_items():
		var place: Dictionary = arena.state.first_bag_position(uid)
		if not check(not place.is_empty(), "Recovery UID has lawful bag cells " + uid): return
		if not accepted(arena.state.move_item(uid, place, arena.state.revision(), arena.build_save_path), "Resolve pending recovery " + uid): return
	if not check(arena.state.pending_items().is_empty(), "Resolve all recovery before actual reward admission"): return
	for ids: Array in [OLD, NEW]:
		var uid := "gear_%06d" % int(arena.state.snapshot().next_item_serial)
		var item := vest(uid, ids)
		if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Actual ownership admits lawful four/six-affix vest"): return
		if ids == OLD: old_uid = uid
		else: new_uid = uid
	check(roll("ironhide").value == 120 and roll("mistweave").value == 450, "Current legal equipment supplies exactly flat armour120/evasion450")
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":10, "xp":0}; candidate.talents.class_id = 4
	candidate.talents.allocated = [ROUTE[0]]; candidate.talents.normal_points = 14; candidate.revision += 1
	if not check(candidate.version == 40 and Model.Rules.reason(candidate).is_empty(), "Lawful schema40 level10 root fixture grants exactly14 earned points"): return
	var path := "user://iron-reflexes-gameplay.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Open isolated lawful-level fixture"): return
	file.store_string(JSON.stringify(candidate, "\t", true, true)); file.close()
	var model := FaultModel.new()
	if not check(model.load_build(path), "Real store loads validated level-budget fixture"): return
	arena._replace_build(model, path)
	model.changed.connect(func() -> void: changes += 1)
	if not equip(new_uid): return
	for id: String in ROUTE.slice(1, ROUTE.size() - 1) + HYBRID_BRANCH:
		if not check(model.available_passives().has(id), "Real connected source node is available " + id): return
		if not accepted(model.allocate_passive(id, 0, model.revision(), path), "Real earned point allocation " + id): return
	if not check(model.talent_points == 1 and model.available_passives().has("10661"), "13 real route/branch points leave one connected Iron Reflexes point"): return
	off_stats = model.get_stats()
	check(not off_stats.has("iron_reflexes") and not off_stats.has("evasion_converted_to_armour"), "Inactive keystone preserves the previous stats key set")
	near(off_stats.armour_increased, 0.06, "Actual35568 contributes six-percent armour")
	near(off_stats.evasion_increased, 0.06, "Actual35568 contributes six-percent evasion")
	near(off_stats.armour, 120.0 * 1.06, "Inactive final armour applies hybrid once")
	near(off_stats.evasion, 465.0 * (1.06 + floorf(off_stats.dexterity / 5.0) * 0.01), "Inactive final evasion includes all raw E and Dexterity")
	near(off_stats.accuracy, (125.0 + 2.0 * off_stats.dexterity) * (1.0 + off_stats.accuracy_increased), "Actual route retains flat accuracy25 and Dexterity accuracy")
	report.route = ROUTE; report.hybrid_branch = HYBRID_BRANCH; report.off_stats = off_stats
	finished = true
func failed_and_successful_transactions() -> void:
	clean(); arena.health *= 0.4; arena.mana *= 0.3
	var old_casts := casts()
	if not check(old_casts.size() > 1 and old_casts.basic.ok, "Real equipped skill and basic attack compile before keystone"): return
	var model: FaultModel = arena.state
	var before := transactional_mark(); model.fail_save = true
	seed(640101); var expected_global := randi(); seed(640101)
	var result := model.allocate_passive("10661", 0, model.revision(), arena.build_save_path)
	check(not result.ok and result.error_code == "save_failed", "Injected allocation save failure rejects complete transaction")
	unchanged(before, "Failed allocation", 1)
	check(randi() == expected_global, "Failed allocation consumes no global RNG")
	model.fail_save = false
	if not set_ir(true): return
	check(model.revision() == JSON.parse_string(before.readonly.disk.get_string_from_utf8()).revision + 1 and model.talent_points == 0 and changes == before.changes + 1, "Successful allocation commits one revision/point/signal")
	on_stats = model.get_stats()
	near(on_stats.evasion, 0.0, "Actual final model has zero evasion")
	near(on_stats.evasion_converted_to_armour, 465.0 * 1.06, "Shared six-percent source counts once and Dexterity is excluded from all raw E")
	near(on_stats.armour, (120.0 + 465.0) * 1.06, "Actual final armour includes original armour and converted raw E once")
	near(on_stats.accuracy, off_stats.accuracy, "Actual accuracy including Dexterity is unchanged")
	var unaffected := on_stats.duplicate(true)
	for key: String in ["armour", "evasion", "iron_reflexes", "evasion_converted_to_armour"]: unaffected.erase(key)
	var previous := off_stats.duplicate(true); previous.erase("armour"); previous.erase("evasion")
	check(unaffected == previous and casts() == old_casts, "Only ratings/active metadata change; all other stats and full compiled skill damage stay identical")
	check(arena._stats == on_stats, "Real build signal refreshes main cached ratings")
	before = transactional_mark(); model.fail_save = true
	seed(640102); expected_global = randi(); seed(640102)
	result = model.refund_passive("10661", model.revision(), arena.build_save_path)
	check(not result.ok and result.error_code == "save_failed", "Injected refund save failure rejects complete transaction")
	unchanged(before, "Failed refund", 1)
	check(randi() == expected_global, "Failed refund consumes no global RNG")
	model.fail_save = false
	if not set_ir(false): return
	check(model.get_stats() == off_stats and casts() == old_casts, "Successful refund restores exact previous stats and casts")
	if not set_ir(true): return
	casts(); before = transactional_mark()
	check(not model.refund_passive("8544", model.revision(), arena.build_save_path).ok, "Disconnecting the actual Iron Reflexes branch rejects")
	unchanged(before, "Disconnected refund")
	check(not model.refund_passive("10661", model.revision() - 1, arena.build_save_path).ok, "Stale refund rejects")
	unchanged(before, "Stale refund")
	report.on_stats = on_stats; report.compiled_skills = old_casts.keys(); finished = true
func readonly_cache_and_equipment() -> void:
	var model: FaultModel = arena.state
	var stats: Dictionary = model.get_stats(); var profile: Dictionary = model.get_defense_conversion_profile()
	var before := transactional_mark()
	check(profile == {"enabled":true, "armour":stats.armour, "evasion":0.0, "converted_armour":stats.evasion_converted_to_armour, "dexterity_evasion_disabled":true}, "Read-only conversion profile reports authoritative final values")
	var panel := CharacterSheet.new(); root.add_child(panel); panel.setup(model)
	check(panel._values.armour.text == "%.2f" % stats.armour and panel._values.evasion.text == "0.00", "Actual C panel displays authoritative model final ratings")
	check(panel._values.accuracy.text == "%d" % roundi(stats.accuracy), "Actual C panel preserves Dexterity accuracy")
	check(panel._defense_cards.armour.tooltip_text.contains("%.2f" % stats.evasion_converted_to_armour), "Actual C tooltip identifies already-included conversion")
	for index: int in range(20):
		model.get_stats(); model.get_defense_conversion_profile(); panel.refresh()
	stats.armour = -1.0; profile.armour = -2.0; profile.enabled = false
	unchanged(before, "Repeated stats/profile/C reads and detached-result mutation")
	panel.free()
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and Planner._same_data(loaded.snapshot(), model.snapshot()) and loaded.get_stats() == on_stats, "Schema40 equipped keystone saves/loads exact build and final stats")
	var kept := resources(); var skill_before := casts()
	if not equip(old_uid): return
	var old: Dictionary = model.get_stats()
	near(old.armour, 15.0 * 1.06, "Switching to same nonrating vest leaves original15 converted")
	near(old.evasion, 0.0, "Equipment switch keeps final evasion zero")
	if not equip(new_uid): return
	near(model.get_stats().armour - old.armour, (120.0 + 450.0) * 1.06, "Actual rating equipment supplies armour and converted evasion gain exactly once")
	check(model.get_stats() == on_stats and arena._stats == on_stats, "Real equipment switch restores full authoritative/main ratings")
	check(resources() == kept and casts() == skill_before, "Equal-resource rating equipment never refills pools or changes compiled damage")
	if not accepted(model.move_item(new_uid, model.first_bag_position(new_uid), model.revision(), arena.build_save_path), "Actual unequip to free bag cells"): return
	near(arena._stats.armour, 15.0 * 1.06, "Unequip retains only converted raw base15")
	near(arena._stats.evasion, 0.0, "Unequip cannot reintroduce evasion while keystone is allocated")
	if not equip(new_uid): return
	if not set_ir(false): return
	check(model.get_stats() == off_stats and not model.get_defense_conversion_profile().dexterity_evasion_disabled, "Refund after equipment switches restores original Dexterity evasion semantics")
	if not set_ir(true): return
	finished = true
func actual_damage_and_evasion() -> void:
	var outcomes := {}
	for enabled: bool in [false, true]:
		if not set_ir(enabled): return
		var stats: Dictionary = arena.state.get_stats(); var by_element := {}
		for element: String in ["physical", "fire", "cold", "lightning"]:
			clean(); var before := readonly(); var hits := 0; var total := 0.0
			for index: int in range(100):
				arena.health = arena._stats.max_health; arena.invulnerable = 0.0
				if arena.hit_player_components({element:40.0}, 0, ["hit", "attack"]):
					hits += 1; total += float(arena.incoming_damage_trace.back().damage_total)
			var probability := Attack.chance(100.0, stats.evasion)
			check(hits == int(round(probability * 100.0)), "Actual100attack count follows existing entropy chance " + element + str(enabled))
			near(arena._player_evasion_entropy, 37.0, "Actual100attack cycle retains exact initial entropy " + element + str(enabled))
			check(readonly() == before, "Actual incoming attack consumer has no save/RNG changes " + element + str(enabled))
			if enabled: check(probability == 1.0 and hits == 100, "Converted zero E uses original100percent hit cap " + element)
			clean(); before = readonly()
			if not check(arena.hit_player_components({element:40.0}, 0, ["hit", "spell"]), "Actual nonattack hit bypasses evasion " + element): return
			var expected: float = 40.0 * (1.0 - minf(0.9, stats.armour / (stats.armour + 200.0))) if element == "physical" else 40.0 * (1.0 - stats[element + "_resistance"])
			near(arena.incoming_damage_trace.back().damage_total, expected, "Actual spell hit applies physical armour or unchanged elemental resistance " + element)
			check(arena.attack_admission_trace.is_empty() and arena._player_evasion_entropy == 37.0 and readonly() == before, "Nonattack consumes neither evasion entropy nor save/RNG " + element)
			by_element[element] = {"hits":hits, "total_damage":total, "chance":probability, "per_hit":expected}
		outcomes["on" if enabled else "off"] = by_element
	check(outcomes.on.physical.per_hit < outcomes.off.physical.per_hit, "Real converted armour reduces physical damage per admitted hit")
	for element: String in ["fire", "cold", "lightning"]:
		near(outcomes.on[element].per_hit, outcomes.off[element].per_hit, "Converted armour never reduces admitted elemental damage " + element)
		check(outcomes.on[element].hits > outcomes.off[element].hits, "Loss of evasion admits more actual elemental attacks " + element)
	report.actual_damage = outcomes; finished = true
func actual_burn_control() -> void:
	var controls: Array = []
	for enabled: bool in [false, true]:
		if not set_ir(enabled): return
		clean(); var before := readonly()
		if not accepted(arena.burn_runtime.apply("player", 0, 71, 20.0, 3.0, 0.0), "Actual persistent burn attaches"): return
		arena.elapsed = 1.0; arena._advance_player_burn(1.0)
		var receipt: Dictionary = arena.burn_trace.back().settlement
		near(receipt.damage_total, 12.0, "Actual burn is reduced only by unchanged40percent fire resistance")
		check(arena.attack_admission_trace.is_empty() and arena._player_evasion_entropy == 37.0, "Actual burn consumes no evasion entropy")
		check(readonly() == before, "Actual burn modifies no build/disk/shared RNG")
		controls.append({"settlement":receipt, "resources":resources(), "status":arena.burn_runtime.status_for("player", 0)})
	check(controls[0] == controls[1], "Actual burn settlement/resources/remaining duration are exact with and without Iron Reflexes")
	report.burn_controls = controls; finished = true
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v064-gameplay-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	if check(arena.save_build(), "Save initial real-main fixture") and accepted(arena.leave_normal_town(arena.world_context().revision), "Enter actual normal practice"):
		for test: Callable in [prepare_real_model, failed_and_successful_transactions, readonly_cache_and_equipment, actual_damage_and_evasion, actual_burn_control]:
			if not section(test): break
	report.merge({"checks":checks, "failures":failures, "sections":sections, "scope":"One bounded actual-main/model fixture; lawful level budget fixture loaded through store; source allocation, equipment and combat use actual APIs. No screenshots or historical full simulation."})
	var output := OS.get_environment("IRON_REFLEXES_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("IRON_REFLEXES_GAMEPLAY ", JSON.stringify({"checks":checks, "failures":failures, "sections":sections}))
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
