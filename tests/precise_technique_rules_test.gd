extends SceneTree
## Pure strict comparison, attack-only MORE, unconditional critical ban and RNG.
const Precise = preload("res://scripts/combat/precise_technique_rules.gd")
const Critical = preload("res://scripts/combat/critical_strike_rules.gd")
const Runtime = preload("res://scripts/combat/critical_strike_runtime.gd")
const Resolute = preload("res://scripts/combat/resolute_technique_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Conversion = preload("res://scripts/combat/physical_fire_conversion_rules.gd")
const Attack = preload("res://scripts/combat/attack_hit_rules.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const OldCritical = preload("res://docs/qa/v070-rules/frozen/critical_strike_rules.gd")
const OldRuntime = preload("res://docs/qa/v070-rules/frozen/critical_strike_runtime.gd")
const TAGS: Array = [["hit", "attack", "projectile"], ["hit", "attack", "melee", "area"],
	["hit", "spell", "projectile"], ["hit", "spell", "area"], ["hit", "spell", "chain"],
	["hit", "area", "secondary", "explosion"], ["hit"], ["utility"], ["attack"], []]
var checks: int = 0
var failures: int = 0
var completed: bool = false
var sections: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_source_contract, _strict_boundaries, _malformed_context,
		_modifier_scope, _validation_precedence, _critical_union, _legacy_rng, _compiler_attachment]:
		completed = false
		var before: int = checks
		test.call()
		_expect(completed, "Section completed without a script exception: " + test.get_method())
		sections[test.get_method()] = checks - before
	var report_path: String = OS.get_environment("PRECISE_RULES_REPORT")
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		_expect(file != null, "Result report opened")
		if file != null:
			file.store_string(JSON.stringify({"checks": checks, "failures": failures, "sections": sections,
				"base_commit": "d25717c4485bf36688df36460f2c85ebb11b7623",
				"scope": "Pure helper, critical compiler, typed damage, current compiler attachment and private RNG; no scene, source allocation, migration, UI or Windows claims"}, "\t", true, true))
	print("Precise technique rules: %d checks, %d failures; %s" % [checks, failures, JSON.stringify(sections)])
	quit(1 if failures else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _same(actual: Variant, expected: Variant, label: String) -> void:
	_expect(var_to_bytes(actual) == var_to_bytes(expected), label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) < 0.00000001, "%s: %.12f / %.12f" % [label, actual, expected])


func _context(accuracy: Variant = 201.0, max_health: Variant = 200.0) -> Dictionary:
	return {Precise.STAT: {"accuracy": accuracy, "max_health": max_health}}


func _critical_source() -> Dictionary:
	return {"critical_modifiers": {"base_chance": 0.05, "base_multiplier": 1.5,
		"crit_chance_increased": 0.2, "attack_crit_chance_increased": 0.4,
		"spell_crit_chance_increased": 0.3, "melee_crit_chance_increased": 0.6,
		"projectile_attack_crit_chance_increased": 0.8, "crit_multiplier_add": 0.1,
		"spell_crit_multiplier_add": 0.2, "melee_crit_multiplier_add": 0.4,
		"projectile_attack_crit_multiplier_add": 0.6}}


func _stats() -> Dictionary:
	return {"damage": 20.0, "accuracy": 201.0, "max_health": 200.0,
		"crit_base_chance": 0.05, "crit_base_multiplier": 1.5, "crit_multiplier_add": 0.2,
		"physical_increased": 0.2, "attack_added_physical": 3.0}


func _source_contract() -> void:
	_same(Precise.from_stats({}), {}, "Absent source produces no field")
	_expect(Precise.snapshot_error({}).is_empty() and not Precise.active({}), "Absent snapshot has no policy")
	_expect(Precise.profile({}).is_empty() and Precise.attack_modifier({}).is_empty(), "Absent snapshot has no modifier or presentation")
	for zero: Variant in [0, 0.0, -0.0]:
		_same(Precise.from_stats({Precise.STAT: zero, "accuracy": NAN, "max_health": null}), {}, "Explicit zero ignores unused context and preserves absence bytes")
	for one: Variant in [1, 1.0]:
		var source: Dictionary = {Precise.STAT: one, "accuracy": 201, "max_health": 200}
		var before: PackedByteArray = var_to_bytes(source)
		var snapshot: Dictionary = Precise.from_stats(source)
		_same(snapshot, _context(), "Selected source captures exactly two final float fields")
		_expect(Precise.active(snapshot), "Selected valid source enables policy")
		source.accuracy = 0; source.max_health = 300
		_same(snapshot, _context(), "Final captured context cannot change with later stats")
		snapshot[Precise.STAT].accuracy = 999.0
		_expect(source.accuracy == 0 and before != var_to_bytes(source), "Changing capture does not mutate source")
	for invalid: Variant in [true, false, "1", "0", null, [], {}, NAN, INF, -INF, -1, 2, 0.5, 1.00000001,
		{"accuracy": 201.0, "max_health": 200.0}]:
		var source: Dictionary = {Precise.STAT: invalid, "accuracy": 201.0, "max_health": 200.0}
		var before: PackedByteArray = var_to_bytes(source)
		var snapshot: Dictionary = Precise.from_stats(source)
		_expect(snapshot.has(Precise.STAT) and not Precise.snapshot_error(snapshot).is_empty(), "Malformed source flag survives for rejection: " + str(invalid))
		_expect(not Precise.active(snapshot) and Precise.profile(snapshot).is_empty() and Precise.attack_modifier(snapshot).is_empty(), "Malformed source cannot activate either effect")
		_expect(var_to_bytes(source) == before, "Malformed source read leaves original untouched")
	var nested: Dictionary = {Precise.STAT: {"nested": [1]}}
	var captured: Dictionary = Precise.from_stats(nested)
	captured[Precise.STAT].invalid_source_flag.nested.append(2)
	_expect(nested[Precise.STAT].nested == [1], "Malformed source is deeply detached")
	for partial: Dictionary in [{Precise.STAT: 1}, {Precise.STAT: 1, "accuracy": 201.0}, {Precise.STAT: 1, "max_health": 200.0}]:
		_expect(not Precise.snapshot_error(Precise.from_stats(partial)).is_empty(), "Selected source requires both final stats")
	completed = true


func _adjacent(value: float, step: int) -> float:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_u64(0, bytes.decode_u64(0) + step)
	return bytes.decode_double(0)


func _strict_boundaries() -> void:
	for max_health: float in [1.0, 200.0, 1024.0, 1.0e-300, 1.0e308]:
		for row: Array in [[_adjacent(max_health, -1), false], [max_health, false], [_adjacent(max_health, 1), true]]:
			var snapshot: Dictionary = _context(row[0], max_health)
			var before: PackedByteArray = var_to_bytes(snapshot)
			var policy: Dictionary = Precise.profile(snapshot)
			_expect(policy == {"enabled": true, "accuracy": row[0], "max_health": max_health,
				"condition_met": row[1], "attack_more": 0.4 if row[1] else 0.0,
				"cannot_deal_critical_strikes": true}, "Strict comparison distinguishes equality and adjacent representable doubles")
			_expect(Precise.active(snapshot) and policy.cannot_deal_critical_strikes, "Critical ban remains active on either side of comparison")
			_expect(Precise.attack_modifier(snapshot).is_empty() != bool(row[1]), "MORE exists only strictly above life")
			policy.accuracy = 0.0; policy.cannot_deal_critical_strikes = false
			_expect(var_to_bytes(snapshot) == before and Precise.profile(snapshot).cannot_deal_critical_strikes, "Profile writes cannot change captured context or future profile")
	_expect(Precise.active(_context(0, 1)) and not Precise.profile(_context(0, 1)).condition_met, "Zero accuracy remains a valid selected keystone")
	completed = true


func _malformed_context() -> void:
	for invalid: Variant in [null, true, false, 0, 1, 0.0, 1.0, "1", [], {},
		{"accuracy": 201}, {"max_health": 200}, {"accuracy": 201, "max_health": 200, "extra": 0},
		{&"accuracy": 201, "max_health": 200}, {"accuracy": 201, &"max_health": 200}]:
		var snapshot: Dictionary = {Precise.STAT: invalid}
		_expect(not Precise.snapshot_error(snapshot).is_empty() and not Precise.active(snapshot), "Snapshot requires exact two named String fields")
		_expect(Precise.profile(snapshot).is_empty() and Precise.attack_modifier(snapshot).is_empty(), "Invalid snapshot fails closed")
	for key: String in ["accuracy", "max_health"]:
		for invalid: Variant in [null, true, false, "201", [], {}, NAN, INF, -INF, -0.00000001]:
			var snapshot: Dictionary = _context()
			snapshot[Precise.STAT][key] = invalid
			_expect(not Precise.snapshot_error(snapshot).is_empty(), "Context rejects coercible and nonfinite fields: " + key)
			var source: Dictionary = {Precise.STAT: 1, "accuracy": 201.0, "max_health": 200.0}
			source[key] = invalid
			_expect(not Precise.snapshot_error(Precise.from_stats(source)).is_empty(), "Malformed final stats survive source capture: " + key)
	for value: Variant in [0, 0.0, -0.0]:
		_expect(not Precise.snapshot_error(_context(1, value)).is_empty(), "Maximum life must be strictly positive")
		_expect(Precise.snapshot_error(_context(value, 1)).is_empty(), "Accuracy permits zero")
	var source: Dictionary = {Precise.STAT: 1, "accuracy": {"nested": [1]}, "max_health": 200.0}
	var snapshot: Dictionary = Precise.from_stats(source)
	snapshot[Precise.STAT].accuracy.nested.append(2)
	_expect(source.accuracy.nested == [1], "Malformed final stat collection is deeply detached")
	completed = true


func _modifier_scope() -> void:
	var modifier: Dictionary = Precise.attack_modifier(_context())
	_same(modifier, {"id": "precise_technique_attack_more", "mode": "more", "value": 0.4,
		"all_tags": ["hit", "attack"], "skills": [], "damage_types": []}, "One canonical unrestricted-type attack hit MORE modifier")
	for tags: Array in TAGS:
		for type: String in Damage.TYPES:
			var packet: Dictionary = Damage.packet({type: 100.0}, tags, "any_skill")
			var allowed: bool = tags.has("hit") and tags.has("attack")
			_expect(Damage.matches(modifier, packet, type) == allowed, "Only actual attack-hit packet tags receive MORE: " + type)
			_near(Damage.resolve(packet, [modifier]).total, 140.0 if allowed else 100.0, "Attack MORE applies to every typed component, never spell or secondary scope")
	var recipe: Dictionary = {"stage": "hit_base", "intrinsic_distribution": {"physical": 0.5, "fire": 0.5},
		"base_coefficient": 1.0, "added_effectiveness": 1.0, "tags": ["hit", "attack", "projectile"], "skill_id": "tornado", "role": "parent"}
	var packet: Dictionary = Conversion.apply(Base.assemble(200.0, recipe), 0.4)
	var modifiers: Array = [modifier, {"id": "increase", "mode": "increased", "value": 0.25},
		{"id": "focus", "mode": "more", "value": 0.2}, {"id": "focus", "mode": "more", "value": -0.2}]
	var resolved: Dictionary = Damage.resolve(packet, modifiers)
	_near(resolved.total, 200.0 * 1.25 * 1.4 * 1.2 * 0.8, "Separate MORE clauses multiply after additive increases")
	for detail: Dictionary in resolved.details:
		for part: Dictionary in detail.parts:
			_expect(part.modifiers.count("precise_technique_attack_more") == 1 and part.modifier_indices.count(0) == 1, "Converted physical/fire lineage applies the same unrestricted entry only once")
			_near(part.more, 1.4 * 1.2 * 0.8, "Native and converted pieces have identical unrestricted MORE products")
	modifier.all_tags.append("spell"); modifier.damage_types.append("fire")
	_expect(Precise.attack_modifier(_context()).all_tags == ["hit", "attack"] and Precise.attack_modifier(_context()).damage_types.is_empty(), "Returned modifier scopes are fresh detached arrays")
	var snapshot: Dictionary = _context()
	_expect(not Resolute.active(snapshot), "Precise does not imply cannot-evade")
	_same(Attack.resolve(201.0, 99999.0, 50.0, Resolute.active(snapshot)), Attack.resolve(201.0, 99999.0, 50.0), "Precise leaves accuracy/evasion admission unchanged")
	completed = true


func _validation_precedence() -> void:
	var malformed: Array = [null, {}, {"base_chance": 0.05}, {"base_chance": NAN, "base_multiplier": 1.5},
		{"base_chance": 0.05, "base_multiplier": 1.5, "unknown": 0},
		{"base_chance": 1.0, "base_multiplier": 1000.0, "crit_multiplier_add": 1000000.0}]
	for invalid: Variant in malformed:
		for tags: Array in TAGS:
			for has_secondary: bool in [false, true]:
				var source: Dictionary = {"critical_modifiers": invalid, "resolute_technique": "bad", Precise.STAT: "bad"}
				_same(Critical.compile(source, tags, has_secondary), OldCritical.compile(source, tags, has_secondary), "Old critical source/derived validation and Resolute errors keep precedence")
	for tags: Array in TAGS:
		var source: Dictionary = _critical_source()
		source[Precise.STAT] = "bad"
		var result: Dictionary = Critical.compile(source, tags, true)
		_expect(not result.ok and result.critical.is_empty() and result.error == Precise.snapshot_error(source), "Precise validates after old rules, including non-hit input")
		source.resolute_technique = "bad"
		_expect(Critical.compile(source, tags, true).error == Resolute.snapshot_error(source), "Resolute error remains ahead of Precise context error")
	var overflow: Dictionary = _critical_source()
	overflow.critical_modifiers.base_multiplier = 1000.0
	overflow.critical_modifiers.crit_multiplier_add = 1000000.0
	overflow.merge(_context())
	_expect(Critical.compile(overflow, ["hit", "attack"], true) == OldCritical.compile(overflow, ["hit", "attack"], true), "Selected keystone never hides invalid derived critical multiplier")
	completed = true


func _critical_union() -> void:
	for accuracy: float in [0.0, 200.0, 201.0]:
		for has_sources: bool in [false, true]:
			for has_secondary: bool in [false, true]:
				for tags: Array in TAGS:
					var snapshot: Dictionary = _critical_source() if has_sources else {}
					var old: Dictionary = OldCritical.compile(snapshot, tags, has_secondary)
					snapshot.merge(_context(accuracy))
					var before: PackedByteArray = var_to_bytes(snapshot)
					var result: Dictionary = Critical.compile(snapshot, tags, has_secondary)
					_expect(result.ok, "Every valid selected condition compiles")
					if not tags.has("hit"):
						_same(result, old, "Non-hit guard keeps old empty critical profiles")
					else:
						_expect(result.critical.size() == (2 if has_secondary else 1), "Only requested primary/secondary profiles are emitted")
						for role: String in result.critical:
							var expected_multiplier: float = old.critical[role].multiplier if has_sources else 1.5
							_same(result.critical[role], {"chance": 0.0, "multiplier": expected_multiplier}, "Unconditional ban preserves validated potential multiplier")
							_expect(not Critical.roll(result.critical[role], 0.0).critical and Critical.roll(result.critical[role], 0.0).multiplier == 1.0, "Banned primary and secondary never crit even at sample zero")
					_expect(var_to_bytes(snapshot) == before, "Compiling ban does not mutate the input")
					var union: Dictionary = snapshot.duplicate(true)
					union.resolute_technique = 1.0
					_same(Critical.compile(union, tags, has_secondary), result, "Resolute union applies one zero-chance ban without duplicate arithmetic")
					_same(Critical.compile(snapshot, tags + tags, has_secondary), result, "Repeated tags cannot duplicate critical scope or ban")
	completed = true


func _legacy_rng() -> void:
	var old_runtime = OldRuntime.new()
	var runtime = Runtime.new()
	old_runtime.reset(63620); runtime.reset(63620)
	for tags: Array in TAGS:
		for has_secondary: bool in [false, true]:
			var source: Dictionary = _critical_source()
			_same(Critical.compile(source, tags, has_secondary), OldCritical.compile(source, tags, has_secondary), "Absent keystone retains full independent old critical bytes")
			for zero: Variant in [0, 0.0, -0.0]:
				source.merge(Precise.from_stats({Precise.STAT: zero}))
				_same(Critical.compile(source, tags, has_secondary), OldCritical.compile(source, tags, has_secondary), "Zero source retains full old critical bytes")
	var raw: Dictionary = _critical_source()
	var old_cast: Dictionary = {"critical": OldCritical.compile(raw, ["hit", "attack"], true).critical, "packet": {"damage": 20.0}}
	var current_cast: Dictionary = {"critical": Critical.compile(raw, ["hit", "attack"], true).critical, "packet": {"damage": 20.0}}
	for index: int in range(16):
		var role: String = "primary" if index % 2 == 0 else "secondary"
		_same(runtime.freeze(current_cast, role), old_runtime.freeze(old_cast, role), "Unselected actual frozen critical rolls match independent baseline")
		_same(runtime.checkpoint(), old_runtime.checkpoint(), "Unselected private draw/event/state bytes match baseline")
	_expect(runtime.draws == 16 and runtime.events == 16, "Ordinary positive chances still draw exactly once per accepted critical event")
	for accuracy: float in [0.0, 200.0, 201.0]:
		var selected: Dictionary = raw.duplicate(true)
		selected.merge(_context(accuracy))
		selected.critical = Critical.compile(selected, ["hit", "spell"], true).critical
		var checkpoint: Dictionary = runtime.checkpoint()
		for role: String in ["primary", "secondary"]:
			selected.critical_roll = {"critical": true, "multiplier": 9.0, "chance": 1.0}
			var before: PackedByteArray = var_to_bytes(selected)
			var frozen: Dictionary = runtime.freeze(selected, role)
			_expect(frozen.ok and not frozen.snapshot.has("critical_roll"), "Existing zero-chance runtime clears inherited roll for both selected conditions")
			_same(runtime.checkpoint(), checkpoint, "Selected cast consumes zero private draws and events")
			_expect(var_to_bytes(selected) == before, "Clearing inherited roll preserves input bytes")
			selected.erase("critical_roll")
			_same(runtime.freeze(selected, role).snapshot, selected, "Fresh selected freeze keeps exact cast bytes")
			_same(runtime.checkpoint(), checkpoint, "Fresh selected freeze also consumes zero private draws")
	_same(runtime.freeze(current_cast), old_runtime.freeze(old_cast), "Old cast created before allocation resumes original roll stream")
	_same(runtime.checkpoint(), old_runtime.checkpoint(), "Later ordinary cast reaches exact baseline checkpoint after zero-draw casts")
	completed = true


func _compiler_attachment() -> void:
	var old_stats: Dictionary = _stats()
	var ordinary: Dictionary = Combat.snapshot(old_stats, [])
	for zero: Variant in [0, 0.0, -0.0]:
		var zero_stats: Dictionary = old_stats.duplicate(true)
		zero_stats[Precise.STAT] = zero
		_same(Combat.snapshot(zero_stats, []), ordinary, "Zero source leaves current complete raw snapshot byte-identical to absence")
		_same(Compiler.compile_basic(Combat.snapshot(zero_stats, [])), Compiler.compile_basic(ordinary), "Zero source leaves complete basic compilation bytes unchanged")
	for accuracy: float in [0.0, 200.0, 201.0]:
		var source: Dictionary = _stats()
		source[Precise.STAT] = 1
		source.accuracy = accuracy
		var raw: Dictionary = Combat.snapshot(source, [])
		var expected_count: int = 1 if accuracy > source.max_health else 0
		_expect(_modifier_count(raw) == expected_count, "Combat snapshot appends the enabled MORE entry exactly once")
		for skill: String in ["basic", "tornado", "cleave", "bolt", "frost", "shade_bolt", "nova", "meteor", "chain", "dash", "ward"]:
			var cast: Dictionary = Compiler.compile_basic(raw) if skill == "basic" else Compiler.compile_group(skill, raw, [])
			_expect(cast.ok, "Selected valid source compiles every skill: " + skill)
			if not cast.ok:
				continue
			_expect(_modifier_count(cast.snapshot) == expected_count, "Compiler never adds the Precise MORE a second time: " + skill)
			_same(cast.snapshot[Precise.STAT], raw[Precise.STAT], "Compiler freezes final context: " + skill)
			for role: String in cast.snapshot.get("critical", {}):
				_expect(cast.snapshot.critical[role].chance == 0.0, "Every compiled skill primary/secondary has zero critical chance")
			cast.snapshot[Precise.STAT].accuracy = 999.0
			_expect(raw[Precise.STAT].accuracy == accuracy, "Compiled context is detached from raw source")
	completed = true


func _modifier_count(snapshot: Dictionary) -> int:
	var count: int = 0
	for modifier: Dictionary in snapshot.modifiers:
		if modifier.get("id") == "precise_technique_attack_more":
			count += 1
	return count
