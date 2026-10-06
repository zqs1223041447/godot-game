extends SceneTree
## Run unchanged against v065 and v066. Captures byte hashes of every old
## legal zero/one/two-support compile and each skill's maximal five-slot group.
const Registry = preload("res://scripts/combat/support_registry.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Data = preload("res://scripts/game_data.gd")


func _initialize() -> void:
	var output: String = OS.get_environment("AMBUSH_SUPPORT_PROBE_OUT")
	if not output.begins_with("/tmp/"):
		quit(78)
		return
	var rows: Array = []
	seed(660065)
	for skill: String in Data.SKILLS:
		var allowed: Array = Registry.supports_for_skill(skill)
		allowed.erase("ambush")
		allowed.sort()
		var selections: Array = [[]]
		for first: int in allowed.size():
			selections.append([allowed[first]])
			for second: int in range(first + 1, allowed.size()):
				var pair: Array = [allowed[first], allowed[second]]
				if Registry.compatibility_reason(skill, pair).is_empty(): selections.append(pair)
		var group: Array = []
		for support: String in allowed:
			if group.size() == 5: break
			var candidate: Array = group.duplicate()
			candidate.append(support)
			if Registry.compatibility_reason(skill, candidate, 5).is_empty(): group = candidate
		if group.size() > 2: selections.append(group)
		for config: int in 3:
			var stats: Dictionary = {"damage": 100.0}
			if config > 0:
				stats.merge({"spell_added_cold": 13.0, "spell_added_lightning": 11.0, "attack_added_physical": 7.0,
					"global_increased": 0.2, "area_increased": 0.1, "spell_increased": 0.3,
					"area_size_increased": 0.25, "mana_cost_efficiency_increased": 0.25,
					"crit_base_chance": 0.5, "crit_base_multiplier": 2.0, "fire_dot_multiplier": 0.2, "burn_faster": 0.25})
			if config == 2: stats.resolute_technique = 1.0
			var snapshot: Dictionary = Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])
			for links: Array in selections:
				var compiled: Dictionary = Compiler.compile_group(skill, snapshot, links)
				if not compiled.ok:
					printerr("Compile failure: ", skill, links, compiled)
					quit(1)
					return
				rows.append({"skill": skill, "config": config, "links": links,
					"compiled": _hash(compiled), "program": _hash(Registry.compile_programs(skill, links, 5))})
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify({"rows": rows, "global_rng": [randi(), randi(), randi()]}))
	file.close()
	print("Old support baseline probe: %d byte-hashed rows" % rows.size())
	quit(0)


static func _hash(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()
