extends SceneTree
## Pure rules only: no scene, state, save, timers, or RNG are constructed.
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const BASELINE_PATH = "res://docs/qa/v058-rules/v057-defense-rules.txt"
const BASELINE_SHA256 = "2c9640795202f607be9dbae6da6eed5911d5b8409a64fba44e8c6835567c8141"
var checks: int = 0
var failures: int = 0
var legacy_cases: int = 0
var old: RefCounted
var current: RefCounted


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func near(actual: float, expected: float, label: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(1.0e-12, absf(expected) * 1.0e-12), label)


func adjacent(value: float, direction: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_s64(0, bytes.decode_s64(0) + direction)
	return bytes.decode_double(0)


func legacy(method: String, args: Array) -> void:
	var before := var_to_bytes(args)
	var expected: Variant = old.callv(method, args)
	check(var_to_bytes(args) == before, "Independent baseline does not mutate inputs: " + method)
	check(var_to_bytes(current.callv(method, args)) == var_to_bytes(expected), "v57 typed-byte equality: " + method + " " + str(args))
	check(var_to_bytes(args) == before, "Current old path does not mutate inputs: " + method)
	legacy_cases += 1
	if method in ["incoming_hit", "incoming_source_hit", "incoming_burn"]:
		for zero: Variant in [0, 0.0, -0.0]:
			for unused_mana: Variant in [0, 99.0, -1.0, NAN, INF, null, true, "unused", {}]:
				var explicit: Array = args.duplicate(true)
				explicit.append(unused_mana)
				explicit.append(zero)
				check(var_to_bytes(current.callv(method, explicit)) == var_to_bytes(expected), "Disabled branch retains v57 bytes and error precedence: " + method)
				legacy_cases += 1


func resolved(components: Dictionary) -> Dictionary:
	return Damage.resolve(Damage.packet(components, ["hit"], "mana_guard_test"), [], {})


func settled(result: Dictionary, shield: float, health: float, mana: float,
		shield_spent: float, mana_spent: float, health_lost: float, overkill: float, label: String) -> void:
	check(result.get("ok", false), label + " accepts")
	if not result.get("ok", false):
		return
	for field: String in ["damage_total", "shield_spent", "mana_spent", "health_lost", "overkill", "remaining_shield", "remaining_mana", "remaining_health"]:
		check(typeof(result.get(field)) == TYPE_FLOAT and is_finite(float(result.get(field))) and float(result.get(field)) >= 0.0, label + " bounded float " + field)
	near(result.shield_spent, shield_spent, label + " shield")
	near(result.mana_spent, mana_spent, label + " mana")
	near(result.health_lost, health_lost, label + " life")
	near(result.overkill, overkill, label + " overkill")
	near(result.remaining_shield, shield - shield_spent, label + " remaining shield")
	near(result.remaining_mana, mana - mana_spent, label + " remaining mana")
	near(result.remaining_health, health - health_lost, label + " remaining life")
	near(result.damage_total, result.shield_spent + result.mana_spent + result.health_lost + result.overkill, label + " resource conservation")


func rejected(result: Dictionary, label: String) -> void:
	check(result.size() == 2 and result.get("ok") == false and result.get("reason") is String and not String(result.reason).is_empty(), label + " atomic failure without resource fields")


func test_profile() -> void:
	check(Defense.mana_guard_profile({}) == {"ok": true, "reason": "", "enabled": false, "fraction": 0.0}, "Absent stat disables diversion")
	for amount: Variant in [0, 0.0, -0.0, 0.4, 1, 1.0, adjacent(1.0, -1), adjacent(0.0, 1)]:
		var stats: Dictionary = {Defense.MANA_GUARD_STAT: amount, "max_mana": 100.0, "unrelated": {"array": [1, 2]}}
		var before := var_to_bytes(stats)
		var profile: Dictionary = Defense.mana_guard_profile(stats)
		check(profile.ok and profile.enabled == (float(amount) != 0.0) and typeof(profile.fraction) == TYPE_FLOAT and profile.fraction == float(amount), "Exact finite fraction accepted " + str(amount))
		check(var_to_bytes(stats) == before, "Profile leaves derived stats untouched")
	for amount: Variant in [-1, -adjacent(0.0, 1), adjacent(1.0, 1), 1.1, NAN, INF, -INF, true, false, "0.4", null, [], {}]:
		rejected(Defense.mana_guard_profile({Defense.MANA_GUARD_STAT: amount}), "Invalid authored fraction " + str(amount))


func test_legacy_equivalence() -> void:
	var components: Array = [{}, {"fire": 0}, {"physical": 23, "fire": 17.5, "cold": 11.0, "lightning": 5.0, "chaos": 2.0}, {"physical": 1.0e308, "fire": 1.0e308}, {"fire": -1}, {"fire": NAN}, {"poison": 1}, {0: 1}, null, true]
	var defenses: Array = [{}, {"fire_resistance": 0.4}, {"fire_resistance": 3.0}, {"fire_resistance": -1}, {"fire_resistance": INF}, {"fire_resistance": true}, {"armour": 80.0}, {"armour": -1.0}, {1: 0.4}]
	var resources: Array = [[0, 0], [10.0, 100.0], [100.0, 10.0], [0.0, 1.0], [-1, NAN], [NAN, -1], ["0", true], [INF, 1.0]]
	for component: Variant in components:
		for stats: Dictionary in defenses:
			for pool: Array in resources:
				# Distinct original adapter ordering is tested by simultaneous errors.
				legacy("incoming_hit", [component, stats, pool[0], pool[1], "player", 0.0])
				legacy("incoming_source_hit", [component, stats, pool[0], pool[1], "monster", 0.0])
	for component: Variant in components:
		for actor: String in ["player", "monster", "unknown"]:
			for increased: Variant in [0, -0.0, 0.15, 1, -0.1, 1.1, true, null, "0", NAN, INF]:
				legacy("incoming_hit", [component, {}, 3.0, 15.0, actor, increased])
				legacy("incoming_source_hit", [component, {}, 3.0, 15.0, actor, increased])
	for raw: Variant in [0, 37.0, 1.0e308, -1.0, NAN, INF, true, null, "10"]:
		for resistance: Variant in [0, 0.25, 0.75, 2.0, -1.0, NAN, true]:
			for pool: Array in resources:
				legacy("incoming_burn", [raw, resistance, pool[0], pool[1], "player"])
	for actor: String in ["monster", "unknown"]:
		legacy("incoming_burn", [10.0, 0.25, -1.0, NAN, actor])
		legacy("incoming_burn", [10.0, 0.25, 0.0, 100.0, actor])
	for method: String in ["incoming_hit", "incoming_source_hit"]:
		for args: Array in [[{"fire": 10.0}, {}, 2, 100], [{"fire": 10.0}, {}, 2.0, 100.0, "monster"]]:
			check(var_to_bytes(current.callv(method, args)) == var_to_bytes(old.callv(method, args)), "All omitted legacy argument arities retain bytes")
	check(var_to_bytes(Defense.incoming_burn(10, 0, 2, 100)) == var_to_bytes(old.callv("incoming_burn", [10, 0, 2, 100])), "Burn omitted actor retains bytes")
	for stats: Dictionary in defenses:
		legacy("source_profile", [stats, "player"])
		legacy("defense_profile", [stats, "monster", Defense.STAGE])
	for stats: Variant in [null, true, "object", []]:
		legacy("defense_profile", [stats, "player", Defense.STAGE])
		legacy("incoming_hit", [{"fire": 10}, stats, 0.0, 100.0, "player", 0.0])
	for component: Variant in components:
		legacy("validate_components", [component])
	legacy("metadata", [])
	var valid: Dictionary = resolved({"physical": 20.0, "fire": 30.0})
	var malformed: Array = [null, [], true, {}, valid]
	for field: String in ["total", "components", "details"]:
		for bad: Variant in [null, true, "bad", -1.0, INF, NAN, {}, []]:
			var packet: Dictionary = valid.duplicate(true)
			packet[field] = bad
			malformed.append(packet)
	for field: String in ["type", "before_defense", "final", "resistance"]:
		for bad: Variant in [null, true, "bad", -1.0, INF, NAN, {}, [], 0.95]:
			var packet: Dictionary = valid.duplicate(true)
			packet.details[0][field] = bad
			malformed.append(packet)
	var missing: Dictionary = valid.duplicate(true)
	missing.details.pop_back()
	malformed.append(missing)
	var repeated: Dictionary = valid.duplicate(true)
	repeated.details.append(repeated.details[0].duplicate(true))
	malformed.append(repeated)
	for packet: Variant in malformed:
		for pool: Array in resources:
			legacy("settle_resolved", [packet, pool[0], pool[1]])
			check(var_to_bytes(Defense.settle_with_mana(packet, pool[0], pool[1], NAN, 0.0)) == var_to_bytes(old.callv("settle_resolved", [packet, pool[0], pool[1]])), "Disabled new helper preserves full v57 settlement bytes")
		if packet is Dictionary:
			for increased: Variant in [0, 0.15, -1, true, NAN]:
				legacy("apply_hit_damage_taken", [packet, increased])


func test_resource_order() -> void:
	var raw: Dictionary = resolved({"physical": 100.0})
	for test: Array in [
		[150.0, 200.0, 100.0, 100.0, 0.0, 0.0, 0.0, "full shield"],
		[20.0, 200.0, 100.0, 20.0, 32.0, 48.0, 0.0, "partial shield"],
		[0.0, 200.0, 100.0, 0.0, 40.0, 60.0, 0.0, "no shield"],
		[20.0, 200.0, 10.0, 20.0, 10.0, 70.0, 0.0, "insufficient mana"],
		[20.0, 200.0, 0.0, 20.0, 0.0, 80.0, 0.0, "empty mana"],
		[20.0, 10.0, 100.0, 20.0, 32.0, 10.0, 38.0, "overkill"],
		[0.0, 0.0, 100.0, 0.0, 40.0, 0.0, 60.0, "zero life"],
		[0.0, 10.0, 5.0, 0.0, 5.0, 10.0, 85.0, "all resources exhausted"],
	]:
		settled(Defense.settle_with_mana(raw, test[0], test[1], test[2], 0.4), test[0], test[1], test[2], test[3], test[4], test[5], test[6], test[7])
	settled(Defense.settle_with_mana(raw, 20.0, 10.0, 100.0, 1.0), 20.0, 10.0, 100.0, 20.0, 80.0, 0.0, 0.0, "ratio one")
	settled(Defense.settle_with_mana(resolved({}), 10.0, 20.0, 30.0, 0.4), 10.0, 20.0, 30.0, 0.0, 0.0, 0.0, 0.0, "empty packet")
	for actor: String in ["player", "monster"]:
		var mixed: Dictionary = Defense.incoming_source_hit({"physical": 100.0, "fire": 100.0, "cold": 100.0, "lightning": 100.0, "chaos": 25.0}, {"armour": 500.0, "fire_resistance": 0.25, "cold_resistance": 0.5, "lightning_resistance": 5.0}, 50.0, 200.0, actor, 0.15, 100.0, 0.4)
		# 50 physical + 75 fire + 50 cold + 25 lightning + 25 chaos = 225;
		# one 15% shock => 258.75; shield => 208.75; mana => 83.5; life => 125.25.
		settled(mixed, 50.0, 200.0, 100.0, 50.0, 83.5, 125.25, 0.0, "mixed mitigation/shock " + actor)
		near(mixed.damage_total, 258.75, "Armour, resistance, one shock then resources")
		near(mixed.raw_components.physical, 100.0, "Mana and shock preserve offensive baseline")
		near(mixed.components.physical, 57.5, "Armour followed by one shock")
		near(mixed.effective_resistances.lightning, 0.75, "Elemental cap before diversion")
		var fire: Dictionary = Defense.incoming_hit({"fire": 100.0}, {"fire_resistance": 0.25}, 15.0, 100.0, actor, 0.0, 50.0, 0.4)
		settled(fire, 15.0, 100.0, 50.0, 15.0, 24.0, 36.0, 0.0, "legacy hit adapter " + actor)
		var burn: Dictionary = Defense.incoming_burn(100.0, 0.25, 15.0, 100.0, actor, 50.0, 0.4)
		settled(burn, 15.0, 100.0, 50.0, 15.0, 24.0, 36.0, 0.0, "burn adapter " + actor)
		check(burn.actor == actor and burn.stage == "burning", "Burn stage and actor preserved")
		for field: String in ["damage_total", "shield_spent", "mana_spent", "health_lost", "overkill", "remaining_shield", "remaining_mana", "remaining_health"]:
			check(var_to_bytes(fire[field]) == var_to_bytes(burn[field]), "Hit and burn share exact resource settlement " + field)
		var no_mana: Dictionary = Defense.incoming_source_hit({"physical": 10.0}, {}, 0.0, 20.0, actor)
		check(not no_mana.has("mana_spent") and not no_mana.has("remaining_mana"), "Existing actor without profile has no invented mana fields")
	var spend: Dictionary = Defense.settle_with_mana(raw, 0.0, 100.0, 100.0, 0.4)
	near(spend.shield_spent + spend.health_lost, 60.0, "Existing actual-damage/feedback/leech sum excludes mana spending")
	var lethal: Dictionary = Defense.incoming_burn(400.0, 0.75, 20.0, 10.0, "player", 100.0, 0.4)
	settled(lethal, 20.0, 10.0, 100.0, 20.0, 32.0, 10.0, 38.0, "burn cap and overkill")


func test_validation_and_isolation() -> void:
	var packet: Dictionary = resolved({"physical": 20.0, "fire": 30.0})
	var original: PackedByteArray = var_to_bytes(packet)
	for bad: Variant in [null, true, false, "10", [], {}, -1, -adjacent(0.0, 1), INF, -INF, NAN]:
		rejected(Defense.settle_with_mana(packet, 5.0, 100.0, bad, 0.4), "Invalid mana " + str(bad))
		for method: String in ["incoming_hit", "incoming_source_hit"]:
			rejected(current.callv(method, [{"fire": 10.0}, {}, 0.0, 100.0, "player", 0.0, bad, 0.4]), "Public hit rejects invalid mana")
		rejected(Defense.incoming_burn(10.0, 0.0, 0.0, 100.0, "player", bad, 0.4), "Burn rejects invalid mana")
	for bad: Variant in [null, true, false, "0.4", [], {}, -1, -adjacent(0.0, 1), adjacent(1.0, 1), INF, -INF, NAN]:
		rejected(Defense.settle_with_mana(packet, 5.0, 100.0, 100.0, bad), "Invalid ratio " + str(bad))
		for method: String in ["incoming_hit", "incoming_source_hit"]:
			rejected(current.callv(method, [{"fire": 10.0}, {}, 0.0, 100.0, "player", 0.0, 100.0, bad]), "Public hit rejects invalid fraction")
		rejected(Defense.incoming_burn(10.0, 0.0, 0.0, 100.0, "player", 100.0, bad), "Burn rejects invalid fraction")
	check(var_to_bytes(packet) == original, "All rejected cases leave original resolved input exact")
	check(Defense.settle_with_mana({}, -1.0, NAN, NAN, NAN).reason == "Shield must be a finite nonnegative scalar", "Existing shield validation precedes new inputs")
	check(Defense.settle_with_mana({}, 0.0, NAN, NAN, NAN).reason == "Health must be a finite nonnegative scalar", "Existing life validation precedes new inputs")
	check(Defense.settle_with_mana({}, 0.0, 1.0, NAN, NAN).reason == "Resolved hit must contain only total, components and details", "Resolved validation cannot be hidden by invalid new inputs")
	var forged: Dictionary = packet.duplicate(true)
	forged.total += 1.0
	var forged_bytes := var_to_bytes(forged)
	rejected(Defense.settle_with_mana(forged, 0.0, 100.0, 100.0, 0.4), "Mana cannot mask forged total")
	check(var_to_bytes(forged) == forged_bytes, "Invalid resolved input stays untouched")
	var first: Dictionary = Defense.settle_with_mana(packet, 5.0, 100.0, 100.0, 0.4)
	var second: Dictionary = Defense.settle_with_mana(packet, 5.0, 100.0, 100.0, 0.4)
	check(var_to_bytes(first) == var_to_bytes(second), "Enabled diversion is deterministic")
	first.components.physical = 999.0
	first.raw_components.fire = 999.0
	first.details[0].modifiers.append("changed")
	check(var_to_bytes(packet) == original, "Successful result has no alias into nested resolved data")
	check(second.components.physical == 20.0 and second.raw_components.fire == 30.0 and second.details[0].modifiers.is_empty(), "Independent result does not alias earlier output")
	var components: Dictionary = {"fire": 100.0, "physical": 20.0}
	var stats: Dictionary = {"armour": 50.0, "fire_resistance": 0.2, Defense.MANA_GUARD_STAT: 0.4}
	var input_bytes := var_to_bytes([components, stats])
	var hit: Dictionary = Defense.incoming_source_hit(components, stats, 5.0, 100.0, "player", 0.15, 20.0, 0.4)
	check(hit.ok and var_to_bytes([components, stats]) == input_bytes, "Source adapter preserves caller inputs")
	hit.effective_resistances.fire = 0.0
	hit.details[0].modifiers.append("changed")
	check(var_to_bytes([components, stats]) == input_bytes, "Source output remains detached from stats/components")
	for method: String in ["incoming_hit", "incoming_source_hit"]:
		for increased: Variant in [-1.0, 1.1, NAN, INF, true]:
			rejected(current.callv(method, [{"fire": 10.0}, {}, 0.0, 100.0, "player", increased, 100.0, 0.4]), "Mana does not bypass invalid hit multiplier")


func test_float_boundaries() -> void:
	var packet: Dictionary = resolved({"physical": 1.0})
	for mana: float in [adjacent(0.4, -1), 0.4, adjacent(0.4, 1)]:
		var result: Dictionary = Defense.settle_with_mana(packet, 0.0, 1.0, mana, 0.4)
		check(result.ok and result.mana_spent == minf(mana, 0.4), "One-ULP mana boundary selects exact lesser amount")
		check(result.remaining_mana >= 0.0 and result.remaining_health >= 0.0 and result.overkill == 0.0, "One-ULP mana boundary stays bounded")
	for shield: float in [adjacent(1.0, -1), 1.0, adjacent(1.0, 1)]:
		var result: Dictionary = Defense.settle_with_mana(packet, shield, 1.0, 1.0, 0.4)
		var remainder: float = maxf(0.0, 1.0 - minf(shield, 1.0))
		check(result.ok and result.mana_spent == remainder * 0.4, "One-ULP shield boundary diverts only exact remainder")
	for health: float in [adjacent(0.6, -1), 0.6, adjacent(0.6, 1)]:
		var result: Dictionary = Defense.settle_with_mana(packet, 0.0, health, 1.0, 0.4)
		check(result.ok and result.health_lost == minf(health, 0.6) and result.overkill == maxf(0.0, 0.6 - result.health_lost), "One-ULP life boundary preserves actual loss and overkill")
	for amount: float in [adjacent(0.0, 1), 1.0e-300, 1.0e300, 1.7976931348623157e308]:
		var result: Dictionary = Defense.settle_with_mana(resolved({"physical": amount}), 0.0, amount, amount, 0.4)
		check(result.ok and result.damage_total == amount and result.mana_spent == amount * 0.4, "Finite damage extremes accept exact diversion " + str(amount))
		for field: String in ["mana_spent", "health_lost", "remaining_mana", "remaining_health", "overkill"]:
			check(is_finite(float(result[field])) and float(result[field]) >= 0.0, "Extreme values remain finite and nonnegative " + field)
	for ratio: float in [adjacent(0.0, 1), adjacent(1.0, -1), 1.0]:
		var result: Dictionary = Defense.settle_with_mana(packet, 0.0, 1.0, 1.0, ratio)
		check(result.ok and result.mana_spent == ratio, "Fraction extremes preserve supplied ratio")


func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v058-rules-"):
		push_error("Use the isolated v058 pure-rules runner")
		quit(78)
		return
	var baseline: PackedByteArray = FileAccess.get_file_as_bytes(BASELINE_PATH)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(baseline)
	check(hash.finish().hex_encode() == BASELINE_SHA256, "Independent baseline is exact published v57 file")
	var script := GDScript.new()
	# Only strip its global class declaration in memory to prevent name collision.
	# The checked-in baseline stays byte-for-byte original and separately hashed.
	script.source_code = baseline.get_string_from_utf8().replace("class_name DefenseRules\n", "")
	var error: Error = script.reload()
	check(error == OK, "Independent v57 baseline compiles")
	if error != OK or failures > 0:
		quit(1)
		return
	old = script.new()
	current = Defense.new()
	test_profile()
	test_legacy_equivalence()
	test_resource_order()
	test_validation_and_isolation()
	test_float_boundaries()
	print("MANA_GUARD_RULES ", JSON.stringify({"checks": checks, "failures": failures, "legacy_typed_byte_cases": legacy_cases, "baseline_commit": "3718d74691f3a7f9e2280fc26419c093b26ee4ac", "baseline_sha256": BASELINE_SHA256}))
	quit(1 if failures else 0)
