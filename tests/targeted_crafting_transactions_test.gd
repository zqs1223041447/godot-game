extends SceneTree
## Focused v0.49 authority, persistence and compiled-consumer checks.
const Model = preload("res://scripts/canonical_game_state.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const OLD_OPERATIONS = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
const TARGETS = {
	"targeted_reforge_critical": ["global_critical_chance", "global_critical_multiplier"],
	"targeted_reforge_life_leech": ["attack_life_leech"],
	"targeted_reforge_mana_leech": ["attack_mana_leech"],
	"targeted_reforge_damage": ["runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread",
		"attack_added_physical", "attack_added_fire", "spell_added_cold", "spell_added_lightning", "whetstone_edge", "tempered_edge"],
}
const METADATA_FIELDS = ["operation", "label", "description", "risk", "cost", "materials", "available", "reason"]
const QUOTE_FIELDS = ["ok", "code", "reason", "operation", "item_id", "revision", "rules_version",
	"source_instance", "cost", "materials", "consumes_item", "handle"]

class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)

var checks := 0
var failures := 0
var changes := 0
var completed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):
		quit(78)
		return
	for test: Callable in [_metadata, _atomic_transactions, _planner_authority,
			_rejected_model_requests, _stale_and_external_changes, _compiled_consumer]:
		completed = false
		test.call()
		_check(completed, "Case completes without script exception: " + test.get_method())
	print("Targeted crafting transactions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _roll(id: String) -> Dictionary:
	return {"id": id, "tier": 1, "value": Gear.affix_definition(id).tiers[0].min}


func _source(uid: String, operation: String, rarity: String = "magic") -> Dictionary:
	var bow := operation == "targeted_reforge_damage"
	var affixes: Array = [_roll("deepwell"), _roll("wellturn")] if bow else \
		[_roll("nine_slot_prefix_vitality"), _roll("nine_slot_suffix_endurance")]
	if rarity == "rare":
		affixes.append(_roll("whetstone_edge" if bow else "nine_slot_prefix_clarity"))
		affixes.append(_roll("coalglow" if bow else "nine_slot_suffix_mana_flow"))
	elif rarity == "normal":
		affixes.clear()
	return {"id": uid, "base_id": "ashwood_bow" if bow else "nine_slot_etched_ring",
		"rarity": rarity, "item_level": 30, "affixes": affixes}


func _fixture(operation: String, rarity: String = "magic", funds: int = -1) -> Dictionary:
	var model := FaultModel.new()
	var source := _source("gear_%06d" % int(model.snapshot().next_item_serial), operation, rarity)
	_check(Gear.validate_instance(source) and model._admit_reward_item(Items.wrap_equipment(source)),
		"Admit catalog-valid source with current canonical serial")
	var cost := 40 if rarity == "rare" else 16
	if funds < 0:
		funds = cost
	var stacks: Array[String] = []
	for quantity: int in [1, funds - 1]:
		if quantity <= 0:
			continue
		var uid := "item_%06d" % int(model.snapshot().next_item_serial)
		_check(model._admit_reward_item(Items.calibration_shard(uid, quantity)), "Admit actual canonical shard UID")
		stacks.append(uid)
	var path := "user://targeted-%s-%s-%d.json" % [operation, rarity, Time.get_ticks_usec()]
	_check(model.save_build(path) == OK, "Save coherent schema30 fixture")
	return {"model": model, "source": source, "path": path, "stacks": stacks, "cost": cost}


func _entry(entries: Array, operation: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.operation == operation:
			return entry
	return {}


func _rejected(result: Dictionary, code: String, label: String) -> void:
	_check(not result.ok and result.get("code", "") == code and not str(result.get("reason", "")).is_empty(), label)
	_check(result.size() == 3 and result.has_all(["ok", "code", "reason"]), "Rejection exposes no partial candidate or result")


func _unchanged(model: FaultModel, before: Dictionary, disk: PackedByteArray, path: String,
		attempts: int, label: String) -> void:
	_check(var_to_bytes(model.snapshot()) == var_to_bytes(before), label + ": complete state remains byte-identical")
	_check(FileAccess.get_file_as_bytes(path) == disk and model.save_attempts == attempts,
		label + ": no save attempt and exact disk bytes preserved")


func _valid_target(item: Dictionary, operation: String) -> void:
	_check(Gear.validate_instance(item), "Replacement passes real catalog validation")
	_check(item.affixes.any(func(a: Dictionary) -> bool: return TARGETS[operation].has(a.id)),
		"Replacement contains a pre-existing family from the selected target: " + operation)
	var groups := {}
	var counts := {"prefix": 0, "suffix": 0}
	for affix: Dictionary in item.affixes:
		var family := Gear.affix_definition(affix.id)
		var tier: Dictionary = family.tiers[int(affix.tier) - 1]
		_check(not groups.has(family.group) and Gear.family_eligible(affix.id, item.base_id),
			"Replacement obeys unique groups and base eligibility")
		_check(int(tier.level) <= int(item.item_level) and int(affix.value) >= int(tier.min)
			and int(affix.value) <= int(tier.max), "Replacement obeys unlocked tiers and inclusive roll bounds")
		groups[family.group] = true
		counts[family.kind] += 1
	var limits: Dictionary = Gear.RARITIES[item.rarity]
	_check(item.affixes.size() >= limits.min_affixes and item.affixes.size() <= limits.max_affixes
		and counts.prefix <= limits.max_prefixes and counts.suffix <= limits.max_suffixes,
		"Replacement obeys original rarity affix and prefix/suffix limits")


func _metadata() -> void:
	var f := _fixture("targeted_reforge_life_leech", "magic", 100)
	var model: FaultModel = f.model
	var before := model.snapshot()
	var disk := FileAccess.get_file_as_bytes(f.path)
	var attempts := model.save_attempts
	var sequence: int = model._craft_sequence
	seed(49001)
	var expected_rng := randi()
	seed(49001)
	var entries := model.crafting_operations(f.source.id, f.path)
	_check(randi() == expected_rng, "Metadata does not advance global RNG")
	_check(entries.size() == 10, "Metadata exposes six existing and four targeted operations")
	_check(model._craft_sequence == sequence and model._craft_quotes.is_empty(), "Metadata creates no quote handle")
	_unchanged(model, before, disk, f.path, attempts, "Metadata")
	for operation: String in OLD_OPERATIONS:
		var entry := _entry(entries, operation)
		_check(entry.size() == METADATA_FIELDS.size() and entry.has_all(METADATA_FIELDS), "Old six metadata shapes preserved: " + operation)
	for operation: String in TARGETS:
		var entry := _entry(entries, operation)
		_check(entry.size() == METADATA_FIELDS.size() + 3 and entry.has_all(METADATA_FIELDS)
			and entry.get("targeted", false) == true and entry.get("target_id", "") == operation.trim_prefix("targeted_reforge_")
			and not str(entry.get("target_label", "")).is_empty(), "Targeted metadata identifies selected family: " + operation)
		if operation != "targeted_reforge_damage":
			_check(entry.available and entry.cost == {Craft.MATERIAL_ID: 16} and entry.materials.is_empty(), "Eligible metadata derives exact magic fee")
		else:
			_check(not entry.available and not entry.reason.is_empty(), "No damage family on ring disables target with reason")
	_entry(entries, "targeted_reforge_life_leech").cost[Craft.MATERIAL_ID] = 0
	_check(_entry(model.crafting_operations(f.source.id, f.path), "targeted_reforge_life_leech").cost == {Craft.MATERIAL_ID: 16},
		"Nested metadata economics are detached")
	for uid: Variant in [null, "", 17, false, "missing"]:
		entries = model.crafting_operations(uid, f.path)
		_check(entries.size() == 10, "Invalid selection retains all ten discoverable operations")
		for entry: Dictionary in entries:
			_check(not entry.available and not entry.reason.is_empty(), "Invalid selection disabled with explanation")
	_unchanged(model, before, disk, f.path, attempts, "Rejected metadata reads")
	completed = true


func _atomic_transactions() -> void:
	for operation: String in TARGETS:
		for rarity: String in ["magic", "rare"]:
			var f := _fixture(operation, rarity)
			var model: FaultModel = f.model
			var source: Dictionary = f.source
			var before := model.snapshot()
			var disk := FileAccess.get_file_as_bytes(f.path)
			var attempts := model.save_attempts
			var quote := model.crafting_quote(operation, source.id, f.path)
			_check(quote.ok, "Quote accepts eligible actual bag item: " + operation + "/" + rarity)
			if not quote.ok:
				continue
			_check(quote.size() == QUOTE_FIELDS.size() and quote.has_all(QUOTE_FIELDS), "Exact existing quote envelope plus handle; no target or future result")
			_check(quote.operation == operation and quote.source_instance == source and quote.revision == before.crafting.revision
				and quote.rules_version == "original-targeted-reforge-v1-affix27" and quote.cost == {Craft.MATERIAL_ID: f.cost}
				and quote.materials.is_empty() and not quote.consumes_item, "Quote binds target in operation and authoritative exact economics")
			model.cancel_crafting_quote(quote.handle)
			_rejected(model.execute_crafting(quote.handle, source), "unknown_quote", "Cancelled target cannot consume")
			_unchanged(model, before, disk, f.path, attempts, "Cancelled transaction")
			quote = model.crafting_quote(operation, source.id, f.path)
			var wrong := source.duplicate(true)
			wrong.item_level = 16
			_rejected(model.execute_crafting(quote.handle, wrong), "source_mismatch", "Changed selected source rejected")
			_rejected(model.execute_crafting(quote, source), "unknown_quote", "Caller cannot submit edited quote dictionary as authority")
			_unchanged(model, before, disk, f.path, attempts, "Tampered source or quote")
			var seed_text := JSON.stringify({"rules": Craft.seed_rules_version(operation),
				"revision": before.crafting.revision, "item": source}, "", true, true)
			var expected := Craft.operation_plan(source, operation, seed_text.sha256_text().substr(0, 15).hex_to_int())
			_check(expected.ok, "Same deterministic authoritative seed produces valid target plan")
			# Public quote edits cannot redirect the server-owned handle, including a
			# different valid target at the same price. The planner itself is stateless.
			quote.operation = "targeted_reforge_damage" if operation != "targeted_reforge_damage" else "targeted_reforge_critical"
			quote.source_instance.item_level = 1
			quote.cost[Craft.MATERIAL_ID] = 0
			quote.target_id = "forged"
			var saves := model.successful_saves
			changes = 0
			model.changed.connect(func(): changes += 1)
			model.fail_save = true
			seed(49002)
			var expected_rng := randi()
			seed(49002)
			var failed := model.execute_crafting(quote.handle, source)
			_check(not failed.ok and randi() == expected_rng, "Failed save uses no global RNG")
			_check(var_to_bytes(model.snapshot()) == var_to_bytes(before) and FileAccess.get_file_as_bytes(f.path) == disk,
				"Failed save preserves all owned items, locations, currency, revisions and exact disk bytes")
			_check(changes == 0 and model.successful_saves == saves and model.save_attempts == attempts + 1,
				"Failed write attempts once, emits no change and records no successful save")
			model.fail_save = false
			seed(49003)
			expected_rng = randi()
			seed(49003)
			var result := model.execute_crafting(quote.handle, source)
			_check(result.ok and randi() == expected_rng, "Same handle retries successfully using isolated deterministic RNG")
			if not result.ok:
				continue
			_check(result.operation == operation and result.cost == {Craft.MATERIAL_ID: f.cost}, "Visible quote tampering cannot redirect operation or price")
			_check(changes == 1 and model.successful_saves == saves + 1 and model.save_attempts == attempts + 2,
				"Successful retry commits exactly once and emits exactly one change")
			var after := model.snapshot()
			var item: Dictionary = model.item(source.id).payload
			_check(item == expected.instance and model.location(source.id) == before.locations[source.id], "Exact seeded replacement preserves original bag page and cells")
			for field: String in ["id", "base_id", "rarity", "item_level"]:
				_check(item[field] == source[field], "Target reforge preserves " + field)
			_valid_target(item, operation)
			if rarity == "magic" or operation != "targeted_reforge_damage":
				_check(item.affixes != source.affixes, "Affixes fully replaced from source lacking the selected target")
			_check(model.crafting_balance() == 0, "Real bag shard balance debited to exact zero")
			var exact := before.duplicate(true)
			exact.items[source.id] = Items.wrap_equipment(item)
			for uid: String in f.stacks:
				_check(model.item(uid).is_empty() and model.location(uid).is_empty(), "Consumed real shard UID removed from items and locations")
				exact.items.erase(uid)
				exact.locations.erase(uid)
			exact.revision += 1
			exact.crafting.revision += 1
			_check(Planner._same_data(after, exact), "Entire resulting build changes only crafted payload, paid shard stacks and two revisions")
			_check(after.version == 30 and after.next_item_serial == before.next_item_serial and after.crafting.keys() == ["revision"],
				"Schema30 and sole crafting revision preserved; no new UID or target ledger")
			var saved_disk := FileAccess.get_file_as_bytes(f.path)
			var replay_attempts := model.save_attempts
			_rejected(model.execute_crafting(quote.handle, source), "unknown_quote", "Successful handle cannot replay")
			_unchanged(model, after, saved_disk, f.path, replay_attempts, "Replay")
			var restored := Model.new()
			_check(restored.load_build(f.path) and Planner._same_data(restored.snapshot(), after), "Full schema30 roundtrip preserves exact target output and unrelated UIDs")
	completed = true


func _reject_plan(context: Dictionary, quote: Dictionary, code: String) -> void:
	var before := var_to_bytes([context, quote])
	seed(49004)
	var expected_rng := randi()
	seed(49004)
	_rejected(Planner.plan(context, quote, 49), code, "Planner rejects " + code)
	_check(var_to_bytes([context, quote]) == before and randi() == expected_rng, "Rejected planner input remains byte-identical and consumes no RNG")


func _planner_authority() -> void:
	for operation: String in TARGETS:
		var f := _fixture(operation)
		var model: FaultModel = f.model
		var context: Dictionary = model._craft_context(f.source.id, f.path)
		var quote := Planner.quote(context, operation, f.source.id)
		_check(quote.ok and quote.size() == Planner.QUOTE_FIELDS.size(), "Planner retains exact established quote envelope")
		if not quote.ok:
			continue
		var before := var_to_bytes([context, quote])
		var plan := Planner.plan(context, quote, 49)
		_check(plan.ok and var_to_bytes([context, quote]) == before, "Planner returns detached atomic candidate without input mutation")
		if plan.ok:
			_valid_target(plan.candidate.equipment_instances[f.source.id], operation)
			_check(plan.candidate.materials[Craft.MATERIAL_ID] == 0 and plan.candidate.revision == context.revision + 1,
				"Planner pays exact target cost and advances one crafting revision")
			_reject_plan(plan.candidate, quote, "insufficient_materials")
			# Re-fund the projection to isolate replay's revision/source rejection
			# from the planner's earlier insufficient-wallet guard.
			var funded_after: Dictionary = plan.candidate.duplicate(true)
			funded_after.materials[Craft.MATERIAL_ID] = context.materials[Craft.MATERIAL_ID]
			_reject_plan(funded_after, quote, "stale_quote")
		for edits: Dictionary in [{"operation": "targeted_reforge_unknown"}, {"cost": {}}, {"cost": {Craft.MATERIAL_ID: 0}},
				{"materials": {Craft.MATERIAL_ID: 1}}, {"consumes_item": true}, {"target_id": "life_leech"}, {"seed": 49}]:
			var forged := quote.duplicate(true)
			forged.merge(edits, true)
			_reject_plan(context, forged, "invalid_quote")
		var forged := quote.duplicate(true)
		forged.source_instance.item_level = 16
		_reject_plan(context, forged, "stale_quote")
		forged = quote.duplicate(true)
		forged.rules_version = "older-rules"
		_reject_plan(context, forged, "stale_quote")
		var changed := context.duplicate(true)
		changed.revision += 1
		_reject_plan(changed, quote, "stale_quote")
		changed = context.duplicate(true)
		changed.materials[Craft.MATERIAL_ID] -= 1
		_reject_plan(changed, quote, "insufficient_materials")
		changed = context.duplicate(true)
		changed.save_writable = false
		_reject_plan(changed, quote, "save_read_only")
	completed = true


func _rejected_model_requests() -> void:
	for operation: String in TARGETS:
		var f := _fixture(operation, "magic", 15)
		var model: FaultModel = f.model
		var before := model.snapshot()
		var disk := FileAccess.get_file_as_bytes(f.path)
		var attempts := model.save_attempts
		var sequence: int = model._craft_sequence
		seed(49005)
		var expected_rng := randi()
		seed(49005)
		_rejected(model.crafting_quote(operation, f.source.id, f.path), "insufficient_materials", "Target quote rejects one-shard deficit")
		for invalid: Variant in ["targeted_reforge_unknown", "targeted_reforge", "", null, 17, false]:
			_rejected(model.crafting_quote(invalid, f.source.id, f.path), "invalid_operation", "Invalid target/action rejected")
		_check(randi() == expected_rng and model._craft_sequence == sequence and model._craft_quotes.is_empty(),
			"Rejected quotes create no authority and consume no RNG")
		_check(not _entry(model.crafting_operations(f.source.id, f.path), operation).available, "Insufficient funds reflected by metadata")
		_unchanged(model, before, disk, f.path, attempts, "Invalid target and insufficient funds")
		f = _fixture(operation, "normal", 100)
		model = f.model
		before = model.snapshot()
		disk = FileAccess.get_file_as_bytes(f.path)
		attempts = model.save_attempts
		_check(not model.crafting_quote(operation, f.source.id, f.path).ok, "Target reforge rejects normal gear")
		_unchanged(model, before, disk, f.path, attempts, "Wrong rarity")
	var f := _fixture("targeted_reforge_damage", "magic", 100)
	var model: FaultModel = f.model
	var before := model.snapshot()
	var disk := FileAccess.get_file_as_bytes(f.path)
	var attempts := model.save_attempts
	for operation: String in ["targeted_reforge_critical", "targeted_reforge_life_leech", "targeted_reforge_mana_leech"]:
		_check(not model.crafting_quote(operation, f.source.id, f.path).ok, "Unsupported bow target rejected with no roll")
	_unchanged(model, before, disk, f.path, attempts, "No eligible target family")
	completed = true


func _stale_and_external_changes() -> void:
	for operation: String in TARGETS:
		var f := _fixture(operation)
		var model: FaultModel = f.model
		var quote := model.crafting_quote(operation, f.source.id, f.path)
		_check(quote.ok, "Issue target authority before intervening build change")
		if not quote.ok:
			continue
		model.add_xp(1)
		var before := model.snapshot()
		var disk := FileAccess.get_file_as_bytes(f.path)
		var attempts := model.save_attempts
		_rejected(model.execute_crafting(quote.handle, f.source), "stale_quote", "Any intervening model revision invalidates target quote")
		_unchanged(model, before, disk, f.path, attempts, "Stale model quote")
		f = _fixture(operation)
		model = f.model
		quote = model.crafting_quote(operation, f.source.id, f.path)
		var file := FileAccess.open(f.path, FileAccess.WRITE)
		file.store_string(JSON.stringify(model.snapshot(), "  "))
		file.close()
		before = model.snapshot()
		disk = FileAccess.get_file_as_bytes(f.path)
		attempts = model.save_attempts
		_rejected(model.execute_crafting(quote.handle, f.source), "save_changed", "Raw external file re-encoding invalidates target quote")
		_unchanged(model, before, disk, f.path, attempts, "External raw bytes change")
		_check(not _entry(model.crafting_operations(f.source.id, f.path), operation).available, "External save protection disables target metadata")
		f = _fixture(operation)
		model = f.model
		quote = model.crafting_quote(operation, f.source.id, f.path)
		_check(model.load_build(f.path), "Reload coherent target fixture")
		_rejected(model.execute_crafting(quote.handle, f.source), "unknown_quote", "Reload clears pre-reload target authority")
	completed = true


func _compiled_consumer() -> void:
	var operation := "targeted_reforge_life_leech"
	var f := _fixture(operation, "magic", 23)
	var model: FaultModel = f.model
	var quote := model.crafting_quote(operation, f.source.id, f.path)
	_check(quote.ok, "Real compiled-consumer target quote issued")
	if not quote.ok:
		completed = true
		return
	var remaining_uid: String = f.stacks[1]
	var position := model.location(remaining_uid)
	_check(model.execute_crafting(quote.handle, f.source).ok, "Real selected-life target craft commits")
	_check(model.item(f.stacks[0]).is_empty() and model.item(remaining_uid).payload.quantity == 7
		and model.location(remaining_uid) == position and model.crafting_balance() == 7,
		"Debit spans actual UIDs, removes empty stack and preserves partially spent stack UID and cells")
	var crafted: Dictionary = model.item(f.source.id).payload
	var fraction := 0.0
	for affix: Dictionary in crafted.affixes:
		if affix.id == "attack_life_leech":
			fraction += float(affix.value) / 10000.0
	_check(fraction > 0.0, "Crafted existing life family carries a real nonzero catalog roll")
	_check(model.move_item(f.source.id, {"kind": "equipment", "slot_id": "ring_1"}, model.revision(), f.path).ok,
		"Crafted same UID equips through authoritative transfer transaction")
	var attempts := model.save_attempts
	var cast := model.get_basic_cast()
	_check(cast.ok and cast.has("leech"), "Real final compiled basic attack includes crafted life-leech consumer")
	if cast.ok and cast.has("leech"):
		_check(is_equal_approx(float(cast.leech.health.attack_fraction), fraction), "Compiled attack consumes exact crafted basis-point fraction")
	var saved := model.snapshot()
	var loaded := Model.new()
	_check(loaded.load_build(f.path) and Planner._same_data(loaded.snapshot(), saved), "Equipped target output roundtrips under unchanged schema30")
	var restored := loaded.get_basic_cast()
	_check(restored.ok and restored.has("leech") and is_equal_approx(float(restored.leech.health.attack_fraction), fraction),
		"Reloaded equipped item reaches real compiled consumer with exact same fraction")
	_check(model.save_attempts == attempts, "Compiling crafted build creates no extra save")
	completed = true
