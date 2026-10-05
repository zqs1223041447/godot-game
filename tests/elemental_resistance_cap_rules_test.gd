extends SceneTree
## Focused, pure rules only. No scene, state, save, timer, catalog or RNG.
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const BASELINE_PATH = "res://docs/qa/v059-rules/v058-defense-rules.txt"
const BASELINE_SHA256 = "7c84a7fedef8c7d978056d232889715d598264e447b05e0c9ce9d2705aee5476"
const ELEMENTS: Array[String] = ["fire", "cold", "lightning"]
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


func rejected(result: Dictionary, label: String) -> void:
	check(result.size() == 2 and result.get("ok") == false and result.get("reason") is String and not String(result.reason).is_empty(), label + " atomic rejection")


func adjacent(value: float, direction: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_s64(0, bytes.decode_s64(0) + direction)
	return bytes.decode_double(0)


func compare_legacy(method: String, args: Array) -> void:
	var before := var_to_bytes(args)
	var expected: Variant = old.callv(method, args)
	check(var_to_bytes(args) == before, "Frozen v58 leaves inputs exact: " + method)
	check(var_to_bytes(current.callv(method, args)) == var_to_bytes(expected), "v58 complete typed-byte equality: " + method + " " + str(args))
	check(var_to_bytes(args) == before, "Current leaves legacy inputs exact: " + method)
	legacy_cases += 1
	if method in ["source_profile", "incoming_source_hit"]:
		var stats_index: int = 0 if method == "source_profile" else 1
		for zero: Variant in [0, 0.0, -0.0]:
			var explicit: Array = args.duplicate(true)
			for type: String in ELEMENTS:
				explicit[stats_index]["maximum_" + type + "_resistance_add"] = zero
			var explicit_before := var_to_bytes(explicit)
			check(var_to_bytes(current.callv(method, explicit)) == var_to_bytes(expected), "Explicit zero max retains full v58 source bytes and error order: " + method)
			check(var_to_bytes(explicit) == explicit_before, "Explicit source zero does not mutate")
			legacy_cases += 1
	if method == "incoming_burn":
		for zero: Variant in [0, 0.0, -0.0]:
			var explicit: Array = args.duplicate(true)
			while explicit.size() < 7:
				explicit.append("player" if explicit.size() == 4 else 0.0)
			explicit.append(zero)
			check(var_to_bytes(current.callv(method, explicit)) == var_to_bytes(expected), "Explicit zero max retains full v58 burn bytes and error order")
			legacy_cases += 1


func test_profiles() -> void:
	var empty: Dictionary = Defense.resistance_profile({})
	check(empty == {"ok": true, "reason": "", "base_cap": 0.75, "safety_cap": 0.83,
		"raw_resistances": {"fire": 0.0, "cold": 0.0, "lightning": 0.0},
		"maximum_resistances": {"fire": 0.75, "cold": 0.75, "lightning": 0.75},
		"effective_resistances": {"fire": 0.0, "cold": 0.0, "lightning": 0.0}}, "Complete default read-only profile")
	for actor: String in ["player", "monster"]:
		for type: String in ELEMENTS:
			for sample: Array in [
				[-0.5, 0.08, 0.83, 0.0], [0.0, 0.08, 0.83, 0.0],
				[0.4, 0.08, 0.83, 0.4], [0.75, 0.08, 0.83, 0.75],
				[0.78, 0.05, 0.8, 0.78], [1.0, 0.0, 0.75, 0.75],
				[1.0, 0.03, 0.78, 0.78], [1.0, 0.08, 0.83, 0.83],
				[1.0, 0.5, 0.83, 0.83], [1.0, 1.7976931348623157e308, 0.83, 0.83],
			]:
				var stats: Dictionary = {type + "_resistance": sample[0], "maximum_" + type + "_resistance_add": sample[1]}
				var before := var_to_bytes(stats)
				var profile: Dictionary = Defense.resistance_profile(stats, actor)
				check(profile.ok and profile.size() == 7, "Complete valid profile " + actor + " " + type)
				if not profile.ok: continue
				near(profile.raw_resistances[type], sample[0], "Raw stays independent")
				near(profile.maximum_resistances[type], sample[2], "Maximum cap clamps at 83 percent")
				near(profile.effective_resistances[type], sample[3], "Effective requires enough raw")
				for other: String in ELEMENTS:
					if other == type: continue
					check(profile.raw_resistances[other] == 0.0 and profile.maximum_resistances[other] == 0.75 and profile.effective_resistances[other] == 0.0, "Elemental bonuses remain isolated")
				check(var_to_bytes(stats) == before, "Profile does not mutate caller")
				var source: Dictionary = Defense.source_profile(stats, actor)
				check(source.ok and var_to_bytes(source.effective_resistances) == var_to_bytes(profile.effective_resistances), "Source uses same authoritative elemental rule")
	var mixed: Dictionary = {"fire_resistance": 0.99, "cold_resistance": 0.99, "lightning_resistance": 0.99,
		"maximum_fire_resistance_add": 0.03, "maximum_cold_resistance_add": 0.02, "maximum_lightning_resistance_add": 0.01}
	var separate: Dictionary = Defense.resistance_profile(mixed)
	near(separate.effective_resistances.fire, 0.78, "Fire-only bonus")
	near(separate.effective_resistances.cold, 0.77, "Cold-only bonus")
	near(separate.effective_resistances.lightning, 0.76, "Lightning-only bonus")
	var summed: Dictionary = Defense.resistance_profile({"fire_resistance": 1.0, "maximum_fire_resistance_add": 0.01 + 0.02})
	near(summed.maximum_resistances.fire, 0.78, "Additive decimal percentage points")
	for raw: float in [adjacent(0.75, -1), 0.75, adjacent(0.75, 1), adjacent(0.83, -1), 0.83, adjacent(0.83, 1)]:
		var profile: Dictionary = Defense.resistance_profile({"fire_resistance": raw, "maximum_fire_resistance_add": 0.08})
		check(profile.effective_resistances.fire == minf(raw, 0.83), "One-ULP effective safety boundary")
	for zero: Variant in [0, 0.0, -0.0]:
		check(var_to_bytes(Defense.resistance_profile({"maximum_fire_resistance_add": zero})) == var_to_bytes(empty), "All numeric zero bonuses match default profile bytes")
	rejected(Defense.resistance_profile({}, "unknown"), "Unknown actor")


func test_validation_and_isolation() -> void:
	for type: String in ELEMENTS:
		for bad: Variant in [-1, -adjacent(0.0, 1), INF, -INF, NAN, true, false, "0.03", null, [], {}]:
			var stats: Dictionary = {"fire_resistance": 0.9, "maximum_" + type + "_resistance_add": bad, "unrelated": {"values": [1, 2]}}
			var before := var_to_bytes(stats)
			rejected(Defense.resistance_profile(stats), "Invalid maximum " + type + " " + str(bad))
			rejected(Defense.source_profile(stats), "Source cannot bypass invalid maximum")
			rejected(Defense.incoming_source_hit({"fire": 100.0}, stats, 1.0, 100.0), "Hit cannot bypass invalid maximum")
			check(var_to_bytes(stats) == before, "Rejected stats stay byte-identical")
			if type == "fire":
				rejected(Defense.incoming_burn(100.0, 0.9, 1.0, 100.0, "player", 20.0, 0.4, bad), "Burn cannot bypass invalid maximum")
		for bad: Variant in [INF, -INF, NAN, true, "0.4", null, [], {}]:
			rejected(Defense.resistance_profile({type + "_resistance": bad}), "Invalid raw resistance " + type)
	for prior_error: Array in [
		[-1, 0.8, 0.0, 100.0, "player", 0.0, 0.0],
		[100.0, true, 0.0, 100.0, "player", 0.0, 0.0],
		[100.0, 0.8, 0.0, 100.0, "unknown", 0.0, 0.0],
		[100.0, 0.8, -1.0, NAN, "player", NAN, NAN],
		[100.0, 0.8, 0.0, NAN, "player", NAN, NAN],
		[100.0, 0.8, 0.0, 100.0, "player", NAN, NAN],
		[100.0, 0.8, 0.0, 100.0, "player", NAN, 0.4],
	]:
		var expected: Dictionary = old.callv("incoming_burn", prior_error)
		check(not expected.ok, "Error precedence fixture is independently invalid")
		for bonus: Variant in [0.08, -1, NAN, true, null, {}]:
			var args: Array = prior_error.duplicate(true)
			args.append(bonus)
			var before := var_to_bytes(args)
			check(var_to_bytes(current.callv("incoming_burn", args)) == var_to_bytes(expected), "New burn bonus never hides any old error")
			check(var_to_bytes(args) == before, "Rejected burn inputs unchanged")
	var stats: Dictionary = {"fire_resistance": 0.9, "cold_resistance": 0.7, "maximum_fire_resistance_add": 0.05, "nested": {"values": [1, 2]}}
	var before := var_to_bytes(stats)
	var first: Dictionary = Defense.resistance_profile(stats)
	var second: Dictionary = Defense.resistance_profile(stats)
	check(var_to_bytes(first) == var_to_bytes(second), "Profile is deterministic")
	first.raw_resistances.fire = 999.0
	first.maximum_resistances.fire = 999.0
	first.effective_resistances.fire = 999.0
	check(var_to_bytes(stats) == before and second.raw_resistances.fire == 0.9 and second.maximum_resistances.fire == 0.8 and second.effective_resistances.fire == 0.8, "Returned profile is detached from input and later calls")
	var components: Dictionary = {"fire": 100.0, "cold": 100.0}
	var input_before := var_to_bytes([components, stats])
	var hit: Dictionary = Defense.incoming_source_hit(components, stats, 5.0, 100.0, "player", 0.15, 20.0, 0.4)
	check(hit.ok, "Enabled maximum hit accepts")
	if hit.ok:
		hit.effective_resistances.fire = 999.0
		hit.raw_resistances.fire = 999.0
		hit.details[0].modifiers.append("changed")
	check(var_to_bytes([components, stats]) == input_before, "Hit and nested output leave caller inputs untouched")


func test_hit_burn_and_resources() -> void:
	for actor: String in ["player", "monster"]:
		for raw: float in [-0.1, 0.4, 0.75, 0.78, 0.83, 1.0]:
			for bonus: float in [0.0, 0.03, 0.08, 0.5]:
				var stats: Dictionary = {"fire_resistance": raw, "maximum_fire_resistance_add": bonus}
				var hit: Dictionary = Defense.incoming_source_hit({"fire": 100.0}, stats, 5.0, 100.0, actor, 0.0, 20.0, 0.4)
				var burn: Dictionary = Defense.incoming_burn(100.0, raw, 5.0, 100.0, actor, 20.0, 0.4, bonus)
				check(hit.ok and burn.ok, "Hit and burn accept identical defenses " + actor)
				if not hit.ok or not burn.ok: continue
				for field: String in ["damage_total", "shield_spent", "mana_spent", "health_lost", "overkill", "remaining_shield", "remaining_mana", "remaining_health"]:
					check(var_to_bytes(hit[field]) == var_to_bytes(burn[field]), "Same fire cap and resource typed bytes: " + field)
				check(hit.details[0].resistance == burn.details[0].resistance, "Hit and burn share effective fire resistance")
				check(burn.actor == actor and burn.stage == "burning", "Burn actor/stage retained")
		var stats: Dictionary = {"fire_resistance": 1.0, "cold_resistance": 1.0, "lightning_resistance": 1.0,
			"maximum_fire_resistance_add": 0.08, "maximum_cold_resistance_add": 0.03, "maximum_lightning_resistance_add": 0.01, "armour": 500.0}
		var mixed: Dictionary = Defense.incoming_source_hit({"physical": 100.0, "fire": 100.0, "cold": 100.0, "lightning": 100.0, "chaos": 25.0}, stats, 20.0, 200.0, actor, 0.15, 100.0, 0.4)
		check(mixed.ok, "Mixed damage accepts " + actor)
		if mixed.ok:
			near(mixed.components.physical, 57.5, "Hit-size armour before one shock")
			near(mixed.components.fire, 19.55, "Fire cap before one shock")
			near(mixed.components.cold, 25.3, "Independent cold cap before one shock")
			near(mixed.components.lightning, 27.6, "Independent lightning cap before one shock")
			near(mixed.components.chaos, 28.75, "Elemental caps do not alter chaos")
			near(mixed.damage_total, 158.7, "Mixed damage final total")
			near(mixed.shield_spent, 20.0, "Shield spends first")
			near(mixed.mana_spent, 55.48, "Mana guard receives remainder after shield")
			near(mixed.health_lost, 83.22, "Life receives remainder after mana")
		var shocked: Dictionary = Defense.incoming_source_hit({"fire": 100.0}, stats, 0.0, 200.0, actor, 0.15)
		var burn: Dictionary = Defense.incoming_burn(100.0, 1.0, 0.0, 200.0, actor, 0.0, 0.0, 0.08)
		near(shocked.damage_total, 19.55, "Shock remains hit-only")
		near(burn.damage_total, 17.0, "Burn has no shock or armour")
		for pool: Array in [[25.0, 20.0, 100.0, 17.0, 0.0, 0.0, 0.0], [5.0, 20.0, 100.0, 5.0, 4.8, 7.2, 0.0], [5.0, 2.0, 100.0, 5.0, 2.0, 10.0, 0.0], [5.0, 20.0, 3.0, 5.0, 4.8, 3.0, 4.2]]:
			var result: Dictionary = Defense.incoming_burn(100.0, 1.0, pool[0], pool[2], actor, pool[1], 0.4, 0.08)
			check(result.ok, "Resource order accepts " + actor)
			if not result.ok: continue
			near(result.shield_spent, pool[3], "Resource case shield")
			near(result.mana_spent, pool[4], "Resource case mana including insufficiency")
			near(result.health_lost, pool[5], "Resource case life")
			near(result.overkill, pool[6], "Resource case overkill")
			near(result.damage_total, result.shield_spent + result.mana_spent + result.health_lost + result.overkill, "Resource conservation")


func test_frozen_v58_compatibility() -> void:
	var defenses: Array = [{}, {"fire_resistance": 0.4}, {"fire_resistance": 0.9, "cold_resistance": 0.7, "lightning_resistance": -0.1, "armour": 500.0}, {"fire_resistance": -1}, {"fire_resistance": INF}, {"fire_resistance": true}, {"armour": -1}, {1: 0.4}]
	var components: Array = [{}, {"fire": 100.0}, {"physical": 15.0, "fire": 30.0, "cold": 20.0, "lightning": 10.0, "chaos": 5.0}, {"fire": -1}, {"fire": NAN}, {"unknown": 1}, null]
	var pools: Array = [[0.0, 100.0, 0.0, 0.0], [5.0, 20.0, 50.0, 0.4], [50.0, 10.0, 2.0, 1.0], [-1, NAN, NAN, NAN], [0, 100, NAN, 0.0], [0, 100, NAN, 0.4], [0, 100, 10, true]]
	for actor: String in ["player", "monster", "unknown"]:
		for stats: Dictionary in defenses:
			compare_legacy("defense_profile", [stats, actor])
			compare_legacy("source_profile", [stats, actor])
			for component: Variant in components:
				for pool: Array in pools:
					for method: String in ["incoming_hit", "incoming_source_hit"]:
						compare_legacy(method, [component, stats, pool[0], pool[1], actor, 0.15, pool[2], pool[3]])
	for raw: Variant in [0, 100.0, 1.0e308, -1, NAN, true]:
		for resistance: Variant in [-1, 0.4, 0.75, 2.0, NAN, true]:
			for pool: Array in pools:
				compare_legacy("incoming_burn", [raw, resistance, pool[0], pool[1], "player", pool[2], pool[3]])
	for method: String in ["incoming_hit", "incoming_source_hit"]:
		compare_legacy(method, [{"fire": 10.0}, {}, 2, 100])
		for shock: Variant in [0, -0.0, 1.0, -1.0, 1.1, NAN, true]:
			compare_legacy(method, [{"fire": 10.0}, {}, 2, 100, "player", shock])
	compare_legacy("incoming_burn", [10, 0, 2, 100])
	compare_legacy("incoming_burn", [10.0, 0.8, 1.0, 100.0, "monster"])
	for stats: Variant in [null, true, [], "stats"]:
		compare_legacy("defense_profile", [stats])
	compare_legacy("defense_profile", [{"maximum_fire_resistance_add": 0.0}])
	compare_legacy("defense_profile", [{"fire_resistance": 0.8}, "player", "unsupported"])
	var old_metadata: Dictionary = old.call("metadata")
	var new_metadata: Dictionary = Defense.metadata()
	check(String(new_metadata.description).contains("默认") and String(new_metadata.description).contains("83%") and String(new_metadata.description).contains("原始抗性仍需另行获得"), "Metadata explains base, maximum and raw independently")
	old_metadata.erase("description")
	new_metadata.erase("description")
	check(var_to_bytes(old_metadata) == var_to_bytes(new_metadata), "Non-description metadata retains v58 typed bytes")
	for stat: String in ["fire_resistance", "maximum_fire_resistance_add", "cold_resistance"]:
		compare_legacy("support_reason", [stat, "player"])
		compare_legacy("supports_stat", [stat, "monster"])
	for component: Variant in components:
		compare_legacy("validate_components", [component])
	var resolved: Dictionary = Damage.resolve(Damage.packet({"physical": 20.0, "fire": 30.0}, ["hit"], "cap_rules"), [], {})
	var packets: Array = [null, {}, resolved]
	for field: String in ["total", "components", "details"]:
		var malformed: Dictionary = resolved.duplicate(true)
		malformed[field] = NAN
		packets.append(malformed)
	for resistance: float in [-1.0, 0.9, -1.1, 0.91]:
		var modified: Dictionary = resolved.duplicate(true)
		modified.details[0].resistance = resistance
		packets.append(modified)
	for packet: Variant in packets:
		for pool: Array in pools:
			compare_legacy("settle_resolved", [packet, pool[0], pool[1]])
			compare_legacy("settle_with_mana", [packet, pool[0], pool[1], pool[2], pool[3]])
		if packet is Dictionary:
			compare_legacy("apply_hit_damage_taken", [packet, 0.15])
	for resistance: float in [-1.5, -1.0, 0.9, 0.95]:
		var original_resolver: Dictionary = Damage.resolve(Damage.packet({"fire": 100.0}, ["hit"], "cap_rules"), [], {"fire": resistance})
		check(original_resolver.details[0].resistance == clampf(resistance, -1.0, 0.9), "DamageResolver retains original minus-one to point-nine compatibility")
		check(Defense.settle_resolved(original_resolver, 0.0, 200.0).ok, "Settlement never reapplies authored elemental safety cap")


func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v059-rules-"):
		push_error("Use the isolated v059 pure-rules runner")
		quit(78)
		return
	var baseline: PackedByteArray = FileAccess.get_file_as_bytes(BASELINE_PATH)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(baseline)
	check(hash.finish().hex_encode() == BASELINE_SHA256, "Frozen baseline is byte-for-byte published v58")
	var script := GDScript.new()
	# Keep the fixture unchanged; remove only the global name in memory.
	script.source_code = baseline.get_string_from_utf8().replace("class_name DefenseRules\n", "")
	var error: Error = script.reload()
	check(error == OK, "Independent frozen v58 baseline compiles")
	if error != OK or failures > 0:
		quit(1)
		return
	old = script.new()
	current = Defense.new()
	test_profiles()
	test_validation_and_isolation()
	test_hit_burn_and_resources()
	test_frozen_v58_compatibility()
	print("ELEMENTAL_RESISTANCE_CAP_RULES ", JSON.stringify({"checks": checks, "failures": failures, "legacy_typed_byte_cases": legacy_cases, "baseline_commit": "71f4863fda4b02d1afd17db4cfa958c85139491f", "baseline_sha256": BASELINE_SHA256}))
	quit(1 if failures else 0)
