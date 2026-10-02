extends SceneTree
## Historical prediction harness. Run against a clean v0.12 checkout, never v0.13.
## The only simulated operation is adding proposed local W to attack packets.
## Production replay lives in tests/local_weapon_budget_test.gd and does not inject W.
const Build = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const LEVELS = [1, 8, 16, 30]
const RARITIES = ["normal", "magic", "rare"]
const CONTEXTS = {"isolated": {}, "detonation_charm": {"global_increased": 0.2, "elemental_increased": 0.3}, "amplification_sensitivity": {"global_increased": 0.5, "projectile_increased": 0.5, "elemental_increased": 0.5}}
const SUPPORT_SETS = {"none": [], "volley": ["volley"], "focus": ["focus"], "both": ["volley", "focus"]}
var support_mode: String = "none"
var evaluated: int = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func subsets(ids: Array, count: int, start: int = 0, selected: Array = []) -> Array:
	if count == 0:
		return [selected.duplicate()]
	var result: Array = []
	for i: int in range(start, ids.size()):
		var next: Array = selected.duplicate()
		next.append(ids[i])
		result.append_array(subsets(ids, count - 1, i + 1, next))
	return result

func max_entry(id: String, level: int) -> Dictionary:
	if id == "local_flat":
		var tier: int = 1 if level < 8 else (2 if level < 16 else 3)
		if OS.get_cmdline_user_args().has("--moderate"):
			return {"id": id, "tier": tier, "value": tier * 2}
		return {"id": id, "tier": tier, "value": tier + (1 if OS.get_cmdline_user_args().has("--flat-plus-one") else 0)}
	if id == "local_inc":
		var tier: int = 1 if level < 8 else (2 if level < 16 else 3)
		if OS.get_cmdline_user_args().has("--moderate"):
			return {"id": id, "tier": tier, "value": [15,22,30][tier - 1]}
		return {"id": id, "tier": tier, "value": [8, 14, 20][tier - 1]}
	var family: Dictionary = Catalog.affix_definition(id)
	var best: Dictionary = {}
	for tier: Dictionary in family.tiers:
		if int(tier.level) <= level:
			best = {"id": id, "tier": tier.tier, "value": tier.max}
	return best

func candidates(base_id: String, level: int, rarity: String) -> Array:
	var predicted: bool = base_id == "predicted_bow"
	var prefixes: Array = []
	var suffixes: Array = []
	var pool: Array = Catalog.AFFIXES.keys() if predicted else Catalog.pool_profile(Catalog.pool_for_base(base_id)).affix_ids
	for id: String in pool:
		var family: Dictionary = Catalog.affix_definition(id)
		if not family.slots.has("weapon"):
			continue
		if not predicted and not Catalog.family_eligible(id, base_id):
			continue
		(prefixes if family.kind == "prefix" else suffixes).append(id)
	if predicted:
		prefixes.append_array(["local_flat", "local_inc"])
	var rules: Dictionary = Catalog.RARITIES[rarity]
	var result: Array = []
	# All maximum-count combinations suffice: every candidate modifier is nonnegative,
	# adding an unused legal family cannot decrease any metric, and max tiers dominate.
	var affix_count: int = int(rules.max_affixes)
	for prefix_count: int in range(maxi(0, affix_count - int(rules.max_suffixes)), mini(affix_count, int(rules.max_prefixes)) + 1):
		for pre: Array in subsets(prefixes, prefix_count):
			for suf: Array in subsets(suffixes, affix_count - prefix_count):
				var affixes: Array = []
				for id: String in pre + suf:
					affixes.append(max_entry(id, level))
				var item: Dictionary = {"id": "gear_000001", "base_id": base_id, "rarity": rarity, "item_level": level, "affixes": affixes}
				if not predicted and not Catalog.validate_instance(item):
					failures.append("Invalid enumerated candidate: " + str(item))
					continue
				var stats: Dictionary = {} if predicted else Catalog.get_stats(item)
				var flat: float = 0.0
				var increased: float = 0.0
				if predicted:
					for affix: Dictionary in affixes:
						if affix.id == "local_flat":
							flat += float(affix.value)
						elif affix.id == "local_inc":
							increased += float(affix.value) / 100.0
						else:
							var family: Dictionary = Catalog.affix_definition(affix.id)
							stats[family.stat] = float(stats.get(family.stat, 0.0)) + float(affix.value) / (100.0 if family.unit == "percent" else 1.0)
				var base_physical: float = 4.0 if OS.get_cmdline_user_args().has("--moderate") else 3.0
				result.append({"base_id": base_id, "affixes": affixes, "stats": stats, "weapon_physical": (base_physical + flat) * (1.0 + increased) if predicted else 0.0})
	return result

func resolved(packet: Dictionary, snapshot: Dictionary, weapon: float, mitigation: Dictionary) -> float:
	var predicted_packet: Dictionary = packet.duplicate(true)
	if predicted_packet.tags.has("attack") and weapon > 0.0:
		predicted_packet.base.physical = float(predicted_packet.base.get("physical", 0.0)) + weapon * float(predicted_packet.assembly.base_coefficient)
	return float(Damage.resolve(predicted_packet, snapshot.modifiers, mitigation).total)

func evaluate(candidate: Dictionary, context: Dictionary, mitigation: Dictionary) -> Dictionary:
	var stats: Dictionary = Build.BASE_STATS.duplicate(true)
	for additions: Dictionary in [candidate.stats, context]:
		for key: String in additions:
			stats[key] = float(stats.get(key, 0.0)) + float(additions[key])
	for rate: String in ["attack_speed", "move_speed", "mana_regen"]:
		stats[rate] = float(stats[rate]) * (1.0 + float(stats[rate + "_increased"]))
	var snapshot: Dictionary = Combat.snapshot(stats, [])
	var weapon: float = float(candidate.weapon_physical)
	var basic: float = resolved(Combat.event_packet(snapshot, "basic", "projectile"), snapshot, weapon, mitigation)
	var metrics: Dictionary = {"basic_hit": basic, "attack_rate": stats.attack_speed, "basic_rate_product": basic * float(stats.attack_speed)}
	for skill_id: String in ["tornado", "bolt", "frost", "nova", "meteor", "chain"]:
		var compiled: Dictionary = Compiler.compile_skill(skill_id, snapshot, SUPPORT_SETS[support_mode] if skill_id in ["tornado", "bolt", "frost"] else [])
		if not compiled.ok:
			failures.append("Compile failure: " + str(compiled))
			continue
		var packets: Dictionary = compiled.packets
		if skill_id == "tornado":
			metrics.tornado_parent = resolved(packets.parent, compiled.snapshot, weapon, mitigation)
			metrics.tornado_child = resolved(packets.child, compiled.snapshot, weapon, mitigation)
			metrics.tornado_carriers = metrics.tornado_parent * compiled.initial_count + metrics.tornado_child * compiled.initial_count * int(snapshot.tornado_recipe.child_count)
		elif skill_id in ["bolt", "frost"]:
			metrics[skill_id + "_hit"] = resolved(packets.projectile, compiled.snapshot, weapon, mitigation)
			metrics[skill_id + "_carriers"] = metrics[skill_id + "_hit"] * compiled.initial_count
		elif skill_id == "chain":
			var total: float = 0.0
			for packet: Dictionary in packets.bounces:
				total += resolved(packet, compiled.snapshot, weapon, mitigation)
			metrics.chain_first = resolved(packets.bounces[0], compiled.snapshot, weapon, mitigation)
			metrics.chain_five_targets = total
		else:
			metrics[skill_id + "_hit"] = resolved(packets.direct, compiled.snapshot, weapon, mitigation)
	metrics.secondary_single = resolved(Combat.secondary_packet(snapshot, "tornado"), snapshot, weapon, mitigation)
	evaluated += 1
	return metrics

func maxima(options: Array, context: Dictionary, mitigation: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for candidate: Dictionary in options:
		var metrics: Dictionary = evaluate(candidate, context, mitigation)
		for metric: String in metrics:
			if not result.has(metric) or float(metrics[metric]) > float(result[metric].value) + 0.0000001:
				result[metric] = {"value": metrics[metric], "base_id": candidate.base_id, "affixes": candidate.affixes, "weapon_physical": candidate.weapon_physical, "attack_rate": metrics.attack_rate}
	return result

func run() -> void:
	if Build.SAVE_VERSION != 8:
		push_error("Historical prediction requires v0.12/save-schema8 sources, not the current production checkout.")
		quit(1)
		return
	if not OS.get_cmdline_user_args().has("--moderate"):
		push_error("The archived acceptance budget requires --moderate (P4/W13).")
		quit(1)
		return
	var output: Dictionary = {"source_head": "1f948911e20081edd4cd7adf96203631d45a6726", "prediction": {"base_physical": 4, "local_flat_max": [2,4,6], "local_inc_max": [15,22,30], "allowed_ordinary_families": "All legacy weapon-eligible families only; no runewood-added families", "method": "Genuine v0.12 compiler and DamageResolver; proposed W is injected into compiled attack packets only. This is a prediction, not production acceptance."}, "contexts": CONTEXTS, "results": [], "support_results": [], "fixed": {}, "fixed_supports": {}, "failures": [], "variant": "moderate"}
	var fixed: Array = []
	for id: String in Data.ITEMS:
		if Data.ITEMS[id].slot == "weapon":
			fixed.append({"base_id": id, "stats": Data.ITEMS[id].stats, "affixes": [], "weapon_physical": 0.0})
	for mode: String in SUPPORT_SETS:
		support_mode = mode
		var fixed_metrics: Dictionary = {}
		for candidate: Dictionary in fixed:
			fixed_metrics[candidate.base_id] = evaluate(candidate, {}, {})
		if mode == "none":
			output.fixed = fixed_metrics
		else:
			output.fixed_supports[mode] = fixed_metrics
		for level: int in LEVELS:
			for rarity: String in RARITIES:
				var old: Array = []
				for base_id: String in ["cinder_reed", "gale_spindle", "runewood_focus"]:
					old.append_array(candidates(base_id, level, rarity))
				var future: Array = candidates("predicted_bow", level, rarity)
				for context_id: String in CONTEXTS:
					for target: String in ["unmitigated", "emberguard"]:
						var mitigation: Dictionary = {} if target == "unmitigated" else {"fire": 0.25}
						var old_best: Dictionary = maxima(old, CONTEXTS[context_id], mitigation)
						var new_best: Dictionary = maxima(future, CONTEXTS[context_id], mitigation)
						var ratios: Dictionary = {}
						for metric: String in new_best:
							ratios[metric] = float(new_best[metric].value) / float(old_best[metric].value)
						var row: Dictionary = {"level": level, "rarity": rarity, "context": context_id, "target": target, "old_candidates": old.size(), "new_candidates": future.size(), "old_best": old_best, "predicted_best": new_best, "ratio": ratios}
						if mode == "none":
							output.results.append(row)
						else:
							row.support = mode
							output.support_results.append(row)
		print("Prediction support complete: ", mode, "; cumulative evaluations: ", evaluated)
		if mode == "none":
			output.baseline_evaluations = evaluated
	output.current_matrix_evaluations = evaluated
	# Explicit future-only stress, excluded from today's 0/25 percent gate.
	support_mode = "none"
	var stress_old: Array = []
	for id: String in ["cinder_reed", "gale_spindle", "runewood_focus"]:
		stress_old.append_array(candidates(id, 16, "rare"))
	var stress_new: Array = candidates("predicted_bow", 16, "rare")
	output.future_stress = {"level": 16, "rarity": "rare", "context": "isolated", "support": "none", "fire_resistance": 0.75, "inside_current_gate": false,
		"old_best": maxima(stress_old, {}, {"fire": 0.75}), "predicted_best": maxima(stress_new, {}, {"fire": 0.75})}
	output.failures = failures
	output.evaluations = evaluated
	var destination: String = "user://weapon-budget-prediction.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			destination = argument.trim_prefix("--output=")
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write prediction: " + destination)
		quit(1)
		return
	file.store_string(JSON.stringify(output, "\t", true, true))
	file.close()
	print("WEAPON_BUDGET_COMPLETE: ", evaluated, " candidate/context/support/target evaluations; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
