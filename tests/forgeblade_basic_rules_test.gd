extends SceneTree
## New basic delivery plus byte-level compatibility with the actual v0.55 tree.
const Probe = preload("res://docs/qa/v056-rules/capture_v055.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Leech = preload("res://scripts/combat/leech_rules.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false
var sections: Dictionary = {}


func _initialize() -> void:call_deferred("_run")


func _run() -> void:
	seed(560056)
	var expected: Array = [randi(), randi(), randi()]
	seed(560056)
	_case(_oracle, "complete_v055_bytes_and_inflight")
	_case(_delivery_and_damage, "new_delivery_and_local_stage")
	_case(_scope_and_resources, "scopes_critical_and_leech")
	_case(_validation, "invalid_inputs_still_reject")
	_case(_frozen_provenance, "frozen_provenance_and_detachment")
	_same([randi(), randi(), randi()], expected, "Compilation/getters/consumers use no global RNG")
	print("Forgeblade basic rules: %d checks, %d failures; sections %s" % [checks, failures, JSON.stringify(sections)])
	quit(1 if failures else 0)


func _case(test: Callable, label: String) -> void:
	var start: int = checks
	completed = false
	test.call()
	_expect(completed, "Case completes without script errors: " + label)
	sections[label] = checks - start


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _same(actual: Variant, expected: Variant, label: String) -> void:
	_expect(var_to_bytes(actual) == var_to_bytes(expected), label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) <= maxf(1.0e-9, 1.0e-12 * absf(expected)), label)


func _snapshot(stats: Dictionary = {"damage": 18.0}, flat: float = 6.0, increased: float = 0.3) -> Dictionary:
	var snapshot: Dictionary = Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])
	snapshot.weapon_profile = Probe.blade(flat, increased)
	return snapshot


func _oracle() -> void:
	var path: String = OS.get_environment("V056_ORACLE_INPUT")
	_expect(not path.is_empty() and FileAccess.file_exists(path), "Independently captured released v055 oracle exists")
	if path.is_empty() or not FileAccess.file_exists(path):return
	var oracle: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(path))
	var actual: Dictionary = Probe.capture_legacy()
	_expect(oracle.legacy.size() > 4000 and oracle.inflight.size() == 24, "Whole-result baseline covers legacy compile and original flight inputs")
	_same(actual.keys(), oracle.legacy.keys(), "Original case order preserved")
	for key: String in oracle.legacy:_same(actual.get(key), oracle.legacy[key], "Entire original return bytes " + key)
	_same(actual, oracle.legacy, "Complete ordered oracle preserves values/types/shape/errors")
	for index: int in range(oracle.inflight.size()):
		var row: Dictionary = oracle.inflight[index]
		_same(Probe.flight_result(row.input), row.output, "Released in-flight basic getters/events/carriers remain original bytes %d" % index)
	_same(oracle.rng_after, oracle.rng_expected, "Released capture did not consume global RNG")
	completed = true


func _delivery_and_damage() -> void:
	_same(Combat.BASIC_MELEE, {"delivery": "melee", "radius": 60.0, "half_angle": PI / 4.0, "max_targets": 1}, "One fixed authored recipe")
	for sample: Array in [[0.0, 0.0, 4.0], [1.0, 0.1, 5.5], [2.0, 0.15, 6.9], [6.0, 0.3, 13.0]]:
		var snapshot: Dictionary = _snapshot({"damage": 18.0, "attack_added_physical": 6.0, "attack_added_fire": 6.0}, sample[0], sample[1])
		var before: PackedByteArray = var_to_bytes(snapshot)
		var cast: Dictionary = Compiler.compile_basic(snapshot)
		_expect(cast.ok and cast.skill_id == "basic", "Legal equipped blade uses existing basic identity")
		_same(cast.keys(), ["ok", "error", "skill_id", "recipe", "snapshot", "packets"], "No mana/cooldown/support/system fields added")
		_same(cast.recipe, Combat.BASIC_MELEE, "White/T1/T3 have identical fixed reach")
		_same(cast.packets.keys(), ["direct"], "Exactly one direct packet; no projectile or secondary")
		var packet: Dictionary = cast.packets.direct
		_same(packet.tags, ["hit", "attack", "melee"], "Strict three melee attack tags, no area")
		_expect(packet.role == "direct" and Base.packet_error(packet).is_empty(), "New direct packet passes shared frozen validation")
		_near(packet.assembly.weapon.components.physical, sample[2], "Independent local W")
		_near(packet.assembly.weapon.contribution.physical, sample[2], "W enters exactly once at coefficient 1")
		_near(packet.base.physical, 24.0 + sample[2], "B + W + external physical")
		_near(packet.base.fire, 6.0, "External fire keeps added effectiveness 1")
		_expect(packet.assembly.base_coefficient == 1.0 and packet.assembly.added_effectiveness == 1.0, "Independent coefficients both 1")
		_expect(not cast.has("mana") and not cast.has("cooldown"), "Legacy basic has no resource debit/cooldown contract")
		_expect(Combat.event_packet(cast.snapshot, "basic", "projectile").is_empty() and Combat.secondary_packet(cast.snapshot, "basic").is_empty(), "Melee compiled snapshot cannot dispatch old flight effects")
		_expect(var_to_bytes(snapshot) == before, "Compile is detached from input")
	var meta: Dictionary = Weapon.metadata()
	_same(meta.consumers_by_base.forgeblade, {"basic": ["direct"], "cleave": ["direct"]}, "Metadata reflects exact authored blade consumers")
	completed = true


func _scope_and_resources() -> void:
	var stats: Dictionary = {"damage": 18.0, "attack_added_fire": 6.0,
		"global_increased": 0.1, "physical_increased": 0.2, "attack_physical_increased": 0.3,
		"melee_physical_increased": 0.4, "area_increased": 9.0, "projectile_increased": 9.0,
		"area_size_increased": 1e300, "melee_area_size_increased": 1e300, "projectile_speed_increased": 1e300,
		"crit_base_chance": 0.1, "crit_base_multiplier": 1.5, "crit_chance_increased": 0.1,
		"attack_crit_chance_increased": 0.2, "melee_crit_chance_increased": 0.3,
		"projectile_attack_crit_chance_increased": 3.0, "spell_crit_chance_increased": 3.0,
		"crit_multiplier_add": 0.1, "melee_crit_multiplier_add": 0.2, "projectile_attack_crit_multiplier_add": 3.0,
		"max_health": 120.0, "max_mana": 100.0, "attack_life_leech": 0.02, "attack_mana_leech": 0.01,
		"physical_attack_life_leech": 0.01, "physical_attack_mana_leech": 0.02}
	var cast: Dictionary = Compiler.compile_basic(_snapshot(stats))
	_expect(cast.ok, "Finite irrelevant spatial modifiers do not scale/reject fixed melee delivery")
	_same(cast.recipe, Combat.BASIC_MELEE, "Projectile speed and all area sizes leave geometry unchanged")
	var resolved: Dictionary = Damage.resolve(cast.packets.direct, cast.snapshot.modifiers)
	_near(resolved.components.physical, 62.0, "Global/physical/attack/melee increased apply after W once")
	_near(resolved.components.fire, 6.6, "Area/projectile modifiers do not affect fire")
	_same(cast.critical.keys(), ["primary"], "Critical profile contains primary only")
	_near(cast.critical.primary.chance, 0.16, "Only global + attack + melee critical chance")
	_near(cast.critical.primary.multiplier, 1.8, "Only global + melee critical multiplier")
	_same(cast.snapshot.critical, cast.critical, "Runtime receives same frozen critical profile")
	_expect(cast.has("leech") and Leech.profile_error(cast.leech).is_empty(), "Shared dual-resource Leech profile admitted")
	var settlement: Dictionary = {"damage_total": 50.0, "components": {"physical": 40.0, "fire": 10.0},
		"shield_spent": 10.0, "health_lost": 30.0, "overkill": 10.0}
	var leech: Dictionary = Leech.plan_hit(cast.leech, cast.packets.direct, settlement)
	_expect(leech.ok, "Actual new direct packet drives existing settlement consumer")
	_near(leech.health.amount, 1.12, "Health Leech uses shield+health actually applied, excluding overkill")
	_near(leech.mana.amount, 1.04, "Mana Leech uses same actual applied hit")
	completed = true


func _validation() -> void:
	for profile: Variant in Probe.Prior.invalid_profiles():
		var snapshot: Dictionary = _snapshot()
		if profile is Dictionary and profile.get("base_id") is String and profile.base_id == "ashwood_bow":
			profile = profile.duplicate(true)
			profile.base_id = "forgeblade"
		snapshot.weapon_profile = profile
		_expect(not Compiler.compile_basic(snapshot).ok, "Malformed blade source remains rejected")
	for values: Variant in [{"projectile_speed_increased": NAN}, {"projectile_speed_increased": INF},
		{"projectile_speed_increased": -1.0}, {"area_size_increased": -0.1}, {"area_size_increased": INF},
		{"melee_area_size_increased": "1"}, {"unknown": 0.2}, [], "spatial"]:
		var snapshot: Dictionary = _snapshot()
		snapshot.spatial_modifiers = values
		_expect(not Compiler.compile_basic(snapshot).ok, "Ignored delivery scope does not wash out invalid statistics")
	for pair: Array in [["critical_modifiers", {"base_chance": NAN, "base_multiplier": 1.5}],
		["leech_modifiers", {}], ["resource_modifiers", []], ["effects", ["unknown"]],
		["base_damage", INF], ["accuracy", -1.0], ["projectile_count", NAN], ["weapon_profile", {}]]:
		var snapshot: Dictionary = _snapshot()
		snapshot[pair[0]] = pair[1]
		_expect(not Compiler.compile_basic(snapshot).ok, "Full original validation retained: " + pair[0])
	var cast: Dictionary = Compiler.compile_basic(_snapshot())
	_expect(not Compiler.compile_basic(cast.snapshot).ok, "Already compiled new snapshots cannot double-add W")
	completed = true


func _frozen_provenance() -> void:
	var cast: Dictionary = Compiler.compile_basic(_snapshot())
	var frozen: PackedByteArray = var_to_bytes(cast.packets.direct)
	cast.snapshot.weapon_profile = Probe.Prior.bow()
	cast.snapshot.base_damage = 999.0
	_expect(var_to_bytes(Combat.event_packet(cast.snapshot, "basic", "direct")) == frozen, "Post-cast weapon swap cannot reinterpret frozen blade")
	cast.packets.direct.assembly.weapon.profile.flat.physical = 999.0
	var getter: Dictionary = Combat.event_packet(cast.snapshot, "basic", "direct")
	getter.assembly.weapon.profile.sources[0].value = 999.0
	_expect(var_to_bytes(Combat.event_packet(cast.snapshot, "basic", "direct")) == frozen, "Return packet/getter nested edits are detached")
	for profile: Variant in [null, Probe.Prior.bow(), {}]:
		var snapshot: Dictionary = Combat.snapshot({"damage": 18.0}, [])
		if profile != null:snapshot.weapon_profile = profile
		_expect(Combat.event_packet(snapshot, "basic", "direct").is_empty(), "No-weapon or bow raw snapshot cannot request direct")
		var recipe: Dictionary = Combat._hit_recipe("basic", "direct", {"physical": 1.0}, 1.0, 1.0, ["hit", "attack", "melee"])
		var packet: Dictionary = Base.assemble(18.0, recipe, {}, [], {} if profile == null else profile)
		_expect(Base.packet_error(packet).is_empty(), "Forged no-weapon packet is arithmetically valid before provenance gate")
		snapshot.compiled_skill_id = "basic"
		snapshot.compiled_packets = {"direct": packet}
		_expect(Combat.event_packet(snapshot, "basic", "direct").is_empty(), "Frozen new role requires validated blade trace")
	for field: String in ["profile", "components", "coefficient", "contribution"]:
		var snapshot: Dictionary = Compiler.compile_basic(_snapshot()).snapshot
		snapshot.compiled_packets.direct.assembly.weapon.erase(field)
		_expect(Combat.event_packet(snapshot, "basic", "direct").is_empty(), "Malformed new trace rejects " + field)
	for tags: Array in [["hit", "attack", "melee", "area"], ["hit", "attack", "projectile"],
		["hit", "spell", "melee"], ["hit", "attack", "melee", "secondary"], ["hit", "attack", "attack"]]:
		var snapshot: Dictionary = Compiler.compile_basic(_snapshot()).snapshot
		snapshot.compiled_packets.direct.tags = tags
		_expect(Combat.event_packet(snapshot, "basic", "direct").is_empty(), "New role rejects wrong/excess/duplicate tags")
	for coefficient: Array in [[2.8, 1.0], [1.0, 2.8]]:
		var recipe: Dictionary = Combat._hit_recipe("basic", "direct", {"physical": 1.0}, coefficient[0], coefficient[1], ["hit", "attack", "melee"])
		var snapshot: Dictionary = _snapshot()
		snapshot.compiled_skill_id = "basic"
		snapshot.compiled_packets = {"direct": Base.assemble(18.0, recipe, {}, [], Probe.blade())}
		_expect(Combat.event_packet(snapshot, "basic", "direct").is_empty(), "Self-consistent but unauthored direct coefficient rejected")
	_expect(Combat.event_packet(Compiler.compile_basic(_snapshot()).snapshot, "basic", "direct", 1).is_empty(), "Only index zero admitted")
	completed = true
