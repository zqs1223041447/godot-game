extends SceneTree
## Typed base assembly contracts. No scene, inventory or user save dependencies.
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Data = preload("res://scripts/game_data.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_typed_points()
	_test_independent_stages()
	_test_scopes_and_supports()
	_test_zero_compatibility()
	_test_sources_and_freezing()
	_test_runtime()
	_test_invalid()
	print("Typed damage base: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00001, "%s (%.8f vs %.8f)" % [label, value, expected])


func _snapshot() -> Dictionary:
	return Combat.snapshot({"damage": 100.0, "attack_added_physical": 10.0, "attack_added_fire": 20.0,
		"spell_added_cold": 30.0, "spell_added_lightning": 40.0}, ["explode_on_flight_end"])


func _source(stat: String, scope: String, type: String, value: float) -> Dictionary:
	return {"item_id": "item-1", "affix_id": "affix-" + stat, "stat": stat,
		"scope": scope, "damage_type": type, "value": value}


func _recipe() -> Dictionary:
	return {"stage": "hit_base", "intrinsic_distribution": {"physical": 0.6, "fire": 0.4},
		"base_coefficient": 1.0, "added_effectiveness": 1.0, "tags": ["hit", "attack", "projectile"],
		"skill_id": "tornado", "role": "parent"}


func _points(packet: Dictionary, expected: Dictionary, label: String) -> void:
	_expect(not packet.is_empty(), label + " assembles")
	if packet.is_empty():
		return
	_expect(Base.packet_error(packet).is_empty(), label + " has valid frozen trace")
	for type: String in Damage.TYPES:
		_near(float(packet.base.get(type, 0.0)), float(expected.get(type, 0.0)), label + " " + type)


func _test_typed_points() -> void:
	var snapshot: Dictionary = _snapshot()
	_points(Combat.event_packet(snapshot, "basic", "projectile"), {"physical": 110.0, "fire": 20.0}, "Basic")
	_points(Combat.tornado_packet(snapshot, "parent"), {"physical": 70.0, "fire": 60.0}, "Tornado parent")
	_points(Combat.tornado_packet(snapshot, "child"), {"physical": 49.0, "fire": 42.0}, "Tornado child")
	_points(Combat.event_packet(snapshot, "bolt", "projectile"), {"cold": 48.0, "lightning": 224.0}, "Bolt")
	_points(Combat.event_packet(snapshot, "frost", "projectile"), {"cold": 110.5, "lightning": 34.0}, "Frost")
	_points(Combat.event_packet(snapshot, "nova"), {"cold": 81.0, "lightning": 378.0}, "Nova")
	_points(Combat.event_packet(snapshot, "meteor"), {"fire": 430.0, "cold": 129.0, "lightning": 172.0}, "Meteor")
	for index: int in range(5):
		var coefficient: float = 2.2 - 0.2 * index
		_points(Combat.event_packet(snapshot, "chain", "direct", index),
			{"cold": 30.0 * coefficient, "lightning": 140.0 * coefficient}, "Chain bounce %d" % index)
	for id: String in ["basic", "tornado", "bolt", "frost"]:
		var secondary: Dictionary = Combat.secondary_packet(snapshot, id)
		_points(secondary, {"fire": 90.0}, id + " secondary")
		_expect(secondary.skill_id == id and secondary.role == "secondary", "Secondary preserves carrier skill provenance " + id)
		_expect(secondary.tags == ["hit", "area", "secondary", "explosion"] and secondary.assembly.added.is_empty(), "Secondary has no attack/spell inheritance " + id)
	_expect(not Compiler.compile_skill("basic", snapshot, []).ok, "Basic packet availability does not create supportability")
	for id: String in ["dash", "ward"]:
		var result: Dictionary = Compiler.compile_skill(id, snapshot, [])
		_expect(result.ok and result.packets.is_empty() and result.snapshot.compiled_packets.is_empty(), "Nondamage skill compiles no packet " + id)


func _test_independent_stages() -> void:
	var recipe: Dictionary = _recipe()
	recipe.base_coefficient = 2.0
	recipe.added_effectiveness = 0.5
	var packet: Dictionary = Base.assemble(100.0, recipe, _snapshot().added_damage)
	_points(packet, {"physical": 125.0, "fire": 90.0}, "Independent coefficient and effectiveness")
	_points(Base.assemble(0.0, recipe, _snapshot().added_damage), {"physical": 5.0, "fire": 10.0}, "Zero intrinsic still allows fixed added points")
	_near(packet.assembly.intrinsic.physical, 120.0, "Trace separates intrinsic points")
	_near(packet.assembly.added.physical, 5.0, "Added physical is not redistributed")
	_near(packet.assembly.added.fire, 10.0, "Added fire uses effectiveness, not base coefficient")
	var snapshot: Dictionary = _snapshot()
	snapshot.tornado_recipe.child.coefficient = 0.25
	snapshot.tornado_recipe.child.added_effectiveness = 2.0
	_points(Compiler.compile_skill("tornado", snapshot, []).packets.child,
		{"physical": 35.0, "fire": 50.0}, "Authored independent child fields reach compilation")


func _test_scopes_and_supports() -> void:
	var snapshot: Dictionary = _snapshot()
	snapshot.modifiers = Combat.modifiers({"global_increased": 0.2, "projectile_increased": 0.5,
		"elemental_increased": 0.3, "spell_increased": 0.4, "attack_elemental_increased": 0.6, "area_increased": 0.7})
	var parent: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
	var resolved: Dictionary = Damage.resolve(parent.packets.parent, parent.snapshot.modifiers)
	_near(resolved.components.physical, 70.0 * 1.7, "Physical increased applies after assembled base")
	_near(resolved.components.fire, 60.0 * 2.6, "Elemental attack increased applies to complete fire component")
	_near(Damage.resolve(parent.packets.secondary, parent.snapshot.modifiers).total, 90.0 * 2.2, "Secondary matches only global elemental and area increases")
	for id: String in ["tornado", "bolt", "frost"]:
		var baseline: Dictionary = Compiler.compile_skill(id, snapshot, [])
		var volley: Dictionary = Compiler.compile_skill(id, snapshot, ["volley"])
		var focus: Dictionary = Compiler.compile_skill(id, snapshot, ["focus"])
		var both: Dictionary = Compiler.compile_skill(id, snapshot, ["focus", "volley"])
		var roles: Array = ["parent", "child"] if id == "tornado" else ["projectile"]
		for role: String in roles:
			_expect(volley.packets[role] == baseline.packets[role], "Support keeps raw assembly stable " + id + role)
			var raw: Dictionary = Damage.resolve(baseline.packets[role], baseline.snapshot.modifiers)
			for entry: Dictionary in [{"compiled": volley, "factor": 0.8}, {"compiled": focus, "factor": 1.25}, {"compiled": both, "factor": 1.0}]:
				var scaled: Dictionary = Damage.resolve(entry.compiled.packets[role], entry.compiled.snapshot.modifiers)
				for type: String in raw.components:
					_near(scaled.components[type], raw.components[type] * float(entry.factor), "Support scales intrinsic plus added " + id + role + type)
		for compiled: Dictionary in [volley, focus, both]:
			_near(Damage.resolve(compiled.packets.secondary, compiled.snapshot.modifiers).total,
				Damage.resolve(baseline.packets.secondary, baseline.snapshot.modifiers).total, "Support never scales carrier secondary " + id)
	var bolt: Dictionary = Compiler.compile_skill("bolt", snapshot, [])
	var first: Dictionary = Damage.resolve(bolt.packets.projectile, bolt.snapshot.modifiers, {"lightning": 0.5})
	var second: Dictionary = Damage.resolve(bolt.packets.projectile, bolt.snapshot.modifiers, {"lightning": 0.0})
	_near(first.components.lightning * 2.0, second.components.lightning, "Mitigation remains live after cast-time packet freeze")


func _test_zero_compatibility() -> void:
	var empty: Dictionary = Combat.snapshot({"damage": 100.0}, [])
	_expect(empty.added_damage == {"attack": {"physical": 0.0, "fire": 0.0}, "spell": {"cold": 0.0, "lightning": 0.0}}, "New stat defaults are detached explicit zeros")
	var expected: Dictionary = {"tornado": {"parent": {"physical": 60.0, "fire": 40.0}, "child": {"physical": 42.0, "fire": 28.0}, "secondary": {"fire": 90.0}},
		"bolt": {"projectile": {"lightning": 160.0}, "secondary": {"fire": 90.0}},
		"frost": {"projectile": {"cold": 85.0}, "secondary": {"fire": 90.0}},
		"nova": {"direct": {"lightning": 270.0}}, "meteor": {"direct": {"fire": 430.0}}}
	for id: String in expected:
		var compiled: Dictionary = Compiler.compile_skill(id, empty, [])
		_expect(compiled.ok, "Zero additions compile " + id)
		for role: String in expected[id]:
			_points(compiled.packets[role], expected[id][role], "Frozen v0.6 " + id + role)
	var chain: Dictionary = Compiler.compile_skill("chain", empty, [])
	for index: int in range(5):
		_near(chain.packets.bounces[index].base.lightning, 100.0 * (2.2 - index * 0.2), "Zero-addition chain preserves v0.6 bounce")
	_points(Combat.event_packet(empty, "basic", "projectile"), {"physical": 100.0}, "Frozen v0.6 basic")
	var legacy: Dictionary = Combat.snapshot({"damage": 118.0}, [])
	_points(Combat.event_packet(legacy, "meteor"), {"fire": 118.0 * 4.3}, "Legacy damage+ remains shared intrinsic base")


func _test_sources_and_freezing() -> void:
	var sources: Array = [_source("attack_added_physical", "attack", "physical", 10.0),
		_source("spell_added_cold", "spell", "cold", 30.0)]
	var stats: Dictionary = {"damage": 100.0, "attack_added_physical": 10.0, "spell_added_cold": 30.0, "added_damage_sources": sources}
	var snapshot: Dictionary = Combat.snapshot(stats, [])
	sources[0].value = 999.0
	_expect(snapshot.added_damage_sources[0].value == 10.0, "Snapshot owns nested provenance")
	var first: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
	var second: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
	_expect(first.packets.parent.assembly.added_damage_sources.size() == 1 and first.packets.parent.assembly.added_damage_sources[0].scope == "attack", "Attack trace filters spell item sources")
	_expect(not first.packets.secondary.assembly.has("added_damage_sources"), "Secondary trace has no inherited sources")
	var spell: Dictionary = Compiler.compile_skill("bolt", snapshot, [])
	_expect(spell.packets.projectile.assembly.added_damage_sources.size() == 1 and spell.packets.projectile.assembly.added_damage_sources[0].scope == "spell", "Spell trace filters attack item sources")
	first.packets.parent.base.physical = 999.0
	first.packets.parent.assembly.added_damage_sources[0].value = 999.0
	_near(first.snapshot.compiled_packets.parent.base.physical, 70.0, "Top-level packet does not alias frozen snapshot packet")
	_near(second.packets.parent.assembly.added_damage_sources[0].value, 10.0, "Separate compile provenance is detached")
	first.snapshot.base_damage = 999.0
	first.snapshot.added_damage.attack.physical = 999.0
	first.snapshot.tornado_recipe.child.coefficient = 999.0
	_points(Combat.event_packet(first.snapshot, "tornado", "child"), {"physical": 49.0, "fire": 28.0}, "Frozen child wins over changed assembly inputs")
	var pulled: Dictionary = Combat.event_packet(second.snapshot, "tornado", "parent")
	pulled.base.physical = 999.0
	_near(second.snapshot.compiled_packets.parent.base.physical, 70.0, "Frozen getter returns a detached packet")
	var chain: Dictionary = Compiler.compile_skill("chain", _snapshot(), [])
	chain.packets.bounces[0].base.cold = 999.0
	_near(chain.snapshot.compiled_packets.bounces[0].base.cold, 66.0, "Nested chain arrays are detached")
	for id: String in Data.SKILLS:
		var compiled: Dictionary = Compiler.compile_skill(id, _snapshot(), [])
		_expect(compiled.snapshot.compiled_skill_id == id, "Frozen packet set marks source skill " + id)
		_expect(not Compiler.compile_skill(id, compiled.snapshot, []).ok, "All compiled snapshots reject re-entry " + id)
		for removed: String in ["compiled_packets", "compiled_skill_id"]:
			var stripped: Dictionary = compiled.snapshot.duplicate(true)
			stripped.erase("initial_count")
			stripped.erase(removed)
			_expect(not Compiler.compile_skill(id, stripped, []).ok, "Either compilation marker rejects re-entry " + id)


func _test_runtime() -> void:
	for compiled_mode: bool in [false, true]:
		var snapshot: Dictionary = _snapshot()
		if compiled_mode:
			snapshot = Compiler.compile_skill("tornado", snapshot, ["focus"]).snapshot
		var runtime = Runtime.new()
		var shots: Array[Dictionary] = []
		_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, snapshot, 100, 1) == 1, "Runtime admits typed tornado")
		snapshot.base_damage = 999.0
		snapshot.added_damage.attack.physical = 999.0
		if compiled_mode:
			snapshot.compiled_packets.child.base.physical = 999.0
		var events: Array[Dictionary] = runtime.advance(shots, 0.4, [], Vector2.ZERO, 100)
		_expect(shots.size() == 3, "Typed tornado splits into three children")
		for child: Dictionary in shots:
			_points(child.payload, {"physical": 49.0, "fire": 42.0}, "Runtime frozen child")
			snapshot = child.snapshot
		events = runtime.advance(shots, 2.0, [], Vector2.ZERO, 100)
		var blasts: int = 0
		for event: Dictionary in events:
			if event.type == "explosion":
				blasts += 1
				_points(event.payload, {"fire": 90.0}, "Runtime typed secondary")
		_expect(blasts == 3 and shots.is_empty(), "Every natural child end emits one typed secondary")
	for id: String in ["basic", "bolt", "frost"]:
		var runtime = Runtime.new()
		var snapshot: Dictionary = _snapshot() if id == "basic" else Compiler.compile_skill(id, _snapshot(), ["focus"]).snapshot
		var shot: Dictionary = runtime.make_projectile(Vector2.ZERO, Vector2.RIGHT,
			{"speed": 100.0, "range": 5.0, "lifetime": 1.0}, Combat.event_packet(snapshot, id, "projectile"), snapshot, runtime.new_cast(), Color.WHITE)
		var shots: Array[Dictionary] = [shot]
		var events: Array[Dictionary] = runtime.advance(shots, 0.1, [], Vector2.ZERO, 100)
		var blasts: int = 0
		for event: Dictionary in events:
			if event.type == "explosion":
				blasts += 1
				_points(event.payload, {"fire": 90.0}, "Spell/basic carried secondary " + id)
				_expect(event.payload.skill_id == id, "Runtime preserves secondary source " + id)
		_expect(blasts == 1, "Natural end emits exactly one secondary " + id)


func _test_invalid() -> void:
	for base: Variant in [-1.0, NAN, INF, "100", null]:
		_expect(Base.assemble(base, _recipe(), _snapshot().added_damage).is_empty(), "Invalid base has no partial packet")
	for pair: Array in [["stage", "weapon_local"], ["stage", "conversion"], ["base_coefficient", -1.0], ["base_coefficient", NAN],
		["added_effectiveness", -1.0], ["added_effectiveness", INF], ["intrinsic_distribution", {"void": 1.0}],
		["intrinsic_distribution", {"physical": 0.6}], ["intrinsic_distribution", {"physical": -1.0, "fire": 2.0}],
		["tags", ["attack", "projectile"]], ["tags", ["hit", "attack", "spell"]], ["tags", ["hit", "spell", "dot"]],
		["tags", ["hit", "hit", "attack"]], ["tags", "attack"], ["role", "unknown"], ["skill_id", ""]]:
		var recipe: Dictionary = _recipe()
		recipe[pair[0]] = pair[1]
		_expect(Base.assemble(100.0, recipe, _snapshot().added_damage).is_empty(), "Malformed stage recipe fails closed " + str(pair[0]))
	for invalid: Variant in [null, [], {"weapon": {"physical": 10.0}}, {"attack": {"void": 10.0}},
		{"spell": {"cold": -1.0}}, {"attack": {"physical": NAN}}, {"attack": {"physical": "10"}}, {"attack": []}]:
		_expect(Base.assemble(100.0, _recipe(), invalid).is_empty(), "Malformed addition rejects packet")
		var snapshot: Dictionary = _snapshot()
		snapshot.added_damage = invalid
		var compiled: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
		_expect(not compiled.ok and compiled.size() == 2, "Malformed addition rejects whole compile")
	var source: Dictionary = _source("attack_added_physical", "attack", "physical", 10.0)
	for pair: Array in [["scope", "spell"], ["damage_type", "fire"], ["stat", "damage"], ["value", -1.0], ["value", NAN], ["item_id", null]]:
		var bad: Dictionary = source.duplicate(true)
		bad[pair[0]] = pair[1]
		_expect(Base.assemble(100.0, _recipe(), {}, [bad]).is_empty(), "Malformed provenance rejected")
	var bad_source: Dictionary = source.duplicate(true)
	bad_source.stage = "weapon_local"
	_expect(Base.assemble(100.0, _recipe(), {}, [bad_source]).is_empty(), "Unknown provenance stage is rejected")
	for id: String in ["unknown", "dash", "ward"]:
		_expect(Combat.event_packet(_snapshot(), id).is_empty(), "No invented damage event for " + id)
	for role: String in ["unknown", "parent", "direct"]:
		_expect(Combat.event_packet(_snapshot(), "bolt", role).is_empty(), "Wrong role cannot assemble spell projectile")
	for index: int in [-1, 5, 100]:
		_expect(Combat.event_packet(_snapshot(), "chain", "direct", index).is_empty(), "Out-of-range chain index fails closed")
	_expect(Combat.event_packet(_snapshot(), "tornado", "child", 1).is_empty(), "Nonchain index is invalid")
	var malformed: Dictionary = _snapshot()
	malformed.explosion_recipe.added_effectiveness = 1.0
	_expect(Combat.secondary_packet(malformed, "frost").is_empty(), "Carrier secondary cannot gain spell effectiveness")
	_expect(not Compiler.compile_skill("frost", malformed, []).ok, "Invalid secondary rejects whole spell compile")
	for key: String in ["base_coefficient", "added_effectiveness"]:
		var spec: Dictionary = Data.SKILLS.nova.hit_recipe.duplicate(true)
		spec[key] = NAN
		_expect(not Compiler._hit_recipe_error(spec, false).is_empty(), "Malformed direct coefficient rejected")
	var chain: Dictionary = Data.SKILLS.chain.hit_recipe.duplicate(true)
	chain.added_effectiveness_loss_per_bounce = 2.0
	_expect(not Compiler._hit_recipe_error(chain, true).is_empty(), "Negative final chain effectiveness rejected")
	for pair: Array in [["all_tags", ["unknown"]], ["damage_types", ["void"]], ["skills", ["unknown"]], ["stage", "weapon_local"]]:
		var snapshot: Dictionary = _snapshot()
		var modifier: Dictionary = {"id": "bad", "mode": "increased", "value": 0.2}
		modifier[pair[0]] = pair[1]
		snapshot.modifiers.append(modifier)
		_expect(not Compiler.compile_skill("tornado", snapshot, []).ok, "Unknown modifier scope rejects compilation")
	var compiled: Dictionary = Compiler.compile_skill("bolt", _snapshot(), [])
	_expect(Combat.event_packet(compiled.snapshot, "frost", "projectile").is_empty(), "Compiled source skill cannot be relabeled")
	for field: String in ["compiled_packets", "compiled_skill_id"]:
		var damaged: Dictionary = compiled.snapshot.duplicate(true)
		damaged.erase(field)
		_expect(Combat.event_packet(damaged, "bolt", "projectile").is_empty(), "Incomplete frozen packet set cannot fall back to reconstruction")
	var corrupted: Dictionary = compiled.snapshot.duplicate(true)
	corrupted.compiled_packets.projectile.base.lightning = -1.0
	_expect(Combat.event_packet(corrupted, "bolt", "projectile").is_empty(), "Malformed frozen points cannot fall back")
	corrupted = compiled.snapshot.duplicate(true)
	corrupted.compiled_packets.projectile.assembly.stage = "conversion"
	_expect(Combat.event_packet(corrupted, "bolt", "projectile").is_empty(), "Unknown frozen stage cannot fall back")
	corrupted = compiled.snapshot.duplicate(true)
	corrupted.compiled_packets.secondary.tags.append("spell")
	_expect(Combat.secondary_packet(corrupted, "bolt").is_empty(), "Frozen secondary cannot be retagged as spell")
