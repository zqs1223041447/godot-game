extends SceneTree
## v055: real owned UIDs, save-first crafting, actual main cleave settlement.
## Run only after the coordinated import, with a fresh isolated XDG directory.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const TOWN_PATH = "user://town_test_build_save.json"
const GROUP = "group_000009"
const FAMILIES = ["whetstone_edge", "tempered_edge", "deepwell", "wellturn", "global_critical_chance", "global_critical_multiplier"]
const DUAL = ["39725", "63649", "49806", "6580", "19711", "20010", "36704"]
class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
var checks := 0
var failures := 0
var finished := false
var fixture_serial := 0
var sections := {}
var report := {}
var arena: Node


func _initialize() -> void: call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-10),
		"%s got=%.12f expected=%.12f" % [label, actual, expected])


func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v055-consumers-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	for test: Callable in [transactions, failures_atomic, real_compiler_budget]:
		finished = false
		var start := checks
		test.call()
		check(finished, "Section completed without a script exception: " + test.get_method())
		sections[test.get_method()] = checks - start
	finished = false
	await main_roundtrip()
	check(finished, "Actual-main section completed without a script exception")
	finished = false
	full_bag()
	check(finished, "Full-bag section completed without a script exception")
	report.merge({"checks": checks, "failures": failures, "sections": sections})
	var output := OS.get_environment("FORGEBLADE_GAMEPLAY_REPORT")
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("Forgeblade actual model/gameplay: %d checks, %d failures; sections %s" % [checks, failures, JSON.stringify(sections)])
	quit(1 if failures else 0)


func affix(id: String, tier: int = 1, maximum: bool = false) -> Dictionary:
	var range_value: Dictionary = Gear.affix_definition(id).tiers[tier - 1]
	return {"id": id, "tier": tier, "value": int(range_value.max if maximum else range_value.min)}


func source(model: Model, rarity: String = "rare", count: int = 4, tier: int = 1, maximum: bool = false) -> Dictionary:
	var rolls: Array = []
	var ids: Array = ["deepwell", "wellturn"] if rarity == "magic" else FAMILIES
	if rarity != "normal":
		for id: String in ids.slice(0, count): rolls.append(affix(id, tier, maximum))
	return {"id": "gear_%06d" % int(model.snapshot().next_item_serial), "base_id": "forgeblade",
		"rarity": rarity, "item_level": 30, "affixes": rolls}


func fixture(rarity: String = "rare", count: int = 4, funds: int = 200) -> Dictionary:
	fixture_serial += 1
	var model := FaultModel.new()
	var item := source(model, rarity, count)
	check(Gear.validate_instance(item) and model._admit_reward_item(Items.wrap_equipment(item)), "Admit catalog-valid forgeblade with actual next UID")
	if funds > 0:
		check(model._admit_reward_item(Items.calibration_shard("item_%06d" % int(model.snapshot().next_item_serial), funds)), "Admit real shard stack")
	var path := "user://forgeblade-%d.json" % fixture_serial
	check(model.save_build(path) == OK, "Persist coherent current-schema owned fixture")
	return {"model": model, "source": item, "path": path}


func entry(rows: Array, operation: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.operation == operation: return row
	return {}


func mark(f: Dictionary) -> Dictionary:
	return {"state": var_to_bytes(f.model.snapshot()), "disk": FileAccess.get_file_as_bytes(f.path),
		"attempts": f.model.save_attempts, "saves": f.model.successful_saves}


func unchanged(f: Dictionary, before: Dictionary, label: String, save_attempts: int = 0) -> void:
	check(var_to_bytes(f.model.snapshot()) == before.state, label + ": complete memory byte-identical")
	check(FileAccess.get_file_as_bytes(f.path) == before.disk, label + ": exact on-disk bytes preserved")
	check(f.model.save_attempts == before.attempts + save_attempts and f.model.successful_saves == before.saves,
		label + ": expected save accounting")


func reject(result: Dictionary, code: String, label: String) -> void:
	check(not result.ok and str(result.get("code", result.get("error_code", ""))) == code and not str(result.get("reason", "")).is_empty(), label)


func transactions() -> void:
	var cases := [
		["enchant", "normal", 0, 8], ["augment", "magic", 1, 6], ["elevate", "magic", 2, 24],
		["reforge", "magic", 2, 10], ["reforge", "rare", 4, 28], ["recalibrate", "rare", 4, 14],
		["salvage", "rare", 4, 0], ["targeted_reforge_damage", "magic", 2, 16],
		["targeted_reforge_damage", "rare", 4, 40], ["targeted_reforge_critical", "magic", 2, 16],
		["targeted_reforge_critical", "rare", 4, 40]]
	for row: Array in cases:
		var f := fixture(row[1], row[2])
		var model: FaultModel = f.model
		var original: Dictionary = model.snapshot()
		var operation: String = row[0]
		var quote: Dictionary = model.crafting_quote(operation, f.source.id, f.path)
		check(quote.ok, "Real model accepts " + operation + "/" + row[1])
		if not quote.ok: continue
		check(int(quote.cost.get(Craft.MATERIAL_ID, 0)) == row[3], "Existing fee unchanged for " + operation + "/" + row[1])
		var before := mark(f)
		seed(55055); var next_random := randi(); seed(55055)
		var result: Dictionary = model.execute_crafting(quote.handle, f.source)
		check(result.ok and randi() == next_random, "Craft commits using isolated deterministic RNG: " + operation)
		if not result.ok: continue
		check(model.successful_saves == before.saves + 1 and model.save_attempts == before.attempts + 1, "One save precedes one committed craft")
		var after: Dictionary = model.snapshot()
		check(after.revision == original.revision + 1 and after.crafting.revision == original.crafting.revision + 1, "Only one build and crafting revision consumed")
		if operation == "salvage":
			check(model.item(f.source.id).is_empty() and model.location(f.source.id).is_empty() and model.crafting_balance() == 207, "Salvage consumes selected UID and credits unchanged 3+sum(tier)=7")
		else:
			var replacement: Dictionary = model.item(f.source.id).payload
			check(Gear.validate_instance(replacement) and replacement.id == f.source.id and replacement.base_id == "forgeblade" and replacement.item_level == 30, "Valid replacement preserves item identity and base")
			check(model.location(f.source.id) == original.locations[f.source.id], "Craft preserves original occupied bag cells")
			check(model.crafting_balance() == 200 - int(row[3]) and after.next_item_serial == original.next_item_serial, "Debit is exact; replacement allocates no UID")
			if operation == "targeted_reforge_damage":
				check(replacement.affixes.any(func(a: Dictionary) -> bool: return a.id in ["whetstone_edge", "tempered_edge"]), "Damage target has a local physical family")
			if operation == "targeted_reforge_critical":
				check(replacement.affixes.any(func(a: Dictionary) -> bool: return a.id in ["global_critical_chance", "global_critical_multiplier"]), "Critical target has a real global critical family")
			if operation == "augment": check(replacement.affixes.size() == 2 and replacement.affixes.has(f.source.affixes[0]), "Augment preserves prior family and adds one")
			if operation == "elevate":
				check(replacement.rarity == "rare" and replacement.affixes.size() >= 4, "Elevate reaches legal rare count")
				for kept: Dictionary in f.source.affixes: check(replacement.affixes.has(kept), "Elevate preserves each original roll")
			if operation == "recalibrate":
				for index: int in range(replacement.affixes.size()):
					check(replacement.affixes[index].id == f.source.affixes[index].id and replacement.affixes[index].tier == f.source.affixes[index].tier, "Recalibrate keeps family order and tiers")
		var replay_before := mark(f)
		reject(model.execute_crafting(quote.handle, f.source), "unknown_quote", "Successful handle cannot replay")
		unchanged(f, replay_before, "Replay")
		var loaded := Model.new()
		check(loaded.load_build(f.path) and Planner._same_data(loaded.snapshot(), after), "Whole actual UID inventory roundtrips after " + operation)
	finished = true


func failures_atomic() -> void:
	var f := fixture()
	var model: FaultModel = f.model
	var before := mark(f)
	seed(55201); var next_random := randi(); seed(55201)
	var operations: Array = model.crafting_operations(f.source.id, f.path)
	for operation: String in ["targeted_reforge_life_leech", "targeted_reforge_mana_leech"]:
		check(not entry(operations, operation).available and not entry(operations, operation).reason.is_empty(), "No leech family disables unsupported target")
		check(not model.crafting_quote(operation, f.source.id, f.path).ok, "Unsupported leech quote cannot issue authority")
	check(randi() == next_random and model._craft_quotes.is_empty(), "Unavailable target consumes no RNG or handle")
	unchanged(f, before, "Unavailable target")
	var quote: Dictionary = model.crafting_quote("targeted_reforge_damage", f.source.id, f.path)
	model.cancel_crafting_quote(quote.handle)
	reject(model.execute_crafting(quote.handle, f.source), "unknown_quote", "Cancelled handle rejected")
	unchanged(f, before, "Cancellation")
	quote = model.crafting_quote("targeted_reforge_damage", f.source.id, f.path)
	var tampered: Dictionary = f.source.duplicate(true); tampered.item_level = 16
	reject(model.execute_crafting(quote.handle, tampered), "source_mismatch", "Changed selected item rejects")
	unchanged(f, before, "Source mismatch")
	model.fail_save = true
	var failed: Dictionary = model.execute_crafting(quote.handle, f.source)
	check(not failed.ok, "Failed disk write rejects craft")
	unchanged(f, before, "Save failure", 1)
	model.fail_save = false
	check(model.execute_crafting(quote.handle, f.source).ok, "Same authorized handle retries after save recovery")
	f = fixture(); model = f.model
	quote = model.crafting_quote("targeted_reforge_damage", f.source.id, f.path)
	check(not model.award_gem("skill:cleave").is_empty(), "Real independent ownership change creates stale snapshot")
	before = mark(f)
	reject(model.execute_crafting(quote.handle, f.source), "stale_quote", "Old quote binds complete snapshot")
	unchanged(f, before, "Stale quote")
	f = fixture(); model = f.model
	quote = model.crafting_quote("targeted_reforge_damage", f.source.id, f.path)
	var file := FileAccess.open(f.path, FileAccess.WRITE)
	file.store_string("external modification\n"); file.close()
	before = mark(f)
	reject(model.execute_crafting(quote.handle, f.source), "save_changed", "External disk edit rejects old receipt")
	unchanged(f, before, "External edit")
	f = fixture("rare", 4, 39); model = f.model; before = mark(f)
	check(not model.crafting_quote("targeted_reforge_damage", f.source.id, f.path).ok, "Insufficient actual shard stack rejects quote")
	unchanged(f, before, "Insufficient funds")
	finished = true


func strip_equipment(model: Model) -> void:
	for slot: String in model.equipped_items().keys(): check(model.unequip(slot), "Unequip existing " + slot + " via real UID transfer")


func admit(model: Model, item: Dictionary, path: String) -> String:
	check(Gear.validate_instance(item) and model._admit_reward_item(Items.wrap_equipment(item)), "Catalog-valid controlled equipment admitted with canonical serial")
	check(model.save_build(path) == OK, "Controlled owned item persisted before transfer")
	return item.id


func noncritical(cast: Dictionary) -> float:
	return float(Damage.resolve(cast.packets.direct, cast.snapshot.modifiers).total)


func real_compiler_budget() -> void:
	var f := fixture("normal", 0, 0)
	var model: Model = f.model
	strip_equipment(model)
	var bare := Compiler.compile_group("cleave", model.get_combat_snapshot(), [])
	near(model.get_stats().damage, 18.0, "Unmodified real model B=18")
	near(bare.packets.direct.base.physical, 50.4, "Real compiler raw B18 cleave contract")
	var innate_increase: float = model.get_stats().melee_physical_increased
	var bare_mana: float = model.get_stats().max_mana
	near(innate_increase, 0.04, "Default source class has real 20-strength four-percent melee increase")
	near(noncritical(bare), 50.4 * 1.04, "Actual class attributes apply after contract raw base")
	var samples := [["white", "normal", 0, 1, false, 61.6], ["T1_low", "rare", 4, 1, false, 65.8],
		["T1_high", "rare", 4, 1, true, 69.72], ["T3_full", "rare", 6, 3, true, 86.8]]
	var budget: Array = []
	for sample: Array in samples:
		var item := source(model, sample[1], sample[2], sample[3], sample[4])
		var uid := admit(model, item, f.path)
		check(model.equip(uid), "Equip real controlled " + sample[0] + " UID")
		var cast := Compiler.compile_group("cleave", model.get_combat_snapshot(), [])
		near(cast.packets.direct.base.physical, sample[5], "Real compiler raw contract budget " + sample[0])
		near(noncritical(cast), float(sample[5]) * (1.0 + innate_increase), "Actual class budget " + sample[0])
		var chance: float = cast.critical.primary.chance
		var multiplier: float = cast.critical.primary.multiplier
		budget.append({"sample": sample[0], "noncritical": noncritical(cast), "chance": chance, "multiplier": multiplier,
			"expectation_zero_defense": noncritical(cast) * (1.0 + chance * (multiplier - 1.0)),
			"raw_contract": cast.packets.direct.base.physical, "contract_expectation_without_class_attributes": float(cast.packets.direct.base.physical) * (1.0 + chance * (multiplier - 1.0))})
		if sample[0] == "T3_full":
			near(chance, 0.07, "Full T3 actual global critical chance")
			near(multiplier, 1.65, "Full T3 actual global multiplier")
			near(budget.back().contract_expectation_without_class_attributes, 90.7494, "Full T3 contract expectation before class attribute modifiers")
			near(budget.back().expectation_zero_defense, 94.379376, "Full T3 actual default-class zero-defense single-hit expectation")
			near(model.get_stats().max_mana - bare_mana, 22.0, "Deepwell adds exact global maximum mana beyond class intelligence")
			near(model.get_stats().mana_regen, 10.26, "Wellturn is a global mana-regeneration consumer")
			for skill: String in ["bolt", "frost", "shade_bolt", "nova", "meteor", "chain", "tornado"]:
				var other := Compiler.compile_group(skill, model.get_combat_snapshot(), [])
				near(other.critical.primary.chance, 0.07, "Global critical chance reaches " + skill)
				near(other.critical.primary.multiplier, 1.65, "Global critical multiplier reaches " + skill)
		check(model.unequip("weapon") and model.item(uid).payload == item, "Unequip preserves same UID and rolls")
	var old: Dictionary = {"id": "gear_%06d" % int(model.snapshot().next_item_serial), "base_id": "runewood_focus", "rarity": "rare", "item_level": 30,
		"affixes": [affix("attack_added_physical", 3, true), affix("attack_added_fire", 3, true), affix("prismedge", 3, true), affix("coalglow", 3, true)]}
	var old_uid := admit(model, old, f.path)
	check(model.equip(old_uid), "Equip legal existing rare runewood comparison")
	var old_cast := Compiler.compile_group("cleave", model.get_combat_snapshot(), [])
	near(noncritical(old_cast), 67.2 * 1.04 + 23.184, "Existing runewood actual class comparison, strength affects physical only")
	near(noncritical(old_cast) - 67.2 * innate_increase, 90.384, "Existing runewood contract comparison excluding class attribute contribution")
	near((noncritical(old_cast) - 67.2 * innate_increase) * 1.025, 92.6436, "Existing runewood contract base-crit expectation")
	var old_defended := Defense.apply_armour(Damage.resolve(old_cast.packets.direct, old_cast.snapshot.modifiers, {"fire": 0.25}), 80.0)
	near(old_defended.total, (67.2 * 1.04) * (1.0 - 80.0 / (80.0 + 5.0 * 67.2 * 1.04)) + 23.184 * 0.75, "Runewood physical armour and fire resistance settle separately")
	report.budget = budget
	finished = true


func clean_combat() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear(); arena.damage_trace.clear()
	arena.leech_runtime.clear(); arena.group_cooldowns.reset(); arena.auto_fire = false
	arena._stats = arena.state.get_stats(); arena._refresh_leech_caps()
	arena.health = float(arena._stats.max_health) * 0.25; arena.mana = float(arena._stats.max_mana) * 0.75
	arena.alive = true; arena.spawn_timer = 10000.0; arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	while arena.hud.is_blocking(): arena.hud.close_panel()
	for id: String in arena.cooldowns: arena.cooldowns[id] = 0.0


func enemy(offset: Vector2, armour: float = 0.0, shield: float = 0.0, health: float = 10000.0) -> Dictionary:
	var value: Dictionary = arena._spawn_monster("crawler", arena.player_pos + offset, "ordinary", "", [], false)
	value.spawn = 0.0; value.health = health; value.max_health = health; value.shield = shield; value.max_shield = shield
	value.armour = armour; value.evasion = 0.0; value.evasion_entropy = 50.0; value.resistances = {}; value.radius = 1.0
	return value


func critical_seed(snapshot: Dictionary) -> int:
	var runtime := Critical.new()
	for seed_value: int in range(55000, 57000):
		runtime.reset(seed_value)
		var frozen := runtime.freeze(snapshot)
		if frozen.ok and frozen.snapshot.get("critical_roll", {}).get("critical", false): return seed_value
	check(false, "A deterministic genuine critical sample is reachable")
	return 55000


func main_roundtrip() -> void:
	var start := checks
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	check(arena.world_context().mode == "town", "Fresh current main is in safe town")
	check(arena.enter_town_test(arena.world_context().revision).ok, "Explicit actual test-town entry succeeds")
	var found := false
	for row: Dictionary in arena.town_stock("equipment_merchant"):
		if row.id == "base:forgeblade":
			found = true
			check(row.available and row.size == Vector2i(1, 3), "Dynamic stock exposes valid available 1x3 forgeblade")
	check(found, "Forgeblade comes from actual dynamic town catalog")
	var bought: Dictionary = arena.town_buy("base:forgeblade", arena.state.revision())
	check(bought.ok, "Actual main buys free white base into bag")
	if not bought.ok: arena.queue_free(); await process_frame; return
	var uid: String = bought.uid
	var model: Model = arena.state
	check(model.location(uid).kind == "bag" and model.item(uid).payload.base_id == "forgeblade", "Town result owns actual selected forgeblade UID")
	check(arena.town_buy("currency:calibration_shard", model.revision()).ok, "Town supplies actual canonical crafting currency")
	var gem: Dictionary = arena.town_buy("skill:cleave", model.revision())
	check(gem.ok and model.move_item(gem.uid, {"kind": "skill_main", "group_id": GROUP}, model.revision(), TOWN_PATH).ok, "Town cleave gem UID placed through real transfer")
	strip_equipment(model)
	check(model.equip(uid), "Shop white forgeblade equipped through authoritative UID")
	near(model.get_group_cast(GROUP).packets.direct.base.physical, 61.6, "Town white weapon reaches real grouped compiler raw contract")
	near(noncritical(model.get_group_cast(GROUP)), 61.6 * 1.04, "Town real class attributes apply once to white weapon hit")
	check(not arena.cast_group(GROUP), "Town rejects combat even with valid weapon and gem")
	check(model.unequip("weapon"), "Same shop UID returned for crafting")
	for operation: String in ["enchant", "elevate", "targeted_reforge_damage"]:
		var owned: Dictionary = model.item(uid).payload
		var quote := model.crafting_quote(operation, uid, TOWN_PATH)
		check(quote.ok and model.execute_crafting(quote.handle, owned).ok, "Actual shop UID crafted by " + operation)
	var crafted: Dictionary = model.item(uid).payload
	check(crafted.id == uid and crafted.rarity == "rare" and crafted.affixes.any(func(a: Dictionary) -> bool: return a.id in ["whetstone_edge", "tempered_edge"]), "Shop-to-targeted-craft preserves UID and gains an effective local family")
	check(model.select_class(4, model.revision(), TOWN_PATH).ok, "Select real Duelist source start")
	model.add_xp(100)
	check(model.save_build(TOWN_PATH) == OK, "Earned XP budget persists without injected stat grants")
	for node: String in DUAL: check(model.allocate_passive(node, 0, model.revision(), TOWN_PATH).ok, "Legal connected dual-leech allocation " + node)
	check(model.equip(uid), "Crafted original shop UID re-equipped")
	near(model.get_leech_profile().health.attack_fraction, 0.004, "Real source grants life leech")
	near(model.get_leech_profile().mana.attack_fraction, 0.004, "Real source grants mana leech")
	check(arena.start_map(arena.map_draft().revision).ok, "Normal test-map entry enables actual combat")
	clean_combat()
	var cast: Dictionary = model.get_group_cast(GROUP)
	var chosen_seed := critical_seed(cast.snapshot)
	arena.critical_runtime.reset(chosen_seed)
	var first := enemy(Vector2(60, 0), 80.0, 5.0)
	var second := enemy(Vector2(70, 15), 0.0, 10.0)
	var rear := enemy(Vector2(-80, 0))
	var mana_before: float = arena.mana
	var life_before: float = arena.health
	check(arena.cast_group(GROUP), "Actual main accepts cleave through gem-group command")
	check(arena.damage_trace.size() == 2, "One forward sector hits both front actors and excludes rear")
	if arena.damage_trace.size() != 2: arena.queue_free(); await process_frame; return
	near(arena.mana, mana_before - float(cast.mana), "Real cast charges compiled mana exactly once")
	near(arena.health, life_before, "Life leech is not instant on hit")
	near(rear.health, 10000.0, "Rear target survives outside sector")
	check(arena.critical_runtime.events == 1 and arena.critical_runtime.draws == 1, "One accepted cleave freezes one critical roll for all targets")
	var life_leech := 0.0; var mana_leech := 0.0
	for index: int in range(2):
		var hit: Dictionary = arena.damage_trace[index]
		var target: Dictionary = first if index == 0 else second
		check(hit.critical.critical and hit.critical == arena.damage_trace[0].critical, "All actual targets share frozen critical result")
		var raw := noncritical(cast) * float(cast.critical.primary.multiplier)
		var expected := raw * (1.0 - minf(0.9, float(target.armour) / (float(target.armour) + 5.0 * raw)))
		near(hit.total, expected, "Actual crit then hit-size armour80/zero formula")
		near(hit.shield_spent, 5.0 if index == 0 else 10.0, "Real hit spends shield before life")
		near(10000.0 - float(target.health), expected - float(hit.shield_spent), "Real target health matches settlement")
		near(hit.leech.health, expected * 0.004, "Actual post-armour loss grants only source life fraction")
		near(hit.leech.mana, expected * 0.004, "Actual post-armour loss grants only source mana fraction")
		life_leech += float(hit.leech.health); mana_leech += float(hit.leech.mana)
	var ledger := var_to_bytes(arena.leech_runtime.snapshot())
	var crit_checkpoint: Dictionary = arena.critical_runtime.checkpoint()
	var debt: Dictionary = arena.group_cooldowns.snapshot()
	check(not arena.cast_group(GROUP) and ledger == var_to_bytes(arena.leech_runtime.snapshot()) and crit_checkpoint == arena.critical_runtime.checkpoint() and debt == arena.group_cooldowns.snapshot(), "Rejected cooldown changes no recovery, critical stream or debt")
	var state_before := var_to_bytes(model.snapshot())
	var saved_bytes := FileAccess.get_file_as_bytes(TOWN_PATH)
	var mana_after: float = arena.mana
	arena._advance_leech(1.0)
	near(arena.health - life_before, life_leech, "Real main recovers complete finite life-leech budget")
	near(arena.mana - mana_after, mana_leech, "Real main recovers complete finite mana-leech budget")
	check(var_to_bytes(model.snapshot()) == state_before and FileAccess.get_file_as_bytes(TOWN_PATH) == saved_bytes, "Runtime leech adds no save data or build mutation")
	# Cleave is immediate. Preserve its already compiled and critical-frozen
	# payload, change real equipment, then probe the same main settlement consumer.
	var frozen_runtime := Critical.new(); frozen_runtime.reset(chosen_seed)
	var frozen: Dictionary = frozen_runtime.freeze(cast.snapshot)
	var frozen_bytes := var_to_bytes([cast.packets.direct, frozen.snapshot])
	check(model.unequip("weapon") and model.item(uid).payload == crafted, "Real unequip preserves same crafted UID and rolls")
	check(var_to_bytes([cast.packets.direct, frozen.snapshot]) == frozen_bytes and noncritical(model.get_group_cast(GROUP)) < noncritical(cast), "New cast drops W while prior compiled packet and critical freeze remain intact")
	clean_combat()
	var tiny := enemy(Vector2(60, 0), 80.0, 7.0, 3.0)
	arena._apply_damage_packet(tiny, cast.packets.direct, frozen.snapshot, Color.WHITE, 0.0, {"cast_id": 555})
	var clipped: Dictionary = arena.damage_trace.back()
	near(clipped.before_defense_components.physical, noncritical(cast) * float(cast.critical.primary.multiplier), "Unequipped current model cannot reinterpret prior weapon and critical payload")
	near(clipped.shield_spent + clipped.health_lost, 10.0, "Frozen prior weapon hit respects real shield+life overkill ceiling")
	near(clipped.leech.health, 0.04, "Overkill excluded from actual life leech")
	near(clipped.leech.mana, 0.04, "Overkill excluded from actual mana leech")
	check(clipped.critical == frozen.snapshot.critical_roll, "Already frozen critical result not reinterpreted after equipment change")
	check(model.equip(uid), "Original crafted UID re-equipped for final save")
	var loaded := Model.new()
	check(loaded.load_build(TOWN_PATH) and Planner._same_data(loaded.snapshot(), model.snapshot()) and loaded.get_group_cast(GROUP) == model.get_group_cast(GROUP), "Save/reload restores exact crafted UID, gems, source nodes and compiled cleave")
	report.actual_main = {"uid": uid, "item": crafted, "critical_seed": chosen_seed, "noncritical": noncritical(cast), "critical": cast.critical,
		"leech": cast.leech, "overkill_frozen_hit": arena.damage_trace.back(), "schema": model.snapshot().version}
	sections.actual_main = checks - start
	arena.queue_free(); await process_frame
	finished = true


func full_bag() -> void:
	var start := checks
	var model := FaultModel.new()
	check(model.load_build(TOWN_PATH), "Load actual completed town inventory for full-bag probe")
	check(model.unequip("weapon"), "Return crafted blade to bag before capacity fixture")
	var uid := ""
	for owned: String in model.snapshot().items:
		if model.item(owned).kind == "equipment" and model.item(owned).payload.get("base_id", "") == "forgeblade": uid = owned; break
	check(not uid.is_empty(), "Locate real forgeblade UID from prior shop flow")
	check(model.town_claim_offer("currency:calibration_shard", model.revision(), TOWN_PATH).ok, "Fund capacity craft using actual supply")
	var candidate := model.snapshot()
	var context := Model.Migration.paged_location_context(candidate, model._socket_ids)
	var occupied: Dictionary = Locations.validate_current(Items.metadata_for_items(candidate.items), candidate.locations, context).occupied_cells
	for page: int in range(2):
		for y: int in range(10):
			for x: int in range(12):
				if occupied.has("bag:%d:%d:%d" % [page, x, y]): continue
				var filler := "item_%06d" % int(candidate.next_item_serial); candidate.next_item_serial += 1
				candidate.items[filler] = Model.Gems.create_instance(filler, "skill:bolt")
				candidate.locations[filler] = {"kind": "bag", "page": page, "x": x, "y": y}
	check(Model.Rules.reason(candidate).is_empty(), "Explicit full 240-cell canonical fixture remains legal")
	model._accept_memory(candidate)
	check(model.save_build(TOWN_PATH) == OK, "Persist valid full inventory fixture")
	var f := {"model": model, "path": TOWN_PATH}
	var before := mark(f)
	reject(model.town_claim_offer("base:forgeblade", model.revision(), TOWN_PATH), "bag_full", "Full bag refuses new 1x3 base")
	unchanged(f, before, "Full-bag supply retains currency, UID serial, revision and pending state")
	var original: Dictionary = model.item(uid).payload
	var original_location: Dictionary = model.location(uid)
	var quote: Dictionary = model.crafting_quote("targeted_reforge_damage", uid, TOWN_PATH)
	check(quote.ok and model.execute_crafting(quote.handle, original).ok, "Full bag permits same-UID in-place targeted craft")
	check(model.location(uid) == original_location and Gear.validate_instance(model.item(uid).payload), "Full-bag replacement needs no new slot and preserves footprint")
	var restored := Model.new()
	check(restored.load_build(TOWN_PATH) and Planner._same_data(restored.snapshot(), model.snapshot()), "Full-bag successful replacement roundtrips")
	sections.full_bag = checks - start
	finished = true
