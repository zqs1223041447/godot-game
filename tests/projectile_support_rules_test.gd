extends SceneTree
## Standalone extension contracts using the real compiler, resolver and runtime.
## This fixture composes the extension explicitly; the game is not integrated yet.
const Rules = preload("res://scripts/combat/projectile_support_rules.gd")
const Data = preload("res://scripts/game_data.gd")
const Legacy = preload("res://scripts/combat/support_catalog.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")

var checks: int = 0
var failures: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_case(_test_metadata, "metadata and corruption")
	_case(_test_composition, "legacy composition and detached results")
	_case(_test_rejections, "complete validation and atomic rejection")
	_case(_test_damage_scope, "typed damage and secondary/basic boundaries")
	_case(_test_serial_targets, "real serial-target hit budgets")
	_case(_test_phase_ledger, "one hit per enemy per phase")
	_case(_test_return_budget, "return keeps remaining pierce budget")
	_case(_test_end_boundaries, "range, lifetime, contact and explosion precedence")
	_case(_test_runtime_detachment, "frozen shots and unrelated carriers")
	print("Projectile support extension: %d checks, %d failures" % [checks, failures])
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


func _snapshot(effects: Array = []) -> Dictionary:
	return Combat.snapshot({"damage": 100.0, "global_increased": 0.2,
		"projectile_increased": 0.3, "spell_increased": 0.4, "fire_increased": 0.1,
		"spell_added_cold": 8.0, "spell_added_lightning": 12.0}, effects)


func _recipe(skill_id: String) -> Dictionary:
	return Data.SKILLS[skill_id].projectile_recipe.duplicate(true)


## Test-only composition, matching the documented future integration seam.
func _cast(skill_id: String, ids: Array, effects: Array = []) -> Dictionary:
	var legacy_ids: Array = []
	for id: Variant in ids:
		if id is String and Legacy.SUPPORTS.has(id):
			legacy_ids.append(id)
	var base: Dictionary = Compiler.compile_skill(skill_id, _snapshot(effects), legacy_ids)
	_expect(base.ok, "Legacy compiler accepts fixture: " + skill_id)
	if not base.ok:
		return {}
	var extension: Dictionary = Rules.compile_extension(skill_id, base.recipe, ids)
	_expect(extension.error.is_empty(), "Extension accepts fixture: %s %s" % [skill_id, ids])
	if not extension.error.is_empty():
		return {}
	base.recipe = extension.recipe
	base.snapshot.modifiers.append_array(extension.modifiers)
	base.mana *= float(extension.mana_multiplier)
	return base


func _shot(runtime: RefCounted, cast: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	# main._shoot uses range 650, lifetime 1.7, runtime default radius 5.5.
	var spec: Dictionary = {"speed": cast.recipe.speed, "pierce": cast.recipe.pierce,
		"slow": cast.recipe.slow, "range": 650.0, "lifetime": 1.7}
	spec.merge(overrides, true)
	return runtime.make_projectile(Vector2.ZERO, Vector2.RIGHT, spec,
		cast.packets.projectile, cast.snapshot, runtime.new_cast(), Color.WHITE)


func _target(id: int, x: float, radius: float = 0.0) -> Dictionary:
	return {"id": id, "pos": Vector2(x, 0.0), "radius": radius, "health": 10000.0, "spawn": 0.0}


func _events(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.type == type:
			result.append(event)
	return result


func _hit_ids(events: Array[Dictionary]) -> Array[int]:
	var ids: Array[int] = []
	for event: Dictionary in _events(events, "hit"):
		ids.append(int(event.target_id))
	return ids


func _test_metadata() -> void:
	_expect(Rules.SUPPORTS.keys() == ["pierce"], "Stable extension ID is pierce")
	var definition: Dictionary = Rules.get_definition("pierce")
	_expect(definition.name == "贯穿辅助" and Rules.definition_error(definition).is_empty(), "Metadata validates")
	_expect(definition.skills == ["bolt", "frost"], "One metadata authority declares eligible skills")
	_expect(definition.operations == [{"op": "add_pierce", "value": 2},
		{"op": "projectile_hit_more", "value": -0.15}, {"op": "mana_multiplier", "value": 1.20}], "Authored operations match requested balance")
	_expect(Rules.get_definition("unknown").is_empty(), "Unknown metadata is empty")
	for id: String in Data.SKILLS:
		_expect(Rules.supports_for_skill(id) == (["pierce"] if id in ["bolt", "frost"] else []), "Metadata eligibility: " + id)
	_expect(Rules.supports_for_skill("basic").is_empty(), "Basic has no extension support")
	definition.operations[0].value = 99
	definition.skills.clear()
	definition.requires.clear()
	_expect(Rules.get_definition("pierce").operations[0].value == 2, "Nested metadata does not alias authoritative operations")
	_expect(Rules.get_definition("pierce").skills == ["bolt", "frost"], "Metadata skill list is detached")
	for invalid: Variant in [null, [], "pierce", {}, 1]:
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject wrong metadata type")
	for key: String in ["name", "description", "skills", "requires", "operations"]:
		var missing: Dictionary = Rules.get_definition("pierce")
		missing.erase(key)
		_expect(not Rules.definition_error(missing).is_empty(), "Reject missing metadata field " + key)
	for change: Array in [["name", ""], ["description", 2], ["skills", []], ["skills", ["tornado"]],
		["skills", ["bolt", "bolt"]], ["requires", ["projectile_hit"]], ["requires", ["projectile_hit", "projectile_hit"]],
		["requires", ["finite_projectile_pierce", "unknown"]], ["operations", []], ["extra", true]]:
		var invalid: Dictionary = Rules.get_definition("pierce")
		invalid[change[0]] = change[1]
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject metadata corruption " + str(change))
	for operation: Variant in [null, {}, {"op": "add_pierce", "value": 2, "extra": true},
		{"op": "unknown", "value": 2}, {"op": "mana_multiplier", "value": 1.2},
		{"op": "add_pierce", "value": "2"}, {"op": "add_pierce", "value": true},
		{"op": "add_pierce", "value": -1}, {"op": "add_pierce", "value": 0},
		{"op": "add_pierce", "value": 0.5}, {"op": "add_pierce", "value": 101},
		{"op": "add_pierce", "value": NAN}, {"op": "add_pierce", "value": INF}]:
		var invalid: Dictionary = Rules.get_definition("pierce")
		invalid.operations[0] = operation
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject operation corruption " + str(operation))
	for bad: Variant in [-1.0, -1.1, 1.01, NAN, INF, false]:
		var invalid: Dictionary = Rules.get_definition("pierce")
		invalid.operations[1].value = bad
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject invalid damage factor")
	for bad: Variant in [0, -1, 10.1, NAN, INF, "1.2"]:
		var invalid: Dictionary = Rules.get_definition("pierce")
		invalid.operations[2].value = bad
		_expect(not Rules.definition_error(invalid).is_empty(), "Reject invalid mana factor")
	completed = true


func _test_composition() -> void:
	for skill: String in ["bolt", "frost"]:
		var recipe: Dictionary = _recipe(skill)
		var before: Dictionary = recipe.duplicate(true)
		var empty: Dictionary = Rules.compile_extension(skill, recipe, [])
		_expect(empty.recipe == recipe and empty.modifiers.is_empty() and empty.error.is_empty(), "Empty extension is a validated no-op")
		_near(empty.mana_multiplier, 1.0, "Empty extension cost unchanged")
		empty.recipe.pierce = 50
		_expect(recipe == before, "Even empty result owns its recipe")
		var ids: Array = ["pierce"]
		var first: Dictionary = Rules.compile_extension(skill, recipe, ids)
		var second: Dictionary = Rules.compile_extension(skill, recipe, ids)
		_expect(first == second, "Fresh-base compilation is deterministic")
		_expect(recipe == before and ids == ["pierce"], "Compilation leaves inputs unchanged")
		var stripped: Dictionary = first.recipe.duplicate(true)
		stripped.erase(Rules.APPLIED_KEY)
		stripped.pierce -= 2
		_expect(stripped == before, "Only pierce and re-entry marker change in recipe")
		_expect(first.modifiers == [{"id": "support:pierce", "mode": "more", "value": -0.15,
			"all_tags": ["hit", "projectile"], "skills": [skill], "damage_types": []}], "Exact resolver-compatible scope")
		_near(first.mana_multiplier, 1.2, "Pierce mana multiplier")
		first.recipe.pierce = 99
		first.recipe[Rules.APPLIED_KEY].clear()
		first.modifiers[0].all_tags.clear()
		first.modifiers[0].skills.clear()
		ids.clear()
		_expect(second == Rules.compile_extension(skill, recipe, ["pierce"]), "Nested outputs and sibling results do not alias")
		for legacy_ids: Array in [[], ["volley"], ["focus"], ["volley", "focus"]]:
			var base: Dictionary = Compiler.compile_skill(skill, _snapshot(), legacy_ids)
			var noop: Dictionary = Rules.compile_extension(skill, base.recipe, legacy_ids)
			_expect(noop.error.is_empty() and noop.recipe == base.recipe and noop.modifiers.is_empty(), "Legacy-only selection is validated without reapplication")
			_near(noop.mana_multiplier, 1.0, "Legacy-only cost belongs to original compiler")
			if legacy_ids.size() == 2:
				continue
			var all_ids: Array = legacy_ids.duplicate()
			all_ids.append("pierce")
			var extension: Dictionary = Rules.compile_extension(skill, base.recipe, all_ids)
			all_ids.reverse()
			_expect(extension == Rules.compile_extension(skill, base.recipe, all_ids), "Entire extension result is order-independent")
			var supported: Dictionary = _cast(skill, all_ids)
			_expect(supported.initial_count == base.initial_count and supported.recipe.initial_count == base.recipe.initial_count,
				"Pierce preserves compiler initial count, including volley")
			_expect(supported.recipe.pierce == int(base.recipe.pierce) + 2, "Pierce adds to actual recipe budget")
			_near(supported.mana, float(base.mana) * 1.2, "Legacy and extension mana multiply once")
			_near(Damage.resolve(supported.packets.projectile, supported.snapshot.modifiers).total,
				Damage.resolve(base.packets.projectile, base.snapshot.modifiers).total * 0.85, "Existing more and extension less multiply once")
			_expect(supported.packets == base.packets, "No raw packet coefficient or added-effectiveness changes")
		_near(_cast(skill, ["pierce"]).mana, float(Data.SKILLS[skill].mana) * 1.2, "Base mana uses same-source skill cost")
	for amount: int in [0, 3, 98]:
		var recipe: Dictionary = _recipe("bolt")
		recipe.pierce = amount
		var result: Dictionary = Rules.compile_extension("bolt", recipe, ["pierce"])
		_expect(result.error.is_empty() and result.recipe.pierce == amount + 2, "Non-default finite recipe adds exactly two")
	var json_recipe: Dictionary = JSON.parse_string(JSON.stringify(_recipe("frost")))
	_expect(Rules.compile_extension("frost", json_recipe, ["pierce"]).error.is_empty(), "Integer-valued JSON floats follow legacy recipe semantics")
	completed = true


func _rejected(skill: Variant, recipe: Variant, ids: Variant) -> void:
	# Serialized equality handles NaN and captures nested caller-owned containers.
	var before: PackedByteArray = var_to_bytes([skill, recipe, ids])
	var result: Dictionary = Rules.compile_extension(skill, recipe, ids)
	_expect(result.size() == 4 and result.has_all(["recipe", "modifiers", "mana_multiplier", "error"]), "Failure preserves stable API shape")
	_expect(result.error is String and not result.error.is_empty(), "Invalid extension fails with reason")
	_expect(result.recipe == {} and result.modifiers == [] and result.mana_multiplier == 1.0, "Failure exposes no partial effects")
	_expect(before == var_to_bytes([skill, recipe, ids]), "Invalid input has no side effects")


func _test_rejections() -> void:
	var catalogs: PackedByteArray = var_to_bytes([Data.SKILLS, Combat.TORNADO, Legacy.SUPPORTS, Rules.SUPPORTS])
	for skill: Variant in [null, 1, true, [], {}, "", "unknown", "basic", "nova", "meteor", "chain", "dash", "ward", "tornado"]:
		_rejected(skill, _recipe("bolt"), ["pierce"])
	_rejected("tornado", Combat.TORNADO.duplicate(true), ["pierce"])
	for ids: Variant in [null, "pierce", 1, {}, PackedStringArray(["pierce"]), [null], [true], [1], [["pierce"]],
		[""], ["unknown"], ["pierce", "unknown"], ["unknown", "pierce"], ["pierce", "pierce"],
		["focus", "focus"], ["volley", "focus", "pierce"]]:
		_rejected("bolt", _recipe("bolt"), ids)
	for recipe: Variant in [null, [], "recipe", 1, {}, Combat.TORNADO.duplicate(true)]:
		_rejected("bolt", recipe, ["pierce"])
	for key: String in _recipe("bolt"):
		var missing: Dictionary = _recipe("bolt")
		missing.erase(key)
		_rejected("bolt", missing, ["pierce"])
	for key: String in ["initial_count", "pierce", "spread", "coefficient", "added_effectiveness", "slow", "speed"]:
		for invalid: Variant in [null, true, "1", {}, [], NAN, INF, -INF]:
			var recipe: Dictionary = _recipe("bolt")
			recipe[key] = invalid
			_rejected("bolt", recipe, ["pierce"])
	for change: Array in [["initial_count", 0], ["initial_count", 10], ["initial_count", 1.5],
		["pierce", -2], ["pierce", -1], ["pierce", 0.5], ["pierce", 99], ["pierce", 100], ["pierce", 101],
		["spread", -0.1], ["coefficient", -1], ["added_effectiveness", -1], ["slow", -1], ["speed", 0],
		["damage_type", "unknown"], ["damage_type", 1], ["extra", {}]]:
		var recipe: Dictionary = _recipe("bolt")
		recipe[change[0]] = change[1]
		_rejected("bolt", recipe, ["pierce"])
	var bad_empty: Dictionary = _recipe("bolt")
	bad_empty.speed = 0
	_rejected("bolt", bad_empty, [])
	for amount: int in [-1, 100]:
		var recipe: Dictionary = _recipe("bolt")
		recipe.pierce = amount
		var noop: Dictionary = Rules.compile_extension("bolt", recipe, [])
		_expect(noop.error.is_empty() and noop.recipe == recipe, "No-op preserves legacy infinite/upper-bound recipe")
	var result: Dictionary = Rules.compile_extension("bolt", _recipe("bolt"), ["pierce"])
	_rejected("bolt", result.recipe, ["pierce"])
	_rejected("bolt", result.recipe, [])
	for marker: Variant in [null, false, "", [], ["pierce"]]:
		var recipe: Dictionary = _recipe("bolt")
		recipe[Rules.APPLIED_KEY] = marker
		_rejected("bolt", recipe, ["pierce"])
	var decorated: Dictionary = _cast("bolt", ["pierce"])
	_expect(not Compiler.compile_skill("bolt", decorated.snapshot, []).ok, "Original compiler also rejects decorated snapshot re-entry")
	_expect(var_to_bytes([Data.SKILLS, Combat.TORNADO, Legacy.SUPPORTS, Rules.SUPPORTS]) == catalogs, "Every rejected input preserves all shared catalogs")
	completed = true


func _test_damage_scope() -> void:
	for skill: String in ["bolt", "frost"]:
		var base: Dictionary = _cast(skill, [])
		var supported: Dictionary = _cast(skill, ["pierce"])
		var defenses: Dictionary = {"cold": 0.25, "lightning": 0.5, "fire": 0.1}
		var before: Dictionary = Damage.resolve(base.packets.projectile, base.snapshot.modifiers, defenses)
		var after: Dictionary = Damage.resolve(supported.packets.projectile, supported.snapshot.modifiers, defenses)
		_near(after.total, float(before.total) * 0.85, "Real typed spell hit includes less exactly once")
		for type: String in before.components:
			_near(after.components[type], float(before.components[type]) * 0.85, "All assembled typed components get same more factor")
		_near(Damage.resolve(supported.packets.secondary, supported.snapshot.modifiers, defenses).total,
			Damage.resolve(base.packets.secondary, base.snapshot.modifiers, defenses).total, "Same-skill independently assembled explosion excludes pierce")
		_expect(not supported.packets.secondary.tags.has("projectile"), "Secondary carries its own delivery tags")
		var all_types: Dictionary = {"physical": 10.0, "fire": 20.0, "cold": 30.0, "lightning": 40.0, "chaos": 50.0}
		for packet: Dictionary in [Damage.packet(all_types, ["hit", "projectile", "attack"], "basic"),
			Damage.packet(all_types, ["hit", "projectile"], "frost" if skill == "bolt" else "bolt"),
			Damage.packet(all_types, ["projectile"], skill), Damage.packet(all_types, ["hit"], skill),
			Damage.packet(all_types, ["hit", "area", "secondary", "explosion"], skill)]:
			_near(Damage.resolve(packet, supported.snapshot.modifiers, defenses).total,
				Damage.resolve(packet, base.snapshot.modifiers, defenses).total, "Basic/wrong-skill/nonhit/nonprojectile boundaries preserve damage")
	completed = true


func _test_serial_targets() -> void:
	for indexed: bool in [false, true]:
		for skill: String in ["bolt", "frost"]:
			for ids: Array in [[], ["pierce"]]:
				for deltas: Array in [[1.0], [0.03, 0.07, 0.2, 0.7]]:
					var cast: Dictionary = _cast(skill, ids, ["return_on_range", "explode_on_flight_end"])
					var runtime = Runtime.new()
					runtime.use_spatial_index = indexed
					var shot: Dictionary = _shot(runtime, cast)
					var shots: Array[Dictionary] = [shot]
					var targets: Array[Dictionary] = []
					# Opposite input order proves contacts follow geometry, not array order.
					for id: int in range(7, 0, -1):
						targets.append(_target(id, id * 50.0))
					var events: Array[Dictionary] = []
					for delta: float in deltas:
						events.append_array(runtime.advance(shots, delta, targets, Vector2.ZERO, 100))
					var expected_count: int = int(cast.recipe.pierce) + 1
					_expect(_hit_ids(events) == range(1, expected_count + 1), "Serial hits equal actual recipe.pierce + 1 in geometric order")
					_expect(expected_count == int(_recipe(skill).pierce) + 1 + (2 if ids.has("pierce") else 0), "Extension increases hit capacity by exactly two")
					_expect(shots.is_empty() and shot.end_reason == "hit_consumed", "Exhausted pierce terminates carrier")
					_expect(_events(events, "terminated").size() == 1 and _events(events, "return_started").is_empty(), "Contact consumption wins before return")
					_expect(_events(events, "explosion").is_empty() and _events(events, "flight_ended").is_empty(), "Hit-consumed carrier never triggers natural-end explosion")
					for event: Dictionary in _events(events, "hit"):
						_near(Damage.resolve(event.payload, event.snapshot.modifiers).total,
							Damage.resolve(cast.packets.projectile, cast.snapshot.modifiers).total, "Real hit event carries exactly compiled damage")
	completed = true


func _test_phase_ledger() -> void:
	for skill: String in ["bolt", "frost"]:
		var runtime = Runtime.new()
		var cast: Dictionary = _cast(skill, ["pierce"], ["return_on_range", "explode_on_flight_end"])
		var shot: Dictionary = _shot(runtime, cast, {"speed": 100.0, "range": 100.0, "lifetime": 3.0, "radius": 0.0})
		var shots: Array[Dictionary] = [shot]
		var targets: Array[Dictionary] = [_target(42, 50.0, 10.0)]
		var events: Array[Dictionary] = []
		for delta: float in [0.4, 0.01, 0.02, 0.02]:
			events.append_array(runtime.advance(shots, delta, targets, Vector2.ZERO, 100))
		_expect(_hit_ids(events) == [42], "Overlapping target is hit only once across outbound frames")
		_expect(shot.pierce == int(cast.recipe.pierce) - 1, "Ignored repeat contact never consumes another pierce")
		events.append_array(runtime.advance(shots, 0.55, targets, Vector2.ZERO, 100))
		_expect(shot.state == "returning", "Range transitions to return phase")
		events.append_array(runtime.advance(shots, 0.45, targets, Vector2.ZERO, 100))
		events.append_array(runtime.advance(shots, 0.01, targets, Vector2.ZERO, 100))
		events.append_array(runtime.advance(shots, 0.02, targets, Vector2.ZERO, 100))
		var hits: Array[Dictionary] = _events(events, "hit")
		_expect(_hit_ids(events) == [42, 42] and hits[0].phase == "outbound" and hits[1].phase == "returning", "Same enemy can be hit once in each phase")
		_expect(shot.hit_ledger == {"outbound:42": true, "returning:42": true}, "Runtime ledger records two phase-scoped keys")
		_expect(shot.pierce == int(cast.recipe.pierce) - 2, "Return uses remaining finite pierce, never resets it")
		events.append_array(runtime.advance(shots, 2.0, targets, Vector2.ZERO, 100))
		_expect(_hit_ids(events) == [42, 42] and _events(events, "return_started").size() == 1, "No further hit or return re-entry")
		_expect(_events(events, "explosion").size() == 1 and shot.end_reason == "lifetime_expired", "Unused pierce still obeys original lifetime and one explosion")
	completed = true


func _test_return_budget() -> void:
	for skill: String in ["bolt", "frost"]:
		for deltas: Array in [[3.0], [0.25, 0.5, 0.25, 0.25, 0.5, 1.25]]:
			var runtime = Runtime.new()
			var cast: Dictionary = _cast(skill, ["pierce"], ["return_on_range", "explode_on_flight_end"])
			var shot: Dictionary = _shot(runtime, cast, {"speed": 100.0, "range": 100.0, "lifetime": 3.0, "radius": 0.0})
			var shots: Array[Dictionary] = [shot]
			var targets: Array[Dictionary] = [_target(3, 75), _target(1, 25), _target(2, 50)]
			var events: Array[Dictionary] = []
			for delta: float in deltas:
				events.append_array(runtime.advance(shots, delta, targets, Vector2.ZERO, 100))
			var hits: Array[Dictionary] = _events(events, "hit")
			_expect(_hit_ids(events) == ([1, 2, 3, 3] if skill == "bolt" else [1, 2, 3, 3, 2]), "Return spends only remaining hit capacity")
			_expect(hits.size() == int(cast.recipe.pierce) + 1, "Lifetime hit budget remains recipe.pierce + 1 across phases")
			_expect(hits[2].phase == "outbound" and hits[3].phase == "returning", "Return permits a second hit on a previously hit enemy")
			_expect(_events(events, "return_started").size() == 1 and shot.end_reason == "hit_consumed", "Return does not replenish pierce")
			_expect(_events(events, "explosion").is_empty(), "Consumption on return also excludes explosion")
	completed = true


func _test_end_boundaries() -> void:
	for skill: String in ["bolt", "frost"]:
		var base: Dictionary = _cast(skill, [], ["explode_on_flight_end"])
		var cast: Dictionary = _cast(skill, ["pierce"], ["explode_on_flight_end"])
		for ending: String in ["range", "lifetime", "tie"]:
			var runtime = Runtime.new()
			var shot: Dictionary = _shot(runtime, cast, {"speed": 100.0, "radius": 0.0,
				"range": 1000.0 if ending == "lifetime" else 100.0, "lifetime": 2.0 if ending == "range" else 1.0})
			var shots: Array[Dictionary] = [shot]
			var events: Array[Dictionary] = runtime.advance(shots, 3.0, [_target(1, 50), _target(2, 100), _target(3, 150)], Vector2.ZERO, 100)
			_expect(_hit_ids(events) == ([1, 2] if ending == "range" else [1]), "Range is inclusive; lifetime excludes exact-deadline hit")
			var blasts: Array[Dictionary] = _events(events, "explosion")
			_expect(blasts.size() == 1 and _events(events, "flight_ended").size() == 1, "Natural end creates one independent explosion")
			_expect(shot.end_reason == ("range_consumed" if ending == "range" else "lifetime_expired"), "Lifetime wins range tie")
			_near(Damage.resolve(blasts[0].payload, blasts[0].snapshot.modifiers).total,
				Damage.resolve(base.packets.secondary, base.snapshot.modifiers).total, "Actual runtime explosion damage is unchanged")
			_expect(runtime.advance(shots, 5.0, [], Vector2.ZERO, 100).is_empty(), "Terminal projectile cannot explode twice")
		# A last allowed contact exactly at range consumes the carrier before return/explosion.
		var runtime = Runtime.new()
		var returning: Dictionary = _cast(skill, ["pierce"], ["return_on_range", "explode_on_flight_end"])
		var shot: Dictionary = _shot(runtime, returning, {"speed": 100.0, "range": 100.0, "lifetime": 3.0, "radius": 0.0})
		var shots: Array[Dictionary] = [shot]
		var targets: Array[Dictionary] = []
		var budget: int = int(returning.recipe.pierce) + 1
		for index: int in range(1, budget + 1):
			targets.append(_target(index, index * 100.0 / budget))
		var events: Array[Dictionary] = runtime.advance(shots, 2.0, targets, Vector2.ZERO, 100)
		_expect(_events(events, "hit").size() == budget and shot.end_reason == "hit_consumed", "Last contact at range exhausts budget")
		_expect(_events(events, "return_started").is_empty() and _events(events, "explosion").is_empty(), "Consumption at range suppresses return and natural-end explosion")
		# Range/lifetime tie with both effects still expires without starting return.
		shot = _shot(runtime, returning, {"speed": 100.0, "range": 100.0, "lifetime": 1.0, "radius": 0.0})
		shots.assign([shot])
		events = runtime.advance(shots, 2.0, [_target(99, 100)], Vector2.ZERO, 100)
		_expect(_events(events, "hit").is_empty() and _events(events, "return_started").is_empty(), "Expiry tie excludes contact and return")
		_expect(_events(events, "explosion").size() == 1, "Expiry tie allows one natural-end explosion")
		shot = _shot(runtime, returning)
		shots.assign([shot])
		events = runtime.cancel_all(shots, "run_reset")
		_expect(shots.is_empty() and _events(events, "explosion").is_empty() and shot.end_reason == "run_reset", "Cancellation never emits extension explosions")
	completed = true


func _test_runtime_detachment() -> void:
	var runtime = Runtime.new()
	var cast: Dictionary = _cast("bolt", ["pierce"], ["explode_on_flight_end"])
	var shot: Dictionary = _shot(runtime, cast)
	var original: Dictionary = shot.duplicate(true)
	var shots: Array[Dictionary] = [shot]
	var targets: Array[Dictionary] = [_target(1, 50), _target(2, 100)]
	var counters: Array = [runtime.next_cast_id, runtime.next_projectile_id]
	_rejected("bolt", cast.recipe, ["pierce"])
	_rejected("bolt", _recipe("bolt"), ["pierce", "unknown"])
	_expect(shot == original and shots == [original] and [runtime.next_cast_id, runtime.next_projectile_id] == counters, "Rejected extension cannot mutate active shots or allocate runtime IDs")
	cast.recipe.pierce = 99
	cast.snapshot.modifiers[-1].value = 9.0
	cast.snapshot.effects.clear()
	cast.packets.projectile.base.lightning = 1.0
	_expect(shot == original, "Active projectile freezes recipe-derived budget, damage, effects and packet")
	var events: Array[Dictionary] = runtime.advance(shots, 2.0, targets, Vector2.ZERO, 100)
	_expect(_hit_ids(events) == [1, 2] and _events(events, "explosion").size() == 1, "Frozen projectile keeps original effect after caller mutation")
	for event: Dictionary in _events(events, "hit"):
		_near(Damage.resolve(event.payload, event.snapshot.modifiers).total, original.damage, "Frozen in-flight damage remains unchanged")
	var snapshot: Dictionary = _snapshot()
	var extension: Dictionary = Rules.compile_extension("bolt", _recipe("bolt"), ["pierce"])
	var decorated: Dictionary = snapshot.duplicate(true)
	decorated.modifiers.append_array(extension.modifiers)
	var basic: Dictionary = Combat.event_packet(snapshot, "basic", "projectile")
	shot = runtime.make_projectile(Vector2.ZERO, Vector2.RIGHT, {"speed": 100.0, "pierce": 0, "radius": 0.0}, basic, decorated, runtime.new_cast(), Color.WHITE)
	shots.assign([shot])
	events = runtime.advance(shots, 2.0, targets, Vector2.ZERO, 100)
	_expect(_hit_ids(events) == [1] and shot.end_reason == "hit_consumed", "Actual basic attack still hits just its first target")
	_near(shot.damage, Damage.resolve(basic, snapshot.modifiers).total, "Actual basic damage ignores skill-scoped extension")
	var tornado: Dictionary = Compiler.compile_skill("tornado", snapshot, [])
	var before: Dictionary = tornado.duplicate(true)
	_rejected("tornado", tornado.recipe, ["pierce"])
	_expect(tornado == before and tornado.recipe.parent.pierce == -1 and tornado.recipe.child.pierce == -1, "Tornado infinite recipes remain untouched")
	tornado.snapshot.modifiers.append_array(extension.modifiers)
	_expect(runtime.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, tornado.snapshot, 100, 1) == 1, "Unrelated tornado still spawns normally")
	events = runtime.advance(shots, 0.4, targets, Vector2.ZERO, 100)
	_expect(_events(events, "split").size() == 1 and shots.size() == 3, "Tornado retains original split behavior")
	for child: Dictionary in shots:
		_expect(child.pierce == -1, "Tornado children retain infinite pierce")
		_near(child.damage, Damage.resolve(child.payload, snapshot.modifiers).total, "Tornado damage excludes bolt extension")
	completed = true
