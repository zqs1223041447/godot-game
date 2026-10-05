extends SceneTree
## v0.55 local weapon contract, complete v0.54 bytes and actual cast consumers.
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const Data = preload("res://scripts/game_data.gd")
const Probe = preload("res://docs/qa/v055-weapon-rules/capture_v054.gd")
var checks: int = 0
var failures: int = 0
var completed: bool = false
var sections: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(550055)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(550055)
	_case(_legacy_bytes, "complete_v054_bytes_and_error_precedence")
	_case(_profiles, "forgeblade_profiles")
	_case(_consumer_matrix, "base_specific_consumer_matrix")
	_case(_assembly, "independent_local_stage")
	_case(_compiled_consumers, "real_compiler_and_frozen_consumers")
	_case(_trace_rejections, "forged_traces")
	_expect([randi(), randi(), randi()] == expected_random, "No global RNG consumed")
	print("Forgeblade hit rules: %d checks, %d failures; sections %s" % [checks, failures, JSON.stringify(sections)])
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
	_expect(is_finite(actual) and absf(actual - expected) <= maxf(1.0e-9, 1.0e-12 * absf(expected)),
		"%s: %.12f versus %.12f" % [label, actual, expected])


func _profile(flat: float = 2.0, increased: float = 0.2) -> Dictionary:
	var result: Dictionary = Probe.bow(flat, increased)
	result.base_id = "forgeblade"
	return result


func _snapshot(profile: Dictionary = {}) -> Dictionary:
	var result: Dictionary = Combat.snapshot({"damage": 18.0}, ["return_on_range", "explode_on_flight_end"])
	if not profile.is_empty():
		result.weapon_profile = profile
	return result


func _recipe() -> Dictionary:
	return Combat._event_recipe(_snapshot(), "cleave", "direct", 0)


func _legacy_bytes() -> void:
	var path: String = OS.get_environment("V055_ORACLE_INPUT")
	_expect(not path.is_empty() and FileAccess.file_exists(path), "Frozen v0.54 independent output exists")
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var frozen_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var v54FrozenOracle: Variant = bytes_to_var(frozen_bytes)
	_expect(v54FrozenOracle is Dictionary and v54FrozenOracle.size() > 1000, "Complete independently captured oracle, not partial fields")
	if not v54FrozenOracle is Dictionary:
		return
	var actual: Dictionary = Probe.capture()
	_same(actual.keys(), v54FrozenOracle.keys(), "All frozen cases retained in original order")
	for key: String in v54FrozenOracle:
		_same(actual.get(key), v54FrozenOracle[key], "Complete original returned Variant bytes: " + key)
	_expect(var_to_bytes(actual) == frozen_bytes, "Whole frozen oracle bytes including int/float types, order, nested fields and error strings")
	completed = true


func _profiles() -> void:
	_expect(Weapon.BASE_ID == "ashwood_bow" and Weapon.BASE_PHYSICAL_BY_ID == {"ashwood_bow": 4.0, "forgeblade": 4.0}, "One new physical4 base; historical base identity retained")
	for pair: Array in [[0.0, 0.0], [1.0, 0.1], [2.0, 0.15], [6.0, 0.3], [3.0, 0.22]]:
		var profile: Dictionary = _profile(pair[0], pair[1])
		var original: PackedByteArray = var_to_bytes(profile)
		var resolved: Dictionary = Weapon.resolve(profile)
		_expect(resolved.ok and profile.size() == 7, "Existing seven-field profile admits blade")
		_near(resolved.components.physical, (4.0 + pair[0]) * (1.0 + pair[1]), "Local formula uses only weapon points")
		resolved.profile.base.physical = 999.0
		resolved.components.physical = 999.0
		_expect(var_to_bytes(profile) == original, "Resolution owns detached profile and components")
	for invalid: Variant in Probe.invalid_profiles():
		var profile: Variant = invalid.duplicate(true) if invalid is Dictionary else invalid
		if profile is Dictionary and profile.get("base_id") is String and profile.base_id == "ashwood_bow":
			profile.base_id = "forgeblade"
		_expect(not Weapon.resolve(profile).ok, "Malformed new profile cannot enter rules")
		for skill: String in ["cleave", "tornado", "bolt", "ward"]:
			var snapshot: Dictionary = _snapshot()
			snapshot.weapon_profile = profile
			_expect(not Compiler.compile_skill(skill, snapshot, []).ok, "Malformed profile rejects before unrelated consumer: " + skill)
		_expect(Base.assemble(18.0, _recipe(), {}, [], profile).is_empty(), "Pure assembly rejects malformed profile")
	var global_stat: Dictionary = _profile()
	global_stat.sources[0].stat = "physical_increased"
	_expect(not Weapon.resolve(global_stat).ok, "Global increased cannot masquerade as local physical")
	var huge: Dictionary = _profile(1e308, 0.0)
	_expect(Weapon.resolve(huge).ok and Base.assemble(0.0, _recipe(), {}, [], huge).is_empty(), "Finite W still rejects coefficient overflow")
	var metadata: Dictionary = Weapon.metadata()
	_expect(metadata.base_ids == ["ashwood_bow", "forgeblade"] and metadata.consumers_by_base.forgeblade == {"basic": ["direct"], "cleave": ["direct"]}, "Metadata maps each base to its actual consumer")
	metadata.consumers_by_base.forgeblade.cleave.clear()
	_expect(Weapon.metadata().consumers_by_base.forgeblade.cleave == ["direct"], "Per-base consumer metadata is detached")
	completed = true


func _consumer_matrix() -> void:
	for base_id: String in ["ashwood_bow", "forgeblade", "unknown", "cinder_reed"]:
		for skill: String in ["basic", "tornado", "cleave", "bolt", "unknown"]:
			for role: String in ["projectile", "parent", "child", "direct", "secondary", "bounce"]:
				for tags: Variant in [["hit", "attack", "projectile"], ["hit", "attack", "melee", "area"],
					["area", "melee", "attack", "hit"], ["hit", "spell", "projectile"], ["hit", "area", "secondary", "explosion"],
					["attack", "melee", "area"], ["hit", "attack", "melee"], ["hit", "attack", "area"],
					["hit", "attack", "melee", "area", "projectile"], ["hit", "attack", "melee", "area", "spell"],
					["hit", "attack", "projectile", "area"], [], null, "hit"]:
					var expected: bool = false
					if base_id == "ashwood_bow":
						expected = tags is Array and tags.has("hit") and tags.has("attack") and tags.has("projectile") \
							and not tags.has("spell") and not tags.has("secondary") and not tags.has("explosion") \
							and ((skill == "basic" and role == "projectile") or (skill == "tornado" and role in ["parent", "child"]))
					elif base_id == "forgeblade":
						expected = role == "direct" and tags is Array and ((skill == "cleave" and (tags == ["hit", "attack", "melee", "area"] or tags == ["area", "melee", "attack", "hit"])) or (skill == "basic" and tags == ["hit", "attack", "melee"]))
					_expect(Weapon.consumes_hit(base_id, skill, role, tags) == expected, "Exact consumer matrix " + base_id + ":" + skill + ":" + role + ":" + str(tags))
	completed = true


func _assembly() -> void:
	_expect(Data.SKILLS.cleave.hit_recipe.base_coefficient == 2.8 and Data.SKILLS.cleave.hit_recipe.added_effectiveness == 2.8, "Existing two coefficients remain2.8")
	for sample: Array in [[0.0, 0.0, 4.0, 61.6], [1.0, 0.1, 5.5, 65.8], [2.0, 0.15, 6.9, 69.72], [6.0, 0.3, 13.0, 86.8]]:
		var packet: Dictionary = Base.assemble(18.0, _recipe(), {}, [], _profile(sample[0], sample[1]))
		_expect(Base.packet_error(packet).is_empty(), "Newly assembled blade trace passes frozen validator")
		_near(packet.assembly.weapon.components.physical, sample[2], "White/T1/T3 frozen W")
		_near(packet.base.physical, sample[3], "White/T1/T3 real compiler budget")
		_near(packet.assembly.intrinsic.physical, 50.4, "Local increased leaves ordinary B unchanged")
	var packet: Dictionary = Base.assemble(18.0, _recipe(), {"attack": {"physical": 6.0, "fire": 6.0}}, [], _profile(6.0, 0.3))
	_near(packet.base.physical, 103.6, "B plus W plus external physical use distinct stages")
	_near(packet.base.fire, 16.8, "External fire never receives local increased")
	_near(packet.assembly.added.physical, 16.8, "External physical never receives local increased")
	var resolved: Dictionary = Damage.resolve(packet, Combat.modifiers({"global_increased": 0.1, "attack_physical_increased": 0.2,
		"melee_physical_increased": 0.3, "physical_increased": 0.4, "area_increased": 0.5, "projectile_increased": 9.0}))
	_near(resolved.components.physical, 103.6 * 2.5, "Ordinary matching increased applies once after local W")
	_near(resolved.components.fire, 16.8 * 1.6, "Only existing global/area increased applies to fire")
	var differing: Dictionary = _recipe()
	differing.base_coefficient = 2.0
	differing.added_effectiveness = 0.5
	var independent: Dictionary = Base.assemble(18.0, differing, {"attack": {"physical": 6.0}}, [], _profile(6.0, 0.3))
	_near(independent.base.physical, 36.0 + 26.0 + 3.0, "W follows base coefficient independently from added effectiveness")
	_same(Base.assemble(18.0, _recipe(), {}, [], Probe.bow()), Base.assemble(18.0, _recipe()), "Bow does not add W to cleave")
	completed = true


func _compiled_consumers() -> void:
	var snapshot: Dictionary = _snapshot(_profile(6.0, 0.3))
	var cast: Dictionary = Compiler.compile_skill("cleave", snapshot, [])
	_expect(cast.ok, "Actual compiler accepts blade cleave")
	_near(cast.packets.direct.base.physical, 86.8, "Actual compiler uses blade W")
	_same(Combat.event_packet(cast.snapshot, "cleave", "direct"), cast.packets.direct, "Runtime frozen getter admits same blade packet")
	var frozen: PackedByteArray = var_to_bytes(cast.snapshot.compiled_packets.direct)
	snapshot.weapon_profile = Probe.bow(0.0, 0.0)
	cast.snapshot.weapon_profile = Probe.bow(6.0, 0.3)
	cast.snapshot.base_damage = 999.0
	cast.packets.direct.assembly.weapon.profile.flat.physical = 999.0
	var hit: Dictionary = Combat.event_packet(cast.snapshot, "cleave", "direct")
	_expect(var_to_bytes(hit) == frozen, "Post-cast swap and input mutation never reinterpret frozen blade packet")
	hit.assembly.weapon.profile.sources[0].value = 999.0
	_expect(var_to_bytes(Combat.event_packet(cast.snapshot, "cleave", "direct")) == frozen, "Frozen getter returns detached nested trace")
	for skill: String in Probe.SKILLS:
		if skill in ["cleave", "basic"]:
			continue
		var old: Dictionary = Probe.compile(skill, _snapshot())
		var current: Dictionary = Probe.compile(skill, _snapshot(_profile(6.0, 0.3)))
		_expect(current.ok and old.ok, "Valid blade may accompany other skill " + skill)
		_same(current.packets, old.packets, "Blade local W absent from all unrelated primary/secondary packets " + skill)
	var shots: Array[Dictionary] = []
	var runtime = Runtime.new()
	var tornado: Dictionary = Compiler.compile_skill("tornado", _snapshot(_profile(6.0, 0.3)), [])
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, tornado.snapshot, 100, 1) == 1, "Actual projectile runtime admits sword-equipped tornado")
	_near(shots[0].payload.base.physical, 10.8, "Actual tornado mother has no sword W")
	runtime.advance(shots, 0.4, [], Vector2.ZERO, 100)
	_expect(shots.size() == 3, "Actual tornado mother splits")
	for child: Dictionary in shots:
		_near(child.payload.base.physical, 7.56, "Actual child has no sword W")
		_expect(not child.payload.assembly.has("weapon"), "Sword trace absent from actual children")
	var stats: Dictionary = {"damage": 18.0, "crit_base_chance": 0.05, "crit_base_multiplier": 1.5,
		"crit_chance_increased": 0.4, "crit_multiplier_add": 0.15, "max_health": 120.0, "max_mana": 102.0,
		"attack_life_leech": 0.02, "attack_mana_leech": 0.01}
	for skill: String in ["cleave", "basic", "tornado", "bolt", "meteor"]:
		var global: Dictionary = Combat.snapshot(stats, ["explode_on_flight_end"])
		global.weapon_profile = _profile(6.0, 0.3)
		var current: Dictionary = Probe.compile(skill, global)
		_expect(current.ok and current.has("critical"), "Global critical still reaches " + skill)
		_near(current.critical.primary.chance, 0.07, "Global critical chance remains shared across skill scopes")
		_near(current.critical.primary.multiplier, 1.65, "Global critical multiplier remains shared across skill scopes")
		if current.critical.has("secondary"):
			_near(current.critical.secondary.chance, 0.07, "Global critical still reaches independent explosion")
		_expect(current.has("leech") == (skill in ["cleave", "basic", "tornado"]), "Existing attack leech scope remains intact")
	var support: Dictionary = Compiler.compile_skill("cleave", _snapshot(_profile(6.0, 0.3)), ["concentrate"])
	_near(Damage.resolve(support.packets.direct, support.snapshot.modifiers).total, 108.5, "Existing more support scales whole blade hit once")
	completed = true


func _trace_rejections() -> void:
	var cast: Dictionary = Compiler.compile_skill("cleave", _snapshot(_profile()), [])
	var original: Dictionary = cast.packets.direct
	for key: String in ["profile", "components", "coefficient", "contribution"]:
		var packet: Dictionary = original.duplicate(true)
		packet.assembly.weapon.erase(key)
		_expect(not Base.packet_error(packet).is_empty(), "Missing new trace field rejects " + key)
	for pair: Array in [["profile", {}], ["profile", null], ["components", {"physical": 999.0}],
		["contribution", {"physical": 999.0}], ["coefficient", 1.0], ["coefficient", NAN], ["quality", 0.2]]:
		var packet: Dictionary = original.duplicate(true)
		packet.assembly.weapon[pair[0]] = pair[1]
		_expect(not Base.packet_error(packet).is_empty(), "Tampered blade trace fails " + str(pair[0]))
	for base_id: Variant in ["ashwood_bow", "unknown", "cinder_reed", 123, &"forgeblade"]:
		var packet: Dictionary = original.duplicate(true)
		packet.assembly.weapon.profile.base_id = base_id
		_expect(not Base.packet_error(packet).is_empty(), "Forged base fails even when numeric stages still sum")
	var source: Dictionary = original.duplicate(true)
	source.assembly.weapon.profile.sources[0].stat = "attack_added_physical"
	_expect(not Base.packet_error(source).is_empty(), "Forged source stat cannot turn external points local")
	for field: String in ["flat", "increased", "base"]:
		var packet: Dictionary = original.duplicate(true)
		packet.assembly.weapon.profile[field].physical += 1.0
		_expect(not Base.packet_error(packet).is_empty(), "Forged raw profile data rejects " + field)
	for event: Array in [["cleave", "projectile", ["hit", "attack", "melee", "area"]],
		["basic", "projectile", ["hit", "attack", "projectile"]], ["tornado", "parent", ["hit", "attack", "projectile"]],
		["tornado", "child", ["hit", "attack", "projectile"]], ["bolt", "projectile", ["hit", "spell", "projectile"]],
		["cleave", "direct", ["hit", "spell", "melee", "area"]], ["cleave", "direct", ["hit", "attack", "melee", "area", "projectile"]],
		["tornado", "secondary", ["hit", "area", "secondary", "explosion"]], ["unknown", "direct", ["hit", "attack", "melee", "area"]]]:
		var packet: Dictionary = original.duplicate(true)
		packet.skill_id = event[0]
		packet.role = event[1]
		packet.tags = event[2]
		_expect(not Base.packet_error(packet).is_empty(), "Self-consistent weapon trace cannot move to unsupported event")
		var snapshot: Dictionary = cast.snapshot.duplicate(true)
		snapshot.compiled_packets.direct = packet
		_expect(Combat.event_packet(snapshot, "cleave", "direct").is_empty(), "Frozen runtime rejects injected trace without fallback reassembly")
	completed = true
