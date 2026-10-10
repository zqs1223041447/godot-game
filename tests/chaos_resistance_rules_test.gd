extends SceneTree
## Bounded pure rules. No model, scene, save, catalog, timer, or RNG.
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const BASELINE_PATH: String = "res://docs/qa/v093-chaos-rules/frozen/v092-defense-rules.txt"
const BASELINE_SHA256: String = "a211d7714f8b23cd382dbe5093328104ee95c8022b99813329aa2f8534c45361"
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
	check(result.size() == 2 and result.get("ok") == false and result.get("reason") is String and not String(result.reason).is_empty(), label + " rejects atomically")


func adjacent(value: float, direction: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_s64(0, bytes.decode_s64(0) + direction)
	return bytes.decode_double(0)


func same_old(method: String, args: Array) -> void:
	var before: PackedByteArray = var_to_bytes(args)
	var expected: Variant = old.callv(method, args)
	var actual: Variant = current.callv(method, args)
	check(var_to_bytes(actual) == var_to_bytes(expected), "Frozen v92 exact typed bytes: " + method + " " + str(args))
	check(var_to_bytes(args) == before, "Legacy comparison leaves caller unchanged: " + method)
	legacy_cases += 1


func without_chaos_maps(result: Dictionary) -> Dictionary:
	var copied: Dictionary = result.duplicate(true)
	if copied.get("ok") == true:
		copied.raw_resistances.erase("chaos")
		copied.effective_resistances.erase("chaos")
	return copied


func test_profiles() -> void:
	check(Defense.chaos_resistance_profile({}) == {"ok": true, "reason": "", "raw": 0.0, "cap": 0.75, "effective": 0.0}, "Missing standalone stat defaults to zero")
	for actor: String in ["player", "monster"]:
		for raw: Variant in [-1.7976931348623157e308, -0.25, -adjacent(0.0, 1), 0, 0.0, -0.0, adjacent(0.0, 1), 0.25, adjacent(0.75, -1), 0.75, adjacent(0.75, 1), 1, 1.7976931348623157e308]:
			var stats: Dictionary = {"chaos_resistance": raw, "fire_resistance": 0.9, "maximum_fire_resistance_add": 0.08, "nested": {"values": [1, 2]}}
			var before: PackedByteArray = var_to_bytes(stats)
			var profile: Dictionary = Defense.chaos_resistance_profile(stats, actor)
			check(profile.ok and profile.size() == 5, "Exact standalone profile schema " + actor)
			if not profile.ok: continue
			check(var_to_bytes(profile.raw) == var_to_bytes(float(raw)), "Raw value including signed zero is retained")
			check(profile.cap == 0.75 and var_to_bytes(profile.effective) == var_to_bytes(clampf(float(raw), 0.0, 0.75)), "Independent fixed 75 percent clamp")
			var source: Dictionary = Defense.source_profile(stats, actor)
			check(source.ok and source.raw_resistances.size() == 4 and source.effective_resistances.size() == 4, "Opt-in source maps append exactly chaos")
			if not source.ok: continue
			check(var_to_bytes(source.raw_resistances.chaos) == var_to_bytes(profile.raw) and var_to_bytes(source.effective_resistances.chaos) == var_to_bytes(profile.effective), "Both actors use the standalone authority")
			var elemental: Dictionary = Defense.resistance_profile(stats, actor)
			check(elemental.raw_resistances.keys() == ELEMENTS and elemental.maximum_resistances.keys() == ELEMENTS and elemental.effective_resistances.keys() == ELEMENTS, "All three elemental maps stay elemental only")
			near(source.effective_resistances.fire, 0.83, "Chaos never changes the fire maximum")
			check(var_to_bytes(stats) == before, "Profiles never mutate input")
			profile.raw = 123.0
			source.raw_resistances.chaos = 123.0
			check(var_to_bytes(Defense.chaos_resistance_profile(stats, actor).raw) == var_to_bytes(float(raw)), "Returned profiles are detached")
	var metadata: Dictionary = Defense.chaos_resistance_metadata()
	check(metadata.origin == "original" and metadata.source_refs.is_empty(), "Original metadata has no false source attribution")
	check(metadata.settlement_order == ["resistance", "shield", "mana_guard", "health"] and metadata.maximum_effective == 0.75, "Metadata states actual settlement and cap")
	check(metadata.unsupported.has("other_source_talent_grants") and String(metadata.description).contains("仅接入58218"), "Metadata advertises only the implemented source node")
	metadata.supported_actors.clear()
	check(Defense.chaos_resistance_metadata().supported_actors == ["player", "monster"], "Metadata is detached")


func test_validation() -> void:
	for bad: Variant in [INF, -INF, NAN, true, false, "0.25", null, [], {}, Vector2.ZERO]:
		var stats: Dictionary = {"chaos_resistance": bad, "nested": {"values": [1, 2]}}
		var before: PackedByteArray = var_to_bytes(stats)
		for actor: String in ["player", "monster"]:
			rejected(Defense.chaos_resistance_profile(stats, actor), "Malformed standalone chaos " + str(bad))
			rejected(Defense.source_profile(stats, actor), "Malformed source chaos " + str(bad))
			for components: Dictionary in [{"chaos": 100.0}, {"fire": 100.0}, {}]:
				rejected(Defense.incoming_source_hit(components, stats, 10.0, 100.0, actor, 0.0, 20.0, 0.4), "Bad chaos never partially settles even an unrelated or empty hit")
		check(var_to_bytes(stats) == before, "Rejected input stays byte-identical")
		check(Defense.resistance_profile(stats) == Defense.resistance_profile({}), "Elemental-only API retains its prior independence")
	for stats: Dictionary in [{}, {"chaos_resistance": NAN}]:
		check(Defense.chaos_resistance_profile(stats, "unknown") == {"ok": false, "reason": "Unknown defense actor"}, "Actor validation precedes chaos validation")
	for prior: Dictionary in [{"fire_resistance": NAN}, {"cold_resistance": true}, {"armour": -1}, {"maximum_fire_resistance_add": -1}, {"maximum_cold_resistance_add": NAN}, {"maximum_lightning_resistance_add": true}]:
		var expected: Dictionary = old.call("source_profile", prior)
		var extended: Dictionary = prior.duplicate(true)
		extended.chaos_resistance = NAN
		check(var_to_bytes(Defense.source_profile(extended)) == var_to_bytes(expected), "Existing source validation wins before new stat")
	check(Defense.incoming_source_hit({"chaos": -1}, {"chaos_resistance": NAN}, -1, NAN).reason == "Damage component must be a finite nonnegative scalar: chaos", "Invalid component keeps first precedence")
	check(Defense.incoming_source_hit({"chaos": 100.0}, {"chaos_resistance": NAN}, -1, NAN).reason == "Chaos resistance must be a finite scalar", "Malformed new stat cannot be hidden by invalid resources")
	for pools: Array in [[-1, 100, 20, 0.4], [10, NAN, 20, 0.4], [10, 100, NAN, 0.4], [10, 100, 20, true], [10, 100, 20, 1.1]]:
		rejected(Defense.incoming_source_hit({"chaos": 100.0}, {"chaos_resistance": 0.25}, pools[0], pools[1], "player", 0.0, pools[2], pools[3]), "Bad resource or mana guard remains atomic")


func test_components_and_resources() -> void:
	for actor: String in ["player", "monster"]:
		var stats: Dictionary = {"armour": 500.0, "fire_resistance": 1.0, "cold_resistance": 0.25, "lightning_resistance": 0.5, "maximum_fire_resistance_add": 0.08}
		var components: Dictionary = {"physical": 100.0, "fire": 100.0, "cold": 100.0, "lightning": 100.0, "chaos": 100.0}
		var before: PackedByteArray = var_to_bytes([stats, components])
		var baseline: Dictionary = Defense.incoming_source_hit(components, stats, 20.0, 200.0, actor, 0.15, 100.0, 0.4)
		var extended: Dictionary = stats.duplicate(true)
		extended.chaos_resistance = 0.25
		var mixed: Dictionary = Defense.incoming_source_hit(components, extended, 20.0, 200.0, actor, 0.15, 100.0, 0.4)
		check(baseline.ok and mixed.ok, "Mixed hit accepts " + actor)
		if not baseline.ok or not mixed.ok: continue
		for type: String in ["physical", "fire", "cold", "lightning"]:
			check(var_to_bytes(mixed.components[type]) == var_to_bytes(baseline.components[type]), "Other component bytes unchanged: " + type)
		near(mixed.components.chaos, 86.25, "Chaos resistance precedes hit-taken multiplier")
		near(mixed.damage_total, 307.05, "Mixed components sum once")
		near(mixed.shield_spent, 20.0, "Chaos does not bypass shield")
		near(mixed.mana_spent, 100.0, "Mana guard caps spending at available mana")
		near(mixed.health_lost, 187.05, "Life receives remaining damage")
		check(var_to_bytes([stats, components]) == before, "Mixed receipt leaves caller unchanged")
		for pool: Array in [[100.0, 20.0, 100.0, 75.0, 0.0, 0.0, 0.0], [25.0, 40.0, 100.0, 25.0, 20.0, 30.0, 0.0], [25.0, 7.0, 100.0, 25.0, 7.0, 43.0, 0.0], [25.0, 40.0, 10.0, 25.0, 20.0, 10.0, 20.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 75.0]]:
			var result: Dictionary = Defense.incoming_source_hit({"chaos": 100.0}, {"chaos_resistance": 0.25}, pool[0], pool[2], actor, 0.0, pool[1], 0.4)
			check(result.ok, "Pure chaos resource case accepts")
			if not result.ok: continue
			for index: int in range(4):
				near(result[["shield_spent", "mana_spent", "health_lost", "overkill"][index]], pool[index + 3], "Expected ordered pool spending")
			near(result.damage_total, result.shield_spent + result.mana_spent + result.health_lost + result.overkill, "Damage is conserved")
			near(result.remaining_shield + result.shield_spent, pool[0], "Shield is conserved")
			near(result.remaining_mana + result.mana_spent, pool[1], "Mana is conserved")
			near(result.remaining_health + result.health_lost, pool[2], "Health is conserved")
		for raw: float in [-0.25, 0.0, 0.25, 0.75, 1.0]:
			var pure: Dictionary = Defense.incoming_source_hit({"chaos": 100.0}, {"chaos_resistance": raw}, 0.0, 200.0, actor)
			near(pure.damage_total, 100.0 * (1.0 - clampf(raw, 0.0, 0.75)), "Pure chaos boundary damage")
			check(not pure.has("mana_spent") and pure.stage == "hit_mitigation", "Disabled mana retains old shape and chaos is a hit")


func test_frozen_compatibility() -> void:
	var samples: Array[Dictionary] = [{}, {"fire_resistance": -0.0, "cold_resistance": -0.0, "armour": -0.0}, {"fire_resistance": 0.5, "cold_resistance": 0.9, "lightning_resistance": -0.25, "armour": 500.0}, {"fire_resistance": 1.0, "maximum_fire_resistance_add": 0.08}, {"maximum_cold_resistance_add": -0.0}, {"fire_resistance": NAN}, {"armour": -1}, {"maximum_fire_resistance_add": NAN}]
	for actor: String in ["player", "monster", "unknown"]:
		for stats: Dictionary in samples:
			same_old("source_profile", [stats, actor])
			same_old("resistance_profile", [stats, actor])
			same_old("defense_profile", [stats, actor])
			for components: Variant in [{"physical": 20.0, "fire": 30.0, "cold": 40.0, "lightning": 10.0, "chaos": 5.0}, {"chaos": -0.0}, {"chaos": -1}, null]:
				same_old("incoming_source_hit", [components, stats, -0.0, 100.0, actor, -0.0, NAN, -0.0])
				same_old("incoming_source_hit", [components, stats, 5.0, 20.0, actor, 0.15, 10.0, 0.4])
		for zero: Variant in [0, 0.0, -0.0]:
			var prior: Dictionary = {"fire_resistance": -0.0, "cold_resistance": 0.25, "maximum_fire_resistance_add": -0.0, "armour": -0.0}
			var extended: Dictionary = prior.duplicate(true)
			extended.chaos_resistance = zero
			check(var_to_bytes(without_chaos_maps(Defense.source_profile(extended, actor))) == var_to_bytes(old.call("source_profile", prior, actor)), "Explicit chaos zero only appends new maps; old profile bytes survive")
			for components: Dictionary in [{"fire": 100.0}, {"physical": -0.0, "fire": -0.0}]:
				var expected: Dictionary = old.call("incoming_source_hit", components, prior, -0.0, 100.0, actor, -0.0, NAN, -0.0)
				check(var_to_bytes(without_chaos_maps(Defense.incoming_source_hit(components, extended, -0.0, 100.0, actor, -0.0, NAN, -0.0))) == var_to_bytes(expected), "Zero chaos keeps all old hit fields byte-identical including negative zero")
		for stat: String in ["fire_resistance", "chaos_resistance", "cold_resistance", "maximum_chaos_resistance_add"]:
			same_old("supports_stat", [stat, actor])
			same_old("support_reason", [stat, actor])
		for raw: Variant in [0, -0.0, 0.25, NAN]:
			same_old("defense_profile", [{"chaos_resistance": raw}, actor])
			same_old("incoming_hit", [{"chaos": 100.0}, {"chaos_resistance": raw}, 20.0, 100.0, actor])
		for args: Array in [[100.0, 0.5, 20.0, 100.0, actor], [100.0, 1.0, 20.0, 100.0, actor, 20.0, 0.4, 0.08], [-0.0, -0.0, -0.0, 100.0, actor, NAN, -0.0], [100.0, NAN, -1, NAN, actor]]:
			same_old("incoming_burn", args)
	same_old("metadata", [])
	check(Defense.ELEMENTS == ELEMENTS and Damage.ELEMENTS == ELEMENTS, "Chaos never joins elemental vocabulary")


func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v093-chaos-rules-"):
		push_error("Use the isolated v093 chaos rules runner after the shared import")
		quit(78)
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(BASELINE_PATH)
	check(FileAccess.get_sha256(BASELINE_PATH) == BASELINE_SHA256, "Frozen defense is exact 897dbfc source")
	var dependencies: Dictionary = {"res://scripts/combat/damage_resolver.gd": "720dc69a7446334e8aec3ac15bdf7c1717fa7b96db5657e0c9622513121a4e23", "res://scripts/combat/hit_penetration_rules.gd": "6b0733c563548a9034cd5169b1736287cbffc4b40a14cdf71f37a729c377fc88"}
	for path: String in dependencies:
		check(FileAccess.get_sha256(path) == dependencies[path], "Frozen oracle dependency stays unchanged: " + path)
	var script := GDScript.new()
	script.source_code = bytes.get_string_from_utf8().replace("class_name DefenseRules\n", "")
	var error: Error = script.reload()
	check(error == OK, "Frozen single-file oracle compiles")
	if error != OK or failures > 0:
		quit(1)
		return
	old = script.new()
	current = Defense.new()
	test_profiles()
	test_validation()
	test_components_and_resources()
	test_frozen_compatibility()
	var report: Dictionary = {"checks": checks, "failures": failures, "legacy_typed_byte_cases": legacy_cases, "baseline_commit": "897dbfc16c1308b2b6916fa9ba52792d9d82c293", "baseline_sha256": BASELINE_SHA256, "scope": "Bounded pure defense rules; no model, UI, save, encounter, export or long-running verification"}
	var report_path: String = OS.get_environment("CHAOS_RULES_REPORT")
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("Could not write chaos rules report")
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("CHAOS_RESISTANCE_RULES ", JSON.stringify(report))
	quit(1 if failures else 0)
