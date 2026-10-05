extends SceneTree
## The same pure trajectory runs externally against the released v47 PCK and in v48.
## Full Variant bytes retain all fields, key order, numeric types and float values.
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Factory = preload("res://scripts/monsters/monster_runtime.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Admission = preload("res://scripts/world/map_admission.gd")


static func records() -> Array:
	var output: Array = []
	for kind: String in ["default", "old_garden", "broken_ruins"]:
		for timed: bool in [false, true]:
			var enemy: Dictionary
			var profile: Dictionary = {}
			var pattern := ""
			if kind == "default":
				enemy = Monsters.make_enemy(1, "crawler", 4, Vector2(111, 222), "ordinary")
			else:
				var map: Dictionary = Maps.compile(kind, [], []).profile
				enemy = Admission.create_root(Factory.new(), map, "rift_warden", map.wave,
					Vector2(111, 222), "map_boss", "", [], true).enemy
				var policy: Dictionary = Monsters.telegraph_policy(enemy)
				profile = policy.profile
				pattern = policy.visual_pattern
			enemy.spawn = 0.0
			var runtime := Runtime.new()
			var started: Dictionary = runtime.start(enemy, Vector2(345.25, 456.5), profile, pattern)
			assert(started.ok)
			var windup: float = started.attack.profile.windup_seconds
			var recovery: float = started.attack.profile.recovery_seconds
			var row := {"kind": kind, "timed": timed, "source": enemy.duplicate(true),
				"start": started, "states": [runtime.state_for(enemy.id)], "events": []}
			for delta: float in [0.0, windup * 0.5, windup * 0.5, recovery * 0.5, recovery * 0.5, 10.0]:
				row.events.append(runtime.advance(delta, [enemy], timed))
				row.states.append(runtime.state_for(enemy.id))
			output.append(row)
	return output


func _initialize() -> void:
	var output_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output_path = argument.trim_prefix("--out=")
	if output_path.is_empty():
		push_error("Pass -- --out=/absolute/path.bin")
		quit(2)
		return
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if not output:
		push_error("Cannot write legacy trajectory")
		quit(2)
		return
	var captured := records()
	var bytes := var_to_bytes(captured)
	output.store_buffer(bytes)
	output.close()
	print("Legacy telegraph capture: %d cases, %d bytes; application %s; echo present %s" %
		[captured.size(), bytes.size(), ProjectSettings.get_setting("application/config/version"),
		not preload("res://scripts/monsters/map_boss_profiles.gd").definition("sunwell_echo").is_empty()])
	quit(0)
