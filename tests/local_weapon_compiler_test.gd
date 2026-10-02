extends SceneTree
## Item-local arithmetic, strict contracts and real detached carrier consumers.
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
var checks: int = 0
var failures: int = 0
var sample_weapon_points: float = 1.2 * float(Weapon.BASE_PHYSICAL_BY_ID.ashwood_bow) + 2.4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_local_rules()
	_test_stage_boundaries()
	_test_legacy_compatibility()
	_test_profile_rejections()
	_test_frozen_packet_rejections()
	_test_detachment_and_consumers()
	_test_preview()
	print("Local weapon compiler: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00001, "%s (%.8f vs %.8f)" % [label, value, expected])


func _profile(flat: float = 2.0, increased: float = 0.2) -> Dictionary:
	var sources: Array[Dictionary] = []
	if flat != 0.0:
		sources.append({"affix_id": "whetstone_edge", "stat": "weapon_added_physical", "value": flat})
	if increased != 0.0:
		sources.append({"affix_id": "tempered_edge", "stat": "weapon_physical_increased", "value": increased})
	return {"stage": "weapon_local", "item_id": "gear_000123", "base_id": "ashwood_bow",
		"base": {"physical": Weapon.BASE_PHYSICAL_BY_ID.ashwood_bow}, "flat": {"physical": flat},
		"increased": {"physical": increased}, "sources": sources}


func _snapshot(local: bool = true) -> Dictionary:
	var value: Dictionary = Combat.snapshot({"damage": 100.0, "attack_added_physical": 10.0,
		"attack_added_fire": 20.0, "spell_added_cold": 30.0, "spell_added_lightning": 40.0},
		["return_on_range", "explode_on_flight_end"])
	if local:
		value.weapon_profile = _profile()
	return value


func _recipe() -> Dictionary:
	return {"stage": "hit_base", "intrinsic_distribution": {"physical": 0.6, "fire": 0.4},
		"base_coefficient": 2.0, "added_effectiveness": 0.5,
		"tags": ["hit", "attack", "projectile"], "skill_id": "tornado", "role": "parent"}


func _test_local_rules() -> void:
	var profile: Dictionary = _profile()
	var before: Dictionary = profile.duplicate(true)
	var resolved: Dictionary = Weapon.resolve(profile)
	_expect(resolved.ok and resolved.reason.is_empty() and resolved.size() == 4, "Rules return complete success contract")
	_expect(resolved.components.size() == 1, "Local result contains only physical")
	_near(resolved.components.physical, sample_weapon_points, "Local base plus 2 points both receive 20 percent increase")
	_near(Weapon.resolve(_profile(3.0, 0.2)).components.physical, 1.2 * float(Weapon.BASE_PHYSICAL_BY_ID.ashwood_bow) + 3.6, "Local increase applies equally to base and local flat")
	_near(Weapon.resolve(_profile(0.0, 0.0)).components.physical, Weapon.BASE_PHYSICAL_BY_ID.ashwood_bow, "Normal bow contributes base without affixes")
	_expect(Weapon.resolve({}) == {"ok": true, "reason": "", "profile": {}, "components": {}}, "Pure helper supports absence")
	_expect(profile == before, "Pure rules preserve source input")
	resolved.profile.sources[0].value = 99.0
	resolved.profile.flat.physical = 99.0
	resolved.components.physical = 99.0
	_expect(profile == before and is_equal_approx(Weapon.resolve(profile).components.physical, sample_weapon_points), "Local profile and components are detached")
	for stat: String in ["weapon_added_physical", "weapon_physical_increased"]:
		_expect(Weapon.supports_stat(stat), "Only explicit local stat is supported " + stat)
		_expect(not Weapon.supports_stat(stat, "hit_base"), "Local stat cannot move to another stage")
	for stat: String in ["damage", "attack_added_physical", "physical_increased", "quality", "weapon_added_fire", "attack_speed"]:
		_expect(not Weapon.supports_stat(stat), "Unknown or global stat cannot enter local stage " + stat)
	var metadata: Dictionary = Weapon.metadata()
	_expect(metadata.stage == "weapon_local" and metadata.scope == "equipped_weapon", "Metadata exposes stage and ownership")
	metadata.consumers.basic.clear()
	metadata.source_refs.clear()
	_expect(Weapon.metadata().consumers.basic == ["projectile"] and Weapon.metadata().source_refs.size() == 2, "Metadata is detached")


func _test_stage_boundaries() -> void:
	var snapshot: Dictionary = _snapshot()
	var packet: Dictionary = Base.assemble(100.0, _recipe(), snapshot.added_damage, [], snapshot.weapon_profile)
	_expect(Base.packet_error(packet).is_empty(), "Mixed stage packet validates")
	_near(packet.base.physical, 125.0 + sample_weapon_points * 2.0, "Physical = 100*.6*2 + W*2 + 10*.5")
	_near(packet.base.fire, 90.0, "Fire = 100*.4*2 + 20*.5; local weapon never converts")
	_near(packet.assembly.intrinsic.physical, 120.0, "Local increased does not multiply old B")
	_near(packet.assembly.added.physical, 5.0, "Local increased does not multiply external physical")
	_near(packet.assembly.weapon.components.physical, sample_weapon_points, "Weapon resolves before skill coefficient")
	_near(packet.assembly.weapon.contribution.physical, sample_weapon_points * 2.0, "Weapon follows coefficient, independently from added effectiveness")
	_expect(packet.assembly.weapon.size() == 4 and packet.assembly.weapon.profile == snapshot.weapon_profile, "Frozen trace owns exact raw local source data")
	var zero: Dictionary = Base.assemble(0.0, _recipe(), snapshot.added_damage, [], snapshot.weapon_profile)
	_near(zero.base.physical, 5.0 + sample_weapon_points * 2.0, "Zero old B retains independent weapon and external points")
	_near(zero.base.fire, 10.0, "Zero old B never distributes weapon into fire")
	for role: String in ["parent", "child"]:
		var old: Dictionary = Combat.tornado_packet(_snapshot(false), role)
		var current: Dictionary = Combat.tornado_packet(snapshot, role)
		_near(current.base.physical - old.base.physical, sample_weapon_points * float(snapshot.tornado_recipe[role].coefficient), "Both tornado carriers add local physical " + role)
		_expect(current.base.fire == old.base.fire and current.assembly.intrinsic == old.assembly.intrinsic and current.assembly.added == old.assembly.added, "Tornado B distribution and external points stay unchanged " + role)
	var basic: Dictionary = Combat.event_packet(snapshot, "basic", "projectile")
	_near(basic.base.physical, 110.0 + sample_weapon_points, "Basic attack includes weapon physical")
	_near(basic.base.fire, 20.0, "Basic external fire stays separate")
	for skill: String in ["bolt", "frost", "nova", "meteor", "chain", "dash", "ward"]:
		var old: Dictionary = Compiler.compile_skill(skill, _snapshot(false), [])
		var current: Dictionary = Compiler.compile_skill(skill, snapshot, [])
		_expect(current.ok and current.packets == old.packets, "Spells and utility packets ignore valid local profile exactly " + skill)
		_expect(Preview.details(current) == Preview.details(old), "Spell and utility preview text remains exact " + skill)
	for skill: String in ["basic", "tornado", "bolt", "frost"]:
		_expect(Combat.secondary_packet(snapshot, skill) == Combat.secondary_packet(_snapshot(false), skill), "Independent explosion remains exact " + skill)
	var modifiers: Array = Combat.modifiers({"global_increased": 0.2, "projectile_increased": 0.5, "elemental_increased": 0.3})
	var resolved: Dictionary = Damage.resolve(packet, modifiers, {"physical": 0.25, "fire": 0.5})
	_near(resolved.components.physical, (125.0 + sample_weapon_points * 2.0) * 1.7 * 0.75, "Global and projectile increases then current defense apply after W")
	_near(resolved.components.fire, 90.0 * 2.0 * 0.5, "Local increased does not enter elemental/global buckets")
	var base_cast: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
	var focused: Dictionary = Compiler.compile_skill("tornado", snapshot, ["focus"])
	_expect(base_cast.packets == focused.packets, "Support more cannot change raw weapon arithmetic")
	_near(Damage.resolve(focused.packets.parent, focused.snapshot.modifiers).total,
		Damage.resolve(base_cast.packets.parent, base_cast.snapshot.modifiers).total * 1.25, "Support more scales full attack including W once")
	_expect(focused.packets.secondary == base_cast.packets.secondary, "Support and weapon never leak into secondary")
	var source: Dictionary = {"item_id": "gear_000456", "affix_id": "attack_added_physical", "stat": "attack_added_physical", "scope": "attack", "damage_type": "physical", "value": 10.0}
	var with_sources: Dictionary = Base.assemble(100.0, _recipe(), snapshot.added_damage, [source], snapshot.weapon_profile)
	_expect(with_sources.assembly.size() == 7 and Base.packet_error(with_sources).is_empty(), "External and local provenance can coexist without counting points twice")
	_near(with_sources.base.physical, packet.base.physical, "Both source traces leave aggregate amount unchanged")


func _test_legacy_compatibility() -> void:
	var recipe: Dictionary = _recipe()
	var expected: Dictionary = {"base": {"physical": 125.0, "fire": 90.0}, "tags": recipe.tags,
		"skill_id": "tornado", "role": "parent", "assembly": {"stage": "hit_base",
			"intrinsic": {"physical": 120.0, "fire": 80.0}, "added": {"physical": 5.0, "fire": 10.0},
			"base_coefficient": 2.0, "added_effectiveness": 0.5}}
	var legacy: Dictionary = Base.assemble(100.0, recipe, _snapshot(false).added_damage)
	_expect(JSON.stringify(legacy) == JSON.stringify(expected), "Absent profile preserves exact old packet order, shape and numbers")
	_expect(JSON.stringify(Base.assemble(100.0, recipe, _snapshot(false).added_damage, [], {})) == JSON.stringify(expected), "Optional assembly helper absence stays byte-equivalent")
	_expect(Preview.assembly_line(legacy) == "固有：物理 120.00 + 火焰 80.00；附加：物理 5.00 + 火焰 10.00；附加效用 0.50", "Legacy preview line is unchanged")
	_expect(not Combat.snapshot({"damage": 100.0}, []).has("weapon_profile"), "Legacy snapshot gets no local field by default")
	var old: Dictionary = Compiler.compile_skill("tornado", _snapshot(false), [])
	for role: String in old.packets:
		_expect(not old.packets[role].assembly.has("weapon") and old.packets[role].assembly.size() == 5, "Legacy frozen trace has no new key " + role)


func _test_profile_rejections() -> void:
	var invalid: Array = [null, [], "profile", 1, true, {"stage": "weapon_local"}]
	for key: String in _profile():
		var missing: Dictionary = _profile()
		missing.erase(key)
		invalid.append(missing)
	for pair: Array in [["stage", "hit_base"], ["stage", 2], ["base_id", "cinder_reed"], ["base_id", "unknown"],
		["item_id", "gear_1"], ["item_id", "gear_000000"], ["item_id", "gear_1000000000"], ["item_id", 123],
		["base", {"physical": float(Weapon.BASE_PHYSICAL_BY_ID.ashwood_bow) + 1.0}], ["base", {}], ["flat", {"fire": 2.0}], ["increased", {"physical": 0.2, "fire": 0.0}],
		["flat", {"physical": NAN}], ["increased", {"physical": INF}], ["flat", {"physical": -1.0}],
		["flat", {"physical": "2"}], ["flat", {&"physical": 2.0}], ["base", {"physical": true}], ["sources", {}], ["sources", [null]],
		["flat", {"physical": 3.0}], ["increased", {"physical": 0.200000001}], ["sources", []]]:
		var malformed: Dictionary = _profile()
		malformed[pair[0]] = pair[1]
		invalid.append(malformed)
	var unknown: Dictionary = _profile()
	unknown.quality = 0.2
	invalid.append(unknown)
	var duplicate: Dictionary = _profile()
	duplicate.sources.append(duplicate.sources[0].duplicate(true))
	duplicate.flat.physical = 4.0
	invalid.append(duplicate)
	for pair: Array in [["affix_id", "unknown"], ["stat", "attack_added_physical"], ["stat", "weapon_physical_increased"], ["value", -2.0], ["value", NAN], ["value", "2"], ["scope", "global"]]:
		var malformed: Dictionary = _profile()
		malformed.sources[0][pair[0]] = pair[1]
		invalid.append(malformed)
	var overflow: Dictionary = _profile(1e308, 1e308)
	invalid.append(overflow)
	for profile: Variant in invalid:
		var result: Dictionary = Weapon.resolve(profile)
		_expect(not result.ok and not result.reason.is_empty() and result.profile.is_empty() and result.components.is_empty(), "Malformed local profile fails with no partial result")
		var snapshot: Dictionary = _snapshot(false)
		snapshot.weapon_profile = profile
		for skill: String in ["tornado", "bolt", "dash", "ward"]:
			_expect(not Compiler.compile_skill(skill, snapshot, []).ok, "Malformed profile rejected even for spell/utility " + skill)
		_expect(Combat.event_packet(snapshot, "basic", "projectile").is_empty(), "Malformed direct basic fails closed")
		_expect(Combat.secondary_packet(snapshot, "basic").is_empty(), "Malformed direct secondary fails rather than hiding profile corruption")
		_expect(Base.assemble(100.0, _recipe(), {}, [], profile).is_empty(), "Malformed direct assembly fails closed")
	var empty: Dictionary = _snapshot(false)
	empty.weapon_profile = {}
	for skill: String in ["tornado", "bolt", "dash", "ward"]:
		_expect(not Compiler.compile_skill(skill, empty, []).ok, "Present empty profile is corruption in snapshot " + skill)
	_expect(Combat.event_packet(empty, "basic", "projectile").is_empty() and Combat.secondary_packet(empty, "basic").is_empty(), "Direct snapshot distinguishes empty profile from absent field")
	var huge: Dictionary = _profile(1e308, 0.0)
	_expect(Weapon.resolve(huge).ok and Base.assemble(0.0, _recipe(), {}, [], huge).is_empty(), "Finite local result rejects coefficient overflow")
	var merged: Dictionary = _recipe()
	merged.base_coefficient = 1.0
	_expect(Base.assemble(1e308, merged, {"attack": {"physical": 1e308}}, [], huge).is_empty(), "Overflow while adding stages rejects packet")


func _test_frozen_packet_rejections() -> void:
	var original: Dictionary = Compiler.compile_skill("tornado", _snapshot(), []).packets.parent
	for field: String in ["profile", "components", "coefficient", "contribution"]:
		var packet: Dictionary = original.duplicate(true)
		packet.assembly.weapon.erase(field)
		_expect(not Base.packet_error(packet).is_empty(), "Missing frozen local field rejected " + field)
	for pair: Array in [["profile", {}], ["profile", null], ["components", {"physical": sample_weapon_points + 0.1}],
		["components", {"physical": sample_weapon_points, "fire": 0.0}], ["contribution", {"physical": sample_weapon_points + 0.1}],
		["coefficient", 0.5], ["coefficient", NAN], ["conversion", true]]:
		var packet: Dictionary = original.duplicate(true)
		packet.assembly.weapon[pair[0]] = pair[1]
		_expect(not Base.packet_error(packet).is_empty(), "Unknown/tampered frozen local metadata rejected " + str(pair[0]))
	var source: Dictionary = original.duplicate(true)
	source.assembly.weapon.profile.sources[0].value += 1.0
	_expect(not Base.packet_error(source).is_empty(), "Frozen source provenance must match totals")
	var base: Dictionary = original.duplicate(true)
	base.base.physical += 1.0
	_expect(not Base.packet_error(base).is_empty(), "Frozen raw packet must include exact checked contribution")
	var subtle: Dictionary = original.duplicate(true)
	subtle.base.physical += 0.000001
	_expect(not Base.packet_error(subtle).is_empty(), "Local packet sum validation rejects even small raw amount tampering")
	var unknown: Dictionary = original.duplicate(true)
	unknown.assembly.script = "unsupported"
	_expect(not Base.packet_error(unknown).is_empty(), "Optional trace allowance does not admit unknown assembly keys")
	for pair: Array in [["skill_id", "bolt"], ["skill_id", "unknown"], ["role", "direct"], ["role", "secondary"],
		["tags", ["hit", "spell", "projectile"]], ["tags", ["hit", "attack"]], ["tags", ["hit", "area", "secondary", "explosion"]]]:
		var packet: Dictionary = original.duplicate(true)
		packet[pair[0]] = pair[1]
		_expect(not Base.packet_error(packet).is_empty(), "Consumer allowlist rejects forged local branch " + str(pair[0]))
	for role: String in ["projectile", "secondary"]:
		var packet: Dictionary = Combat.event_packet(_snapshot(), "bolt", role)
		packet.assembly.weapon = original.assembly.weapon.duplicate(true)
		packet.base.physical = sample_weapon_points
		_expect(not Base.packet_error(packet).is_empty(), "Spell/secondary cannot carry a self-consistent local trace " + role)
	var frozen: Dictionary = Compiler.compile_skill("tornado", _snapshot(), []).snapshot
	frozen.compiled_packets.child.assembly.weapon.contribution.physical = 999.0
	_expect(Combat.event_packet(frozen, "tornado", "child").is_empty(), "Corrupt frozen child fails without raw input fallback")


func _test_detachment_and_consumers() -> void:
	var raw: Dictionary = _snapshot()
	var before: Dictionary = raw.duplicate(true)
	var cast: Dictionary = Compiler.compile_skill("tornado", raw, [])
	_expect(raw == before, "Compile preserves full input profile")
	cast.packets.parent.assembly.weapon.profile.sources[0].value = 999.0
	cast.packets.parent.assembly.weapon.components.physical = 999.0
	cast.snapshot.weapon_profile = {}
	cast.snapshot.base_damage = 999.0
	cast.snapshot.added_damage.attack.physical = 999.0
	var pulled: Dictionary = Combat.event_packet(cast.snapshot, "tornado", "parent")
	_near(pulled.base.physical, 70.0 + sample_weapon_points, "Frozen packets win over mutable input fields and top-level preview packet")
	pulled.assembly.weapon.profile.flat.physical = 999.0
	_near(cast.snapshot.compiled_packets.parent.assembly.weapon.profile.flat.physical, 2.0, "Frozen getter owns detached nested profile")
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(before))
	_expect(Compiler.compile_skill("tornado", serialized, []).ok, "JSON roundtrip local profile compiles")
	for compiled_mode: bool in [false, true]:
		var snapshot: Dictionary = _snapshot()
		if compiled_mode:
			snapshot = Compiler.compile_skill("tornado", snapshot, []).snapshot
		var runtime = Runtime.new()
		var shots: Array[Dictionary] = []
		_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, snapshot, 100, 1) == 1, "Runtime admits local weapon mother")
		_near(shots[0].payload.base.physical, 70.0 + sample_weapon_points, "Runtime mother uses local stage")
		snapshot.weapon_profile.sources[0].value = 999.0
		snapshot.weapon_profile.flat.physical = 999.0
		if compiled_mode:
			snapshot.compiled_packets.child.assembly.weapon.components.physical = 999.0
		var events: Array[Dictionary] = runtime.advance(shots, 0.4, [], Vector2.ZERO, 100)
		_expect(shots.size() == 3, "Local mother splits after outside snapshot mutation")
		for child: Dictionary in shots:
			_near(child.payload.base.physical, 49.0 + sample_weapon_points * 0.7, "Descendant inherits original W and child coefficient")
			_near(child.payload.base.fire, 42.0, "Descendant has no local fire leakage")
			_near(child.payload.assembly.weapon.profile.sources[0].value, 2.0, "Descendant freezes raw affix provenance")
		events = runtime.advance(shots, 0.7, [], Vector2.ZERO, 100)
		for child: Dictionary in shots:
			_expect(child.state == "returning", "Child uses actual return lifecycle")
			_near(child.payload.base.physical, 49.0 + sample_weapon_points * 0.7, "Return retains original local weapon hit")
		events = runtime.advance(shots, 2.0, [], Vector2.ZERO, 100)
		var blasts: int = 0
		for event: Dictionary in events:
			if event.type == "explosion":
				blasts += 1
				_expect(event.payload.base == {"fire": 90.0} and not event.payload.assembly.has("weapon"), "Real secondary consumer excludes local weapon")
		_expect(blasts == 3 and shots.is_empty(), "All local child lineages finish with independent secondary")
	var snapshot: Dictionary = _snapshot()
	var runtime = Runtime.new()
	var payload: Dictionary = Combat.event_packet(snapshot, "basic", "projectile")
	var shot: Dictionary = runtime.make_projectile(Vector2.ZERO, Vector2.RIGHT,
		{"speed": 100.0, "range": 10.0, "lifetime": 1.0, "pierce": -1}, payload, snapshot, 1, Color.WHITE)
	snapshot.weapon_profile = _profile(0.0, 0.0)
	payload.assembly.weapon.profile.flat.physical = 99.0
	_near(shot.payload.base.physical, 110.0 + sample_weapon_points, "Basic projectile owns original local payload")
	_near(shot.snapshot.weapon_profile.flat.physical, 2.0, "Basic secondary snapshot owns original local profile")
	var bad: Dictionary = _snapshot()
	bad.weapon_profile.sources[0].stat = "attack_added_physical"
	var shots: Array[Dictionary] = []
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, bad, 100, 1) == 0 and shots.is_empty(), "Malformed local profile rejects before projectile admission")


func _test_preview() -> void:
	var cast: Dictionary = Compiler.compile_skill("tornado", _snapshot(), [])
	var before: Dictionary = cast.duplicate(true)
	var line: String = Preview.assembly_line(cast.packets.parent)
	_expect(line.contains("固有：物理 60.00 + 火焰 40.00") and line.contains("附加：物理 10.00 + 火焰 20.00"), "Preview keeps B and external addition separate")
	_expect(line.contains("武器：物理 %.2f" % sample_weapon_points) and line.contains("(%.2f + 2.00) × (1 + 0.20) × 技能倍率 1.00" % float(Weapon.BASE_PHYSICAL_BY_ID.ashwood_bow)), "Preview exposes physical W contribution and original formula")
	_expect(Preview.details(cast).contains(line) and Preview.summary(cast).contains("母箭 %.2f" % (130.0 + sample_weapon_points)), "Existing detail and summary consumers display actual local packet")
	_expect(cast == before, "Preview formatting does not mutate frozen local provenance")
