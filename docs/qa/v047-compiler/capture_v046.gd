extends SceneTree
## External probe: run this file under the frozen v046 project, then unchanged
## under the candidate. The oracle is real released code, never a feature switch.
const SKILLS: Array[String] = ["tornado", "bolt", "frost", "nova", "dash", "ward", "meteor", "chain", "cleave", "shade_bolt"]
const LINKS: Dictionary = {
	"tornado": [["focus", "volley"], ["focus", "volley", "physical_focus", "fire_focus", "efficiency"],
		["ignite"], ["ignite", "fire_focus", "focus", "volley", "efficiency"]],
	"meteor": [["breadth", "concentrate"], ["breadth", "concentrate", "fire_focus", "efficiency", "quickcast"],
		["ignite"], ["ignite", "fire_focus", "efficiency", "quickcast", "concentrate"]],
}

func _initialize() -> void:
	var output: String = ""
	var comparison: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--compare="): comparison = argument.trim_prefix("--compare=")
	if output.is_empty():
		push_error("Pass -- --output=/absolute/path/compiler-v046.bin")
		quit(2)
		return
	var compiler = load("res://scripts/combat/skill_compiler.gd")
	var combat = load("res://scripts/combat/combat_data.gd")
	var supports = load("res://scripts/combat/support_registry.gd")
	var fixtures: Dictionary = {
		"base": combat.snapshot({"damage": 100.0}, []),
		"rich": combat.snapshot({"damage": 137.0, "projectile_count": 2,
			"global_increased": 0.19, "projectile_increased": 0.31, "area_increased": 0.23,
			"elemental_increased": 0.29, "spell_increased": 0.37, "fire_increased": 0.41,
			"physical_increased": 0.17, "attack_elemental_increased": 0.13,
			"attack_added_physical": 11.0, "attack_added_fire": 17.0,
			"spell_added_cold": 13.0, "spell_added_lightning": 19.0,
			"crit_base_chance": 0.17, "crit_base_multiplier": 1.75,
			"crit_chance_increased": 0.21, "projectile_attack_crit_multiplier_add": 0.23,
			"max_health": 500.0, "max_mana": 200.0,
			"attack_life_leech": 0.025, "physical_attack_mana_leech": 0.04,
			"mana_cost_efficiency_increased": 0.13, "mana_cost_increased": 0.07,
			"area_size_increased": 0.17, "projectile_speed_increased": 0.11},
			["return_on_range", "explode_on_flight_end"]),
	}
	var records: Array[Dictionary] = []
	var failures: int = 0
	for fixture: String in fixtures:
		for skill: String in SKILLS:
			failures += _capture(records, compiler, fixture, fixtures[fixture], skill, [])
		for skill: String in LINKS:
			for links: Array in LINKS[skill]:
				failures += _capture(records, compiler, fixture, fixtures[fixture], skill, links)
		failures += _capture(records, compiler, fixture, fixtures[fixture], "basic", [])
	var sources: Dictionary = {}
	for path: String in ["scripts/combat/skill_compiler.gd", "scripts/combat/support_registry.gd",
			"scripts/combat/ignite_support_rules.gd", "scripts/combat/burn_rules.gd",
			"scripts/combat/combat_data.gd", "scripts/game_data.gd"]:
		sources[path] = FileAccess.get_sha256("res://" + path)
	var result: Dictionary = {"schema": 1, "engine": Engine.get_version_info().string,
		"source_has_ignite": supports.SUPPORTS.has("ignite"),
		"source_has_ember": supports.SUPPORTS.has("ember_proliferation"),
		"source_hashes": sources, "records": records}
	if not comparison.is_empty():
		var old_file = FileAccess.open(comparison, FileAccess.READ)
		if old_file == null:
			push_error("Cannot read frozen comparison: " + comparison)
			quit(2)
			return
		var old: Dictionary = old_file.get_var(false)
		old_file.close()
		if old.get("source_has_ember", true) or not old.get("source_has_ignite", false) or old.records.size() != records.size():
			failures += 1
			push_error("Oracle must be an Ignite-capable pre-Ember compiler with matching cases")
		else:
			for index: int in range(records.size()):
				if var_to_bytes(old.records[index]) != var_to_bytes(records[index]):
					failures += 1
					push_error("Frozen-v046 full-byte mismatch: " + records[index].id)
		print("Frozen-v046 full-byte comparison: %d records, %d failures" % [records.size(), failures])
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write fixture: " + output)
		quit(2)
		return
	file.store_var(result, false)
	file.close()
	print("Compiler probe: %d records, %d failures; source_has_ignite=%s; source_has_ember=%s" % [records.size(), failures, result.source_has_ignite, result.source_has_ember])
	quit(1 if failures else 0)

func _capture(records: Array[Dictionary], compiler, fixture: String, snapshot: Dictionary, skill: String, links: Array) -> int:
	var before: PackedByteArray = var_to_bytes(snapshot)
	var cast: Dictionary = compiler.compile_basic(snapshot) if skill == "basic" else compiler.compile_group(skill, snapshot, links)
	if not cast.get("ok", false) or before != var_to_bytes(snapshot):
		push_error("Probe failed: %s/%s/%s: %s" % [fixture, skill, str(links), cast.get("error", "input mutated")])
		return 1
	var bytes: PackedByteArray = var_to_bytes(cast)
	var label: String = "%s/%s/%s" % [fixture, skill, ",".join(links)]
	records.append({"id": label, "skill": skill, "supports": links.duplicate(true),
		"snapshot": snapshot.duplicate(true), "cast_bytes": bytes})
	var digest = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	print("%s %s" % [label, digest.finish().hex_encode()])
	return 0
