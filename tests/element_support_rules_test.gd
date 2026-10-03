extends SceneTree
## Real hit assembly/resolution, fixed native eligibility and pure program contracts.
const Rules = preload("res://scripts/combat/element_support_rules.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Data = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
const EXPECTED: Dictionary = {
	"physical_focus": ["物理专注辅助", "physical", ["tornado"]],
	"fire_focus": ["火焰专注辅助", "fire", ["tornado", "meteor"]],
	"cold_focus": ["冰霜专注辅助", "cold", ["frost"]],
	"lightning_focus": ["闪电专注辅助", "lightning", ["bolt", "nova", "chain"]],
}
var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(619204)
	randi()
	var expected_global: Array = [randi(), randi(), randi()]
	seed(619204)
	randi()
	var custom: RandomNumberGenerator = RandomNumberGenerator.new()
	custom.seed = 619205
	custom.randi()
	var custom_before: int = custom.state
	var catalog_before: PackedByteArray = var_to_bytes([Data.SKILLS, Combat.TORNADO, Rules.SUPPORTS, Program.PRIMARY_TAGS, Damage.TYPES])
	_case(_test_metadata, "metadata and corruption")
	_case(_test_selection, "native whitelist and atomic rejection")
	_case(_test_numbers, "known typed multiplication and weapon points")
	_case(_test_real_packets, "all native primary packet roles and added components")
	_case(_test_boundaries, "secondary, basic and other skill boundaries")
	_case(_test_detachment, "determinism and detached inputs/results")
	_expect(custom.state == custom_before, "Compilation and validation preserve custom RNG state")
	_expect([randi(), randi(), randi()] == expected_global, "Compilation, validation and packet resolution preserve global RNG")
	_expect(catalog_before == var_to_bytes([Data.SKILLS, Combat.TORNADO, Rules.SUPPORTS, Program.PRIMARY_TAGS, Damage.TYPES]), "No authoritative catalog or primary tags change")
	print("Element support rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	completed = false
	test.call()
	_expect(completed, "Case completes without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00001, "%s (actual %.8f, expected %.8f)" % [label, value, expected])


func _snapshot() -> Dictionary:
	var result: Dictionary = Combat.snapshot({"damage": 100.0, "attack_added_physical": 10.0,
		"attack_added_fire": 20.0, "spell_added_cold": 30.0, "spell_added_lightning": 40.0},
		["return_on_range", "explode_on_flight_end"])
	# Exercise every resolver component through genuine hit assembly, including chaos.
	result.added_damage.attack.merge({"cold": 3.0, "lightning": 5.0, "chaos": 7.0})
	result.added_damage.spell.merge({"physical": 3.0, "fire": 5.0, "chaos": 7.0})
	result.weapon_profile = {"stage": "weapon_local", "item_id": "gear_000123", "base_id": "ashwood_bow",
		"base": {"physical": Weapon.BASE_PHYSICAL_BY_ID.ashwood_bow}, "flat": {"physical": 2.0},
		"increased": {"physical": 0.2}, "sources": [
			{"affix_id": "whetstone_edge", "stat": "weapon_added_physical", "value": 2.0},
			{"affix_id": "tempered_edge", "stat": "weapon_physical_increased", "value": 0.2}]}
	return result


func _packet(skill: String, snapshot: Dictionary) -> Dictionary:
	var role: String = "parent" if skill == "tornado" else ("projectile" if skill in ["basic", "bolt", "frost"] else "direct")
	return Combat.event_packet(snapshot, skill, role)


func _test_metadata() -> void:
	_expect(Rules.SUPPORTS.keys() == EXPECTED.keys(), "Exactly four stable specialization IDs")
	_expect(Rules.get_definition("unknown").is_empty(), "Unknown metadata returns an empty copy")
	for id: String in EXPECTED:
		var definition: Dictionary = Rules.get_definition(id)
		_expect(definition.size() == 6 and definition.has_all(["name", "description", "skills", "requires", "operations", "family"]), "Exact six-field metadata contract: " + id)
		_expect(Rules.definition_error(definition).is_empty() and definition.name == EXPECTED[id][0], "Authored metadata and translated name: " + id)
		_expect(definition.family == "element" and definition.requires == [] and definition.skills == EXPECTED[id][2], "Native skill eligibility is the authority: " + id)
		_expect(definition.operations == [{"op": "primary_component_more", "damage_type": EXPECTED[id][1], "value": 0.20},
			{"op": "other_components_more", "damage_type": EXPECTED[id][1], "value": -0.20},
			{"op": "mana_multiplier", "value": 1.15}], "Exact authored operation balance: " + id)
		var serialized: Dictionary = JSON.parse_string(JSON.stringify(definition))
		_expect(Rules.definition_error(serialized).is_empty(), "JSON round trip preserves valid metadata: " + id)
		definition.operations.reverse()
		_expect(Rules.definition_error(definition).is_empty(), "Validation does not depend on operation order")
	for invalid: Variant in [null, false, 1, 1.5, "physical_focus", [], {}]:
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject non-metadata variant")
	for field: String in ["name", "description", "skills", "requires", "operations", "family"]:
		var missing: Dictionary = Rules.get_definition("physical_focus")
		missing.erase(field)
		_expect(not Rules.definition_error(missing).is_empty(), "Reject missing metadata " + field)
	for change: Array in [["name", ""], ["name", false], ["description", 12], ["description", ""],
		["family", "projectile"], ["family", true], ["requires", ["projectile_hit"]], ["requires", null],
		["skills", ["tornado", "tornado"]], ["skills", ["bolt"]], ["skills", []], ["skills", [false]],
		["skills", ["tornado", "meteor"]], ["operations", []], ["operations", {}], ["extra", true]]:
		var invalid: Dictionary = Rules.get_definition("physical_focus")
		invalid[change[0]] = change[1]
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject corrupted metadata " + str(change))
	for operation: Variant in [null, true, [], {}, {"op": "unknown", "value": 0.2},
		{"op": "mana_multiplier", "value": 1.15}, {"op": "primary_component_more", "value": 0.2},
		{"op": "primary_component_more", "damage_type": "chaos", "value": 0.2},
		{"op": "primary_component_more", "damage_type": "fire", "value": 0.2},
		{"op": "primary_component_more", "damage_type": true, "value": 0.2},
		{"op": "primary_component_more", "damage_type": ["physical"], "value": 0.2},
		{"op": "primary_component_more", "damage_type": "physical", "value": 0.2, "extra": true}]:
		var invalid: Dictionary = Rules.get_definition("physical_focus")
		invalid.operations[0] = operation
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject malformed, duplicate or mismatched operation")
	for index: int in range(3):
		for bad: Variant in [null, true, false, "0.2", {}, [], NAN, INF, -INF, -1.0, 0.0, 10.0]:
			var invalid: Dictionary = Rules.get_definition("physical_focus")
			invalid.operations[index].value = bad
			_expect(not Rules.definition_error(invalid).is_empty(), "Reject nonfinite, bool, mistyped or unauthored value")
	var invalid_mana: Dictionary = Rules.get_definition("physical_focus")
	invalid_mana.operations[2].damage_type = "physical"
	_expect(not Rules.definition_error(invalid_mana).is_empty(), "Mana operation has exactly two fields")
	completed = true


func _rejected(skill: Variant, ids: Variant) -> void:
	var before: PackedByteArray = var_to_bytes([skill, ids])
	var result: Dictionary = Rules.compile_program(skill, ids)
	_expect(result.size() == 5 and result.has_all(["error", "modifiers", "mana_multiplier", "cooldown_multiplier", "recipe_factors"]), "Failure keeps shared envelope")
	_expect(result.error is String and not result.error.is_empty(), "Invalid selection has a reason")
	var effects: Dictionary = result.duplicate(true)
	effects.error = ""
	_expect(effects == Program.empty(), "Rejected selection exposes no partial effects")
	_expect(before == var_to_bytes([skill, ids]), "Rejection preserves caller-owned values")


func _test_selection() -> void:
	for skill: String in Data.SKILLS:
		_expect(Rules.compile_program(skill, []) == Program.empty(), "Empty selection is a pure no-op: " + skill)
		for id: String in EXPECTED:
			if EXPECTED[id][2].has(skill):
				var result: Dictionary = Rules.compile_program(skill, [id])
				_expect(result.error.is_empty() and result.modifiers.size() == 2 and result.recipe_factors.is_empty(), "Whitelist admits only native support: " + skill + ":" + id)
				_near(result.mana_multiplier, 1.15, "One support multiplies mana once")
				_near(result.cooldown_multiplier, 1.0, "Specialization leaves cooldown unchanged")
			else:
				_rejected(skill, [id])
	for skill: Variant in [null, true, 1, [], {}, "", "unknown", "basic"]:
		_rejected(skill, ["physical_focus"])
	for ids: Variant in [null, true, 1, {}, "physical_focus", PackedStringArray(["physical_focus"]),
		[null], [false], [1], [[]], [""], ["unknown"], ["physical_focus", "unknown"],
		["unknown", "physical_focus"], ["physical_focus", "physical_focus"],
		["physical_focus", "fire_focus", "cold_focus"]]:
		_rejected("tornado", ids)
	# All five types are present after equipment-like additions. That never grants eligibility.
	var snapshot: Dictionary = _snapshot()
	for skill: String in Program.PRIMARY_TAGS:
		var packet: Dictionary = _packet(skill, snapshot)
		_expect(packet.base.size() == 5, "Real packet includes all added types: " + skill)
		for id: String in EXPECTED:
			_expect(Rules.compile_program(skill, [id]).error.is_empty() == EXPECTED[id][2].has(skill), "Added components cannot open another specialization: " + skill + ":" + id)
	completed = true


func _test_numbers() -> void:
	var plain: Dictionary = Combat.snapshot({"damage": 100.0}, [])
	var parent: Dictionary = Combat.tornado_packet(plain, "parent")
	var physical: Dictionary = Rules.compile_program("tornado", ["physical_focus"])
	var fire: Dictionary = Rules.compile_program("tornado", ["fire_focus"])
	var both: Dictionary = Rules.compile_program("tornado", ["physical_focus", "fire_focus"])
	_near(Damage.resolve(parent, physical.modifiers).total, 104.0, "60 physical * 1.2 + 40 fire * .8 = 104")
	_near(Damage.resolve(parent, fire.modifiers).total, 96.0, "60 physical * .8 + 40 fire * 1.2 = 96")
	_near(Damage.resolve(parent, both.modifiers).total, 96.0, "Two valid native specializations multiply to .96, not additive zero")
	_near(both.mana_multiplier, 1.3225, "Two specializations cost 1.15 squared")
	_expect(both.error.is_empty() and both.modifiers.size() == 4, "Compatible element family supports coexist")
	var snapshot: Dictionary = _snapshot()
	var expected_base: Dictionary = {"physical": 77.2, "fire": 60.0, "cold": 3.0, "lightning": 5.0, "chaos": 7.0}
	for role: String in ["parent", "child"]:
		var packet: Dictionary = Combat.tornado_packet(snapshot, role)
		var coefficient: float = 1.0 if role == "parent" else 0.7
		_expect(Base.packet_error(packet).is_empty(), "Weapon-backed tornado packet validates: " + role)
		_near(packet.assembly.weapon.components.physical, 7.2, "Local weapon resolves before specialization")
		for type: String in Damage.TYPES:
			_near(packet.base[type], expected_base[type] * coefficient, "Raw component includes correct added/weapon points: " + role + ":" + type)
			_near(Damage.resolve(packet, physical.modifiers).components[type], expected_base[type] * coefficient * (1.2 if type == "physical" else 0.8), "Physical support covers local weapon and all other types: " + role + ":" + type)
			_near(Damage.resolve(packet, both.modifiers).components[type], expected_base[type] * coefficient * (0.96 if type in ["physical", "fire"] else 0.64), "Two supports multiply per component exactly: " + role + ":" + type)
	completed = true


func _test_real_packets() -> void:
	var snapshot: Dictionary = _snapshot()
	var existing: Array = Combat.modifiers({"global_increased": 0.2, "projectile_increased": 0.3,
		"elemental_increased": 0.4, "spell_increased": 0.5})
	var mitigation: Dictionary = {"physical": 0.1, "fire": 0.2, "cold": 0.3, "lightning": 0.4, "chaos": -0.1}
	for id: String in EXPECTED:
		for skill: String in EXPECTED[id][2]:
			var program: Dictionary = Rules.compile_program(skill, [id])
			var packets: Array = [_packet(skill, snapshot)]
			if skill == "tornado":
				packets.append(Combat.tornado_packet(snapshot, "child"))
			elif skill == "chain":
				for index: int in range(1, int(Data.SKILLS.chain.hit_recipe.bounce_count)):
					packets.append(Combat.event_packet(snapshot, skill, "bounce", index))
			for packet: Dictionary in packets:
				_expect(Base.packet_error(packet).is_empty(), "Use real validated primary packet: " + skill)
				var before: Dictionary = Damage.resolve(packet, existing, mitigation)
				var with_support: Array = existing.duplicate(true)
				with_support.append_array(program.modifiers)
				var after: Dictionary = Damage.resolve(packet, with_support, mitigation)
				for type: String in Damage.TYPES:
					_near(after.components[type], before.components[type] * (1.2 if type == EXPECTED[id][1] else 0.8), "More applies once after additions/increased and before defenses: " + skill + ":" + type)
					var matched: int = 0
					for modifier: Dictionary in program.modifiers:
						matched += 1 if Damage.matches(modifier, packet, type) else 0
					_expect(matched == 1, "Exactly one side of each specialization matches a damage component")
	completed = true


func _test_boundaries() -> void:
	var snapshot: Dictionary = _snapshot()
	for id: String in EXPECTED:
		for skill: String in EXPECTED[id][2]:
			var program: Dictionary = Rules.compile_program(skill, [id])
			var unaffected: Array = [Combat.event_packet(snapshot, "basic", "projectile")]
			for secondary_skill: String in ["basic", "tornado", "bolt", "frost"]:
				unaffected.append(Combat.secondary_packet(snapshot, secondary_skill))
			for other_skill: String in Program.PRIMARY_TAGS:
				if other_skill != skill:
					unaffected.append(_packet(other_skill, snapshot))
			for packet: Dictionary in unaffected:
				_expect(Base.packet_error(packet).is_empty(), "Scope fixture is a real validated packet")
				_expect(Damage.resolve(packet, program.modifiers) == Damage.resolve(packet, []), "Other skills, basic and independent explosions are exactly unchanged")
	completed = true


func _test_detachment() -> void:
	var ids: Array = ["physical_focus", "fire_focus"]
	var before: Array = ids.duplicate()
	var first: Dictionary = Rules.compile_program("tornado", ids)
	var second: Dictionary = Rules.compile_program("tornado", ["fire_focus", "physical_focus"])
	_expect(first == second and ids == before, "Full program is independent of selection order and leaves input untouched")
	for modifier: Dictionary in first.modifiers:
		modifier.all_tags.clear()
		modifier.skills.clear()
		modifier.damage_types.clear()
	first.recipe_factors.extra = 99
	first.modifiers.clear()
	ids.clear()
	_expect(second == Rules.compile_program("tornado", before), "Compiled programs and nested scopes are detached")
	var definition: Dictionary = Rules.get_definition("physical_focus")
	definition.skills.clear()
	definition.requires.append("anything")
	definition.operations[0].value = 99.0
	_expect(Rules.get_definition("physical_focus").skills == ["tornado"] and Rules.get_definition("physical_focus").operations[0].value == 0.2, "Metadata copies never alias authoritative nested values")
	var snapshot: Dictionary = _snapshot()
	var packet: Dictionary = Combat.tornado_packet(snapshot, "parent")
	var all_before: PackedByteArray = var_to_bytes([snapshot, packet, second])
	Damage.resolve(packet, second.modifiers)
	_expect(all_before == var_to_bytes([snapshot, packet, second]), "Resolving support effects leaves caller snapshot, packet and program untouched")
	var empty: Dictionary = Rules.compile_program("tornado", [])
	empty.modifiers.append({})
	empty.recipe_factors.extra = 99
	_expect(Rules.compile_program("tornado", []) == Program.empty(), "Empty result is detached too")
	completed = true
