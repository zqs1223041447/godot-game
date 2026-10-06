extends SceneTree
## Focused v078 gate. Prior scripts come directly from the immutable base commit
## and compile in memory, so compatibility cannot silently track current code.
const Conversion = preload("res://scripts/combat/physical_fire_conversion_rules.gd")
const Penetration = preload("res://scripts/combat/hit_penetration_rules.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const BASELINE: String = "07922581e2924dbb6fbadd1fb51242ae87a16293"
var checks: int = 0
var failures: int = 0
var legacy_damage: GDScript
var legacy_base: GDScript
var legacy_conversion: GDScript


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_baseline()
	if failures == 0:
		_test_legacy_bytes()
	_test_snapshot_contracts()
	_test_all_splits()
	_test_lineage_and_more()
	_test_strict_admission()
	_test_penetration()
	_test_settlement_and_detachment()
	print("Elemental conversion and hit penetration: %d checks, %d failures; baseline %s" % [checks, failures, BASELINE])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _bytes(value: Variant, expected: Variant, label: String) -> void:
	_expect(var_to_bytes(value) == var_to_bytes(expected), label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) <= maxf(0.00000000001, absf(expected) * 0.000000000001), "%s: %.16f / %.16f" % [label, value, expected])


func _failure(result: Dictionary, label: String) -> void:
	_expect(result.size() == 4 and result.get("total") == 0.0 and result.get("components") == {} and result.get("details") == [] and not str(result.get("error", "")).is_empty(), label)


func _recipe(distribution: Dictionary = {"physical": 1.0}) -> Dictionary:
	return {"stage": "hit_base", "intrinsic_distribution": distribution, "base_coefficient": 1.0,
		"added_effectiveness": 1.0, "tags": ["hit", "attack", "projectile"], "skill_id": "tornado", "role": "parent"}


func _packet(amount: float = 100.0, native: Dictionary = {"fire": 20.0, "cold": 30.0, "lightning": 40.0, "chaos": 10.0}) -> Dictionary:
	return Base.assemble(amount, _recipe(), {"attack": native})


func _snapshot(mask: int) -> Dictionary:
	var snapshot: Dictionary = {}
	for index: int in range(Damage.ELEMENTS.size()):
		if mask & (1 << index):
			snapshot[Conversion.STATS[Damage.ELEMENTS[index]]] = 0.4
	return snapshot


func _modifier(id: String, mode: String, value: float, types: Array = [], tags: Array = [], skills: Array = []) -> Dictionary:
	return {"id": id, "mode": mode, "value": value, "damage_types": types, "all_tags": tags, "skills": skills}


func _detail(result: Dictionary, type: String) -> Dictionary:
	for detail: Dictionary in result.details:
		if detail.type == type:
			return detail
	return {}


func _load_script(path: String) -> GDScript:
	var output: Array = []
	var result: int = OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "show", BASELINE + ":" + path], output, true)
	_expect(result == 0 and output.size() == 1, "Read immutable baseline " + path)
	if result != 0 or output.size() != 1:
		return null
	var source: String = str(output[0])
	source = source.substr(source.find("\n") + 1) # Drop global class name only.
	source = source.replace('const Damage = preload("res://scripts/combat/damage_resolver.gd")', 'static var Damage: GDScript')
	source = source.replace('const Base = preload("res://scripts/combat/damage_base_compiler.gd")', 'static var Base: GDScript')
	source = source.replace('const FRACTION: float = Damage.CONVERSION_FRACTION', 'const FRACTION: float = 0.4')
	var script: GDScript = GDScript.new()
	script.source_code = source
	_expect(script.reload() == OK, "Compile frozen baseline in memory " + path)
	return script


func _load_baseline() -> void:
	legacy_damage = _load_script("scripts/combat/damage_resolver.gd")
	legacy_base = _load_script("scripts/combat/damage_base_compiler.gd")
	legacy_conversion = _load_script("scripts/combat/physical_fire_conversion_rules.gd")
	if failures > 0:
		return
	legacy_base.set("Damage", legacy_damage)
	legacy_conversion.set("Damage", legacy_damage)
	legacy_conversion.set("Base", legacy_base)


func _test_legacy_bytes() -> void:
	var modifiers: Array = [_modifier("inc", "increased", 0.23), _modifier("focus", "more", 0.2, ["physical"]),
		_modifier("focus", "more", -0.2, ["fire", "cold", "lightning"]), _modifier("ignore", "increased", INF)]
	var packets: Array[Dictionary] = [_packet(), _packet(13.3, {}), _packet(0.0), Base.assemble(33.3, _recipe({"fire": 1.0}))]
	for raw: Dictionary in packets:
		_bytes(Base.packet_error(raw), legacy_base.packet_error(raw), "Unconverted Base validation bytes match")
		for fraction: Variant in [0, 0.0, -0.0, 0.4]:
			var expected: Dictionary = legacy_conversion.apply(raw, fraction)
			var current: Dictionary = Conversion.apply(raw, fraction)
			_bytes(current, expected, "Old apply packets retain complete bytes")
			_bytes(Conversion.apply_snapshot(raw, {Conversion.STAT: fraction}), expected, "Snapshot fire-only and zero delegate legacy bytes")
			_bytes(Base.packet_error(current), legacy_base.packet_error(expected), "Fire Base validation bytes match")
			for critical: float in [1.0, 1.5, 1000000.0, 0.0, NAN, INF]:
				_bytes(Damage.resolve(current, modifiers, {"physical": -99.0, "fire": 99.0, "cold": 0.35}, critical), legacy_damage.resolve(expected, modifiers, {"physical": -99.0, "fire": 99.0, "cold": 0.35}, critical), "Old fire/disabled resolver typed bytes match")
	for invalid: Variant in [null, true, false, "0.4", [], {}, NAN, INF, -INF, -0.4, 0.40000000001, 0.2, 1]:
		_bytes(Conversion.snapshot_error({Conversion.STAT: invalid}), legacy_conversion.snapshot_error({Conversion.STAT: invalid}), "Old invalid fire source error bytes match")
		_bytes(Conversion.from_stats({Conversion.STAT: invalid}), legacy_conversion.from_stats({Conversion.STAT: invalid}), "Old invalid fire source snapshot bytes match")
		_bytes(Conversion.apply(_packet(), invalid), legacy_conversion.apply(_packet(), invalid), "Old invalid apply result bytes match")
	var valid: Dictionary = Conversion.apply(_packet(), 0.4)
	for field: String in valid.conversion:
		var bad: Dictionary = valid.duplicate(true)
		bad.conversion.erase(field)
		_bytes(Base.packet_error(bad), legacy_base.packet_error(bad), "Old missing conversion field validation bytes match")
		_bytes(Damage.resolve(bad, []), legacy_damage.resolve(bad, []), "Old missing conversion field failure bytes match")
	for extra: String in ["gain_as_extra", "version"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.conversion[extra] = 2
		_bytes(Base.packet_error(bad), legacy_base.packet_error(bad), "Old extra field error bytes match")
	for pair: Array in [["tags", []], ["role", "wrong"], ["assembly", {}], ["base", {"physical": -1.0}], ["skill_id", ""]]:
		var bad: Dictionary = _packet()
		bad[pair[0]] = pair[1]
		_bytes(Base.packet_error(bad), legacy_base.packet_error(bad), "Old base invalid field precedence retained")
	var multiple: Dictionary = valid.duplicate(true)
	multiple.tags = []
	multiple.assembly.intrinsic.physical = 1.0
	_bytes(Base.packet_error(multiple), legacy_base.packet_error(multiple), "Multiple old invalid conditions preserve precedence")


func _test_snapshot_contracts() -> void:
	for field: String in Conversion.STATS.values():
		for zero: Variant in [0, 0.0, -0.0]:
			_expect(Conversion.snapshot_error({field: zero}).is_empty(), "Every source accepts numeric zero")
			_expect(Conversion.from_stats({field: zero}).is_empty() and Conversion.profile_from_snapshot({field: zero}).is_empty(), "Every zero source omits snapshot/profile")
		for invalid: Variant in [null, true, false, "0.4", [], {}, NAN, INF, -INF, -0.4, 0.400000000000001, 0.2, 1]:
			var stats: Dictionary = {field: invalid}
			_expect(not Conversion.snapshot_error(stats).is_empty(), "Conversion rejects invalid " + field)
			_bytes(Conversion.from_stats(stats), stats, "Invalid conversion source preserved for compiler rejection")
			_expect(Conversion.apply_snapshot(_packet(), stats).is_empty() and Conversion.profile_from_snapshot(stats).is_empty(), "Invalid conversion source cannot compile")
	for type: String in Penetration.STAT_FIELDS:
		var field: String = Penetration.STAT_FIELDS[type]
		for zero: Variant in [0, 0.0, -0.0]:
			_expect(Penetration.from_stats({field: zero}).is_empty(), "Penetration numeric zero omits snapshot")
		_bytes(Penetration.from_stats({field: 0.06}), {"hit_penetration": {type: 0.06}}, "Penetration active field canonicalizes")
		for invalid: Variant in [null, true, false, "0.06", [], {}, NAN, INF, -INF, -0.06, 0.060000000000001, 0.4, 1]:
			var snapshot: Dictionary = Penetration.from_stats({field: invalid})
			_expect(not Penetration.snapshot_error(snapshot).is_empty(), "Invalid penetration source survives to rejection")
			_expect(Penetration.profile_from_snapshot(snapshot).is_empty() and Penetration.attach(_packet(), snapshot).is_empty(), "Invalid penetration cannot attach")
	for malformed: Variant in [null, [], {}, 0.06, {"cold": 0.0}, {"fire": 0.06}, {"chaos": 0.06}, {1: 0.06}]:
		_expect(not Penetration.snapshot_error({"hit_penetration": malformed}).is_empty(), "Penetration map rejects empty/zero/unsupported shape")
	_bytes(Conversion.profile_from_snapshot(_snapshot(1)), Conversion.profile(0.4), "Fire-only profile retains exact four fields")
	_bytes(Penetration.profile_from_snapshot({"hit_penetration": {"lightning": 0.06, "cold": 0.06}}), {"enabled": true, "fractions": {"cold": 0.06, "lightning": 0.06}, "minimum_resistance": -1.0}, "Penetration profile order and floor canonical")


func _test_all_splits() -> void:
	for mask: int in range(8):
		var snapshot: Dictionary = _snapshot(mask)
		var profile: Dictionary = Conversion.profile_from_snapshot(snapshot)
		for amount: float in [0.0, _next_positive(0.0), 1e-300, 0.125, 1.1, 13.3, 100.0, 1e18, 1e300]:
			var raw: Dictionary = _packet(amount, {})
			var packet: Dictionary = Conversion.apply_snapshot(raw, snapshot)
			_expect(not packet.is_empty() and Base.packet_error(packet).is_empty(), "Every subset/magnitude has valid split")
			_bytes(packet.base, raw.base, "Conversion never rewrites raw typed base")
			_bytes(packet.assembly, raw.assembly, "Conversion never rewrites assembly provenance")
			if mask == 0 or amount == 0.0:
				_bytes(packet, raw, "Inactive/source-zero conversion preserves bytes")
				continue
			_expect(Conversion.apply_snapshot(packet, snapshot).is_empty() and Conversion.apply_snapshot(packet, {}).is_empty(), "Frozen conversion rejects repeat/removal")
			if mask == 1:
				_expect(packet.conversion.size() == 6 and not packet.conversion.has("version"), "Single fire retains v1 descriptor")
				continue
			_expect(packet.conversion.size() == 7 and packet.conversion.version == 2 and profile.size() == 7, "New conversion has exact v2 descriptor/profile shape")
			var count: int = snapshot.size()
			var requested_total: float = 0.0
			for _index: int in range(count): requested_total += 0.4
			var expected_ratio: float = 0.4 / requested_total if count == 3 else 0.4
			var expected_remaining: float = 0.0 if count == 3 else amount * (1.0 - requested_total)
			_expect(packet.conversion.remaining_base == expected_remaining, "Remainder uses requested total or explicit zero")
			_expect(profile.physical_fraction is float and profile.normalized == (count == 3), "Profile publishes typed fraction and normalization decision")
			var order: Array = []
			for type: String in Damage.ELEMENTS:
				if snapshot.has(Conversion.STATS[type]):
					order.append(type)
					_expect(packet.conversion.requested[type] == 0.4 and packet.conversion.effective[type] == expected_ratio and packet.conversion.converted_base[type] == amount * expected_ratio, "Exact requested/effective/product provenance")
			_expect(packet.conversion.requested.keys() == order and packet.conversion.effective.keys() == order and packet.conversion.converted_base.keys() == order, "All maps retain fire/cold/lightning order")
			var resolved: Dictionary = Damage.resolve(packet, [])
			_expect(not resolved.has("error"), "Every authored split resolves")
			if count == 3:
				_expect(not resolved.components.has("physical") and _detail(resolved, "physical").is_empty(), "Normalized split has no ghost physical receipt")
	print("V078_THREE_WAY ", JSON.stringify(Conversion.apply_snapshot(_packet(), _snapshot(7)).conversion))


func _test_lineage_and_more() -> void:
	var packet: Dictionary = Conversion.apply_snapshot(_packet(), _snapshot(6))
	var modifiers: Array = [_modifier("global", "increased", 0.1), _modifier("physical", "increased", 0.2, ["physical"]),
		_modifier("cold", "increased", 0.3, ["cold"]), _modifier("union", "increased", 0.4, ["physical", "cold", "lightning"]),
		_modifier("scoped", "increased", 0.5, [], ["hit", "projectile"], ["tornado"]),
		_modifier("wrong_skill", "increased", 99.0, [], [], ["meteor"]), _modifier("wrong_tags", "increased", 99.0, [], ["spell"])]
	var resolved: Dictionary = Damage.resolve(packet, modifiers)
	var cold: Dictionary = _detail(resolved, "cold")
	var lightning: Dictionary = _detail(resolved, "lightning")
	_expect(resolved.details.size() == 5 and cold.parts.size() == 2 and lightning.parts.size() == 2, "Each final type has one receipt with separate native and converted parts")
	_expect(cold.parts[0].lineage == ["cold"] and cold.parts[1].lineage == ["physical", "cold"], "Native cold precedes converted cold")
	_expect(lightning.parts[0].lineage == ["lightning"] and lightning.parts[1].lineage == ["physical", "lightning"], "Native lightning precedes converted lightning")
	_expect(cold.parts[1].modifier_indices == [0, 1, 2, 3, 4], "Overlapping damage types apply each modifier entry once")
	_expect(cold.parts[0].modifier_indices == [0, 2, 3, 4], "Native element never inherits physical increase")
	_near(cold.parts[1].increased, 1.5, "Lineage increases add")
	_near(cold.before_defense, 30.0 * 2.3 + 40.0 * 2.5, "Parts scale before they merge")
	var physical_focus: Array = [_modifier("same_id", "more", 0.2, ["physical"]), _modifier("same_id", "more", -0.2, ["fire", "cold", "lightning"])]
	var fire_focus: Array = [_modifier("same_id", "more", 0.2, ["fire"]), _modifier("same_id", "more", -0.2, ["physical", "cold", "lightning", "chaos"])]
	for focus: Array in [physical_focus, fire_focus]:
		var focused: Dictionary = Damage.resolve(Conversion.apply_snapshot(_packet(), _snapshot(7)), focus)
		for type: String in Damage.ELEMENTS:
			var part: Dictionary = _detail(focused, type).parts[1]
			var expected: float = 1.2 * 0.8 if focus == physical_focus or type == "fire" else 0.8
			_near(part.more, expected, "Physical focus all conversions .96; fire focus cold/lightning .8 once")
			_expect(part.modifier_indices == ([0, 1] if expected != 0.8 else [1]), "Array-entry identity retained without ID deduplication")
	physical_focus.append(_modifier("union_more", "more", 0.25, ["physical", "cold", "lightning"]))
	physical_focus.append(_modifier("global_more", "more", 0.5))
	var focused: Dictionary = Damage.resolve(packet, physical_focus, {}, 2.0)
	var part: Dictionary = _detail(focused, "cold").parts[1]
	_near(part.more, 1.2 * 0.8 * 1.25 * 1.5, "Independent MORE factors multiply exactly once")
	_near(part.before_defense, 40.0 * 1.2 * 0.8 * 1.25 * 1.5 * 2.0, "Critical applies once after final MORE")
	_expect(part.modifiers == ["same_id", "same_id", "union_more", "global_more"], "Duplicate IDs remain visible")


func _reject_conversion(packet: Dictionary, label: String) -> void:
	_expect(not Base.packet_error(packet).is_empty(), label + " Base rejects")
	_failure(Damage.resolve(packet, []), label + " resolver rejects atomically")


func _next_positive(value: float) -> float:
	var data: PackedByteArray = PackedByteArray()
	data.resize(8)
	data.encode_double(0, value)
	data.encode_u64(0, data.decode_u64(0) + 1)
	return data.decode_double(0)


func _test_strict_admission() -> void:
	var valid: Dictionary = Conversion.apply_snapshot(_packet(), _snapshot(7))
	for field: String in valid.conversion:
		var missing: Dictionary = valid.duplicate(true)
		missing.conversion.erase(field)
		_reject_conversion(missing, "Missing v2 field " + field)
	var extra: Dictionary = valid.duplicate(true)
	extra.conversion.unearned = 1.0
	_reject_conversion(extra, "Extra v2 field")
	for pair: Array in [["version", 2.0], ["version", true], ["version", 3], ["source_type", "fire"], ["source_base", 99.0], ["remaining_base", _next_positive(0.0)], ["requested", {}], ["effective", {}], ["converted_base", {}]]:
		var bad: Dictionary = valid.duplicate(true)
		bad.conversion[pair[0]] = pair[1]
		_reject_conversion(bad, "Forged v2 " + str(pair[0]))
	for field: String in ["source_base", "remaining_base"]:
		for invalid: Variant in [null, true, false, "0.4", [], {}, NAN, INF, -INF, -1.0]:
			var bad: Dictionary = valid.duplicate(true)
			bad.conversion[field] = invalid
			_reject_conversion(bad, "Invalid v2 scalar " + field)
	for field: String in ["requested", "effective", "converted_base"]:
		for malformed: Variant in [null, [], 0.4, "cold", {"cold": 0.4}, {"fire": 0.4, "cold": 0.4, "chaos": 0.4}]:
			var bad: Dictionary = valid.duplicate(true)
			bad.conversion[field] = malformed
			_reject_conversion(bad, "Invalid v2 map " + field)
		for invalid: Variant in [null, true, false, "0.4", [], {}, NAN, INF, -INF, -1.0]:
			var bad: Dictionary = valid.duplicate(true)
			bad.conversion[field].cold = invalid
			_reject_conversion(bad, "Invalid v2 map value " + field)
		var next: Dictionary = valid.duplicate(true)
		next.conversion[field].cold = _next_positive(float(next.conversion[field].cold))
		_reject_conversion(next, "One-ULP forged derived/requested value " + field)
	var next_source: Dictionary = valid.duplicate(true)
	next_source.conversion.source_base = _next_positive(next_source.conversion.source_base)
	_reject_conversion(next_source, "One-ULP forged source")
	var conserved: Dictionary = valid.duplicate(true)
	conserved.conversion.converted_base.cold += 1.0
	conserved.conversion.converted_base.lightning -= 1.0
	_reject_conversion(conserved, "Conservation does not permit altered authored products")
	var alternate: Dictionary = valid.duplicate(true)
	alternate.conversion.requested = {"fire": 0.4}
	alternate.conversion.effective = {"fire": 0.4}
	alternate.conversion.converted_base = {"fire": 40.0}
	alternate.conversion.remaining_base = 60.0
	_reject_conversion(alternate, "V2 cannot replace legacy single-fire shape")
	for tags: Array in [["dot"], ["hit", "dot", "attack"], []]:
		var dot: Dictionary = valid.duplicate(true)
		dot.tags = tags
		_reject_conversion(dot, "Nonhit/DOT converted packet")
		_expect(Conversion.apply_snapshot(dot, _snapshot(6)).is_empty(), "DOT cannot enter conversion helper")
	var overflow: Dictionary = _packet(1e308, {"fire": 1e308})
	_expect(Conversion.apply_snapshot(overflow, _snapshot(7)).is_empty(), "Summed pre-conversion overflow fails closed")
	for modifiers: Array in [[_modifier("overflow", "increased", 1e308)], [_modifier("overflow", "more", 1e200), _modifier("overflow", "more", 1e200)], [null]]:
		_failure(Damage.resolve(valid, modifiers), "New converted offensive overflow/malformed modifier fails atomically")
	for invalid: Variant in [null, true, "0.5", NAN, INF, -INF]:
		_failure(Damage.resolve(valid, [], {"cold": invalid}), "Invalid converted mitigation fails closed")


func _test_penetration() -> void:
	var snapshot: Dictionary = Penetration.from_stats({"cold_penetration": 0.06, "lightning_penetration": 0.06})
	var raw: Dictionary = _packet()
	for mask: int in [0, 1, 2, 4, 6, 7]:
		var converted: Dictionary = Conversion.apply_snapshot(raw, _snapshot(mask))
		var packet: Dictionary = Penetration.attach(converted, snapshot)
		_expect(packet.size() == 6 + int(packet.has("conversion")) and Base.packet_error(packet).is_empty(), "Penetration is exact optional map in legal hit")
		_bytes(packet.penetration, {"cold": 0.06, "lightning": 0.06}, "Penetration retains canonical typed map")
		for resistance: float in [-99.0, -1.0, -0.98, -0.5, 0.0, 0.75, 0.9, 99.0]:
			var mitigation: Dictionary = {"physical": 0.1, "fire": 0.3, "cold": resistance, "lightning": resistance, "chaos": 0.2}
			var before: PackedByteArray = var_to_bytes([packet, mitigation])
			var result: Dictionary = Damage.resolve(packet, [], mitigation)
			var ordinary: Dictionary = Damage.resolve(converted, [], mitigation)
			for type: String in ["cold", "lightning"]:
				var detail: Dictionary = _detail(result, type)
				var expected_effective: float = clampf(resistance, -1.0, 0.9)
				var expected_used: float = maxf(-1.0, expected_effective - 0.06)
				_expect(detail.effective_resistance == expected_effective and detail.penetration == 0.06 and detail.resistance == expected_used, "Effective cap precedes penetration then -100 floor")
				_near(detail.final, detail.before_defense * (1.0 - expected_used), "Penetration uses final type exactly once")
				_expect(detail.before_defense == _detail(ordinary, type).before_defense, "Penetration never inflates offensive pre-defense amount")
				if detail.has("parts"):
					_bytes(detail.parts, _detail(ordinary, type).parts, "Penetration does not alter lineage offensive parts")
			for type: String in ["physical", "fire", "chaos"]:
				_bytes(_detail(result, type), _detail(ordinary, type), "No penetration leaks to other final type")
			_expect(var_to_bytes([packet, mitigation]) == before, "Resolution never mutates target or input")
			var settled: Dictionary = Defense.settle_resolved(result, 10.0, 1000.0)
			_expect(settled.ok, "Existing Defense accepts capped and negative pierced results")
			_expect(settled.raw_components.cold == _detail(result, "cold").before_defense, "Defense retains true pre-defense cold amount")
			_near(settled.damage_total, result.total, "Defense does not apply resistance twice")
	var pure_fire: Dictionary = Base.assemble(50.0, _recipe({"fire": 1.0}))
	var secondary_recipe: Dictionary = _recipe({"fire": 1.0})
	secondary_recipe.role = "secondary"
	secondary_recipe.tags = ["hit", "area", "secondary", "explosion"]
	secondary_recipe.added_effectiveness = 0.0
	var secondary: Dictionary = Base.assemble(50.0, secondary_recipe)
	for packet: Dictionary in [pure_fire, secondary, _packet(50.0, {})]:
		_bytes(Penetration.attach(packet, snapshot), packet, "Unmatched/independent explosion penetration retains complete packet bytes")
		if not packet.base.has("physical"):
			_bytes(Conversion.apply_snapshot(packet, _snapshot(7)), packet, "No-source explosion retains bytes")
	var converted_only: Dictionary = Conversion.apply_snapshot(_packet(100.0, {}), _snapshot(2))
	var attached: Dictionary = Penetration.attach(converted_only, snapshot)
	_bytes(attached.penetration, {"cold": 0.06}, "Converted-only cold acquires penetration without native cold")
	var only_cold: Dictionary = Base.assemble(100.0, _recipe({"cold": 1.0}))
	_bytes(Penetration.attach(only_cold, snapshot).penetration, {"cold": 0.06}, "Unused lightning is omitted")
	for zero: Dictionary in [{}, Penetration.from_stats({"cold_penetration": 0, "lightning_penetration": -0.0})]:
		_bytes(Penetration.attach(raw, zero), raw, "Absent/zero penetration preserves exact packet bytes")
	var valid: Dictionary = Penetration.attach(raw, snapshot)
	for fractions: Variant in [null, [], {}, {"fire": 0.06}, {"cold": 0.0}, {"cold": true}, {"cold": 0.060000000000001}, {"cold": INF}, {"cold": 0.06, "chaos": 0.06}]:
		var bad: Dictionary = valid.duplicate(true)
		bad.penetration = fractions
		_expect(not Base.packet_error(bad).is_empty(), "Base rejects malformed penetration")
		_failure(Damage.resolve(bad, []), "Resolver independently rejects malformed penetration")
	var dot: Dictionary = valid.duplicate(true)
	dot.tags = ["dot", "spell"]
	_expect(Penetration.attach(dot, snapshot).is_empty() and not Base.packet_error(dot).is_empty(), "DOT cannot attach hit penetration")
	_failure(Damage.resolve(dot, []), "Forged DOT penetration fails closed")
	dot.erase("penetration")
	_bytes(Damage.resolve(dot, []), legacy_damage.resolve(dot, []), "Ordinary DOT has exact historical damage bytes")
	print("V078_PENETRATION_90 ", JSON.stringify(Damage.resolve(Penetration.attach(only_cold, snapshot), [], {"cold": 0.9})))
	print("V078_PENETRATION_ZERO ", JSON.stringify(Damage.resolve(Penetration.attach(only_cold, snapshot), [], {"cold": 0.0})))
	print("V078_PENETRATION_FLOOR ", JSON.stringify(Damage.resolve(Penetration.attach(only_cold, snapshot), [], {"cold": -1.0})))


func _test_settlement_and_detachment() -> void:
	var raw: Dictionary = _packet()
	var snapshot: Dictionary = _snapshot(6)
	snapshot.hit_penetration = {"cold": 0.06, "lightning": 0.06}
	var modifiers: Array = [_modifier("physical_inc", "increased", 0.2, ["physical"])]
	var mitigation: Dictionary = {"cold": 0.75, "lightning": 0.0}
	var inputs: PackedByteArray = var_to_bytes([raw, snapshot, modifiers, mitigation])
	seed(780006)
	var expected_random: int = randi()
	seed(780006)
	var packet: Dictionary = Penetration.attach(Conversion.apply_snapshot(raw, snapshot), snapshot)
	var result: Dictionary = Damage.resolve(packet, modifiers, mitigation, 2.0)
	var armored: Dictionary = Defense.apply_armour(result, 600.0)
	var settled: Dictionary = Defense.settle_with_mana(armored, 20.0, 1000.0, 80.0, 0.25)
	_expect(randi() == expected_random, "Conversion/penetration/defense pipeline consumes no additional RNG")
	_expect(settled.ok and settled.details.size() == 5, "Real shield/mana/life settlement accepts conversion and penetration")
	_near(_detail(result, "cold").before_defense, (30.0 + 40.0 * 1.2) * 2.0, "Combined converted/native pre-defense amount")
	_near(settled.raw_components.cold, 156.0, "Raw settlement amount is offensive only")
	_near(settled.components.cold, 156.0 * (1.0 - (0.75 - 0.06)), "Settlement uses already pierced final damage")
	_near(settled.shield_spent, 20.0, "Shield is spent before mana/life")
	_near(settled.mana_spent, minf(80.0, (settled.damage_total - 20.0) * 0.25), "Mana uses only post-shield damage")
	_near(settled.health_lost, settled.damage_total - settled.shield_spent - settled.mana_spent, "Life receives remaining damage")
	_expect(var_to_bytes([raw, snapshot, modifiers, mitigation]) == inputs, "All pipeline caller inputs remain byte-identical")
	var repeat: Dictionary = Damage.resolve(packet, modifiers, mitigation, 2.0)
	_bytes(result, repeat, "Repeated resolution has complete deterministic typed bytes")
	packet.penetration.cold = 9.0
	packet.conversion.requested.cold = 9.0
	packet.assembly.intrinsic.physical = 9.0
	_expect(var_to_bytes([raw, snapshot, modifiers, mitigation]) == inputs, "Attached packet is deeply detached")
	print("V078_SETTLEMENT ", JSON.stringify(settled))
	settled.details[2].parts[1].lineage.append("changed")
	settled.details[2].parts[1].modifier_indices.append(99)
	_bytes(result, repeat, "Settlement deeply detaches new explanatory parts")
	var invalid: Dictionary = {"physical_to_cold_conversion": {"nested": [1]}, "cold_penetration": {"nested": [1]}}
	var converted: Dictionary = Conversion.from_stats(invalid)
	var pierced: Dictionary = Penetration.from_stats(invalid)
	converted.physical_to_cold_conversion.nested.append(2)
	pierced.hit_penetration.cold.nested.append(2)
	_expect(invalid.physical_to_cold_conversion.nested == [1] and invalid.cold_penetration.nested == [1], "Malformed source records also detach nested aliases")
