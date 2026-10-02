extends SceneTree
## Focused, standalone suite: no build model, scene, save file or live wallet.
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const ITEM_ID: String = "gear_000123"
const OTHER_ID: String = "gear_000124"
var checks: int = 0
var failures: int = 0
var eligible_pairs: int = 0
var planned_items: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_atomic_candidates, _authority_and_quotes, _replay,
			_material_revision_bounds, _schema_and_detachment, _rng, _all_catalog_items]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	print("Crafting transactions: %d bases, %d eligible pairs, %d items; %d checks, %d failures" % [
		Catalog.all_base_ids().size(), eligible_pairs, planned_items, checks, failures])
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _roll(id: String, tier: int = 1, maximum: bool = false) -> Dictionary:
	var info: Dictionary = Catalog.affix_definition(id).tiers[tier - 1]
	return {"id": id, "tier": tier, "value": info.max if maximum else info.min}


func _item(base_id: String = "cinder_reed", affixes: Array = [], level: int = 16,
		rarity: String = "magic") -> Dictionary:
	return {"id": ITEM_ID, "base_id": base_id, "rarity": rarity, "item_level": level,
		"affixes": [_roll("deepwell")] if affixes.is_empty() and rarity == "magic" else affixes.duplicate(true)}


func _context(item: Dictionary, balance: int = 100, serialized: bool = false) -> Dictionary:
	var other: Dictionary = _item("pulse_seed", [_roll("rootwell")])
	other.id = OTHER_ID
	var positions: Dictionary = {"item:" + ITEM_ID: Vector2i(2, 0),
		"item:" + OTHER_ID: Vector2i(4, 0), "item:swift_blade": Vector2i(5, 0),
		"jewel:jewel_000001": Vector2i(7, 0)}
	if serialized:
		for key: String in positions:
			var cell: Vector2i = positions[key]
			positions[key] = [cell.x, cell.y]
	var inventory: Array[String] = [ITEM_ID, OTHER_ID, "ember_wand", "guardian_robe", "azure_charm", "swift_blade"]
	return {"revision": 7, "inventory": inventory, "equipment_instances": {ITEM_ID: item.duplicate(true), OTHER_ID: other},
		"equipped": {"weapon": "ember_wand", "armor": "guardian_robe", "charm": "azure_charm"},
		"backpack_positions": positions, "materials": {Craft.MATERIAL_ID: balance}, "save_writable": true}


func _failure(result: Dictionary, code: String) -> void:
	_expect(not result.ok and result.code == code and result.reason is String and not result.reason.is_empty(),
		"Failure has stable code and explanation: " + code)
	_expect(result.size() == 3 and result.has_all(["ok", "code", "reason"]),
		"Failure exposes no candidate, source, economics or partial results")


func _reject_quote(context: Variant, operation: Variant, id: Variant, code: String) -> void:
	var before: PackedByteArray = var_to_bytes(context)
	_failure(Planner.quote(context, operation, id), code)
	_expect(var_to_bytes(context) == before, "Rejected quote does not mutate context")


func _reject_plan(context: Variant, quoted: Variant, seed_value: Variant, code: String) -> void:
	var before: PackedByteArray = var_to_bytes([context, quoted])
	_failure(Planner.plan(context, quoted, seed_value), code)
	_expect(var_to_bytes([context, quoted]) == before, "Rejected plan mutates neither authority nor submitted quote")


func _verify_item(item: Dictionary, serialized: bool = false, seed_value: int = -17) -> void:
	planned_items += 1
	_expect(Catalog.validate_instance(item), "Real-catalog fixture is valid: " + item.base_id)
	var context: Dictionary = _context(item, 100, serialized)
	var before: PackedByteArray = var_to_bytes(context)
	for operation: String in ["salvage", "recalibrate"]:
		var quoted: Dictionary = Planner.quote(context, operation, ITEM_ID)
		_expect(quoted.ok, "Owned affixed item can be quoted: " + operation)
		if not quoted.ok:
			continue
		_expect(quoted.size() == 11 and quoted.has_all(Planner.QUOTE_FIELDS), "Quote contains only the declared economics/binding fields")
		_expect(not quoted.has("instance") and not quoted.has("definition") and not quoted.has("seed")
			and not quoted.has("candidate"), "Quote never exposes rolled values, preview or seed")
		_expect(quoted.source_instance == item and quoted.revision == context.revision
			and quoted.rules_version == Craft.RULES_VERSION and quoted.item_id == ITEM_ID, "Quote binds exact original, identity, revision and rule version")
		var rule: Dictionary = Craft.salvage_quote(item) if operation == "salvage" else Craft.recalibrate_plan(item, seed_value)
		_expect(quoted.cost == rule.cost and quoted.materials == rule.materials
			and quoted.consumes_item == rule.consumes_item, "Economics come directly from Craft without a copied table")
		var quote_bytes: PackedByteArray = var_to_bytes(quoted)
		var result: Dictionary = Planner.plan(context, quoted, seed_value)
		_expect(result.ok, "Valid transaction produces an atomic candidate: " + operation)
		if not result.ok:
			continue
		var expected: Dictionary = context.duplicate(true)
		if operation == "salvage":
			expected.inventory.erase(ITEM_ID)
			expected.equipment_instances.erase(ITEM_ID)
			expected.backpack_positions.erase("item:" + ITEM_ID)
		else:
			expected.equipment_instances[ITEM_ID] = rule.instance.duplicate(true)
		expected.materials[Craft.MATERIAL_ID] += int(rule.materials.get(Craft.MATERIAL_ID, 0)) - int(rule.cost.get(Craft.MATERIAL_ID, 0))
		expected.revision += 1
		_expect(var_to_bytes(result.candidate) == var_to_bytes(expected), "Complete candidate matches authoritative rule result and only intended transaction changes")
		_expect(result.candidate.size() == 7 and result.candidate.has_all(Planner.CONTEXT_FIELDS), "Candidate preserves the whole seven-field projection")
		_expect(result.candidate.equipped == context.equipped and result.candidate.save_writable,
			"Unrelated worn items and writable flag survive")
		_expect(Planner.plan(context, quoted, seed_value) == result, "Same authority, quote and seed deterministically reproduce the candidate")
		_expect(var_to_bytes(context) == before and var_to_bytes(quoted) == quote_bytes, "Successful quote/plan leave both inputs byte-identical")


func _atomic_candidates() -> void:
	_verify_item(_item())
	_verify_item(_item("ashwood_bow", [_roll("whetstone_edge", 3), _roll("tempered_edge", 2),
		_roll("farweave"), _roll("coalglow", 3)], 16, "rare"), true, 20261002)
	var context: Dictionary = _context(_item())
	var quoted: Dictionary = Planner.quote(context, "recalibrate", ITEM_ID)
	# Plan reads current authority, including a changed wallet/position. The quote
	# is economics, not a reservation; integration must advance revisions on edits.
	context.materials[Craft.MATERIAL_ID] = 50
	context.backpack_positions["item:" + ITEM_ID] = Vector2i(8, 2)
	var result: Dictionary = Planner.plan(context, quoted, 19)
	_expect(result.ok and result.candidate.materials[Craft.MATERIAL_ID] == 50 - quoted.cost[Craft.MATERIAL_ID],
		"Debit is applied to current authoritative balance rather than a quoted balance")
	_expect(result.ok and result.candidate.backpack_positions == context.backpack_positions,
		"Recalibration preserves current authoritative positions")
	completed = true


func _authority_and_quotes() -> void:
	var context: Dictionary = _context(_item())
	var quoted: Dictionary = Planner.quote(context, "recalibrate", ITEM_ID)
	var changed: Dictionary = context.duplicate(true)
	changed.save_writable = false
	_reject_quote(changed, "salvage", ITEM_ID, "save_read_only")
	_reject_plan(changed, quoted, 1, "save_read_only")
	changed = context.duplicate(true)
	changed.equipped.weapon = ITEM_ID
	changed.backpack_positions.erase("item:" + ITEM_ID)
	changed.backpack_positions["item:ember_wand"] = Vector2i(2, 0)
	_reject_quote(changed, "recalibrate", ITEM_ID, "item_equipped")
	_reject_plan(changed, quoted, 1, "item_equipped")
	changed = context.duplicate(true)
	changed.inventory.erase(ITEM_ID)
	changed.equipment_instances.erase(ITEM_ID)
	changed.backpack_positions.erase("item:" + ITEM_ID)
	_reject_quote(changed, "salvage", ITEM_ID, "not_owned")
	_reject_plan(changed, quoted, 1, "not_owned")
	for operation: String in ["salvage", "recalibrate"]:
		_reject_quote(context, operation, "swift_blade", "fixed_item")
		_reject_quote(context, operation, "gear_999999", "not_owned")
		_reject_quote(_context(_item("cinder_reed", [], 1, "normal")), operation, ITEM_ID, "no_affixes")
	for operation: Variant in [null, true, 1, 1.0, [], {}, "upgrade", &"salvage"]:
		_reject_quote(context, operation, ITEM_ID, "invalid_operation")
	for id: Variant in [null, true, 1, 1.0, [], {}, "", &"gear_000123"]:
		_reject_quote(context, "salvage", id, "invalid_item_id")
	changed = context.duplicate(true)
	changed.revision += 1
	_reject_plan(changed, quoted, 1, "stale_quote")
	changed = context.duplicate(true)
	changed.equipment_instances[ITEM_ID].affixes[0] = _roll("deepwell", 1, true)
	_reject_plan(changed, quoted, 1, "stale_quote")
	var forged: Dictionary = quoted.duplicate(true)
	forged.rules_version = "different-rules"
	_reject_plan(context, forged, 1, "stale_quote")
	forged = quoted.duplicate(true)
	forged.source_instance.affixes[0].value += 1
	_reject_plan(context, forged, 1, "stale_quote")
	forged = quoted.duplicate(true)
	forged.item_id = OTHER_ID
	_reject_plan(context, forged, 1, "stale_quote")
	for edits: Dictionary in [{"cost": {}}, {"cost": {Craft.MATERIAL_ID: 0}},
			{"cost": {Craft.MATERIAL_ID: float(quoted.cost[Craft.MATERIAL_ID])}},
			{"materials": {Craft.MATERIAL_ID: 500}}, {"consumes_item": true}, {"consumes_item": 0},
			{"operation": "salvage"}, {"code": "success"}, {"reason": "edited"}, {"ok": false},
			{"revision": float(quoted.revision)}, {"rules_version": 1}]:
		forged = quoted.duplicate(true)
		forged.merge(edits, true)
		_reject_plan(context, forged, 1, "invalid_quote")
	for key: String in quoted:
		forged = quoted.duplicate(true)
		forged.erase(key)
		_reject_plan(context, forged, 1, "invalid_quote")
	for key: String in ["instance", "definition", "candidate", "seed"]:
		forged = quoted.duplicate(true)
		forged[key] = {}
		_reject_plan(context, forged, 1, "invalid_quote")
	for value: Variant in [null, true, 1, [], {}, RefCounted.new(), Planner.quote(context, "invalid", ITEM_ID)]:
		_reject_plan(context, value, 1, "invalid_quote")
	# Key insertion order is not provenance. Legitimate detached dictionaries may
	# be rebuilt without permitting altered types, economics or source values.
	var reordered: Dictionary = {}
	var keys: Array = quoted.keys()
	keys.reverse()
	for key: String in keys:
		reordered[key] = quoted[key].duplicate(true) if quoted[key] is Dictionary else quoted[key]
	var source: Dictionary = {}
	keys = reordered.source_instance.keys()
	keys.reverse()
	for key: String in keys:
		source[key] = reordered.source_instance[key]
	reordered.source_instance = source
	_expect(Planner.plan(context, reordered, 1).ok, "Field order does not cause a false forged/stale quote rejection")
	completed = true


func _replay() -> void:
	var item: Dictionary = _item()
	var same_seed: int = -1
	for seed_value: int in range(256):
		if var_to_bytes(Craft.recalibrate_plan(item, seed_value).instance) == var_to_bytes(item):
			same_seed = seed_value
			break
	_expect(same_seed >= 0, "A real same-value reroll seed is found")
	if same_seed < 0:
		completed = true
		return
	var context: Dictionary = _context(item)
	var quoted: Dictionary = Planner.quote(context, "recalibrate", ITEM_ID)
	var result: Dictionary = Planner.plan(context, quoted, same_seed)
	_expect(result.ok, "Same-value reroll is a valid paid transaction")
	if not result.ok:
		completed = true
		return
	_expect(var_to_bytes(result.candidate.equipment_instances[ITEM_ID]) == var_to_bytes(item), "Fixture really rerolled every value identically")
	_expect(result.candidate.revision == context.revision + 1 and result.candidate.materials[Craft.MATERIAL_ID]
		== context.materials[Craft.MATERIAL_ID] - quoted.cost[Craft.MATERIAL_ID], "Unchanged values still consume cost and advance revision")
	_reject_plan(result.candidate, quoted, same_seed, "stale_quote")
	var fresh: Dictionary = Planner.quote(result.candidate, "recalibrate", ITEM_ID)
	_expect(fresh.ok and Planner.plan(result.candidate, fresh, same_seed).ok, "A fresh quote can perform the next paid reroll")
	var salvage: Dictionary = Planner.quote(context, "salvage", ITEM_ID)
	_reject_plan(result.candidate, salvage, 0, "stale_quote")
	var salvaged: Dictionary = Planner.plan(context, salvage, 0)
	_expect(salvaged.ok, "Salvage produces a committed-state projection")
	if salvaged.ok:
		_reject_plan(salvaged.candidate, salvage, 0, "not_owned")
		_reject_plan(salvaged.candidate, quoted, same_seed, "not_owned")
	_expect(Planner.plan(context, quoted, same_seed).ok, "Stateless planning alone does not mark an uncommitted quote as consumed")
	completed = true


func _material_revision_bounds() -> void:
	var context: Dictionary = _context(_item())
	var recalibrate: Dictionary = Planner.quote(context, "recalibrate", ITEM_ID)
	var salvage: Dictionary = Planner.quote(context, "salvage", ITEM_ID)
	var debit: int = recalibrate.cost[Craft.MATERIAL_ID]
	var credit: int = salvage.materials[Craft.MATERIAL_ID]
	var changed: Dictionary = context.duplicate(true)
	changed.materials[Craft.MATERIAL_ID] = 0
	_reject_quote(changed, "recalibrate", ITEM_ID, "insufficient_materials")
	_reject_plan(changed, recalibrate, 0, "insufficient_materials")
	var result: Dictionary = Planner.plan(changed, salvage, 0)
	_expect(result.ok and result.candidate.materials[Craft.MATERIAL_ID] == credit, "Salvage works at the zero wallet lower bound")
	changed.materials[Craft.MATERIAL_ID] = debit - 1
	_reject_plan(changed, recalibrate, 0, "insufficient_materials")
	changed.materials[Craft.MATERIAL_ID] = debit
	result = Planner.plan(changed, recalibrate, 0)
	_expect(result.ok and result.candidate.materials[Craft.MATERIAL_ID] == 0, "Exact balance recalibration atomically reaches zero")
	changed.materials[Craft.MATERIAL_ID] = Planner.MAX_MATERIAL_COUNT - credit
	result = Planner.plan(changed, salvage, 0)
	_expect(result.ok and result.candidate.materials[Craft.MATERIAL_ID] == Planner.MAX_MATERIAL_COUNT,
		"Salvage can reach the signed-int upper bound exactly")
	changed.materials[Craft.MATERIAL_ID] += 1
	_reject_quote(changed, "salvage", ITEM_ID, "material_overflow")
	_reject_plan(changed, salvage, 0, "material_overflow")
	changed.materials[Craft.MATERIAL_ID] = Planner.MAX_MATERIAL_COUNT
	_reject_plan(changed, salvage, 0, "material_overflow")
	result = Planner.plan(changed, recalibrate, 0)
	_expect(result.ok and result.candidate.materials[Craft.MATERIAL_ID] == Planner.MAX_MATERIAL_COUNT - debit,
		"Recalibration safely debits the exact upper bound without float conversion")
	for value: Variant in [-1, -9223372036854775807 - 1, true, false, 0.0, 1.0, 1.5, NAN, INF, -INF,
			float(Planner.MAX_MATERIAL_COUNT), "100", null, [], {}]:
		changed = context.duplicate(true)
		changed.materials[Craft.MATERIAL_ID] = value
		_reject_quote(changed, "salvage", ITEM_ID, "invalid_materials")
		_reject_plan(changed, recalibrate, 0, "invalid_materials")
	for wallet: Variant in [null, true, [], {}, {"unknown": 1}, {Craft.MATERIAL_ID: 1, "unknown": 1}]:
		changed = context.duplicate(true)
		changed.materials = wallet
		_reject_plan(changed, salvage, 0, "invalid_materials")
	for revision: int in [0, Planner.MAX_REVISION - 1]:
		changed = context.duplicate(true)
		changed.revision = revision
		var quoted: Dictionary = Planner.quote(changed, "recalibrate", ITEM_ID)
		result = Planner.plan(changed, quoted, 0)
		_expect(result.ok and result.candidate.revision == revision + 1, "Revision reaches each valid boundary exactly")
	changed = context.duplicate(true)
	changed.revision = Planner.MAX_REVISION
	_reject_quote(changed, "recalibrate", ITEM_ID, "revision_overflow")
	_reject_plan(changed, recalibrate, 0, "revision_overflow")
	for revision: Variant in [-1, true, false, 0.0, 7.0, 1.5, NAN, INF, "7", null, [], {}]:
		changed = context.duplicate(true)
		changed.revision = revision
		_reject_plan(changed, salvage, 0, "invalid_revision")
	for seed_value: int in [0, 1, -1, 9223372036854775807, -9223372036854775807 - 1]:
		_verify_item(_item(), false, seed_value)
	for seed_value: Variant in [null, false, true, 0.0, 1.0, 1.25, NAN, INF, "1", [], {}, RefCounted.new()]:
		_reject_plan(context, recalibrate, seed_value, "invalid_seed")
		_reject_plan(context, salvage, seed_value, "invalid_seed")
	completed = true


func _schema_and_detachment() -> void:
	var context: Dictionary = _context(_item(), 100, true)
	var quoted: Dictionary = Planner.quote(context, "recalibrate", ITEM_ID)
	var changed: Dictionary
	for key: String in Planner.CONTEXT_FIELDS:
		changed = context.duplicate(true)
		changed.erase(key)
		_reject_quote(changed, "salvage", ITEM_ID, "invalid_context")
		_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.next_equipment_id = 125
	_reject_plan(changed, quoted, 0, "invalid_context")
	for value: Variant in [null, true, 1, "context", [], RefCounted.new()]:
		_reject_plan(value, quoted, 0, "invalid_context")
	for key: String in ["inventory", "equipment_instances", "equipped", "backpack_positions", "save_writable"]:
		for value: Variant in [null, 1, "invalid", RefCounted.new()]:
			changed = context.duplicate(true)
			changed[key] = value
			_reject_plan(changed, quoted, 0, "invalid_context")
	# Container mismatches, duplicate IDs, orphan records and wrong slots are
	# rejected before any transaction candidate can be built.
	for edits: Dictionary in [{"inventory": {}}, {"equipment_instances": []}, {"equipped": []},
			{"backpack_positions": []}, {"save_writable": 1.0}]:
		changed = context.duplicate(true)
		changed.merge(edits, true)
		_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.inventory.append(ITEM_ID)
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	# Use an untyped array so the planner, not Array[String], rejects this value.
	changed.inventory = [ITEM_ID, OTHER_ID, "ember_wand", "guardian_robe", "azure_charm", 1]
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.inventory.erase(ITEM_ID)
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.equipment_instances[OTHER_ID].id = ITEM_ID
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.equipment_instances[OTHER_ID].affixes[0].value = 999
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.equipment_instances[ITEM_ID] = null
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.equipped.weapon = "guardian_robe"
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.equipped.unknown = "ember_wand"
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.equipped.weapon = "gear_999999"
	_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.backpack_positions.erase("item:" + ITEM_ID)
	_reject_plan(changed, quoted, 0, "invalid_context")
	for key: Variant in ["item:gear_999999", "item:ember_wand", "unknown:key", "jewel:", 1]:
		changed = context.duplicate(true)
		changed.backpack_positions[key] = [0, 0]
		_reject_plan(changed, quoted, 0, "invalid_context")
	for cell: Variant in [null, true, 1, Vector2.ZERO, Vector2i(-1, 0), [], [0], [0, 0, 0],
			[-1, 0], [false, 0], ["0", 0], [0.5, 0], [NAN, 0], [INF, 0]]:
		changed = context.duplicate(true)
		changed.backpack_positions["item:" + ITEM_ID] = cell
		_reject_plan(changed, quoted, 0, "invalid_context")
	changed = context.duplicate(true)
	changed.backpack_positions["item:" + ITEM_ID] = [2.0, 0.0]
	_expect(Planner.plan(changed, quoted, 0).ok, "Serialized finite integral position coordinates are accepted")
	var json_item: Dictionary = JSON.parse_string(JSON.stringify(_item()))
	_verify_item(json_item, true)
	var before: PackedByteArray = var_to_bytes(context)
	var quote_before: PackedByteArray = var_to_bytes(quoted)
	var constants_before: PackedByteArray = var_to_bytes([Data.ITEMS, Craft.BALANCE,
		Catalog.base_definition("cinder_reed"), Catalog.affix_definition("deepwell")])
	var result: Dictionary = Planner.plan(context, quoted, 20)
	var repeat: Dictionary = Planner.plan(context, quoted, 20)
	_expect(result.ok and repeat.ok, "Detachment fixture produces full candidates")
	if result.ok and repeat.ok:
		var repeat_before: PackedByteArray = var_to_bytes(repeat)
		result.candidate.inventory.clear()
		result.candidate.equipment_instances[ITEM_ID].affixes[0].value = 999
		result.candidate.equipment_instances[OTHER_ID].affixes[0].value = 999
		result.candidate.equipped.clear()
		result.candidate.backpack_positions["item:swift_blade"][0] = 99
		result.candidate.backpack_positions["jewel:jewel_000001"][0] = 99
		result.candidate.materials[Craft.MATERIAL_ID] = 0
		result.candidate.revision = 0
		_expect(var_to_bytes(context) == before and var_to_bytes(quoted) == quote_before,
			"Candidate mutations cannot affect any nested authority or quote field")
		_expect(var_to_bytes(repeat) == repeat_before, "Independent candidates share no nested arrays or dictionaries")
	quoted.source_instance.affixes[0].value = 999
	quoted.cost[Craft.MATERIAL_ID] = 0
	quoted.materials[Craft.MATERIAL_ID] = 999
	_expect(var_to_bytes(context) == before, "Mutating detached quote source/economics cannot change authority")
	_reject_plan(context, quoted, 20, "stale_quote")
	var salvage: Dictionary = Planner.quote(context, "salvage", ITEM_ID)
	salvage.materials[Craft.MATERIAL_ID] += 1
	_reject_plan(context, salvage, 0, "invalid_quote")
	_expect(var_to_bytes([Data.ITEMS, Craft.BALANCE, Catalog.base_definition("cinder_reed"),
		Catalog.affix_definition("deepwell")]) == constants_before, "Returned values never alias Craft or catalog constants")
	completed = true


func _global_samples() -> Array:
	var samples: Array = []
	for unused: int in range(12):
		samples.append(randi())
		samples.append(randf())
	return samples


func _rng() -> void:
	var caller_rng := RandomNumberGenerator.new()
	caller_rng.seed = 20261002
	var item: Dictionary = Catalog.generate_for_pool(caller_rng, ITEM_ID, 16, "rare", "local_weapon")
	var caller_state: int = caller_rng.state
	var context: Dictionary = _context(item)
	var before: PackedByteArray = var_to_bytes(context)
	seed(20261002)
	var expected: Array = _global_samples()
	seed(20261002)
	for operation: String in ["salvage", "recalibrate"]:
		var quoted: Dictionary = Planner.quote(context, operation, ITEM_ID)
		_expect(quoted.ok and Planner.plan(context, quoted, 23).ok, "RNG isolation includes successful quote and plan")
		_reject_plan(context, quoted, caller_rng, "invalid_seed")
		var changed: Dictionary = context.duplicate(true)
		changed.save_writable = false
		_reject_plan(changed, quoted, 23, "save_read_only")
		quoted.revision -= 1
		_reject_plan(context, quoted, 23, "stale_quote")
	_expect(_global_samples() == expected, "Quotes, plans and rejection paths never consume or reseed the global RNG")
	_expect(caller_rng.state == caller_state, "Caller loot RNG is unchanged even when supplied as an invalid seed")
	_expect(var_to_bytes(context) == before, "RNG checks leave authority byte-identical")
	completed = true


func _all_catalog_items() -> void:
	var seen_bases: Dictionary = {}
	var seen_families: Dictionary = {}
	for base_id: String in Catalog.all_base_ids():
		for family_id: String in Catalog.all_affix_ids():
			if not Catalog.family_eligible(family_id, base_id):
				continue
			eligible_pairs += 1
			seen_bases[base_id] = true
			seen_families[family_id] = true
			for tier: Dictionary in Catalog.affix_definition(family_id).tiers:
				for maximum: bool in [false, true]:
					_verify_item(_item(base_id, [_roll(family_id, tier.tier, maximum)], tier.level), maximum)
		# Exercise all real bases with full rare counts/order and mixed tiers.
		for count: int in [4, 5, 6]:
			var prefixes: Array = []
			var suffixes: Array = []
			for family_id: String in Catalog.all_affix_ids():
				if not Catalog.family_eligible(family_id, base_id):
					continue
				var target: Array = prefixes if Catalog.affix_definition(family_id).kind == "prefix" else suffixes
				target.append(_roll(family_id, target.size() % 3 + 1))
			var prefix_count: int = 3 if count == 6 else 2
			var affixes: Array = prefixes.slice(0, prefix_count) + suffixes.slice(0, count - prefix_count)
			_verify_item(_item(base_id, affixes, Catalog.MAX_ITEM_LEVEL, "rare"), count == 5, 31)
		var normal: Dictionary = _item(base_id, [], Catalog.MAX_ITEM_LEVEL, "normal")
		for operation: String in ["salvage", "recalibrate"]:
			_reject_quote(_context(normal), operation, ITEM_ID, "no_affixes")
	_expect(seen_bases.size() == Catalog.all_base_ids().size(), "Every applicable real base is exercised")
	_expect(seen_families.size() == Catalog.all_affix_ids().size() and eligible_pairs == 91,
		"Every actual family and all 91 applicable base/family pairs are exercised")
	completed = true
