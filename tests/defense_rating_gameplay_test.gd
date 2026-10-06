extends SceneTree
## Bounded v062 real-model/main consumers; no production hooks or visual gate.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
const CharacterSheet = preload("res://scripts/ui/canonical_character_panel.gd")
const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
const OLD = ["rootwell", "emberward", "rimeward", "stormward"]
const NEW = ["ironhide", "mistweave", "rootwell", "emberward", "rimeward", "stormward"]
const OPS = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
var arena: Node
var checks := 0
var failures := 0
var serial := 0
var finished := false
var sections := {}
var report := {}
var old_uid := ""
var new_uid := ""
var route: Array = []
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
func next_uid(model: Model) -> String: return "gear_%06d" % int(model.snapshot().next_item_serial)
func roll(id: String) -> Dictionary:
	return {"id":id, "tier":3, "value":int(Gear.affix_definition(id).tiers[2].max)}
func vest(uid: String, rarity: String = "rare", ids: Array = NEW) -> Dictionary:
	var affixes: Array = []
	if rarity != "normal":
		for id: String in ids: affixes.append(roll(id))
	return {"id":uid, "base_id":"emberhide_vest", "rarity":rarity, "item_level":16, "affixes":affixes}
func prepare_recovery(model: Model, path: String) -> bool:
	for uid: String in model.pending_items():
		var place: Dictionary = model.first_bag_position(uid)
		if not check(not place.is_empty(), "Recovery UID has lawful bag cells " + uid): return false
		if not accepted(model.move_item(uid, place, model.revision(), path), "Actual recovery-to-bag transaction " + uid): return false
	return check(model.pending_items().is_empty(), "All recovery ownership resolved before acquisition")
func equip(uid: String) -> bool:
	return accepted(arena.state.move_item(uid, {"kind":"equipment", "slot_id":"body_armour"}, arena.state.revision(), arena.build_save_path), "Actual body armour equip " + uid)
func mark(model: Model, path: String) -> Dictionary:
	return {"model":var_to_bytes(model.snapshot()), "disk":FileAccess.get_file_as_bytes(path), "attempts":model.save_attempts, "saves":model.successful_saves}
func unchanged(model: Model, path: String, before: Dictionary, label: String, attempts: int = 0) -> void:
	check(var_to_bytes(model.snapshot()) == before.model and FileAccess.get_file_as_bytes(path) == before.disk, label + " preserves all state and exact disk bytes")
	check(model.save_attempts == before.attempts + attempts and model.successful_saves == before.saves, label + " preserves save accounting")
func readonly() -> Dictionary:
	return {"saved":mark(arena.state, arena.build_save_path), "rng":arena.rng.state, "critical":arena.critical_runtime.checkpoint()}
func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.incoming_damage_trace.clear(); arena.attack_admission_trace.clear(); arena.burn_trace.clear()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.leech_runtime.clear(); arena.feedback_runtime = arena.FeedbackRuntime.new()
	arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0; arena.elapsed = 0.0
	arena._burn_immunity_until = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._stats = arena.state.get_stats(); arena.health = arena._stats.max_health; arena.shield = 0.0; arena.mana = arena._stats.max_mana
	arena._player_evasion_entropy = 0.0; arena.hud._process(0.0); arena.hud.close_panel()
func shortest_rating_route() -> Array:
	var start: String = Source.Data.start_for_class(4)
	var paths := {start:[start]}; var queue: Array[String] = [start]; var index := 0
	while index < queue.size():
		var current: String = queue[index]; index += 1
		for id: String in Source.Data.adjacency(current):
			var node: Dictionary = Source.Data.node(id)
			if paths.has(id) or node.type in ["mastery", "start"] or node.source.get("isProxy", false) or node.source.get("isBlighted", false): continue
			var effect := Source.node_effect(id, 0, 38)
			if effect.status != "full": continue
			paths[id] = paths[current] + [id]
			var ratings := {}
			for grant: Dictionary in effect.grants:
				if grant.stat in ["armour_increased", "evasion_increased"] and grant.value > 0.0: ratings[grant.stat] = true
			if ratings.size() == 2: return paths[id]
			queue.append(id)
	return []
func rating_delta(label: String) -> void:
	if not equip(old_uid): return
	var old: Dictionary = arena.state.get_stats()
	if not equip(new_uid): return
	var current: Dictionary = arena.state.get_stats()
	var armour_factor := 1.0 + float(current.armour_increased)
	var evasion_factor := 1.0 + float(current.evasion_increased) + floorf(float(current.dexterity) / 5.0) * 0.01
	near(current.armour - old.armour, 120.0 * armour_factor, label + " global flat120 armour receives aggregate increase once")
	near(current.evasion - old.evasion, 450.0 * evasion_factor, label + " global flat450 evasion receives increase and Dexterity once")
	near(current.evasion, 465.0 * evasion_factor, label + " original15 and equipment450 combine before final multiplier")
	if current.armour_increased > 0.0:
		check(not is_equal_approx(current.armour - old.armour, 120.0 * armour_factor * armour_factor), label + " armour is not squared")
	if current.evasion_increased > 0.0:
		check(not is_equal_approx(current.evasion - old.evasion, 450.0 * evasion_factor * evasion_factor), label + " evasion is not squared")
	report[label] = {"baseline":old, "equipped":current, "armour_factor":armour_factor, "evasion_factor":evasion_factor}
func owned_equipment_source() -> void:
	if not prepare_recovery(arena.state, arena.build_save_path): return
	for ids: Array in [OLD, NEW]:
		var item := vest(next_uid(arena.state), "rare", ids)
		if not check(Gear.validate_instance(item) and arena.state._admit_reward_item(Items.wrap_equipment(item)), "Legal four/six-affix vest enters actual bag"): return
		if ids == OLD: old_uid = item.id
		else: new_uid = item.id
	rating_delta("root_only")
	route = shortest_rating_route()
	if not check(route.size() > 1 and route.size() <= 124, "Fully implemented connected armour/evasion source path exists"): return
	var candidate: Dictionary = arena.state.snapshot()
	candidate.progress = {"level":maxi(1, route.size() - 5), "xp":0}; candidate.talents.class_id = 4
	candidate.talents.allocated = [route[0]]; candidate.talents.normal_points = mini(candidate.progress.level + 4, 123); candidate.revision += 1
	if not check(Model.Rules.reason(candidate).is_empty(), "Earned-level root fixture obeys source budget"): return
	if not accepted(arena.state._commit(candidate, arena.build_save_path), "Persist lawful source root"): return
	for id: String in route.slice(1):
		if not check(arena.state.available_passives().has(id), "Source path is actually available " + id): return
		if not accepted(arena.state.allocate_passive(id, 0, arena.state.revision(), arena.build_save_path), "Spend real source point " + id): return
	var stats: Dictionary = arena.state.get_stats()
	check(stats.armour_increased > 0.0 and stats.evasion_increased > 0.0, "Real allocated source supplies both existing increases")
	rating_delta("source_allocated")
	var before := readonly()
	var panel := CharacterSheet.new(); root.add_child(panel); panel.setup(arena.state)
	check(panel._values.armour.text == "%.2f" % stats.armour and panel._values.evasion.text == "%.2f" % stats.evasion, "Existing C page shows authoritative final rating values")
	var card := Presenter.view(arena.state, new_uid)
	for id: String in ["ironhide", "mistweave"]:
		check(card.affix_lines.has(Gear.affix_display(roll(id)).line), "Existing item Presenter consumes flat formatter " + id)
	check(readonly() == before, "C metadata and Presenter are read-only with no save or RNG")
	panel.queue_free()
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and Planner._same_data(loaded.snapshot(), arena.state.snapshot()) and loaded.get_stats() == stats, "New equipped ratings plus actual source allocations reload exactly")
	if not accepted(arena.state.refund_passive(route.back(), arena.state.revision(), arena.build_save_path), "Refund reachable terminal rating node"): return
	rating_delta("source_refunded")
	if not accepted(arena.state.allocate_passive(route.back(), 0, arena.state.revision(), arena.build_save_path), "Reallocate same connected rating node"): return
	near(arena._stats.armour, stats.armour, "Real build signal restores armour once after refund/reallocate")
	near(arena._stats.evasion, stats.evasion, "Real build signal restores evasion once after refund/reallocate")
	if not accepted(arena.state.move_item(new_uid, arena.state.first_bag_position(new_uid), arena.state.revision(), arena.build_save_path), "Actual unequip returns rating UID to bag"): return
	near(arena._stats.armour, 0.0, "Actual unequip removes flat equipment armour")
	near(arena._stats.evasion, 15.0 * (1.0 + stats.evasion_increased + floorf(stats.dexterity / 5.0) * 0.01), "Actual unequip restores raw base15 before existing source")
	if not equip(new_uid): return
	report.source_route = route; finished = true
func actual_attacks_and_nonattacks() -> void:
	var results := {}
	for uid: String in [old_uid, new_uid]:
		if not equip(uid): return
		var profile: Dictionary = arena.state.get_stats(); var by_element := {}
		for element: String in ["physical", "cold", "lightning"]:
			clean(); var hits := 0; var damage := 0.0; var before := readonly(); var chance := Attack.chance(100.0, profile.evasion)
			for index: int in range(100):
				arena.health = arena._stats.max_health; arena.invulnerable = 0.0
				if arena.hit_player_components({element:40.0}, 0, ["hit", "attack"]):
					hits += 1; damage += float(arena.incoming_damage_trace.back().damage_total)
			check(hits == int(round(chance * 100.0)), "Actual100 attacks match deterministic rounded entropy chance " + element)
			near(arena._player_evasion_entropy, 0.0, "100 actual attacks complete exact entropy cycle " + element)
			check(readonly() == before, "Actual incoming attack rating consumer changes no save/shared RNG " + element)
			by_element[element] = {"hits":hits, "damage":damage, "chance":chance}
			clean(); before = readonly()
			if not check(arena.hit_player_components({element:40.0}, 0, ["hit", "spell"]), "Nonattack hit bypasses evasion " + element): return
			var expected := 40.0 * (1.0 - minf(0.9, profile.armour / (profile.armour + 200.0))) if element == "physical" else 30.0
			near(arena.incoming_damage_trace.back().damage_total, expected, "Nonattack uses physical armour only, preserves elemental resistance " + element)
			check(arena.attack_admission_trace.is_empty() and arena._player_evasion_entropy == 0.0 and readonly() == before, "Nonattack has no evasion or RNG/save side effect " + element)
		results[uid] = by_element
	for element: String in ["physical", "cold", "lightning"]:
		check(results[new_uid][element].hits < results[old_uid][element].hits, "Actual new evasion reduces admitted attacks " + element)
		check(results[new_uid][element].damage < results[old_uid][element].damage, "Actual new ratings reduce total100attack damage " + element)
		if element != "physical": near(results[new_uid][element].damage / results[new_uid][element].hits, 30.0, "Admitted elemental attack unchanged by armour " + element)
	report.actual_attacks = results; finished = true
func burn_and_resource_order() -> void:
	var controls: Array = []
	for uid: String in [old_uid, new_uid]:
		if not equip(uid): return
		clean(); var before := readonly()
		if not accepted(arena.burn_runtime.apply("player", 0, 71, 20.0, 3.0, 0.0), "Actual persistent burn attaches"): return
		arena.elapsed = 1.0; arena._advance_player_burn(1.0)
		var receipt: Dictionary = arena.burn_trace.back().settlement
		near(receipt.damage_total, 12.0, "Burn applies same40percent fire resistance")
		check(arena.attack_admission_trace.is_empty() and arena._player_evasion_entropy == 0.0, "Existing burn never reads attack entropy")
		check(readonly() == before, "Burn uses no new saved rating state or RNG")
		controls.append({"settlement":receipt, "resources":[arena.health, arena.mana, arena.shield], "status":arena.burn_runtime.status_for("player", 0)})
	check(controls[0] == controls[1], "Real burn settlement/resources/remaining duration are exactly equal with and without ratings")
	# Synthetic resource capacities/guard isolate the established post-mitigation
	# shield -> mana guard -> life order; armour/evasion remain real equipment stats.
	clean(); arena._stats.damage_taken_from_mana_before_life = 0.4
	arena.health = 1000.0; arena.shield = 10.0; arena.mana = 100.0; arena._player_evasion_entropy = 99.0
	var armour: float = arena._stats.armour
	if not check(arena.hit_player_components({"physical":100.0}, 0, ["hit", "attack"]), "Real rating attack admitted for synthetic resource-order control"): return
	var hit: Dictionary = arena.incoming_damage_trace.back()
	var mitigated := 100.0 * (1.0 - minf(0.9, armour / (armour + 500.0)))
	near(hit.damage_total, mitigated, "Actual armour mitigates before resource spending")
	near(hit.shield_spent, 10.0, "Actual receipt spends shield first")
	near(hit.mana_spent, (mitigated - 10.0) * 0.4, "Actual receipt spends mana on postshield share")
	near(hit.health_lost, (mitigated - 10.0) * 0.6, "Actual receipt spends residual life last")
	near(arena.health, 1000.0 - hit.health_lost, "Actual life pool agrees with spent receipt")
	near(arena.mana, 100.0 - hit.mana_spent, "Actual mana pool agrees with spent receipt")
	report.burn_exact_controls = controls; report.synthetic_resource_order = hit; finished = true
func craft_fixture(operation: String, funds: int = 200) -> Dictionary:
	serial += 1; var model := FaultModel.new(); var path := "user://rating-craft-%d.json" % serial
	if not prepare_recovery(model, path): return {}
	var source := vest(next_uid(model))
	if operation == "enchant": source = vest(source.id, "normal")
	elif operation in ["augment", "elevate"]: source = vest(source.id, "magic", ["ironhide"])
	if not check(Gear.validate_instance(source) and model._admit_reward_item(Items.wrap_equipment(source)), "Actual lawful selected source admitted " + operation): return {}
	if funds > 0 and not check(model._admit_reward_item(Items.calibration_shard("item_%06d" % int(model.snapshot().next_item_serial), funds)), "Actual shard stack admitted"): return {}
	if not check(model.save_build(path) == OK, "Craft fixture persists"): return {}
	return {"model":model, "path":path, "source":source}
func actual_crafts() -> void:
	var outputs := {}
	for operation: String in OPS:
		var f := craft_fixture(operation)
		if f.is_empty(): return
		var model: FaultModel = f.model; var source: Dictionary = f.source; var original := model.snapshot(); var before := mark(model, f.path)
		var rng := RandomNumberGenerator.new(); rng.seed = 62017; var rng_before := rng.state
		seed(62018); var expected_global := randi(); seed(62018)
		var quote := model.crafting_quote(operation, source.id, f.path)
		if not accepted(quote, "Actual selectedUID craft quote " + operation): return
		check(not quote.has("seed") and not quote.has("instance") and not quote.has("candidate"), "Quote leaks no future roll")
		model.cancel_crafting_quote(quote.handle)
		check(not model.execute_crafting(quote.handle, source).ok, "Cancelled selected quote cannot execute")
		unchanged(model, f.path, before, "Cancelled " + operation)
		quote = model.crafting_quote(operation, source.id, f.path)
		if not accepted(quote, "New selectedUID quote " + operation): return
		var wrong := source.duplicate(true); wrong.id = "gear_999999"
		check(not model.execute_crafting(quote.handle, wrong).ok, "Different selected UID rejected")
		unchanged(model, f.path, before, "WrongUID " + operation)
		model.fail_save = true
		check(not model.execute_crafting(quote.handle, source).ok, "Injected write error rejects whole craft " + operation)
		unchanged(model, f.path, before, "Failed save " + operation, 1)
		model.fail_save = false
		var economics := Craft.operation_quote(source, operation)
		var seed_text := JSON.stringify({"rules":Craft.seed_rules_version(operation), "revision":original.crafting.revision, "item":source}, "", true, true)
		var expected := Craft.operation_plan(source, operation, seed_text.sha256_text().substr(0, 15).hex_to_int())
		if not accepted(model.execute_crafting(quote.handle, source), "Same authority retry commits " + operation): return
		check(rng.state == rng_before and randi() == expected_global, "Quote/cancel/wrongUID/save failure/retry consume no RNG " + operation)
		check(model.crafting_balance() == 200 - int(economics.cost.get(Craft.MATERIAL_ID, 0)) + int(economics.materials.get(Craft.MATERIAL_ID, 0)), "Actual exact shard debit/credit " + operation)
		var after := model.snapshot()
		check(after.version == 39 and after.crafting.revision == original.crafting.revision + 1 and after.revision == original.revision + 1, "One schema39 craft revision " + operation)
		check(after.journey == original.journey and after.next_item_serial == original.next_item_serial, "Craft keeps journey and item serial " + operation)
		if operation == "salvage": check(model.item(source.id).is_empty(), "Salvage consumes selected rating UID")
		else:
			var actual: Dictionary = model.item(source.id).payload
			check(actual == expected.instance and Gear.validate_instance(actual) and model.location(source.id) == original.locations[source.id], "Exact current-rules craft output preserves owned UID and cells " + operation)
			outputs[operation] = actual
		var loaded := Model.new()
		check(loaded.load_build(f.path) and Planner._same_data(loaded.snapshot(), after), "Sixcraft schema39 full roundtrip " + operation)
		before = mark(model, f.path)
		check(not model.execute_crafting(quote.handle, source).ok, "Completed authority cannot charge twice")
		unchanged(model, f.path, before, "Replay " + operation)
		if operation != "salvage":
			var empty := craft_fixture(operation, 0)
			if empty.is_empty(): return
			before = mark(empty.model, empty.path)
			seed(62019); expected_global = randi(); seed(62019)
			check(not empty.model.crafting_quote(operation, empty.source.id, empty.path).ok and randi() == expected_global, "Insufficient shards reject before RNG " + operation)
			unchanged(empty.model, empty.path, before, "Insufficient shards " + operation)
	report.actual_craft_outputs = outputs; finished = true
func full_bag_and_natural_supply() -> void:
	var f := craft_fixture("recalibrate")
	if f.is_empty(): return
	var model: FaultModel = f.model; var candidate := model.snapshot()
	var context := Model.Migration.paged_location_context(candidate, model._socket_ids)
	var occupied: Dictionary = Locations.validate_current(Items.metadata_for_items(candidate.items), candidate.locations, context).occupied_cells
	for page: int in range(2):
		for y: int in range(10):
			for x: int in range(12):
				if occupied.has("bag:%d:%d:%d" % [page, x, y]): continue
				var uid := "item_%06d" % int(candidate.next_item_serial); candidate.next_item_serial += 1
				candidate.items[uid] = Model.Gems.create_instance(uid, "skill:bolt")
				candidate.locations[uid] = {"kind":"bag", "page":page, "x":x, "y":y}
	if not check(Model.Rules.reason(candidate).is_empty(), "Full240cell owned fixture is valid"): return
	model._accept_memory(candidate)
	if not check(model.save_build(f.path) == OK, "Fullbag fixture persists"): return
	var rng := RandomNumberGenerator.new(); rng.seed = 620611
	for pool: String in ["current", Gear.CURRENT_DEFENSE_POOL_ID, "defense"]:
		var before := mark(model, f.path); var rng_before := rng.state
		check(model.award_equipment(rng, 16, "rare", pool).is_empty() and rng.state == rng_before, "Fullbag award rejects before RNG " + pool)
		unchanged(model, f.path, before, "Fullbag " + pool)
	var quote := model.crafting_quote("recalibrate", f.source.id, f.path)
	if not accepted(quote, "Fullbag allows in-place rating quote"): return
	if not accepted(model.execute_crafting(quote.handle, f.source), "Fullbag allows in-place sameUID rating craft"): return
	check(model.location(f.source.id) == candidate.locations[f.source.id] and model.crafting_balance() == 158, "Fullbag sameUID craft pays42 and preserves cells")
	if not prepare_recovery(arena.state, arena.build_save_path): return
	arena.wave = 9; arena.reward_kills = 0; arena.kills = 0; arena.enemies.clear(); arena.monster_runtime = arena.MonsterLifecycle.new()
	var witnesses := {}
	for family: String in ["ironhide", "mistweave"]:
		var chosen := 0
		for trial: int in range(1, 401):
			var probe := RandomNumberGenerator.new(); probe.seed = trial
			var sample := Gear.generate_for_pool(probe, "gear_000999", 17, "rare", Gear.CURRENT_DEFENSE_POOL_ID)
			if sample.affixes.any(func(a: Dictionary) -> bool: return a.id == family): chosen = trial; break
		if not check(chosen > 0, "Current supply family witness exists " + family): return
		var enemy: Dictionary = arena._spawn_monster("ember_guard", arena.player_pos + Vector2(160, 0), "ordinary", "", [], true)
		if not check(enemy.rarity == "rare" and enemy.equipment_pool == "defense" and enemy.reward_eligible, "Natural guard requests logical defense supply"): return
		var uid := next_uid(arena.state); var oracle := RandomNumberGenerator.new(); oracle.seed = chosen
		var expected := Gear.generate_for_pool(oracle, uid, 17, "rare", Gear.CURRENT_DEFENSE_POOL_ID)
		arena.rng.seed = chosen; enemy.health = 0.0; arena._finish_enemy_death(enemy, false)
		if not check(not arena.state.item(uid).is_empty(), "Actual guard death awards item " + family): return
		check(arena.state.item(uid).payload == expected and arena.state.location(uid).kind == "bag", "Actual logical defense maps to v39 current supplied family " + family)
		witnesses[family] = {"seed":chosen, "item":expected}
		var before := readonly(); var kills: int = arena.reward_kills
		arena._finish_enemy_death(enemy, false)
		check(readonly() == before and arena.reward_kills == kills, "Repeated natural death cannot award twice")
	report.natural_supply = witnesses; finished = true
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v062-consumers-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	if check(arena.save_build(), "Initial actualmain save") and accepted(arena.leave_normal_town(arena.world_context().revision), "Actual practice entry"):
		for test: Callable in [owned_equipment_source, actual_attacks_and_nonattacks, burn_and_resource_order, actual_crafts, full_bag_and_natural_supply]:
			if not section(test): break
	report.merge({"checks":checks, "failures":failures, "sections":sections, "scope":"One bounded actual-main/model fixture; C/Presenter metadata only; resource-order control explicitly synthetic"})
	var output := OS.get_environment("DEFENSE_RATING_REPORT")
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("DEFENSE_RATING_GAMEPLAY ", JSON.stringify({"checks":checks, "failures":failures, "sections":sections}))
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
