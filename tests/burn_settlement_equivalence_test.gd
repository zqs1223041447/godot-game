extends SceneTree
## One focused pure batch. The oracle and its only dependency are frozen v62.
const Current = preload("res://scripts/mechanics/defense_rules.gd")
const Before = preload("res://docs/qa/v063-settlement-rules/frozen/scripts/mechanics/defense_rules.gd")
const FrozenDamage = preload("res://docs/qa/v063-settlement-rules/frozen/scripts/combat/damage_resolver.gd")
const EVIDENCE = "res://docs/qa/v063-settlement-rules/"
const MAX_FINITE: float = 1.7976931348623157e308
var current := Current.new()
var before := Before.new()
var checks: int = 0
var failures: int = 0
var categories: Dictionary = {}
var timings: Dictionary = {}


func _initialize() -> void:
	if OS.get_name() != "Linux" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v063-"):
		push_error("Use the isolated v063 pure-rules runner")
		quit(78)
		return
	_verify_oracle()
	if failures:
		quit(1)
		return
	_valid_scalars()
	_float_samples()
	_invalid_priority()
	_optional_paths()
	_public_settlement()
	_other_adapters()
	_detached_returns()
	if failures == 0:
		_benchmark()
	var report: Dictionary = {"checks": checks, "failures": failures,
		"typed_byte_comparisons": categories, "baseline_commit": "b93018005413444ad6f988974f4ef3ea09902c5e",
		"engine": Engine.get_version_info().string, "microbenchmark": timings,
		"scope": "Pure incoming_burn receipts and unchanged public defense paths. Not a gameplay/frame-rate result."}
	var report_file := FileAccess.open(EVIDENCE + "results.json", FileAccess.WRITE)
	if report_file == null:
		push_error("Could not write focused rules report")
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t") + "\n")
	print("BURN_SETTLEMENT_EQUIVALENCE ", JSON.stringify(report))
	quit(1 if failures else 0)


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 20:
			push_error(label)


func _compare(method: String, args: Array, category: String) -> Dictionary:
	var expected: Variant = before.callv(method, args)
	var actual: Variant = current.callv(method, args)
	categories[category] = int(categories.get(category, 0)) + 1
	_check(var_to_bytes(actual) == var_to_bytes(expected), "%s %s args=%s expected=%s actual=%s" % [category, method, str(args), str(expected), str(actual)])
	return actual if actual is Dictionary else {}


func _verify_oracle() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE + "manifest.json"))
	_check(manifest is Dictionary and manifest.source_commit == "b93018005413444ad6f988974f4ef3ea09902c5e", "Oracle is pinned to published v62")
	if not manifest is Dictionary:
		return
	_check(manifest.entries.size() == 2, "Frozen recursive closure has exactly defense and DamageResolver")
	for entry: Dictionary in manifest.entries:
		_check(FileAccess.get_sha256(EVIDENCE + "source/" + entry.path + ".txt") == entry.source_sha256, "Original Git bytes hash: " + entry.path)
		_check(FileAccess.get_sha256(EVIDENCE + "frozen/" + entry.path) == entry.frozen_sha256, "Relocated oracle hash: " + entry.path)
		var code: String = FileAccess.get_file_as_string(EVIDENCE + "frozen/" + entry.path)
		_check(not code.contains("class_name ") and not code.contains('preload("res://scripts/'), "Oracle has no live production preload: " + entry.path)


func _adjacent(value: float, direction: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_u64(0, bytes.decode_u64(0) + direction)
	return bytes.decode_double(0)


func _valid_scalars() -> void:
	var tiny: float = _adjacent(0.0, 1)
	var amounts: Array = [0, 0.0, -0.0, tiny, tiny * 2.0, 2.2250738585072014e-308,
		1.0e-300, 1.0e-12, _adjacent(1.0, -1), 1.0, _adjacent(1.0, 1),
		7, 37.25, 255.0, 9007199254740991, 9007199254740993,
		9223372036854775807, 1.0e100, 1.0e300, MAX_FINITE]
	var resistances: Array = [-MAX_FINITE, -1, -tiny, -0.0, 0, 0.0, tiny,
		0.1, 0.25, _adjacent(0.75, -1), 0.75, _adjacent(0.75, 1), 0.83, 1, MAX_FINITE]
	var pools: Array = [[0, 0], [0.0, 0.0], [-0.0, -0.0], [-0.0, 0.0], [0.0, -0.0],
		[tiny, tiny], [0, 1], [1, 0], [0.1, 0.2], [10.0, 100.0], [100.0, 10.0],
		[1.0e300, 1.0e300], [MAX_FINITE, MAX_FINITE]]
	var zeroes: Array = [0, 0.0, -0.0]
	for raw: Variant in amounts:
		for resistance: Variant in resistances:
			for actor: String in ["monster", "player"]:
				for index: int in range(pools.size()):
					var pool: Array = pools[index]
					_compare("incoming_burn", [raw, resistance, pool[0], pool[1], actor, NAN, zeroes[index % 3], zeroes[(index / 3) % 3]], "valid_scalar_grid")
				var amount: float = float(raw) * (1.0 - clampf(float(resistance), 0.0, 0.75))
				if amount > 0.0:
					for boundary: float in [_adjacent(amount, -1), amount, _adjacent(amount, 1)]:
						if is_finite(boundary):
							_compare("incoming_burn", [raw, resistance, boundary, amount, actor], "shield_ulp_boundary")
							_compare("incoming_burn", [raw, resistance, 0.0, boundary, actor], "health_ulp_boundary")
	for raw: Variant in [0, 0.0, -0.0, tiny, MAX_FINITE]:
		for resistance: Variant in [-0.0, 0.0, 0.75]:
			for ratio: Variant in zeroes:
				for bonus: Variant in zeroes:
					for shield: Variant in zeroes:
						for health: Variant in zeroes:
							_compare("incoming_burn", [raw, resistance, shield, health, "monster", {"ignored": [1, 2]}, ratio, bonus], "zero_sign_and_types")
	var signed: Dictionary = _compare("incoming_burn", [-0.0, -0.0, -0.0, -0.0, "monster"], "explicit_signed_zero")
	_check(var_to_bytes(signed.damage_total) == var_to_bytes(0.0), "Negative-zero fire retains +0.0 accumulated damage_total")
	_check(var_to_bytes(signed.components.fire) == var_to_bytes(-0.0), "Negative-zero component remains -0.0")
	_check(signed.details.is_typed() and signed.details.get_typed_builtin() == TYPE_DICTIONARY, "Burn receipt details remain Array[Dictionary]")
	_check(signed.keys() == ["ok", "reason", "raw_components", "components", "mitigated_components", "damage_total", "shield_spent", "health_lost", "remaining_shield", "remaining_health", "overkill", "details", &"actor", &"stage"], "Receipt insertion order stays exact")
	_check(typeof(signed.keys()[12]) == TYPE_STRING_NAME and typeof(signed.keys()[13]) == TYPE_STRING_NAME, "Original property-assigned actor/stage keys remain StringName")
	for count: int in range(4, 9):
		_compare("incoming_burn", [37, 0.25, 10, 100, "monster", 0, 0, 0].slice(0, count), "omitted_defaults")


func _random_positive(rng: RandomNumberGenerator) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u32(0, rng.randi())
	bytes.encode_u32(4, rng.randi() & 0x7fffffff)
	var value: float = bytes.decode_double(0)
	return value if is_finite(value) else MAX_FINITE


func _float_samples() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x635e771e
	for index: int in range(6000):
		var raw: float = _random_positive(rng)
		var resistance: float = _random_positive(rng) * (-1.0 if index % 3 == 0 else 1.0)
		if index % 3 == 1:
			resistance = rng.randf_range(-0.01, 0.84)
		_compare("incoming_burn", [raw, resistance, _random_positive(rng), _random_positive(rng), "monster", null, 0.0, -0.0], "deterministic_float_bits")


func _invalid_priority() -> void:
	var bad: Array = [null, false, true, "0", &"0", [], {}, Vector2.ZERO,
		-1, -_adjacent(0.0, 1), NAN, INF, -INF]
	var positions: Array[int] = [0, 1, 2, 3, 5, 6, 7]
	for actor: String in ["monster", "player", "unknown", "", "MONSTER"]:
		for position: int in positions:
			for value: Variant in bad:
				var args: Array = [20.0, 0.25, 5.0, 100.0, actor, 30.0, 0.0, 0.0]
				args[position] = value
				_compare("incoming_burn", args, "individual_invalid_and_ignored")
		for first: int in range(positions.size()):
			for second: int in range(first + 1, positions.size()):
				for first_bad: Variant in bad:
					for second_bad: Variant in bad:
						var args: Array = [20.0, 0.25, 5.0, 100.0, actor, 30.0, 0.0, 0.0]
						args[positions[first]] = first_bad
						args[positions[second]] = second_bad
						_compare("incoming_burn", args, "pairwise_error_priority")
	for row: Array in [
		[[NAN, NAN, NAN, NAN, "bad", NAN, NAN, NAN], "Burn amount must be finite and nonnegative"],
		[[1.0, NAN, NAN, NAN, "bad", NAN, NAN, NAN], "Unknown defense actor: bad"],
		[[1.0, NAN, NAN, NAN, "monster", NAN, NAN, NAN], "Defense stat must be a finite scalar: fire_resistance"],
		[[1.0, 0.0, NAN, NAN, "monster", NAN, NAN, NAN], "Shield must be a finite nonnegative scalar"],
		[[1.0, 0.0, 0.0, NAN, "monster", NAN, NAN, NAN], "Health must be a finite nonnegative scalar"],
		[[1.0, 0.0, 0.0, 1.0, "monster", NAN, NAN, NAN], "Mana guard fraction must be a finite scalar from 0 to 1"],
		[[1.0, 0.0, 0.0, 1.0, "monster", NAN, 0.4, NAN], "Mana must be a finite nonnegative scalar"],
		[[1.0, 0.0, 0.0, 1.0, "monster", NAN, 0.0, NAN], "Maximum resistance bonus must be finite and nonnegative: maximum_fire_resistance_add"],
	]:
		var result: Dictionary = _compare("incoming_burn", row[0], "full_error_precedence")
		_check(result == {"ok": false, "reason": row[1]}, "Explicit complete precedence chain: " + row[1])


func _optional_paths() -> void:
	var tiny: float = _adjacent(0.0, 1)
	for actor: String in ["monster", "player"]:
		for raw: Variant in [-0.0, tiny, 37.0, 1.0e300, MAX_FINITE]:
			for resistance: Variant in [-0.0, 0.4, 0.75, 0.83, 1.0]:
				for ratio: Variant in [0, -0.0, tiny, 0.4, 1.0, _adjacent(1.0, 1), -1, true, INF]:
					for bonus: Variant in [0, -0.0, tiny, 0.01, 0.08, 0.5, MAX_FINITE, -1, false, NAN]:
						for pool: Array in [[0.0, 0.0, 0.0], [10.0, 100.0, 40.0], [MAX_FINITE, MAX_FINITE, MAX_FINITE], [-1.0, NAN, "bad"]]:
							_compare("incoming_burn", [raw, resistance, pool[0], pool[1], actor, pool[2], ratio, bonus], "mana_cap_player_fallback")
	for mana: Variant in [null, false, [], {}, "unused", NAN, INF, -1]:
		for ratio: Variant in [0, -0.0, 0.4]:
			for bonus: Variant in [0, -0.0, 0.08, NAN]:
				_compare("incoming_burn", [100.0, 0.9, 20.0, 10.0, "monster", mana, ratio, bonus], "ignored_or_validated_mana")


func _public_settlement() -> void:
	var packet: Dictionary = FrozenDamage.resolve(FrozenDamage.packet({"physical": 23.0, "fire": 31.0}, ["hit"], "test"), [], {"fire": 0.25})
	var packets: Array = [null, false, [], {}, packet, {"total": 0.0, "components": {}, "details": []}]
	var bad: Array = [null, true, "bad", -1.0, INF, NAN, {}, [], 0.95]
	for field: String in ["total", "components", "details"]:
		for value: Variant in bad:
			var forged: Dictionary = packet.duplicate(true)
			forged[field] = value
			packets.append(forged)
	for field: String in ["type", "before_defense", "resistance", "final"]:
		for value: Variant in bad:
			var forged: Dictionary = packet.duplicate(true)
			forged.details[0][field] = value
			packets.append(forged)
	var missing: Dictionary = packet.duplicate(true)
	missing.details.pop_back()
	packets.append(missing)
	var repeated: Dictionary = packet.duplicate(true)
	repeated.details.append(repeated.details[0].duplicate(true))
	packets.append(repeated)
	var extra: Dictionary = packet.duplicate(true)
	extra.extra = true
	packets.append(extra)
	var wrong: Dictionary = packet.duplicate(true)
	wrong.total = 12345.0
	packets.append(wrong)
	for resolved: Variant in packets:
		for pool: Array in [[0, 0], [-0.0, -0.0], [10.0, 100.0], [100.0, 1.0], [-1, NAN], [0, INF]]:
			_compare("settle_resolved", [resolved, pool[0], pool[1]], "public_settle_resolved")
			for ratio: Variant in [0, -0.0, 0.4, 1.0, false, NAN]:
				_compare("settle_with_mana", [resolved, pool[0], pool[1], 25.0, ratio], "public_mana_settlement")
		if resolved is Dictionary:
			for increased: Variant in [0, -0.0, 0.15, 1, -1, true, NAN]:
				_compare("apply_hit_damage_taken", [resolved, increased], "public_hit_multiplier")


func _other_adapters() -> void:
	var components: Array = [{}, {"fire": -0.0}, {"physical": 23, "fire": 37.0, "cold": 1.0, "chaos": 3.0},
		{"fire": MAX_FINITE, "cold": MAX_FINITE}, {"poison": 1}, {"fire": NAN}, null, true]
	var defenses: Array = [{}, {"fire_resistance": 0.5}, {"fire_resistance": 2.0, "maximum_fire_resistance_add": 0.08},
		{"armour": 800.0}, {"fire_resistance": false}, {"armour": -1.0}]
	for component: Variant in components:
		_compare("validate_components", [component], "unchanged_components")
		for stats: Dictionary in defenses:
			for actor: String in ["monster", "player", "bad"]:
				for options: Array in [[10, 100, 0.0, NAN, 0], [0.0, 10.0, 0.15, 3.0, 0.4], [-1, NAN, NAN, NAN, NAN]]:
					for method: String in ["incoming_hit", "incoming_source_hit"]:
						_compare(method, [component, stats, options[0], options[1], actor, options[2], options[3], options[4]], "ordinary_nonburn_adapters")
	for actor: String in ["monster", "player", "bad"]:
		for stats: Dictionary in defenses:
			for method: String in ["source_profile", "resistance_profile", "recharge_profile"]:
				_compare(method, [stats, actor], "unchanged_profiles")
			_compare("defense_profile", [stats, actor], "unchanged_profiles")
	_compare("metadata", [], "unchanged_metadata")


func _detached_returns() -> void:
	for actor: String in ["monster", "player"]:
		for options: Array in [[0, 0], [0.4, 0], [0, 0.08], [0.4, 0.08]]:
			var args: Array = [100.0, 0.9, 10.0, 20.0, actor, 50.0, options[0], options[1]]
			var first: Dictionary = current.callv("incoming_burn", args)
			var second: Dictionary = current.callv("incoming_burn", args)
			var saved: PackedByteArray = var_to_bytes(second)
			first.raw_components.fire = 999.0
			first.components.fire = 999.0
			first.mitigated_components.fire = 999.0
			first.details[0].final = 999.0
			first.details.append({"changed": true})
			_check(var_to_bytes(second) == saved, "Burn wrappers return independent nested dictionaries and typed arrays")
			_check(var_to_bytes(current.callv("incoming_burn", args)) == saved, "Mutating a prior burn return cannot alter a later return")
	var resolved: Dictionary = FrozenDamage.resolve(FrozenDamage.packet({"fire": 20.0}, ["hit"], "test"), [], {})
	var inputs: PackedByteArray = var_to_bytes(resolved)
	var settled: Dictionary = Current.settle_resolved(resolved, 0.0, 100.0)
	settled.components.fire = 999.0
	settled.raw_components.fire = 999.0
	settled.details[0].modifiers.append("changed")
	_check(var_to_bytes(resolved) == inputs, "Public settlement remains detached from nested input packet")
	var component: Dictionary = {"fire": 20.0, "physical": 10.0}
	var stats: Dictionary = {"fire_resistance": 0.25}
	inputs = var_to_bytes([component, stats])
	for method: String in ["incoming_hit", "incoming_source_hit"]:
		var hit: Dictionary = current.callv(method, [component, stats, 0.0, 100.0, "monster"])
		hit.components.fire = 999.0
		hit.effective_resistances.fire = 999.0
		hit.details[0].modifiers.append("changed")
		_check(var_to_bytes([component, stats]) == inputs, "Nonburn wrapper retains detached caller data: " + method)


func _time_burn(subject: RefCounted, actors: Array[String], iterations: int) -> Dictionary:
	var total: float = 0.0
	var started: int = Time.get_ticks_usec()
	for index: int in range(iterations):
		var result: Dictionary = subject.incoming_burn(0.4 + float(index % 7) * 0.03, float(index % 4) * 0.25, float(index % 3) * 0.2, 100.0, actors[index % actors.size()])
		total += result.health_lost + result.shield_spent
	return {"usec": Time.get_ticks_usec() - started, "sum": total}


func _benchmark() -> void:
	# Direct rule-call measurements only; parent owns unwrapped full-scene timing.
	var actors: Array[String] = ["monster"]
	_time_burn(before, actors, 1000)
	_time_burn(current, actors, 1000)
	var old_samples: Array[int] = []
	var new_samples: Array[int] = []
	for index: int in range(7):
		var old_result: Dictionary
		var new_result: Dictionary
		if index % 2 == 0:
			old_result = _time_burn(before, actors, 6000)
			new_result = _time_burn(current, actors, 6000)
		else:
			new_result = _time_burn(current, actors, 6000)
			old_result = _time_burn(before, actors, 6000)
		_check(var_to_bytes(old_result.sum) == var_to_bytes(new_result.sum), "Timed receipt consumer totals agree exactly")
		old_samples.append(old_result.usec)
		new_samples.append(new_result.usec)
	var sorted_old: Array[int] = old_samples.duplicate()
	var sorted_new: Array[int] = new_samples.duplicate()
	sorted_old.sort()
	sorted_new.sort()
	timings = {"calls_per_sample": 6000, "warmup_each": 1000, "order": "alternating before/current",
		"before_usec": old_samples, "current_usec": new_samples,
		"before_median_usec": sorted_old[3], "current_median_usec": sorted_new[3],
		"median_reduction_percent": 100.0 * (1.0 - float(sorted_new[3]) / float(sorted_old[3]))}
