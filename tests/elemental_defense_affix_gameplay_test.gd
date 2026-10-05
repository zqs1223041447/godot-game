extends SceneTree
## v060 bounded actual-main/model consumers. Run after the coordinated import.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const CharacterPanel = preload("res://scripts/ui/canonical_character_panel.gd")
const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
const SIX = ["rootwell", "deepwell", "lanternveil", "emberward", "rimeward", "stormward"]
const NEW = ["rimeward", "stormward"]
const OPS = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
var arena: Node
var checks := 0
var failures := 0
var serial := 0
var changes := 0
var finished := false
var sections := {}
var report := {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= 1e-8, "%s got=%s expected=%s" % [label, actual, expected])
func roll(id: String) -> Dictionary:
	return {"id": id, "tier": 3, "value": int(Gear.affix_definition(id).tiers[2].max)}
func vest(uid: String, rarity: String = "rare", ids: Array = SIX) -> Dictionary:
	var affixes: Array = []
	if rarity != "normal":
		for id: String in ids: affixes.append(roll(id))
	return {"id": uid, "base_id": "emberhide_vest", "rarity": rarity, "item_level": 16, "affixes": affixes}
func has_new(item: Dictionary) -> bool:
	return item.affixes.any(func(a: Dictionary) -> bool: return NEW.has(a.id))
func next_uid(model: Model) -> String: return "gear_%06d" % int(model.snapshot().next_item_serial)
func mark(f: Dictionary) -> Dictionary:
	return {"state": var_to_bytes(f.model.snapshot()), "disk": FileAccess.get_file_as_bytes(f.path),
		"attempts": f.model.save_attempts, "saves": f.model.successful_saves}
func unchanged(f: Dictionary, before: Dictionary, label: String, attempts: int = 0) -> void:
	check(var_to_bytes(f.model.snapshot()) == before.state, label + ": complete state byte-identical")
	check(FileAccess.get_file_as_bytes(f.path) == before.disk, label + ": exact disk bytes preserved")
	check(f.model.save_attempts == before.attempts + attempts and f.model.successful_saves == before.saves, label + ": expected save accounting")
func fixture(operation: String = "recalibrate", funds: int = 200) -> Dictionary:
	serial += 1
	var model := FaultModel.new()
	var source := vest(next_uid(model))
	if operation == "enchant": source = vest(source.id, "normal")
	elif operation in ["elevate", "augment"]: source = vest(source.id, "magic", ["rimeward"])
	check(Gear.validate_instance(source) and model._admit_reward_item(Items.wrap_equipment(source)), "Actual legal emberhide UID admitted for " + operation)
	if funds > 0:
		check(model._admit_reward_item(Items.calibration_shard("item_%06d" % int(model.snapshot().next_item_serial), funds)), "Real shard stack admitted")
	# Pick a lawful crafting-revision witness for growth output. This chooses
	# input, never injects the replacement into the transaction's output.
	if operation in ["enchant", "reforge"]:
		var candidate := model.snapshot()
		var found := false
		for revision: int in range(200):
			var seed_text := JSON.stringify({"rules": Craft.seed_rules_version(operation), "revision": revision, "item": source}, "", true, true)
			var plan := Craft.operation_plan(source, operation, seed_text.sha256_text().substr(0, 15).hex_to_int())
			if plan.ok and has_new(plan.instance):
				candidate.crafting.revision = revision
				found = true
				break
		check(found and Model.Rules.reason(candidate).is_empty(), "Lawful current-pool growth seed witness " + operation)
		model._accept_memory(candidate)
	var path := "user://elemental-affix-%d.json" % serial
	check(model.save_build(path) == OK, "Persist coherent current-schema owned fixture")
	return {"model": model, "source": source, "path": path}

func budget() -> void:
	var full := vest("gear_000001")
	check(Gear.validate_instance(full), "All six T3 maximum affixes form legal three-prefix/three-suffix vest")
	var definition := Gear.definition(full)
	for field: String in ["max_health", "max_mana", "max_shield", "fire_resistance", "cold_resistance", "lightning_resistance"]:
		var expected: Dictionary = {"max_health":40.0, "max_mana":22.0, "max_shield":22.0, "fire_resistance":0.40, "cold_resistance":0.25, "lightning_resistance":0.25}
		near(definition.stats[field], expected[field], "Maximum item budget including base: " + field)
	for id: String in ["wellturn", "trailstep", "coalglow"]:
		var crowded := full.duplicate(true); crowded.affixes.append(roll(id))
		check(not Gear.validate_instance(crowded), "Three resistances leave no fourth suffix for " + id)
	check(not Gear.validate_instance(vest("gear_000001", "magic", NEW)), "Magic one-suffix limit prevents simultaneous cold/lightning")
	var normal := Gear.definition(vest("gear_000001", "normal"))
	near(normal.stats.fire_resistance, 0.15, "White base still supplies15fire")
	near(normal.stats.get("cold_resistance", 0.0), 0.0, "White base has no cold")
	near(normal.stats.get("lightning_resistance", 0.0), 0.0, "White base has no lightning")
	for id: String in NEW:
		var shown := Gear.affix_display(roll(id))
		check(shown.ok and shown.value_text == "+25%", "Shared formatter uses integer percent once: " + id)
	finished = true

func transactions() -> void:
	var outputs := {}
	for operation: String in OPS:
		var f := fixture(operation)
		var model: FaultModel = f.model
		var original: Dictionary = model.snapshot()
		var source: Dictionary = f.source
		var before := mark(f)
		var economics := Craft.operation_quote(source, operation)
		var metadata := model.crafting_operations(source.id, f.path)
		check(metadata.size() == 10 and model._craft_quotes.is_empty(), "Six existing plus four targeted operations, no new action or issued handle")
		unchanged(f, before, "Read-only craft metadata " + operation)
		var quote := model.crafting_quote(operation, source.id, f.path)
		check(quote.ok and quote.cost == economics.cost and quote.materials == economics.materials, "Authoritative exact economics " + operation)
		if not quote.ok: continue
		check(not quote.has("seed") and not quote.has("candidate") and not quote.has("instance"), "Quote exposes no future roll")
		model.cancel_crafting_quote(quote.handle)
		check(not model.execute_crafting(quote.handle, source).ok, "Cancellation rejects execution " + operation)
		unchanged(f, before, "Cancelled craft " + operation)
		quote = model.crafting_quote(operation, source.id, f.path)
		var wrong := source.duplicate(true); wrong.item_level = 17
		check(not model.execute_crafting(quote.handle, wrong).ok, "Changed selected source rejected " + operation)
		unchanged(f, before, "Wrong source " + operation)
		var seed_text := JSON.stringify({"rules": Craft.seed_rules_version(operation), "revision": original.crafting.revision, "item": source}, "", true, true)
		var expected := Craft.operation_plan(source, operation, seed_text.sha256_text().substr(0, 15).hex_to_int())
		changes = 0; model.changed.connect(func(): changes += 1)
		model.fail_save = true
		check(not model.execute_crafting(quote.handle, source).ok, "Injected write failure rejects whole transaction " + operation)
		unchanged(f, before, "Failed write " + operation, 1)
		check(changes == 0, "No failure changed signal")
		model.fail_save = false
		seed(60017); var global_next := randi(); seed(60017)
		var result := model.execute_crafting(quote.handle, source)
		check(result.ok and randi() == global_next, "Same authority retry succeeds without global RNG draw " + operation)
		if not result.ok: continue
		check(changes == 1 and model.successful_saves == before.saves + 1, "Exactly one save and changed signal " + operation)
		check(model.crafting_balance() == 200 - int(economics.cost.get(Craft.MATERIAL_ID, 0)) + int(economics.materials.get(Craft.MATERIAL_ID, 0)), "Actual shard quantity changes by exact debit/credit " + operation)
		var after := model.snapshot()
		check(after.version == 37 and after.crafting.revision == original.crafting.revision + 1 and after.revision == original.revision + 1 and after.journey == original.journey, "One atomic craft revision and unchanged journey")
		check(after.next_item_serial == original.next_item_serial, "Existing currency stack needs no new serial")
		if operation == "salvage": check(model.item(source.id).is_empty() and model.location(source.id).is_empty(), "Salvage consumes exactly selected new-affix UID")
		else:
			var item: Dictionary = model.item(source.id).payload
			check(item == expected.instance and Gear.validate_instance(item) and model.location(source.id) == original.locations[source.id], "Exact seeded legal output keeps UID/base/bag cells " + operation)
			if operation == "recalibrate":
				for i: int in range(source.affixes.size()):
					check(item.affixes[i].id == source.affixes[i].id and item.affixes[i].tier == source.affixes[i].tier, "Calibration preserves each family/order/tier including new suffixes")
			if operation in ["augment", "elevate"]: check(item.affixes[0] == source.affixes[0], "Growth preserves existing exact cold roll")
			if operation in ["enchant", "reforge"]: check(has_new(item), "Real committed growth produces new family " + operation)
			outputs[operation] = item
		for uid: String in original.items:
			if uid == source.id or original.items[uid].kind == "currency": continue
			check(after.items[uid] == original.items[uid] and after.locations[uid] == original.locations[uid], "Unrelated owned UID/payload/cells unchanged")
		before = mark(f)
		check(not model.execute_crafting(quote.handle, source).ok, "Successful authority cannot charge twice")
		unchanged(f, before, "Replay " + operation)
		var loaded := Model.new()
		check(loaded.load_build(f.path) and Planner._same_data(loaded.snapshot(), after), "Full schema37 disk reload " + operation)
		report[operation] = {"cost": economics.cost, "materials": economics.materials, "balance": model.crafting_balance()}
	report.crafted_outputs = outputs
	finished = true

func rejected_crafts() -> void:
	for operation: String in OPS:
		if operation == "salvage": continue
		var f := fixture(operation, 0)
		var before := mark(f)
		check(not f.model.crafting_quote(operation, f.source.id, f.path).ok, "No-money quote rejects before debit " + operation)
		unchanged(f, before, "No-money " + operation)
	for kind: String in ["revision", "external", "reload"]:
		var f := fixture()
		var quote: Dictionary = f.model.crafting_quote("recalibrate", f.source.id, f.path)
		check(quote.ok, "New-affix quote before " + kind)
		if kind == "revision": f.model.add_xp(1)
		elif kind == "external":
			var file := FileAccess.open(f.path, FileAccess.WRITE)
			file.store_string(JSON.stringify(f.model.snapshot(), "  ")); file.close()
		else: check(f.model.load_build(f.path), "Actual reload before stale confirm")
		var before := mark(f)
		check(not f.model.execute_crafting(quote.handle, f.source).ok, "Intervening " + kind + " rejects old authority")
		unchanged(f, before, "Stale/external " + kind)
	finished = true

func targeted_tradeoff() -> void:
	var f := fixture()
	var quote: Dictionary = f.model.crafting_quote("targeted_reforge_damage", f.source.id, f.path)
	check(quote.ok and quote.cost == {Craft.MATERIAL_ID:40}, "Existing damage target retains exact rare40 fee")
	check(f.model.execute_crafting(quote.handle, f.source).ok, "Actual damage-target transaction on three-resistance source")
	var item: Dictionary = f.model.item(f.source.id).payload
	var damage_count := 0; var resistance_count := 0; var suffix_count := 0
	for affix: Dictionary in item.affixes:
		if affix.id in ["coalglow", "rimeecho", "sparkthread"]: damage_count += 1
		if affix.id in ["emberward", "rimeward", "stormward"]: resistance_count += 1
		if Gear.affix_definition(affix.id).kind == "suffix": suffix_count += 1
	check(Gear.validate_instance(item) and damage_count >= 1 and resistance_count <= 2 and suffix_count <= 3, "Damage guarantee consumes suffix capacity, preventing all-three-resistance target output")
	check(f.model.crafting_balance() == 160 and f.model.location(item.id).kind == "bag", "Damage target pays actual wallet and preserves original UID location")
	report.targeted_damage_output = item
	finished = true

func full_bag() -> void:
	var f := fixture()
	var model: FaultModel = f.model
	var candidate := model.snapshot()
	var context := Model.Migration.paged_location_context(candidate, model._socket_ids)
	var occupied: Dictionary = Locations.validate_current(Items.metadata_for_items(candidate.items), candidate.locations, context).occupied_cells
	for page: int in range(2):
		for y: int in range(10):
			for x: int in range(12):
				if occupied.has("bag:%d:%d:%d" % [page, x, y]): continue
				var uid := "item_%06d" % int(candidate.next_item_serial); candidate.next_item_serial += 1
				candidate.items[uid] = Model.Gems.create_instance(uid, "skill:bolt")
				candidate.locations[uid] = {"kind":"bag", "page":page, "x":x, "y":y}
	check(Model.Rules.reason(candidate).is_empty(), "Full240-cell canonical fixture validates")
	model._accept_memory(candidate)
	check(model.save_build(f.path) == OK, "Full inventory persisted")
	var rng := RandomNumberGenerator.new(); rng.seed = 600611
	for pool: String in ["current", Gear.CURRENT_DEFENSE_POOL_ID, "defense", "missing"]:
		var before := mark(f); var rng_before := rng.state
		check(model.award_equipment(rng, 16, "rare", pool).is_empty(), "Full bag or invalid pool rejects award " + pool)
		check(rng.state == rng_before, "Rejected award preserves exact RNG " + pool)
		unchanged(f, before, "Full bag/invalid pool keeps all currency/UIDs " + pool)
	var original_location := model.location(f.source.id)
	var quote := model.crafting_quote("recalibrate", f.source.id, f.path)
	check(quote.ok and model.execute_crafting(quote.handle, f.source).ok, "Full bag still permits in-place existing-UID calibration")
	check(model.location(f.source.id) == original_location and model.crafting_balance() == 158, "Full-bag in-place success pays42 and preserves cells")
	finished = true

func live_mark() -> Dictionary:
	return {"state": arena.state.snapshot(), "disk": FileAccess.get_file_as_bytes(arena.build_save_path), "saves":arena.state.successful_saves, "rng":arena.rng.state}
func ready_hit() -> void:
	arena._stats = arena.state.get_stats()
	arena.enemies.clear(); arena.projectiles.clear(); arena.incoming_damage_trace.clear()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.leech_runtime.clear()
	arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.health = 1000.0; arena.shield = 0.0; arena.mana = 100.0
	arena._stats.max_health = 1000.0; arena._stats.armour = 0.0; arena._stats.evasion = 0.0
	arena.hud._process(0.0); arena.hud.close_panel()
func main_equipment() -> void:
	var full := vest(next_uid(arena.state))
	check(arena.state._admit_reward_item(Items.wrap_equipment(full)), "Legal six-maximum actual item enters real main bag")
	check(arena.state.move_item(full.id, {"kind":"equipment", "slot_id":"body_armour"}, arena.state.revision(), arena.build_save_path).ok, "Real guarded equip installs exactly one body armour UID")
	var stats: Dictionary = arena.state.get_stats()
	near(stats.cold_resistance, 0.25, "Equipped cold ticks divided100 exactly once")
	near(stats.lightning_resistance, 0.25, "Equipped lightning ticks divided100 exactly once")
	near(stats.fire_resistance, 0.40, "Equipped white15 plus suffix25fire")
	check(arena.state.equipped_items().body_armour == full.id, "Authoritative single chest slot owns new UID")
	for element: String in ["cold", "lightning"]:
		ready_hit(); var before := live_mark()
		check(arena.hit_player_components({element:100.0}), "Actual incoming elemental hit accepted " + element)
		near(arena.incoming_damage_trace.back().damage_total, 75.0, "Real Defense produces75 from100 " + element)
		near(arena.health, 925.0, "Actual main health loses75 " + element)
		check(live_mark() == before, "New raw resistance settlement consumes no saved state/RNG " + element)
	var before := live_mark()
	var profile: Dictionary = arena.state.get_resistance_profile()
	var panel := CharacterPanel.new(); root.add_child(panel); panel.setup(arena.state)
	for element: String in ["cold", "lightning"]:
		near(profile.raw_resistances[element], 0.25, "Authoritative C-page profile raw " + element)
		near(profile.maximum_resistances[element], 0.75, "New affix does not raise maximum " + element)
		check(panel._values[element + "_resistance"].text == "25%" and panel._resistance_cards[element + "_resistance"].tooltip_text.contains("25.0%"), "Real C-page formatted value and raw tooltip " + element)
	var card := Presenter.view(arena.state, full.id)
	check(card.affix_lines.has(Gear.affix_display(roll("rimeward")).line) and card.affix_lines.has(Gear.affix_display(roll("stormward")).line), "Actual item card uses shared new-affix formatter")
	check(live_mark() == before, "Profile, actual C page and item presentation are read-only")
	panel.queue_free()
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and Planner._same_data(loaded.snapshot(), arena.state.snapshot()) and loaded.get_resistance_profile() == profile, "Equipped UID/location/save reload preserves raw and effective profile")
	var white := vest(next_uid(arena.state), "normal")
	check(arena.state._admit_reward_item(Items.wrap_equipment(white)), "Actual replacement white vest acquired")
	check(arena.state.move_item(white.id, {"kind":"equipment", "slot_id":"body_armour"}, arena.state.revision(), arena.build_save_path).ok, "Real slot swap atomically returns six-affix vest to bag")
	check(arena.state.location(full.id).kind == "bag" and arena.state.location(white.id).kind == "equipment", "Swap preserves both item UIDs and resolves locations")
	for element: String in ["cold", "lightning"]:
		near(arena._stats[element + "_resistance"], 0.0, "Build signal clears removed elemental raw on swap " + element)
	near(arena._stats.fire_resistance, 0.15, "White swap retains only base15fire")
	check(arena.state.move_item(full.id, {"kind":"equipment", "slot_id":"body_armour"}, arena.state.revision(), arena.build_save_path).ok, "Reequip original maximum item through actual command")
	for element: String in ["cold", "lightning"]:
		ready_hit()
		# Explicit controlled combat stats, not a claim that one vest or an
		# unallocated source build alone supplies90raw or raises its maximum.
		arena._stats[element + "_resistance"] += 0.65
		arena._stats["maximum_" + element + "_resistance_add"] = 0.20
		check(arena.hit_player_components({element:100.0}), "Controlled90raw with over-cap maximum hit admitted")
		near(arena.incoming_damage_trace.back().effective_resistances[element], 0.83, "Shared safety cap clamps controlled high raw/max " + element)
		near(arena.incoming_damage_trace.back().damage_total, 17.0, "Safety83 cap leaves17damage " + element)
	check(arena.state.move_item(full.id, arena.state.first_bag_position(full.id), arena.state.revision(), arena.build_save_path).ok, "Real unequip returns original UID to bag")
	for element: String in ["cold", "lightning"]: near(arena._stats[element + "_resistance"], 0.0, "Actual unequip clears elemental raw " + element)
	finished = true

func natural_rewards() -> void:
	arena.wave = 9; arena.reward_kills = 0; arena.kills = 0
	arena.enemies.clear(); arena.monster_runtime = arena.MonsterLifecycle.new()
	var witnesses := {}
	for family: String in NEW:
		var chosen_seed := 0
		for trial: int in range(1, 400):
			var probe := RandomNumberGenerator.new(); probe.seed = trial
			var item := Gear.generate_for_pool(probe, "gear_000999", 17, "rare", Gear.CURRENT_DEFENSE_POOL_ID)
			if item.affixes.any(func(a: Dictionary) -> bool: return a.id == family): chosen_seed = trial; break
		check(chosen_seed > 0, "Natural current defense-family witness found " + family)
		var enemy: Dictionary = arena._spawn_monster("ember_guard", arena.player_pos + Vector2(160,0), "ordinary", "", [], true)
		check(enemy.rarity == "rare" and enemy.equipment_pool == "defense" and enemy.reward_eligible, "Natural ember guard retains logical defense source and rare root eligibility")
		var next: String = next_uid(arena.state); var before_reward: int = arena.reward_kills
		var oracle := RandomNumberGenerator.new(); oracle.seed = chosen_seed
		var expected := Gear.generate_for_pool(oracle, next, 17, "rare", Gear.CURRENT_DEFENSE_POOL_ID)
		arena.rng.seed = chosen_seed; enemy.health = 0.0
		arena._finish_enemy_death(enemy, false)
		check(arena.reward_kills == before_reward + 1 and not arena.state.item(next).is_empty(), "Actual rare root death awards one real equipment item")
		if not arena.state.item(next).is_empty():
			var actual: Dictionary = arena.state.item(next).payload
			check(actual == expected and actual.affixes.any(func(a: Dictionary) -> bool: return a.id == family), "Main maps logical defense to new current pool and actually drops " + family)
			check(arena.state.location(next).kind == "bag", "Natural new-family drop enters real bag")
			witnesses[family] = {"seed":chosen_seed, "item":actual}
		var before := live_mark(); var reward_count: int = arena.reward_kills
		arena._finish_enemy_death(enemy, false)
		check(live_mark() == before and arena.reward_kills == reward_count, "Repeated root death cannot award again")
	var parent: Dictionary = arena._spawn_monster("splitter", arena.player_pos + Vector2(180,0), "ordinary", "", [], true)
	parent.health = 0.0; arena._finish_enemy_death(parent, false)
	var children: Array = arena.monster_runtime.drain(55, arena.ARENA)
	check(not children.is_empty(), "Actual splitter produces real lifecycle descendants")
	var before := live_mark(); var reward_count: int = arena.reward_kills
	for child: Dictionary in children:
		check(not child.reward_eligible and child.generation == 1, "Actual child inherits nonrewarding lineage")
		child.health = 0.0; arena._finish_enemy_death(child, false)
	check(live_mark() == before and arena.reward_kills == reward_count, "All child deaths preserve reward RNG/model/UID/currency")
	var rng := RandomNumberGenerator.new(); rng.seed = 60031
	var old_uid := next_uid(arena.state)
	var old_oracle := RandomNumberGenerator.new(); old_oracle.seed = 60031
	var old_expected := Gear.generate_for_pool(old_oracle, old_uid, 16, "rare", "defense")
	check(arena.state.award_equipment(rng, 16, "rare", "defense") == old_uid and arena.state.item(old_uid).payload == old_expected and not has_new(old_expected), "Explicit old defense award remains old fire-only interface")
	check(arena.save_build(), "Natural reward state persists through actual main save")
	var loaded := Model.new()
	check(loaded.load_build(arena.build_save_path) and Planner._same_data(loaded.snapshot(), arena.state.snapshot()), "Real natural drops and lineage reward state survive reload")
	report.natural_reward_witnesses = witnesses
	finished = true

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v060-consumers-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	for test: Callable in [budget, transactions, rejected_crafts, targeted_tradeoff, full_bag]:
		finished = false; var start := checks
		test.call()
		check(finished, "Section completed without script exception: " + test.get_method())
		sections[test.get_method()] = checks - start
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	check(arena.save_build(), "Initial legitimate main save")
	check(arena.leave_normal_town(arena.world_context().revision).ok, "Actual normal practice entry for combat")
	for test: Callable in [main_equipment, natural_rewards]:
		finished = false; var start := checks
		test.call()
		check(finished, "Section completed without script exception: " + test.get_method())
		sections[test.get_method()] = checks - start
	report.merge({"checks":checks, "failures":failures, "sections":sections})
	var output := OS.get_environment("ELEMENTAL_AFFIX_REPORT")
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("Elemental affix actual model/gameplay: %d checks, %d failures; sections %s" % [checks, failures, JSON.stringify(sections)])
	arena.queue_free(); await process_frame
	quit(1 if failures else 0)
