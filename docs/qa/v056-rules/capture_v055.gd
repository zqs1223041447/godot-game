extends SceneTree
## Execute this exact probe against the complete, unchanged released v0.55 tree.
## Oracle rows keep whole returned Variants, including original typed bytes.
const Prior = preload("res://docs/qa/v055-weapon-rules/capture_v054.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")


static func blade(flat: float = 2.0, increased: float = 0.2) -> Dictionary:
	var result: Dictionary = Prior.bow(flat, increased)
	result.base_id = "forgeblade"
	return result


static func capture_legacy() -> Dictionary:
	var rows: Dictionary = Prior.capture()
	var number: int = 0
	for stats: Dictionary in [{"damage": 18.0}, {"damage": 0},
		{"damage": 18.0, "attack_added_physical": 6.0, "attack_added_fire": 6.0,
			"area_size_increased": 0.5, "melee_area_size_increased": 0.75, "projectile_speed_increased": 0.2,
			"crit_base_chance": 0.05, "crit_base_multiplier": 1.5, "melee_crit_chance_increased": 0.8,
			"projectile_attack_crit_chance_increased": 0.6, "melee_crit_multiplier_add": 0.2,
			"max_health": 120.0, "max_mana": 102.0, "attack_life_leech": 0.02, "attack_mana_leech": 0.01}]:
		for profile: Variant in [null, Prior.bow(0.0, 0.0), Prior.bow(6.0, 0.3), blade(0.0, 0.0), blade(6.0, 0.3)]:
			for effects: Array in [[], ["return_on_range"], ["explode_on_flight_end"], ["return_on_range", "explode_on_flight_end"]]:
				var snapshot: Dictionary = Combat.snapshot(stats, effects)
				if profile != null:snapshot.weapon_profile = profile
				for skill: String in Prior.SKILLS:
					if skill == "basic" and profile is Dictionary and profile.base_id == "forgeblade":continue
					for supports: Array in [[], ["focus"], ["concentrate"], ["overcharge"], ["echo"]]:
						rows["expanded:%d:%s:%s" % [number, skill, str(supports)]] = Prior.compile(skill, snapshot, supports)
				number += 1
	# All invalid non-blade basic inputs preserve their complete original errors.
	for values: Variant in [{"projectile_speed_increased": NAN}, {"projectile_speed_increased": -1.0},
		{"area_size_increased": -0.1}, {"area_size_increased": INF}, {"unknown": 0.2}, [], "spatial"]:
		var snapshot: Dictionary = Combat.snapshot({"damage": 18.0}, [])
		snapshot.spatial_modifiers = values
		rows["invalid-spatial:%d" % number] = Compiler.compile_basic(snapshot)
		number += 1
	return rows


static func flight_result(input: Dictionary) -> Dictionary:
	var runtime = Runtime.new()
	var shots: Array[Dictionary] = []
	shots.append(runtime.make_projectile(Vector2.ZERO, Vector2.RIGHT, input.spec, input.packet,
		input.snapshot, runtime.new_cast(), Color.WHITE))
	var frames: Array = [{"shots": shots.duplicate(true)}]
	var targets: Array[Dictionary] = []
	targets.assign(input.targets)
	for delta: float in [0.15, 0.2, 1.0]:
		var events: Array[Dictionary] = runtime.advance(shots, delta, targets, Vector2.ZERO, 100)
		frames.append({"events": events.duplicate(true), "shots": shots.duplicate(true)})
	return {"projectile": Combat.event_packet(input.snapshot, "basic", "projectile"),
		"secondary": Combat.secondary_packet(input.snapshot, "basic"),
		"direct": Combat.event_packet(input.snapshot, "basic", "direct"), "frames": frames}


static func capture_inflight() -> Array:
	var rows: Array = []
	for profile: Variant in [null, Prior.bow(6.0, 0.3), blade(6.0, 0.3)]:
		for effects: Array in [[], ["return_on_range"], ["explode_on_flight_end"], ["return_on_range", "explode_on_flight_end"]]:
			for targets: Array in [[], [{"id": 1, "pos": Vector2(42.0, 0.0), "radius": 6.0}]]:
				var snapshot: Dictionary = Combat.snapshot({"damage": 18.0, "attack_added_fire": 6.0,
					"area_size_increased": 0.5, "projectile_speed_increased": 0.2,
					"crit_base_chance": 0.05, "crit_base_multiplier": 1.5}, effects)
				if profile != null:snapshot.weapon_profile = profile
				var cast: Dictionary = Compiler.compile_basic(snapshot)
				var input: Dictionary = {"snapshot": cast.snapshot, "packet": cast.packets.projectile,
					"spec": {"speed": cast.recipe.speed, "range": 120.0, "lifetime": 0.65, "pierce": -1}, "targets": targets}
				rows.append({"input": input.duplicate(true), "output": flight_result(input)})
	return rows


func _initialize() -> void:
	var path: String = OS.get_environment("V056_ORACLE_OUTPUT")
	if path.is_empty():quit(78);return
	seed(560056)
	var expected: Array = [randi(), randi(), randi()]
	seed(560056)
	var rows: Dictionary = {"legacy": capture_legacy(), "inflight": capture_inflight()}
	rows.rng_after = [randi(), randi(), randi()]
	rows.rng_expected = expected
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:quit(1);return
	file.store_buffer(var_to_bytes(rows))
	file.close()
	print("Frozen v055 basic oracle: %d complete result rows, %d original in-flight carriers" % [rows.legacy.size(), rows.inflight.size()])
	quit(0)
