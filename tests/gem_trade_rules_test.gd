extends SceneTree
## Standalone pure-rule contract: no inventory, wallet, scenes or saves are created.
const Trade = preload("res://scripts/items/gem_trade_rules.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const RESULT_KEYS: Array[String] = ["ok", "code", "reason", "operation", "target",
	"definition_id", "name", "cost", "materials"]
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_all_definitions, _reject_operations_and_targets,
		_reject_buy_instances, _reject_recycle_instances, _detachment, _rng_and_input_purity]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	print("Gem trade rules: 26 definitions (10 active, 16 support); %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _all_definitions() -> void:
	var catalog: Dictionary = Gems.definitions()
	var offers: Array[Dictionary] = Trade.offers()
	var seen: Dictionary = {}
	var active_count: int = 0
	var support_count: int = 0
	_expect(Trade.MATERIAL_ID == "calibration_shard", "Trades use the existing material")
	_expect(Trade.ACTIVE_COST == 8 and Trade.SUPPORT_COST == 4 and Trade.RECYCLE_CREDIT == 1,
		"Original prototype prices are eight / four / one")
	_expect(catalog.size() == 26 and offers.size() == catalog.size(), "All twenty-six real definitions are offered")
	for offer: Dictionary in offers:
		_expect(offer.size() == 4 and offer.has_all(["definition_id", "kind", "name", "cost"]),
			"Offers expose only basic detached display fields")
		_expect(catalog.has(offer.definition_id) and not seen.has(offer.definition_id), "Each offer names a unique real definition")
		seen[offer.definition_id] = true
		var definition: Dictionary = catalog[offer.definition_id]
		var expected_cost: int = 8 if definition.kind == "skill_gem" else 4
		active_count += 1 if definition.kind == "skill_gem" else 0
		support_count += 1 if definition.kind == "support_gem" else 0
		_expect(offer.kind == definition.kind and offer.name == definition.name, "Offer uses exact catalog kind and display name")
		_expect(offer.cost is int and offer.cost == expected_cost, "Offer cost matches independent kind-based balance")
		var buy: Dictionary = Trade.quote("buy", offer.definition_id)
		_check_envelope(buy)
		_expect(buy.ok and buy.code == "" and buy.reason == "", "Every real definition has a successful purchase quote")
		_expect(buy.operation == "buy" and buy.target == offer.definition_id and buy.definition_id == offer.definition_id,
			"Purchase preserves operation and exact definition identity")
		_expect(buy.name == definition.name and buy.cost == {"calibration_shard": expected_cost} and buy.materials.is_empty(),
			"Purchase quotes one cost and no credit")
		_expect(buy.cost.calibration_shard is int, "Purchase cost remains an exact integer")
		var instance: Dictionary = Gems.create_instance("trade-test:" + offer.definition_id, offer.definition_id)
		var before: PackedByteArray = var_to_bytes(instance)
		var recycle: Dictionary = Trade.quote("recycle", instance.uid, instance)
		_check_envelope(recycle)
		_expect(recycle.ok and recycle.code == "" and recycle.reason == "", "Every real gem instance has a recycle quote")
		_expect(recycle.operation == "recycle" and recycle.target == instance.uid and recycle.definition_id == offer.definition_id,
			"Recycle preserves exact instance UID and resolves its real definition")
		_expect(recycle.name == definition.name and recycle.cost.is_empty() and recycle.materials == {"calibration_shard": 1},
			"Every real gem recycles for exactly one shard")
		_expect(recycle.materials.calibration_shard is int, "Recycle credit remains an exact integer")
		_expect(buy.cost.calibration_shard >= 4 and buy.cost.calibration_shard > recycle.materials.calibration_shard,
			"Buying then recycling any offered gem always loses material")
		_expect(var_to_bytes(instance) == before and instance.payload == {"level": 1, "quality": 0},
			"Quotes preserve fixed-level, zero-quality instance bytes")
		_expect(buy == Trade.quote("buy", offer.definition_id, {}) and recycle == Trade.quote("recycle", instance.uid, instance),
			"Repeated quotes are deterministic")
	_expect(active_count == 10 and support_count == 16, "Offer coverage is exactly ten active and sixteen support gems")
	_expect(seen.size() == catalog.size(), "No source definition is omitted")
	completed = true


func _reject_operations_and_targets() -> void:
	var instance: Dictionary = Gems.create_instance("gem:test", "skill:bolt")
	for operation: Variant in [null, false, true, 0, 1.0, [], {}, &"buy", &"recycle", RefCounted.new(), "", "Buy", "sell", "salvage", " buy"]:
		_reject(operation, "skill:bolt", {}, "invalid_operation")
	for target: Variant in [null, false, true, 0, 1.0, [], {}, &"skill:bolt", &"gem:test", RefCounted.new(), ""]:
		_reject("buy", target, {}, "invalid_target")
		_reject("recycle", target, instance, "invalid_target")
	for target: String in ["bolt", "focus", "skill:missing", "support:missing", "gem:test", " skill:bolt", "skill:bolt ", "skill:Bolt", " "]:
		_reject("buy", target, {}, "unknown_definition")
	for target: String in ["other-uid", "skill:bolt", " gem:test", "gem:test ", " "]:
		_reject("recycle", target, instance, "target_mismatch")
	completed = true


func _reject_buy_instances() -> void:
	for instance: Variant in [null, false, true, 0, 1.0, "", &"", [], RefCounted.new(),
		{"uid": "gem:test"}, Gems.create_instance("gem:test", "skill:bolt")]:
		_reject("buy", "skill:bolt", instance, "invalid_instance")
	_expect(Trade.quote("buy", "skill:bolt", {}).ok, "Only an empty Dictionary is the optional buy instance")
	completed = true


func _reject_recycle_instances() -> void:
	var valid: Dictionary = Gems.create_instance("gem:test", "skill:bolt")
	for instance: Variant in [null, false, true, 0, 1.0, "gem:test", &"gem:test", [], {}, RefCounted.new()]:
		_reject("recycle", "gem:test", instance, "invalid_instance")
	for key: String in valid:
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(key)
		_reject("recycle", "gem:test", missing, "invalid_instance")
		for value: Variant in [null, false, true, 1, 1.0, [], {}, "", StringName(valid[key]) if valid[key] is String else &"payload"]:
			var wrong: Dictionary = valid.duplicate(true)
			wrong[key] = value
			_reject("recycle", "gem:test", wrong, "invalid_instance")
	var extra: Dictionary = valid.duplicate(true)
	extra["location"] = {"kind": "bag"}
	_reject("recycle", "gem:test", extra, "invalid_instance")
	for key: String in ["level", "quality"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.payload.erase(key)
		_reject("recycle", "gem:test", missing, "invalid_instance")
		for value: Variant in [null, false, true, [], {}, "1", &"1", -1, 2, 1.0, 0.0, NAN, INF]:
			var wrong: Dictionary = valid.duplicate(true)
			wrong.payload[key] = value
			_reject("recycle", "gem:test", wrong, "invalid_instance")
		var other_number: Dictionary = valid.duplicate(true)
		other_number.payload[key] = 0 if key == "level" else 1
		_reject("recycle", "gem:test", other_number, "invalid_instance")
	var extra_payload: Dictionary = valid.duplicate(true)
	extra_payload.payload["experience"] = 0
	_reject("recycle", "gem:test", extra_payload, "invalid_instance")
	for field: String in ["uid", "definition_id", "kind"]:
		var bad: Dictionary = valid.duplicate(true)
		bad[field] = {"uid": "bad\nuid", "definition_id": "bolt", "kind": "support_gem"}[field]
		_reject("recycle", "gem:test", bad, "invalid_instance")
	_reject("recycle", "gem:test", JSON.parse_string(JSON.stringify(valid)), "invalid_instance")
	_reject("recycle", "gem:test", {}, "invalid_instance")
	completed = true


func _detachment() -> void:
	var baseline: Array[Dictionary] = Trade.offers()
	var offers: Array[Dictionary] = Trade.offers()
	_expect(offers == baseline, "Offer enumeration is deterministic")
	offers[0].definition_id = "skill:missing"
	offers[0].name = "changed"
	offers[0].kind = "currency"
	offers[0].cost = -10
	offers.remove_at(offers.size() - 1)
	_expect(Trade.offers() == baseline, "Mutating returned entries and arrays cannot change later offers")
	var instance: Dictionary = Gems.create_instance("gem:test", "skill:bolt")
	var before: PackedByteArray = var_to_bytes(instance)
	var buy: Dictionary = Trade.quote("buy", "skill:bolt")
	var pristine_buy: Dictionary = buy.duplicate(true)
	var recycle: Dictionary = Trade.quote("recycle", instance.uid, instance)
	var pristine_recycle: Dictionary = recycle.duplicate(true)
	buy.cost.calibration_shard = -1
	buy.materials.calibration_shard = 99
	buy.name = "changed"
	buy.definition_id = "skill:missing"
	recycle.materials.calibration_shard = 99
	recycle.cost.calibration_shard = -1
	recycle.target = "another-uid"
	_expect(Trade.quote("buy", "skill:bolt") == pristine_buy, "Purchase quote dictionaries are detached")
	_expect(Trade.quote("recycle", instance.uid, instance) == pristine_recycle, "Recycle quote dictionaries are detached")
	_expect(var_to_bytes(instance) == before and Trade.offers() == baseline, "Result mutation never reaches inputs or catalog offers")
	var rejected: Dictionary = Trade.quote("buy", "unknown")
	rejected.cost.calibration_shard = 4
	rejected.materials.calibration_shard = 1
	var next_rejected: Dictionary = Trade.quote("buy", "unknown")
	_expect(next_rejected.cost.is_empty() and next_rejected.materials.is_empty(), "Rejected quote dictionaries are also detached")
	instance.payload.level = 2
	instance.uid = "later-uid"
	_expect(pristine_recycle.target == "gem:test" and pristine_recycle.materials == {"calibration_shard": 1},
		"Later input mutation cannot alter a previous quote")
	completed = true


func _rng_and_input_purity() -> void:
	seed(441008)
	var expected: Array = _rng_samples()
	seed(441008)
	for unused: int in range(8):
		for offer: Dictionary in Trade.offers():
			var instance: Dictionary = Gems.create_instance("purity:" + offer.definition_id, offer.definition_id)
			var before: PackedByteArray = var_to_bytes(instance)
			Trade.quote("buy", offer.definition_id)
			Trade.quote("recycle", instance.uid, instance)
			Trade.quote("recycle", "wrong-uid", instance)
			Trade.quote("buy", offer.definition_id, instance)
			_expect(var_to_bytes(instance) == before, "Successful and rejected calls preserve all input bytes")
		Trade.quote(&"buy", "skill:bolt")
		Trade.quote("buy", &"skill:bolt")
		Trade.quote("recycle", "unknown", {})
	_expect(_rng_samples() == expected, "Offers and successful / rejected quotes never consume or reseed global RNG")
	var first: Array[Dictionary] = Trade.offers()
	seed(777)
	_rng_samples()
	_expect(Trade.offers() == first, "Ambient RNG state cannot affect offers")
	completed = true


func _rng_samples() -> Array:
	var result: Array = []
	for unused: int in range(12):
		result.append(randi())
		result.append(randf())
	return result


func _reject(operation: Variant, target: Variant, instance: Variant, code: String) -> void:
	var before: PackedByteArray = var_to_bytes([operation, target, instance])
	var result: Dictionary = Trade.quote(operation, target, instance)
	_check_envelope(result)
	_expect(not result.ok and result.code == code and not result.reason.is_empty(), "Rejected input reports stable reason: " + code)
	_expect(result.cost.is_empty() and result.materials.is_empty(), "Rejection exposes no cost or credit")
	_expect(result.definition_id.is_empty() and result.name.is_empty(), "Rejection exposes no valid-looking gem definition")
	_expect(result.operation == (operation if typeof(operation) == TYPE_STRING else "") and
		result.target == (target if typeof(target) == TYPE_STRING else ""), "Envelope never coerces operation or target types")
	_expect(var_to_bytes([operation, target, instance]) == before, "Rejected arguments remain byte-identical")


func _check_envelope(result: Dictionary) -> void:
	_expect(result.size() == RESULT_KEYS.size() and result.has_all(RESULT_KEYS), "Quote contains exactly the documented envelope")
	_expect(result.ok is bool and result.code is String and result.reason is String and result.operation is String
		and result.target is String and result.definition_id is String and result.name is String
		and result.cost is Dictionary and result.materials is Dictionary, "Every envelope field has its exact public type")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GemTradeRules: " + message)
