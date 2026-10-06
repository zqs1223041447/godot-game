extends SceneTree
## Pure bounded conversion, original modifier-entry identity and final settlement.
const Conversion = preload("res://scripts/combat/physical_fire_conversion_rules.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const LegacyDamage = preload("res://docs/qa/v069-rules/frozen/damage_resolver.gd")
const LegacyBase = preload("res://docs/qa/v069-rules/frozen/damage_base_compiler.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_source_contract()
	_test_assembled_split()
	_test_zero_and_legacy_bytes()
	_test_lineage_increased()
	_test_more_entry_identity()
	_test_defense_and_critical()
	_test_invalid_and_overflow()
	_test_detachment()
	print("Physical-to-fire conversion rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00000001, "%s (%.12f vs %.12f)" % [label, value, expected])


func _bytes(value: Variant, expected: Variant, label: String) -> void:
	_expect(var_to_bytes(value) == var_to_bytes(expected), label)


func _recipe(distribution: Dictionary = {"physical": 0.5, "fire": 0.25, "cold": 0.05, "lightning": 0.1, "chaos": 0.1}) -> Dictionary:
	return {"stage": "hit_base", "intrinsic_distribution": distribution,
		"base_coefficient": 1.0, "added_effectiveness": 1.0,
		"tags": ["hit", "attack", "projectile"], "skill_id": "tornado", "role": "parent"}


func _packet() -> Dictionary:
	return Base.assemble(200.0, _recipe())


func _modifier(id: String, mode: String, value: float, types: Array = [], tags: Array = [], skills: Array = []) -> Dictionary:
	return {"id": id, "mode": mode, "value": value, "damage_types": types, "all_tags": tags, "skills": skills}


func _detail(result: Dictionary, type: String) -> Dictionary:
	for detail: Dictionary in result.details:
		if detail.type == type:
			return detail
	return {}


func _failure(result: Dictionary, label: String) -> void:
	_expect(result.size() == 4 and result.get("total") == 0.0 and result.get("components") == {} and result.get("details") == [] and not str(result.get("error", "")).is_empty(), label)


func _test_source_contract() -> void:
	_expect(Conversion.snapshot_error({}).is_empty() and Conversion.from_stats({}).is_empty(), "Absent source adds no snapshot field")
	for zero: Variant in [0, 0.0, -0.0]:
		_expect(Conversion.snapshot_error({Conversion.STAT: zero}).is_empty(), "Numeric zero is valid")
		_expect(Conversion.from_stats({Conversion.STAT: zero}).is_empty() and Conversion.profile(zero).is_empty(), "Zero source and profile remain absent")
	_expect(Conversion.from_stats({Conversion.STAT: 0.4}) == {Conversion.STAT: 0.4}, "Only authored 40 percent enters snapshot")
	_expect(Conversion.profile(0.4) == {"enabled": true, "source_type": "physical", "target_type": "fire", "fraction": 0.4}, "Public profile has exact four fields")
	for invalid: Variant in [null, true, false, "0.4", [], {}, NAN, INF, -INF, -0.4, 0.40000000001, 0.400001, 0.2, 1, 1.0]:
		var source: Dictionary = {Conversion.STAT: invalid}
		var before: PackedByteArray = var_to_bytes(source)
		_expect(not Conversion.snapshot_error(source).is_empty(), "Invalid source fails closed: " + str(invalid))
		_bytes(Conversion.from_stats(source), source, "Invalid source survives for compiler rejection")
		_expect(Conversion.apply(_packet(), invalid).is_empty() and Conversion.profile(invalid).is_empty(), "Invalid ratio cannot produce packet or profile")
		_expect(var_to_bytes(source) == before, "Source validation never mutates input")
	var source: Dictionary = {Conversion.STAT: {"nested": [1]}}
	var snapshot: Dictionary = Conversion.from_stats(source)
	snapshot[Conversion.STAT].nested.append(2)
	_expect(source[Conversion.STAT].nested == [1], "Even invalid source snapshots are detached")


func _test_assembled_split() -> void:
	var recipe: Dictionary = _recipe({"physical": 0.6, "fire": 0.4})
	recipe.base_coefficient = 2.0
	recipe.added_effectiveness = 0.5
	var weapon: Dictionary = {"stage": "weapon_local", "item_id": "gear_000123", "base_id": "ashwood_bow",
		"base": {"physical": 4.0}, "flat": {"physical": 2.0}, "increased": {"physical": 0.2},
		"sources": [{"affix_id": "whetstone_edge", "stat": "weapon_added_physical", "value": 2.0},
			{"affix_id": "tempered_edge", "stat": "weapon_physical_increased", "value": 0.2}]}
	var raw: Dictionary = Base.assemble(100.0, recipe, {"attack": {"physical": 10.0, "fire": 20.0}}, [], weapon)
	var before: PackedByteArray = var_to_bytes(raw)
	var converted: Dictionary = Conversion.apply(raw, 0.4)
	_expect(not converted.is_empty() and Base.packet_error(converted).is_empty(), "Fully assembled split has valid provenance")
	_expect(converted.size() == 6 and converted.conversion.size() == 6, "Only exact optional six-field split is appended")
	_near(converted.conversion.source_base, 120.0 + 5.0 + 14.4, "Intrinsic plus added plus resolved local weapon all convert")
	_near(converted.conversion.remaining_base, 139.4 * 0.6, "Physical remainder uses source times one minus fraction")
	_near(converted.conversion.converted_base, 139.4 * 0.4, "Converted fire uses the same complete source")
	_near(converted.base.fire, 90.0, "Native fire remains separately authored")
	_expect(var_to_bytes(raw) == before, "Conversion does not alter the input packet")
	_bytes(converted.base, raw.base, "Original raw base typed bytes retained")
	_bytes(converted.assembly, raw.assembly, "Original local/intrinsic/added provenance typed bytes retained")
	_expect(Conversion.apply(converted, 0.4).is_empty() and Conversion.apply(converted, 0.0).is_empty(), "A frozen conversion cannot be applied again or removed by a second stage")
	print("CONVERSION_SPLIT ", JSON.stringify(converted.conversion))


func _test_zero_and_legacy_bytes() -> void:
	var raw: Dictionary = _packet()
	var no_physical: Dictionary = Base.assemble(100.0, _recipe({"fire": 1.0}))
	var authored_zero: Dictionary = Base.assemble(0.0, _recipe({"physical": 1.0}), {"attack": {"fire": 3.0}})
	var secondary_recipe: Dictionary = _recipe({"fire": 1.0})
	secondary_recipe.tags = ["hit", "area", "secondary", "explosion"]
	secondary_recipe.role = "secondary"
	secondary_recipe.added_effectiveness = 0.0
	var secondary: Dictionary = Base.assemble(90.0, secondary_recipe)
	for packet: Dictionary in [raw, no_physical, authored_zero, secondary]:
		for zero: Variant in [0, 0.0, -0.0]:
			var copied: Dictionary = Conversion.apply(packet, zero)
			_bytes(copied, packet, "Zero conversion retains complete typed packet bytes")
			_expect(not copied.has("conversion"), "Disabled conversion adds no optional field")
	for packet: Dictionary in [no_physical, authored_zero, secondary]:
		_bytes(Conversion.apply(packet, 0.4), packet, "Enabled source with no physical retains complete typed bytes")
	var modifiers: Array = [_modifier("increase", "increased", 0.23), _modifier("focus", "more", 0.2, ["physical"]),
		_modifier("focus", "more", -0.2, ["fire", "cold", "lightning"]), _modifier("bad_amount", "increased", INF)]
	var legacy_packets: Array[Dictionary] = [raw, no_physical, authored_zero, secondary,
		Damage.packet({"physical": -5.0, "fire": 2}, [], "legacy"), Damage.packet({}, [], "legacy")]
	for packet: Dictionary in legacy_packets:
		for critical: float in [1.0, 1.5, 1000000.0, 0.0, NAN, INF]:
			_bytes(Damage.resolve(packet, modifiers, {"physical": -99.0, "fire": 99.0}, critical),
				LegacyDamage.resolve(packet, modifiers, {"physical": -99.0, "fire": 99.0}, critical), "No-conversion resolve equals frozen 094c1d7 typed bytes")
	var malformed: Array = [null, [], {}, raw]
	for pair: Array in [["base", {"physical": -1.0}], ["assembly", {}], ["tags", []], ["role", "wrong"], ["skill_id", ""]]:
		var bad: Dictionary = raw.duplicate(true)
		bad[pair[0]] = pair[1]
		malformed.append(bad)
	var multiple_errors: Dictionary = raw.duplicate(true)
	multiple_errors.tags = []
	multiple_errors.assembly.intrinsic.physical = 1.0
	malformed.append(multiple_errors)
	for packet: Variant in malformed:
		_bytes(Base.packet_error(packet), LegacyBase.packet_error(packet), "Absent conversion keeps frozen packet-validation error and precedence")


func _test_lineage_increased() -> void:
	var packet: Dictionary = Conversion.apply(_packet(), 0.4)
	var modifiers: Array = [_modifier("global", "increased", 0.1), _modifier("physical", "increased", 0.2, ["physical"]),
		_modifier("fire", "increased", 0.3, ["fire"]), _modifier("both", "increased", 0.4, ["physical", "fire"]),
		_modifier("projectile", "increased", 0.5, [], ["hit", "projectile"], ["tornado"]),
		_modifier("attack_elemental", "increased", 0.6, ["fire", "cold", "lightning"], ["attack"]),
		_modifier("spell_only", "increased", 50.0, [], ["spell"]), _modifier("wrong_skill", "increased", 50.0, [], [], ["meteor"])]
	var resolved: Dictionary = Damage.resolve(packet, modifiers)
	var physical: Dictionary = _detail(resolved, "physical")
	var fire: Dictionary = _detail(resolved, "fire")
	_expect(resolved.details.size() == 5 and fire.parts.size() == 2, "Five final-type receipts with two distinct fire parts")
	_expect(physical.parts[0].lineage == ["physical"] and fire.parts[0].lineage == ["fire"] and fire.parts[1].lineage == ["physical", "fire"], "Stable native-before-converted lineage ordering")
	_expect(physical.parts[0].modifier_indices == [0, 1, 3, 4], "Physical remainder receives original tag/skill/type matches")
	_expect(fire.parts[0].modifier_indices == [0, 2, 3, 4, 5], "Native fire does not inherit physical increase")
	_expect(fire.parts[1].modifier_indices == [0, 1, 2, 3, 4, 5], "Converted piece receives union once, not one pass per lineage type")
	_near(physical.parts[0].increased, 1.2, "Physical increased sums")
	_near(fire.parts[0].increased, 1.9, "Native fire increased sums")
	_near(fire.parts[1].increased, 2.1, "Converted physical and fire increases are additive")
	_near(resolved.components.physical, 132.0, "Physical remainder is scaled after split")
	_near(resolved.components.fire, 269.0, "Native and converted fire sum only after their own scaling")
	_near(resolved.components.cold, 22.0, "Unconverted cold keeps its own lineage")
	_near(resolved.components.lightning, 44.0, "Unconverted lightning keeps its own lineage")
	_near(resolved.components.chaos, 32.0, "Chaos gains no elemental or physical lineage")
	for detail: Dictionary in resolved.details:
		_expect(detail.size() == 5 and not detail.has("base") and not detail.has("increased") and not detail.has("more") and not detail.has("modifiers"), "Final receipt invents no aggregate offensive multiplier")
		for part: Dictionary in detail.parts:
			_expect(part.size() == 7, "Every lineage part has exact seven-field explanatory receipt")


func _test_more_entry_identity() -> void:
	var packet: Dictionary = Conversion.apply(_packet(), 0.4)
	var focus: Array = [_modifier("focus", "more", 0.2, ["physical"]), _modifier("focus", "more", -0.2, ["fire", "cold", "lightning"])]
	var focused: Dictionary = Damage.resolve(packet, focus)
	var part: Dictionary = _detail(focused, "fire").parts[1]
	_near(part.more, 1.2 * 0.8, "Two separate focus clauses sharing id both apply: 0.96")
	_expect(part.modifiers == ["focus", "focus"] and part.modifier_indices == [0, 1], "Same-id clauses retain independent original-entry identities")
	var modifiers: Array = focus.duplicate(true)
	modifiers.append(_modifier("both", "more", 0.25, ["physical", "fire"]))
	modifiers.append(_modifier("global", "more", 0.5))
	modifiers.append(_modifier("ignored", "unknown", 50.0))
	modifiers.append(_modifier("not_finite", "more", INF))
	var resolved: Dictionary = Damage.resolve(packet, modifiers)
	_near(resolved.components.physical, 135.0, "Physical receives its own focus and independent MORE factors")
	_near(resolved.components.fire, 147.0, "Dual-type MORE clause applies once to each piece")
	part = _detail(resolved, "fire").parts[1]
	_expect(part.modifier_indices == [0, 1, 2, 3], "Ignored clauses do not enter applied receipts")
	_near(part.more, 1.2 * 0.8 * 1.25 * 1.5, "Independent MORE product uses each array entry exactly once")
	print("CONVERSION_FOCUS ", JSON.stringify(_detail(resolved, "fire")))


func _test_defense_and_critical() -> void:
	var packet: Dictionary = Conversion.apply(Base.assemble(100.0, _recipe({"physical": 1.0}), {"attack": {"fire": 50.0}}), 0.4)
	var resolved: Dictionary = Damage.resolve(packet, [], {"fire": 0.5}, 2.0)
	_near(_detail(resolved, "physical").parts[0].before_defense, 120.0, "Critical is applied once to physical part")
	_near(_detail(resolved, "fire").parts[0].before_defense, 100.0, "Critical is applied once to native fire part")
	_near(_detail(resolved, "fire").parts[1].before_defense, 80.0, "Critical is applied once to converted fire part")
	_near(_detail(resolved, "fire").before_defense, 180.0, "One pre-defense fire total includes both critical-scaled parts")
	_near(resolved.components.fire, 90.0, "Fire resistance applies to the merged fire hit once")
	var armoured: Dictionary = Defense.apply_armour(resolved, 600.0)
	_near(armoured.components.physical, 60.0, "Hit-size armour uses only remaining 120 physical, not original 200")
	_near(armoured.components.fire, 90.0, "Armour does not apply to converted fire")
	var settled: Dictionary = Defense.settle_resolved(armoured, 20.0, 200.0)
	_expect(settled.ok and settled.details.size() == 2, "Shared defense accepts exactly one receipt per final type")
	_near(settled.raw_components.physical, 120.0, "Settlement keeps residual physical offensive amount")
	_near(settled.raw_components.fire, 180.0, "Settlement keeps aggregate fire offensive amount")
	_near(settled.mitigated_components.physical, 60.0, "Armour prevention remains explicit")
	_near(settled.mitigated_components.fire, 90.0, "Fire resistance prevention remains explicit")
	_near(settled.damage_total, 150.0, "Final settlement applies no second resistance")
	_near(settled.shield_spent, 20.0, "Shield absorbs mitigated damage first")
	_near(settled.health_lost, 130.0, "Health receives remaining mitigated hit")
	_near(settled.remaining_health, 70.0, "Health receipt is complete")
	seed(690040)
	var expected_random: int = randi()
	seed(690040)
	Damage.resolve(packet, [], {"fire": 0.5}, 2.0)
	_expect(randi() == expected_random, "Pure conversion resolution consumes no global RNG")
	for invalid: float in [0.0, NAN, INF, 1000001.0]:
		_bytes(Damage.resolve(packet, [], {}, invalid), LegacyDamage.resolve(packet, [], {}, invalid), "Critical validation keeps exact historical error bytes")
	print("CONVERSION_DEFENSE ", JSON.stringify(settled))


func _test_invalid_and_overflow() -> void:
	var valid: Dictionary = Conversion.apply(_packet(), 0.4)
	for pair: Array in [["source_type", "fire"], ["source_type", 1], ["target_type", "cold"], ["fraction", 0.0], ["fraction", 0.40000000001],
		["source_base", 99.0], ["remaining_base", 60.00000000001], ["converted_base", 39.99999999999]]:
		var bad: Dictionary = valid.duplicate(true)
		bad.conversion[pair[0]] = pair[1]
		_expect(not Base.packet_error(bad).is_empty(), "Forged split rejected: " + str(pair[0]))
		_failure(Damage.resolve(bad, []), "Resolver independently rejects forged split")
	for field: String in ["fraction", "source_base", "remaining_base", "converted_base"]:
		for invalid: Variant in [null, true, false, "0.4", [], {}, NAN, INF, -INF, -0.1]:
			var bad: Dictionary = valid.duplicate(true)
			bad.conversion[field] = invalid
			_expect(not Base.packet_error(bad).is_empty(), "Conversion numeric field rejects malformed value: " + field)
			_failure(Damage.resolve(bad, []), "Malformed conversion cannot partly resolve")
	for trace: Variant in [null, [], {}, "conversion"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.conversion = trace
		_expect(not Base.packet_error(bad).is_empty(), "Conversion record must have exact structure")
		_failure(Damage.resolve(bad, []), "Malformed record returns atomic failure")
	for field: String in valid.conversion:
		var bad: Dictionary = valid.duplicate(true)
		bad.conversion.erase(field)
		_expect(not Base.packet_error(bad).is_empty(), "Missing conversion field rejects")
	var extra: Dictionary = valid.duplicate(true)
	extra.conversion.gain_as_extra = true
	_expect(not Base.packet_error(extra).is_empty(), "Gain-as-extra or any seventh field rejects")
	var conserved: Dictionary = valid.duplicate(true)
	conserved.conversion.remaining_base = 70.0
	conserved.conversion.converted_base = 30.0
	_expect(not Base.packet_error(conserved).is_empty(), "Conservation alone cannot forge an alternate split")
	var bad_assembly: Dictionary = valid.duplicate(true)
	bad_assembly.assembly.intrinsic.physical += 1.0
	_expect(not Base.packet_error(bad_assembly).is_empty(), "Original assembly provenance is still validated")
	for malformed: Variant in [null, [], {}, Damage.packet({"physical": 100.0}, ["hit"], "not_assembled")]:
		_expect(Conversion.apply(malformed, 0.4).is_empty(), "Public helper requires a complete valid assembled packet")
	var dot: Dictionary = _packet()
	dot.tags = ["dot", "attack"]
	_expect(Conversion.apply(dot, 0.4).is_empty(), "DOT cannot acquire a conversion stage")
	dot = valid.duplicate(true)
	dot.tags = ["hit", "dot", "attack"]
	_failure(Damage.resolve(dot, []), "Resolver refuses forged DOT conversion")
	var zero: Dictionary = valid.duplicate(true)
	zero.base.physical = 0.0
	zero.assembly.intrinsic.physical = 0.0
	for field: String in ["source_base", "remaining_base", "converted_base"]:
		zero.conversion[field] = 0.0
	_expect(not Base.packet_error(zero).is_empty(), "No-source packet cannot carry a meaningless conversion record")
	var huge: Dictionary = Base.assemble(1.0e308, _recipe({"physical": 1.0}), {"attack": {"fire": 1.0e308}})
	_expect(Conversion.apply(huge, 0.4).is_empty(), "Finite individual pre-conversion points cannot overflow their aggregate")
	for modifiers: Array in [[_modifier("huge_inc", "increased", 1.0e308)],
		[_modifier("huge_inc_1", "increased", 1.0e308), _modifier("huge_inc_2", "increased", 1.0e308)],
		[_modifier("huge_more_1", "more", 1.0e200), _modifier("huge_more_2", "more", 1.0e200)], [null]]:
		_failure(Damage.resolve(valid, modifiers), "New conversion path rejects arithmetic overflow without partial receipts")
	for field: String in ["all_tags", "skills", "damage_types"]:
		for invalid: Variant in [null, "physical", {}, [null], [true]]:
			var modifier: Dictionary = _modifier("bad_scope", "increased", 0.5)
			modifier[field] = invalid
			_failure(Damage.resolve(valid, [modifier]), "Malformed modifier scope rejects without engine type errors")
	var large: Dictionary = Conversion.apply(Base.assemble(1.0e308, _recipe({"physical": 1.0})), 0.4)
	_failure(Damage.resolve(large, [], {}, 1000000.0), "Critical multiplication overflow fails atomically")
	for invalid: Variant in [null, true, "0.5", NAN, INF, -INF]:
		_failure(Damage.resolve(valid, [], {"fire": invalid}), "Non-finite or nonscalar conversion resistance fails closed")


func _test_detachment() -> void:
	var input: Dictionary = _packet()
	var original: PackedByteArray = var_to_bytes(input)
	var zero: Dictionary = Conversion.apply(input, 0.0)
	zero.tags.append("changed")
	zero.assembly.intrinsic.physical = 999.0
	_expect(var_to_bytes(input) == original, "Disabled result deeply detaches original packet")
	var packet: Dictionary = Conversion.apply(input, 0.4)
	packet.assembly.intrinsic.physical = 999.0
	packet.base.fire = 999.0
	_expect(var_to_bytes(input) == original, "Enabled result deeply detaches original base and provenance")
	packet = Conversion.apply(input, 0.4)
	var modifiers: Array = [_modifier("both", "more", 0.25, ["physical", "fire"])]
	var mitigation: Dictionary = {"fire": 0.5}
	var before: PackedByteArray = var_to_bytes([packet, modifiers, mitigation])
	var resolved: Dictionary = Damage.resolve(packet, modifiers, mitigation)
	var repeated: Dictionary = Damage.resolve(packet, modifiers, mitigation)
	_bytes(resolved, repeated, "Repeated converted resolutions have identical complete typed bytes")
	_expect(var_to_bytes([packet, modifiers, mitigation]) == before, "Resolver leaves every caller argument unchanged")
	var settled: Dictionary = Defense.settle_resolved(resolved, 10.0, 100.0)
	_expect(settled.ok, "Detached conversion result settles")
	settled.details[1].parts[1].lineage.append("changed")
	settled.details[1].parts[1].modifier_indices.append(99)
	_bytes(resolved, repeated, "Defense settlement deeply detaches lineage parts and identities")
	resolved.details[1].parts[1].lineage.append("changed")
	resolved.details[1].parts[1].modifiers.append("changed")
	resolved.details[1].parts[1].modifier_indices.append(99)
	_expect(_detail(repeated, "fire").parts[1].lineage == ["physical", "fire"], "Separate resolves own their lineage arrays")
	_expect(var_to_bytes([packet, modifiers, mitigation]) == before, "Mutating receipts cannot mutate caller arguments")
