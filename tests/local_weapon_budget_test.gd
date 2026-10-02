extends SceneTree
## Independent production acceptance of the frozen v0.12 P4/W13 prediction.
## Real legal EquipmentCatalog instances -> equipped BuildState snapshots ->
## SkillCompiler/CombatData -> DamageResolver. No test-side damage or W formula.
const Build = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const PREDICTION_PATH = "res://docs/benchmarks/v0.13-weapon-budget-prediction.json"
const SOURCE_HEAD = "1f948911e20081edd4cd7adf96203631d45a6726"
const LEVELS = [1, 8, 16, 30]
const RARITIES = ["normal", "magic", "rare"]
const OLD_BASES = ["cinder_reed", "gale_spindle", "runewood_focus"]
const SUPPORTS = {"none": [], "volley": ["volley"], "focus": ["focus"], "both": ["volley", "focus"]}
const CONTEXTS = {"isolated": {}, "detonation_charm": {"global_increased": 0.2, "elemental_increased": 0.3}, "amplification_sensitivity": {"global_increased": 0.5, "projectile_increased": 0.5, "elemental_increased": 0.5}}
const TARGETS = {"unmitigated": {}, "emberguard": {"fire": 0.25}}
const PROJECTILE_SKILLS = ["tornado", "bolt", "frost"]
const SKILLS = ["tornado", "bolt", "frost", "nova", "meteor", "chain"]
var checks: int = 0
var failures: Array[String] = []
var evaluations: int = 0
var compiled_skills: int = 0
var prepared_instances: int = 0
var prediction: Dictionary = {}
var expected_rows: Dictionary = {}
var output: Dictionary = {}
var max_old_error: float = 0.0
var max_new_error: float = 0.0
var max_any: Dictionary = {"ratio": 0.0}
var max_rare: Dictionary = {"ratio": 0.0}
var max_weapon: float = 0.0
var stress_old: Array = []
var stress_new: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		if failures.size() <= 20:
			push_error(label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= maxf(0.0000001, absf(expected) * 0.000000001), "%s: %.12f vs %.12f" % [label, actual, expected])


func _subsets(ids: Array, count: int, start: int = 0, selected: Array = []) -> Array:
	if count == 0:
		return [selected.duplicate()]
	var result: Array = []
	for index: int in range(start, ids.size()):
		var next: Array = selected.duplicate()
		next.append(ids[index])
		result.append_array(_subsets(ids, count - 1, index + 1, next))
	return result


func _max_entry(id: String, level: int) -> Dictionary:
	var best: Dictionary = {}
	for tier: Dictionary in Catalog.affix_definition(id).tiers:
		if int(tier.level) <= level:
			best = {"id": id, "tier": tier.tier, "value": tier.max}
	return best


func _candidates(base_id: String, level: int, rarity: String) -> Array:
	var prefixes: Array = []
	var suffixes: Array = []
	for id: String in Catalog.pool_profile(Catalog.pool_for_base(base_id)).affix_ids:
		if Catalog.family_eligible(id, base_id):
			var family: Dictionary = Catalog.affix_definition(id)
			(prefixes if family.kind == "prefix" else suffixes).append(id)
	var rules: Dictionary = Catalog.RARITIES[rarity]
	var count: int = int(rules.max_affixes)
	var result: Array = []
	# Every eligible modifier is nonnegative. Maximum legal count/top unlocked
	# tier/max ticks dominate their lower-count, lower-tier and lower-tick subsets.
	for prefix_count: int in range(maxi(0, count - int(rules.max_suffixes)), mini(count, int(rules.max_prefixes)) + 1):
		for prefix: Array in _subsets(prefixes, prefix_count):
			for suffix: Array in _subsets(suffixes, count - prefix_count):
				var affixes: Array = []
				for id: String in prefix + suffix:
					affixes.append(_max_entry(id, level))
				var instance: Dictionary = {"id": "gear_000001", "base_id": base_id, "rarity": rarity, "item_level": level, "affixes": affixes}
				_expect(Catalog.validate_instance(instance), "Every enumerated maximum is a legal production instance: " + str(instance))
				if Catalog.validate_instance(instance):
					result.append(_prepare({"instance": instance, "base_id": base_id, "affixes": affixes}))
	return result


func _state(candidate: Dictionary):
	var state = Build.new()
	state.equipped.clear()
	state.inventory.clear()
	state.allocated_nodes.assign([Build.Passives.START_ID])
	state.socketed_jewels.clear()
	state.jewels.clear()
	state.jewel_inventory.clear()
	state.equipment_instances.clear()
	state.backpack_positions.clear()
	var id: String = str(candidate.get("fixed_id", "gear_000001"))
	if candidate.has("instance"):
		state.equipment_instances[id] = candidate.instance.duplicate(true)
		state.next_equipment_id = 2
	state.inventory.assign([id, "detonation_charm"])
	_expect(state.equip(id), "Equip owned budget candidate through BuildState: " + candidate.base_id)
	_expect(not state._validate_snapshot(state._snapshot()).is_empty(), "Budget candidate has fully valid persistent BuildState ownership, root and layout")
	return state


func _prepare(candidate: Dictionary) -> Dictionary:
	var state = _state(candidate)
	candidate.attack_rate = state.get_stats().attack_speed
	candidate.snapshots = {"isolated": state.get_combat_snapshot()}
	_expect(state.equip("detonation_charm"), "Real detonation context equips the fixed charm")
	candidate.snapshots.detonation_charm = state.get_combat_snapshot()
	_expect(state.unequip("charm"), "Remove detonation charm before synthetic context")
	var sensitivity: Dictionary = state.get_combat_snapshot()
	# A labelled sensitivity input, not a claim about an attainable talent build.
	sensitivity.modifiers.append_array(Combat.modifiers(CONTEXTS.amplification_sensitivity))
	candidate.snapshots.amplification_sensitivity = sensitivity
	var local: bool = candidate.base_id == "ashwood_bow"
	for snapshot: Dictionary in candidate.snapshots.values():
		_expect(snapshot.has("weapon_profile") == local, "Only the actually equipped new bow contributes a raw local profile")
		if local:
			_expect(snapshot.weapon_profile.size() == 7 and snapshot.weapon_profile == Catalog.weapon_profile(candidate.instance), "BuildState passes the exact raw seven-key catalog profile")
	var basic: Dictionary = Combat.event_packet(candidate.snapshots.isolated, "basic", "projectile")
	_expect(not basic.is_empty(), "Real basic attack packet compiles")
	candidate.weapon_physical = float(basic.get("assembly", {}).get("weapon", {}).get("components", {}).get("physical", 0.0))
	max_weapon = maxf(max_weapon, candidate.weapon_physical)
	_expect(not state.get_stats().has("weapon_added_physical") and not state.get_stats().has("weapon_physical_increased"), "Local terms never leak into character stats")
	prepared_instances += 1
	return candidate


func _compile(candidate: Dictionary, context: String, mode: String) -> Dictionary:
	var snapshot: Dictionary = candidate.snapshots[context]
	var result: Dictionary = {"snapshot": snapshot, "attack_rate": candidate.attack_rate, "basic": Combat.event_packet(snapshot, "basic", "projectile"), "skills": {}}
	for skill: String in SKILLS:
		var compiled: Dictionary = Compiler.compile_skill(skill, snapshot, SUPPORTS[mode] if PROJECTILE_SKILLS.has(skill) else [])
		_expect(compiled.ok, "Production compiler accepts legal candidate/support: " + skill + "/" + mode)
		if not compiled.ok:
			return {}
		result.skills[skill] = compiled
		compiled_skills += 1
	return result


func _resolved(packet: Dictionary, snapshot: Dictionary, mitigation: Dictionary) -> float:
	return float(Damage.resolve(packet, snapshot.modifiers, mitigation).total)


func _measure(bundle: Dictionary, mitigation: Dictionary) -> Dictionary:
	var basic: float = _resolved(bundle.basic, bundle.snapshot, mitigation)
	var metrics: Dictionary = {"basic_hit": basic, "attack_rate": bundle.attack_rate, "basic_rate_product": basic * float(bundle.attack_rate)}
	for skill: String in SKILLS:
		var compiled: Dictionary = bundle.skills[skill]
		var packets: Dictionary = compiled.packets
		if skill == "tornado":
			metrics.tornado_parent = _resolved(packets.parent, compiled.snapshot, mitigation)
			metrics.tornado_child = _resolved(packets.child, compiled.snapshot, mitigation)
			# A declared one-hit-per-carrier potential, not simulated or actual DPS.
			metrics.tornado_carriers = metrics.tornado_parent * compiled.initial_count + metrics.tornado_child * compiled.initial_count * int(compiled.snapshot.tornado_recipe.child_count)
		elif skill in ["bolt", "frost"]:
			metrics[skill + "_hit"] = _resolved(packets.projectile, compiled.snapshot, mitigation)
			metrics[skill + "_carriers"] = metrics[skill + "_hit"] * compiled.initial_count
		elif skill == "chain":
			var total: float = 0.0
			for packet: Dictionary in packets.bounces:
				total += _resolved(packet, compiled.snapshot, mitigation)
			metrics.chain_first = _resolved(packets.bounces[0], compiled.snapshot, mitigation)
			metrics.chain_five_targets = total
		else:
			metrics[skill + "_hit"] = _resolved(packets.direct, compiled.snapshot, mitigation)
	metrics.secondary_single = _resolved(bundle.skills.tornado.packets.secondary, bundle.skills.tornado.snapshot, mitigation)
	evaluations += 1
	return metrics


func _maxima(options: Array, context: String, mode: String, targets: Dictionary = TARGETS) -> Dictionary:
	var result: Dictionary = {}
	for target: String in targets:
		result[target] = {}
	for candidate: Dictionary in options:
		var bundle: Dictionary = _compile(candidate, context, mode)
		if bundle.is_empty():
			continue
		for target: String in targets:
			var metrics: Dictionary = _measure(bundle, targets[target])
			for metric: String in metrics:
				if not result[target].has(metric) or float(metrics[metric]) > float(result[target][metric].value) + 0.0000001:
					# Every metric owns its own witness. Do not advertise a single
					# item as simultaneously maximizing attacks, spells and rate.
					result[target][metric] = {"value": metrics[metric], "base_id": candidate.base_id, "affixes": candidate.affixes,
						"weapon_physical": candidate.weapon_physical, "attack_rate": candidate.attack_rate}
	return result


func _row_key(row: Dictionary, mode: String) -> String:
	return "%s/%s/%s/%s/%s" % [str(int(row.level)), row.rarity, row.context, row.target, mode]


func _compare_row(row: Dictionary) -> void:
	var key: String = _row_key(row, row.support)
	_expect(expected_rows.has(key), "Frozen prediction includes " + key)
	if not expected_rows.has(key):
		return
	var expected: Dictionary = expected_rows[key]
	_expect(row.old_candidates == int(expected.old_candidates) and row.new_candidates == int(expected.new_candidates), "Candidate matrix matches historical prediction: " + key)
	row.ratio = {}
	for metric: String in expected.old_best:
		var old: float = float(row.old_best[metric].value)
		var future: float = float(row.production_best[metric].value)
		var old_error: float = absf(old - float(expected.old_best[metric].value))
		var new_error: float = absf(future - float(expected.predicted_best[metric].value))
		max_old_error = maxf(max_old_error, old_error)
		max_new_error = maxf(max_new_error, new_error)
		_near(old, float(expected.old_best[metric].value), "Unchanged old maximum " + key + "/" + metric)
		_near(future, float(expected.predicted_best[metric].value), "Production matches independent prediction " + key + "/" + metric)
		var ratio: float = future / old
		row.ratio[metric] = ratio
		_near(ratio, float(expected.ratio[metric]), "Budget ratio " + key + "/" + metric)
		_expect(ratio <= 1.25 + 0.000000001, "Current-target 25 percent gate " + key + "/" + metric)
		var witness: Dictionary = {"ratio": ratio, "level": row.level, "rarity": row.rarity, "context": row.context, "target": row.target, "support": row.support, "metric": metric}
		if ratio > float(max_any.ratio):
			max_any = witness
		if row.rarity == "rare" and ratio > float(max_rare.ratio):
			max_rare = witness


func _fixed_weapons() -> void:
	output.fixed = {}
	output.fixed_supports = {}
	output.fixed_carrier_counts = {}
	for id: String in ["ember_wand", "prism_bow", "swift_blade"]:
		var candidate: Dictionary = _prepare({"fixed_id": id, "base_id": id, "affixes": []})
		for mode: String in SUPPORTS:
			var bundle: Dictionary = _compile(candidate, "isolated", mode)
			var metrics: Dictionary = _measure(bundle, {})
			var expected: Dictionary = prediction.fixed[id] if mode == "none" else prediction.fixed_supports[mode][id]
			for metric: String in expected:
				_near(metrics[metric], float(expected[metric]), "Fixed historical weapon unchanged: " + id + "/" + mode + "/" + metric)
			if mode == "none":
				output.fixed[id] = metrics
			else:
				if not output.fixed_supports.has(mode):
					output.fixed_supports[mode] = {}
				output.fixed_supports[mode][id] = metrics
			if id == "prism_bow":
				output.fixed_carrier_counts[mode] = {"prism_bow_parents": bundle.skills.tornado.initial_count,
					"prism_bow_children": int(bundle.skills.tornado.initial_count) * int(bundle.skills.tornado.snapshot.tornado_recipe.child_count)}
				_expect(bundle.skills.tornado.initial_count == (7 if mode in ["volley", "both"] else 5), "Prism bow retains its actual extra parents in every support mode")
	_near(output.fixed.prism_bow.tornado_carriers, 477.4, "Unmodified fixed prism potential")


func _same_item_isolation() -> void:
	output.same_item_isolation = []
	for level: int in [1, 8, 16]:
		var affixes: Array = []
		for id: String in ["whetstone_edge", "tempered_edge", "runesong", "coalglow", "sparkthread", "beatlink"]:
			affixes.append(_max_entry(id, level))
		var on_item: Dictionary = {"id": "gear_000001", "base_id": "ashwood_bow", "rarity": "rare", "item_level": level, "affixes": affixes}
		var off_item: Dictionary = on_item.duplicate(true)
		off_item.affixes = affixes.filter(func(entry: Dictionary) -> bool: return not entry.id in ["whetstone_edge", "tempered_edge"])
		_expect(Catalog.validate_instance(on_item) and Catalog.validate_instance(off_item), "Same-item local-affix toggle preserves legal rarity/counts")
		var on: Dictionary = _prepare({"instance": on_item, "base_id": "ashwood_bow", "affixes": on_item.affixes})
		var off: Dictionary = _prepare({"instance": off_item, "base_id": "ashwood_bow", "affixes": off_item.affixes})
		_expect(Catalog.get_stats(on_item) == Catalog.get_stats(off_item), "Only local affixes changed; all ordinary modifiers identical")
		_near(on.attack_rate, off.attack_rate, "Local prefixes do not change ordinary attack rate")
		_expect(on.weapon_physical > off.weapon_physical, "Local affixes actually increase resolved physical points")
		for context: String in CONTEXTS:
			for mode: String in SUPPORTS:
				var on_bundle: Dictionary = _compile(on, context, mode)
				var off_bundle: Dictionary = _compile(off, context, mode)
				for skill: String in ["bolt", "frost", "nova", "meteor", "chain"]:
					_expect(on_bundle.skills[skill].packets == off_bundle.skills[skill].packets, "Every spell packet remains identical with local prefixes off/on: " + skill)
				for skill: String in PROJECTILE_SKILLS:
					_expect(on_bundle.skills[skill].packets.secondary == off_bundle.skills[skill].packets.secondary, "Independent secondary packet remains identical: " + skill)
					_expect(on_bundle.skills[skill].mana == off_bundle.skills[skill].mana and on_bundle.skills[skill].cooldown == off_bundle.skills[skill].cooldown, "Local prefixes change no mana/cooldown")
				_expect(on_bundle.skills.tornado.initial_count == (5 if mode in ["volley", "both"] else 3), "New bow retains three parents before volley")
				_expect(on_bundle.skills.tornado.initial_count == off_bundle.skills.tornado.initial_count, "Local prefixes change no carrier count")
				_expect(on_bundle.skills.tornado.packets.parent.base.physical > off_bundle.skills.tornado.packets.parent.base.physical, "Actual compiled tornado benefits from the changed local affixes")
				for target: String in TARGETS:
					var on_metrics: Dictionary = _measure(on_bundle, TARGETS[target])
					var off_metrics: Dictionary = _measure(off_bundle, TARGETS[target])
					for metric: String in ["attack_rate", "bolt_hit", "bolt_carriers", "frost_hit", "frost_carriers", "nova_hit", "meteor_hit", "chain_first", "chain_five_targets", "secondary_single"]:
						_near(on_metrics[metric], off_metrics[metric], "Same-item no-local-leak resolved " + metric)
		output.same_item_isolation.append({"level": level, "off_instance": off_item, "on_instance": on_item, "off_weapon_physical": off.weapon_physical, "on_weapon_physical": on.weapon_physical,
			"off_attack_rate": off.attack_rate, "on_attack_rate": on.attack_rate, "contexts": 3, "support_modes": 4, "targets": 2, "identical_spell_and_secondary_packets": true})
	# A normal bow's intrinsic W also leaves spell/secondary packets unchanged.
	var normal: Dictionary = _candidates("ashwood_bow", 1, "normal")[0]
	var state = _state(normal)
	var equipped: Dictionary = state.get_combat_snapshot()
	_expect(state.unequip("weapon"), "Unequip normal bow for intrinsic local isolation")
	var unarmed: Dictionary = state.get_combat_snapshot()
	for mode: String in SUPPORTS:
		for skill: String in SKILLS:
			var ids: Array = SUPPORTS[mode] if PROJECTILE_SKILLS.has(skill) else []
			var with_bow: Dictionary = Compiler.compile_skill(skill, equipped, ids)
			var without: Dictionary = Compiler.compile_skill(skill, unarmed, ids)
			if skill != "tornado":
				_expect(with_bow.packets == without.packets, "Local base does not change spell packet: " + skill)
			if PROJECTILE_SKILLS.has(skill):
				_expect(with_bow.packets.secondary == without.packets.secondary, "Local base does not change independent secondary: " + skill)
	output.normal_bow_spell_secondary_invariance = true


func _future_stress() -> void:
	var old: Dictionary = _maxima(stress_old, "isolated", "none", {"future": {"fire": 0.75}}).future
	var future: Dictionary = _maxima(stress_new, "isolated", "none", {"future": {"fire": 0.75}}).future
	for metric: String in old:
		_near(old[metric].value, prediction.future_stress.old_best[metric].value, "Future-only old prediction " + metric)
		_near(future[metric].value, prediction.future_stress.predicted_best[metric].value, "Future-only production prediction " + metric)
	var ratio: float = float(future.tornado_parent.value) / float(old.tornado_parent.value)
	_expect(ratio > 1.25, "Future 75 percent fire stress is explicitly beyond today's gate, not silently accepted")
	output.future_stress = {"inside_current_gate": false, "level": 16, "rarity": "rare", "support": "none", "context": "isolated", "fire_resistance": 0.75,
		"old_best": old, "production_best": future, "tornado_parent_ratio": ratio}


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREDICTION_PATH))
	_expect(loaded is Dictionary, "Portable historical prediction fixture is readable")
	if not loaded is Dictionary:
		quit(1)
		return
	prediction = loaded
	_expect(prediction.source_head == SOURCE_HEAD and prediction.variant == "moderate" and prediction.failures.is_empty(), "Fixture records a clean genuine v0.12 P4 prediction")
	_expect(int(prediction.baseline_evaluations) == 22899 and prediction.results.size() == 72 and prediction.support_results.size() == 216, "Complete independent baseline plus all support choices are archived")
	for row: Dictionary in prediction.results:
		expected_rows[_row_key(row, "none")] = row
	for row: Dictionary in prediction.support_results:
		expected_rows[_row_key(row, row.support)] = row
	output = {"historical_source_head": SOURCE_HEAD, "prediction_fixture": PREDICTION_PATH, "method": "Legal real catalog instances equipped through BuildState, then production SkillCompiler/CombatData and DamageResolver. No injected W or copied damage formula.",
		"contexts": CONTEXTS, "support_sets": SUPPORTS, "targets": TARGETS, "results": [], "maxima_are_independent": true, "carrier_sums_are_dps": false, "basic_rate_product_is_dps": false}
	_expect(Catalog.RARITIES.magic.max_prefixes == 1, "Magic cannot combine both local prefixes")
	for id: String in ["whetstone_edge", "tempered_edge"]:
		var family: Dictionary = Catalog.affix_definition(id)
		_expect(family.kind == "prefix" and family.stage == "weapon_local" and not str(family.stat).contains("speed"), "Both new families consume prefix slots and grant no local attack speed")
	_fixed_weapons()
	for level: int in LEVELS:
		for rarity: String in RARITIES:
			var old: Array = []
			for base_id: String in OLD_BASES:
				old.append_array(_candidates(base_id, level, rarity))
			var future: Array = _candidates("ashwood_bow", level, rarity)
			if level == 16 and rarity == "rare":
				stress_old = old
				stress_new = future
			for context: String in CONTEXTS:
				for mode: String in SUPPORTS:
					var old_best: Dictionary = _maxima(old, context, mode)
					var new_best: Dictionary = _maxima(future, context, mode)
					for target: String in TARGETS:
						var row: Dictionary = {"level": level, "rarity": rarity, "context": context, "target": target, "support": mode,
							"old_candidates": old.size(), "new_candidates": future.size(), "old_best": old_best[target], "production_best": new_best[target]}
						_compare_row(row)
						output.results.append(row)
			if OS.get_cmdline_user_args().has("--progress"):
				print("Production budget replay: ilvl ", level, " ", rarity, " complete; ", evaluations, " evaluations; ", failures.size(), " failures")
	output.current_matrix_evaluations = evaluations
	_expect(evaluations == int(prediction.current_matrix_evaluations), "Production and frozen reference evaluate the same complete current matrix")
	_same_item_isolation()
	_future_stress()
	_near(max_weapon, 13.0, "Production maximum local physical budget remains W13")
	output.summary = {"max_any_current_ratio": max_any, "max_rare_current_ratio": max_rare, "max_old_absolute_error": max_old_error, "max_prediction_absolute_error": max_new_error,
		"maximum_weapon_physical": max_weapon, "current_matrix_rows": output.results.size(), "current_gate_passed": float(max_any.ratio) <= 1.25, "prepared_instances": prepared_instances,
		"candidate_context_support_target_evaluations": evaluations, "compiled_skills": compiled_skills, "checks": checks, "failure_count": failures.size(), "elapsed_ms": Time.get_ticks_msec() - started}
	output.failures = failures
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			destination = argument.trim_prefix("--report=")
	if not destination.is_empty():
		var file := FileAccess.open(destination, FileAccess.WRITE)
		_expect(file != null, "Replay artifact destination opens")
		if file != null:
			output.summary.checks = checks
			output.summary.failure_count = failures.size()
			file.store_string(JSON.stringify(output, "\t", true, true))
			file.close()
	print("Local weapon budget: %d checks, %d failures; current max +%.6f%%, rare max +%.6f%%; old error %.12f, prediction error %.12f" % [checks, failures.size(), (float(max_any.ratio) - 1.0) * 100.0, (float(max_rare.ratio) - 1.0) * 100.0, max_old_error, max_new_error])
	quit(0 if failures.is_empty() else 1)
