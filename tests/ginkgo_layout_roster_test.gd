extends SceneTree
## One bounded v083 batch: real geometry/admission, all legal modifier choices,
## source-policy roster replay, and exact released old-map output comparison.
const Maps = preload("res://scripts/world/map_compiler.gd")
const Catalog = preload("res://scripts/world/map_catalog.gd")
const Normal = preload("res://scripts/world/normal_map_catalog.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const State = preload("res://scripts/world/map_camp_state.gd")
const Rules = preload("res://scripts/world/ginkgo_roster_rules.gd")
const Mist = preload("res://scripts/world/mist_skitter_roster_rules.gd")
const Admission = preload("res://scripts/world/map_camp_admission.gd")
const RootAdmission = preload("res://scripts/world/map_admission.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Bosses = preload("res://scripts/monsters/map_boss_profiles.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Modifiers = preload("res://scripts/encounters/encounter_catalog.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const BASELINE_DIRECTORY := "res://docs/qa/v083-layout/"
const BASELINES := {
	"map_catalog": ["MapCatalog", "1ab4fd17f6df4314abe23605e3d21101dd5f0dad7841a9b403fd544a5af0c225"],
	"normal_map_catalog": ["NormalMapCatalog", "7916feb807b79cb9b578642f56b5016d77b96c0d4a34b2d1c760741339349ca1"],
	"map_geometry": ["MapGeometry", "182959f178e95ae48fdc6b1866bc0a9f87281e5813d4dbb76160d002e3f2db4a"],
	"map_camp_layout": ["MapCampLayout", "c3903c7eb964743c329f27d38ded79d42e5814d8cf59c976598697e29d073f39"],
	"map_camp_state": ["MapCampState", "5dc15ba169efe3955fe53d715577820be441ca30964f46e191261be3c950c1bf"],
	"map_boss_profiles": ["MapBossProfiles", "e499f0c06c4442a2026c0c2205fc15a86df85f08b85a26c931ff6ec360629924"],
}
const EXPECTED_PATTERNS := {
	"camp_west": ["skitter", "crawler", "skitter", "crawler", "brute", "skitter"],
	"camp_north": ["brute", "frost_guard", "crawler", "brute", "frost_guard", "crawler"],
	"camp_east": ["brute", "storm_skitter", "skitter", "brute", "crawler", "storm_skitter"],
}
const POLICIES := [Monsters.LEGACY_ROLL_POLICY, Monsters.STRIDE_ROLL_POLICY, Monsters.DAMAGE_LIFE_ROLL_POLICY, Monsters.CURRENT_ROLL_POLICY]
var oracles: Dictionary = {}
var checks := 0
var failures := 0
var routes := 0
var profiles := 0
var admitted_roots := 0
var old_cases := 0
var roster_cases := 0
var min_trigger_gap := INF
var min_body_gap := INF
var max_ordinary_radius := 0.0
var boss_radius := 0.0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	if not _load_oracles():
		quit(1)
		return
	seed(830083)
	var expected_global_random := randi()
	seed(830083)
	_test_geometry_and_routes()
	_test_legal_profiles()
	_test_activation_edges()
	_test_roster_contract()
	_test_fixed_descendants()
	_test_old_maps()
	check(randi() == expected_global_random, "Map generation and all helpers never consume global RNG")
	check(profiles == 286, "All 286 legal fixed/normal modifier profiles were admitted")
	check(admitted_roots == profiles * 37, "Every profile admits exactly 36 ordinary roots and one boss")
	print("Ginkgo layout/roster: %d checks, %d failures; %d legal profiles; %d admitted roots; %d routes; %d roster replays; %d exact old-map checkpoints" % [checks, failures, profiles, admitted_roots, routes, roster_cases, old_cases])
	print("Safety: all root centers to all four trigger disk edges minimum %.6f >= 230; simultaneous root body gap %.6f; real ordinary/boss radii %.1f/%.1f; boss own disk gap 256" % [min_trigger_gap, min_body_gap, max_ordinary_radius, boss_radius])
	print("Bounds: %s; accepted east center (1690,150); original candidate east center (1600,150) rejected" % [View.WORLD_ARENA])
	quit(1 if failures else 0)


func _load_oracles() -> bool:
	for name: String in BASELINES:
		var path := BASELINE_DIRECTORY + name + ".gd.baseline.txt"
		check(FileAccess.get_sha256(path) == BASELINES[name][1], "Frozen f18cf07 baseline bytes: " + name)
		var script := GDScript.new()
		script.source_code = FileAccess.get_file_as_string(path).replace("class_name " + str(BASELINES[name][0]) + "\n", "")
		check(script.reload() == OK, "Released oracle loads once: " + name)
		oracles[name] = script
	return failures == 0


func _test_geometry_and_routes() -> void:
	var geometry := Geometry.new()
	check(geometry.configure("ginkgo_arcade", View.WORLD_ARENA), "Ginkgo configures at the actual world bounds")
	var shape: Dictionary = geometry.snapshot()
	var origin: Vector2 = View.WORLD_ARENA.position
	check(shape.walls == [Rect2(origin + Vector2(660,230), Vector2(520,250)), Rect2(origin + Vector2(420,310), Vector2(90,90)), Rect2(origin + Vector2(1330,310), Vector2(90,90))], "Exactly the three approved solid planters, no added blockers")
	check(shape.obstacle_style == "ginkgo_planters", "Visual style identifies the existing wall snapshot")
	var layout := Layout.layout("ginkgo_arcade", View.WORLD_ARENA)
	check(layout.ok, "Actual bounds admit full fixed layout")
	var landmarks: Dictionary = layout.landmarks
	check(landmarks.entry == origin + Vector2(920,670), "Entry is the exact approved origin-relative point")
	var centers := [Vector2(230,150), Vector2(920,100), Vector2(1690,150)]
	var triggers := [Vector2(230,570), Vector2(1310,130), Vector2(1600,570)]
	var all_positions: Array[Vector2] = []
	var disks: Array[Dictionary] = []
	disks.assign(landmarks.camps)
	disks.append(landmarks.boss)
	for wave: int in [3,6,10]:
		for template_id: String in Monsters.TEMPLATES:
			var enemy: Dictionary = Monsters.make_enemy(1, template_id, wave, landmarks.entry, "map_boss" if template_id == "rift_warden" else "ordinary")
			check(not enemy.is_empty(), "Real factory produces every known body at each map wave")
			if template_id == "rift_warden": boss_radius = maxf(boss_radius, float(enemy.radius))
			else: max_ordinary_radius = maxf(max_ordinary_radius, float(enemy.radius))
	check(max_ordinary_radius == 22.0 and boss_radius == 27.5, "Real maximum ordinary and boss radii stay 22 and 27.5")
	for index: int in range(3):
		var camp: Dictionary = landmarks.camps[index]
		check(camp.id == State.CAMP_IDS[index] and camp.center == origin + centers[index] and camp.trigger_center == origin + triggers[index], "Stable camp ID and final exact coordinates")
		check(camp.root_count == 12 and camp.positions.size() == 12 and camp.trigger_radius == 64.0, "Complete twelve-root formation and radius-64 trigger")
		check(geometry.is_clear(camp.center, 22.0) and geometry.is_clear(camp.trigger_center, 15.0), "Formation and activation point clear actual walls")
		check(geometry.is_clear(camp.trigger_center, 79.0), "Whole activation circle plus player's body stays clear of walls/bounds")
		var expected_positions: Array[Vector2] = []
		for y: float in [-56.0,0.0,56.0]:
			for x: float in [-84.0,-28.0,28.0,84.0]: expected_positions.append(camp.center + Vector2(x,y))
		check(camp.positions == expected_positions, "Unscaled four columns by three rows retain all twelve slots")
		for point: Vector2 in camp.positions:
			all_positions.append(point)
			check(geometry.is_clear(point, max_ordinary_radius), "Each maximum ordinary body clears every wall and boundary")
			for disk: Dictionary in disks:
				var gap: float = point.distance_to(disk.trigger_center) - float(disk.trigger_radius)
				min_trigger_gap = minf(min_trigger_gap, gap)
				check(gap >= Admission.PLAYER_CLEARANCE, "Exact root-to-disk lower bound covers all four full activation circles")
			_route(geometry, point, camp.trigger_center, 22.0)
			_route(geometry, camp.trigger_center, point, 22.0)
	check(all_positions.size() == 36, "All three simultaneous formations contain 36 roots")
	for first: int in range(all_positions.size()):
		for second: int in range(first+1, all_positions.size()):
			var gap := all_positions[first].distance_to(all_positions[second]) - 44.0
			min_body_gap = minf(min_body_gap, gap)
			check(gap >= 0.0, "Every pair of maximum-size simultaneous root bodies remains disjoint")
	var boss: Dictionary = landmarks.boss
	check(boss.center == origin + Vector2(1530,330) and boss.trigger_center == origin + Vector2(1530,650) and boss.trigger_radius == 64.0, "Exact boss center and trigger contract")
	check(geometry.is_clear(boss.center, boss_radius) and geometry.is_clear(boss.trigger_center, 15.0), "Real boss and player activation bodies clear walls and bounds")
	check(Vector2(boss.center).distance_to(boss.trigger_center) - float(boss.trigger_radius) == 256.0, "Whole boss activation disk keeps 256-unit spawn clearance")
	var candidate_gap: float = Vector2(1516,150).distance_to(Vector2(1310,130)) - 64.0
	check(candidate_gap < 230.0, "Original east-center candidate is explicitly rejected for cross-trigger safety")
	# All directional pairs cover the ring's upper/lower halves, central side
	# passages, outside side planters, every camp, entry, and boss landmarks.
	var route_points: Array[Vector2] = [landmarks.entry, boss.center, boss.trigger_center]
	for camp: Dictionary in landmarks.camps: route_points.append_array([camp.center, camp.trigger_center])
	for point: Vector2 in [Vector2(120,355), Vector2(570,355), Vector2(1255,355), Vector2(1660,400), Vector2(920,200), Vector2(920,510)]: route_points.append(origin + point)
	for radius: float in [15.0,22.0,27.5]:
		for start: Vector2 in route_points:
			for goal: Vector2 in route_points:
				if start != goal: _route(geometry, start, goal, radius)
	for wall: Rect2 in shape.walls:
		var a := Vector2(wall.position.x - 40, wall.get_center().y)
		var b := Vector2(wall.end.x + 40, wall.get_center().y)
		for radius: float in [0.0,4.5,15.0,22.0,27.5]:
			check(geometry.sweep(a,b,radius).hit and not geometry.visible(a,b,radius), "Each authored wall blocks projectiles, sight and actual bodies")
	check(var_to_bytes(geometry.snapshot()) == var_to_bytes(shape), "Validation/navigation never changes authoritative geometry")
	var shifted := Rect2(Vector2(-150,50), View.WORLD_ARENA.size)
	var translated := Layout.layout("ginkgo_arcade", shifted)
	check(translated.ok and translated.landmarks.camps[2].center == shifted.position + Vector2(1690,150), "Origin changes translate without rescaling the corrected formation")


func _route(geometry: RefCounted, start: Vector2, goal: Vector2, radius: float) -> void:
	var point := start
	var valid: bool = geometry.is_clear(start,radius) and geometry.is_clear(goal,radius)
	var steps := 0
	while valid and point.distance_to(goal) > 0.05 and steps < 900:
		var direction: Vector2 = geometry.direction(point,goal,radius,5.0)
		var next: Vector2 = geometry.move(point,point+direction*5.0,radius)
		valid = next.is_finite() and geometry.is_clear(next,radius) and geometry.visible(point,next,radius)
		if next == point: break
		point = next
		steps += 1
	routes += 1
	check(valid and point.distance_to(goal) <= 0.05, "Real bidirectional navigation converges: %s -> %s radius %.1f" % [start,goal,radius])


func _normal_choices() -> Array[Array]:
	var choices: Array[Array] = [[]]
	var ids: Array[String] = Modifiers.get_ids()
	for first: int in range(ids.size()):
		choices.append([ids[first]])
		for second: int in range(first+1,ids.size()): choices.append([ids[first],ids[second]])
	return choices


func _test_legal_profiles() -> void:
	var geometry := Geometry.new()
	check(geometry.configure("ginkgo_arcade",View.WORLD_ARENA), "Admission uses actual Ginkgo geometry")
	var landmarks: Dictionary = Layout.layout("ginkgo_arcade",View.WORLD_ARENA).landmarks
	for tier: int in [0,1,2,3]:
		for normal: Array in _normal_choices():
			for special: Array in [[],["elemental_aegis"],["frost_patrol"],["storm_patrol"]]:
				var compiled := Maps.compile("ginkgo_arcade",normal,special) if tier == 0 else Maps.compile_normal("ginkgo_arcade",tier,normal,special)
				if tier == 1 and not special.is_empty():
					check(not compiled.ok, "Tier I wave three rejects all minimum-wave-four/five specials")
					continue
				check(compiled.ok and Maps.profile_reason(compiled.profile).is_empty(), "Every legal choice compiles to canonical profile")
				if not compiled.ok: continue
				profiles += 1
				var profile: Dictionary = compiled.profile
				check(profile.wave == [6,3,6,10][tier] and profile.ordinary_target == 36, "Fixed test and formal tiers keep exact wave/root budgets")
				if tier > 0:
					check(profile.fee == [0,4,8][tier-1] and profile.base_completion_reward == [4,8,12][tier-1], "Formal fees and base rewards inherit approved progression")
					check(profile.completion_reward == profile.base_completion_reward + normal.size() + 2*special.size() and profile.completion_reward <= profile.base_completion_reward+4, "Existing modifier reward bonus never exceeds four")
				var state := State.new()
				check(state.begin(profile,landmarks,43,Monsters.CURRENT_ROLL_POLICY).ok, "Actual frozen camp selection accepts legal profile")
				check(not Mist.eligible_profile(profile), "Ginkgo never qualifies for Sunwell-only mist replacement")
				var runtime := Runtime.new()
				for camp: Dictionary in landmarks.camps:
					var entries: Array[Dictionary] = state.entries(camp.id)
					var plan := Admission.plan(runtime,profile,entries,geometry,camp.trigger_center,100-runtime.roots.size())
					check(plan.ok and plan.enemies.size() == 12, "Actual twelve-root admission succeeds for every legal combination")
					if not plan.ok: continue
					var ids: Array[int] = []
					for enemy: Dictionary in plan.enemies:
						check(enemy.generation == 0 and enemy.root_id == enemy.id and enemy.reward_eligible and enemy.radius <= 22.0, "Ordinary roots retain identity, rewards and actual radius")
						check(enemy.template_id != "mist_skitter", "No new-map root becomes mist skitter")
						ids.append(enemy.id)
						admitted_roots += 1
					Encounter._restore(runtime,plan.runtime_checkpoint)
					check(state.activate(camp.id,ids), "Whole camp keeps unique root membership")
				var boss: Dictionary = landmarks.boss
				var boss_entries: Array[Dictionary] = [{"template_id":"rift_warden","rarity":"boss","mechanisms":[],"position":boss.center}]
				var plan := Admission.plan(runtime,profile,boss_entries,geometry,boss.trigger_center,64,"map_boss")
				check(plan.ok and plan.enemies.size() == 1, "Real boss admission succeeds after 36 ordinary identities")
				if plan.ok:
					var enemy: Dictionary = plan.enemies[0]
					var policy: Dictionary = Monsters.telegraph_policy(enemy)
					check(enemy.id == 37 and enemy.radius == 27.5 and enemy.map_boss_attack_id == "ginkgo_shelter_slam", "Boss is root 37 with exact radius and new attack metadata")
					check(policy.target_rule == "self_at_start" and policy.trigger_distance == 240.0 and policy.profile.radius == 240.0 and policy.profile.windup_seconds == 1.4 and policy.profile.damage_multiplier == 1.2, "Actual attack policy locks self at start with approved readable circle")
					check(is_equal_approx(float(policy.profile.recovery_seconds),1.9*Monsters.BASE_ATTACK_SPEED/float(enemy.attack_speed)), "Existing attack speed scales only base recovery")
					check(not Bosses.definition("ginkgo_shelter_slam").has("pulse_count"), "New attack uses the existing single-event scheduler path")
					admitted_roots += 1
				check(runtime.next_id == 36 and runtime.roots.size() == 36, "Detached boss plan cannot mutate committed root state")


func _roll(rng: RandomNumberGenerator, wave: int, policy: String) -> Dictionary:
	if policy == Monsters.CURRENT_ROLL_POLICY: return Monsters.ordinary_roll_current(rng,wave)
	if policy == Monsters.DAMAGE_LIFE_ROLL_POLICY: return Monsters.ordinary_roll_source_damage_life(rng,wave)
	if policy == Monsters.STRIDE_ROLL_POLICY: return Monsters.ordinary_roll_source_stride(rng,wave)
	return Monsters.ordinary_roll(rng,wave)


func _expected_template(wave: int, camp_id: String, ordinal: int, original: String) -> String:
	if original not in ["crawler","skitter","brute"]: return original
	var selected: String = EXPECTED_PATTERNS[camp_id][(ordinal-1)%6]
	if selected == "frost_guard" and wave < 4: return "brute"
	if selected == "storm_skitter" and wave < 5: return "skitter"
	return selected


func _test_roster_contract() -> void:
	check(Rules.PATTERNS == EXPECTED_PATTERNS, "Reviewed six-slot compositions are exact")
	var landmarks: Dictionary = Layout.layout("ginkgo_arcade",View.WORLD_ARENA).landmarks
	for wave: int in [3,4,5,6,10]:
		for camp_id: String in State.CAMP_IDS:
			for ordinal: int in range(1,13):
				for original: String in Monsters.TEMPLATES:
					var roll := {"template":original,"rarity":"rare","mechanisms":["grove_vitality"]}
					var before := var_to_bytes(roll)
					check(Rules.template_for_roll(wave,camp_id,ordinal,roll) == _expected_template(wave,camp_id,ordinal,original), "Mapping touches only base templates; min-wave fallbacks and reserved/fixed templates stay exact")
					check(var_to_bytes(roll) == before, "Roster mapper does not mutate source rarity or mechanisms")
	for tier: int in [0,1,2,3]:
		for special: Array in [[],["elemental_aegis"],["frost_patrol"],["storm_patrol"]]:
			var compiled := Maps.compile("ginkgo_arcade",[],special) if tier == 0 else Maps.compile_normal("ginkgo_arcade",tier,[],special)
			if not compiled.ok: continue
			var profile: Dictionary = compiled.profile
			for policy: String in POLICIES:
				for seed_value: int in [0,43,-71]:
					var state := State.new()
					check(state.begin(profile,landmarks,seed_value,policy).ok, "All supported source policies accept Ginkgo roster")
					var rng := RandomNumberGenerator.new()
					rng.seed = seed_value
					var admission_index := 0
					for camp: Dictionary in landmarks.camps:
						var entries: Array[Dictionary] = state.entries(camp.id)
						for index: int in range(entries.size()):
							admission_index += 1
							var reserved := Monsters.encounter_for_admission(profile.wave,admission_index)
							var expected: Dictionary = {"admission_index":admission_index,"template_id":reserved,"rarity":"","mechanisms":[],"position":camp.positions[index]}
							if reserved.is_empty():
								var roll := _roll(rng,profile.wave,policy)
								expected.template_id = _expected_template(profile.wave,camp.id,index+1,roll.template)
								expected.rarity = roll.rarity
								expected.mechanisms = roll.mechanisms
								if special.has("frost_patrol") and expected.template_id in ["brute","frost_guard"]: expected.template_id = "frost_guard"
								if special.has("storm_patrol") and expected.template_id in ["skitter","storm_skitter"]: expected.template_id = "storm_skitter"
							check(var_to_bytes(entries[index]) == var_to_bytes(expected), "Exact canonical RNG replay retains rarity, mechanisms, fixed ember/splitter/brood slots and final patrol precedence")
					var reverse := landmarks.duplicate(true)
					reverse.camps.reverse()
					var repeated := State.new()
					check(repeated.begin(profile,reverse,seed_value,policy).ok, "Reversed landmark order remains valid")
					for camp_id: String in State.CAMP_IDS:
						check(var_to_bytes(repeated.entries(camp_id)) == var_to_bytes(state.entries(camp_id)), "Frozen roster depends on canonical camp order only")
					roster_cases += 1


func _test_old_maps() -> void:
	for map_id: String in ["old_garden","broken_ruins","sunwell_terrace"]:
		check(var_to_bytes(Catalog.MAPS[map_id]) == var_to_bytes(oracles.map_catalog.MAPS[map_id]), "Old map metadata retains every original byte")
		var old_layout: Dictionary = oracles.map_camp_layout.layout(map_id,View.WORLD_ARENA)
		check(var_to_bytes(Layout.layout(map_id,View.WORLD_ARENA)) == var_to_bytes(old_layout), "Old map landmarks retain every original byte")
		var current_geometry := Geometry.new()
		var old_geometry: RefCounted = oracles.map_geometry.new()
		check(current_geometry.configure(map_id,View.WORLD_ARENA) and old_geometry.configure(map_id,View.WORLD_ARENA), "Both geometry implementations accept old map")
		check(var_to_bytes(current_geometry.snapshot()) == var_to_bytes(old_geometry.snapshot()), "Old walls, spawn, style, bounds, revision preserve exact bytes")
		var attack_id: String = Catalog.MAPS[map_id].boss_attack_id
		check(var_to_bytes(Bosses.definition(attack_id)) == var_to_bytes(oracles.map_boss_profiles.definition(attack_id)), "All released boss attacks keep exact profile bytes")
		for tier: int in [0,1,2,3]:
			if tier > 0:
				check(var_to_bytes(Normal.definition(map_id,tier)) == var_to_bytes(oracles.normal_map_catalog.definition(map_id,tier)), "Old three-tier progression outputs remain byte-identical")
			for normal: Array in [[],["enemy_max_health_120","enemy_attack_speed_110"]]:
				for special: Array in [[],["elemental_aegis"],["frost_patrol"],["storm_patrol"]]:
					var compiled := Maps.compile(map_id,normal,special) if tier == 0 else Maps.compile_normal(map_id,tier,normal,special)
					if not compiled.ok: continue
					for policy: String in [Monsters.LEGACY_ROLL_POLICY,Monsters.CURRENT_ROLL_POLICY]:
						for seed_value: int in [43,-71]:
							var current := State.new()
							var previous: RefCounted = oracles.map_camp_state.new()
							check(current.begin(compiled.profile,old_layout.landmarks,seed_value,policy).ok and previous.begin(compiled.profile,old_layout.landmarks,seed_value,policy).ok, "Same old-map seed/profile/source policy accepted")
							check(var_to_bytes(current.checkpoint()) == var_to_bytes(previous.checkpoint()), "Old three-map seed/roster/position/rarity/mechanism snapshots are exact baseline bytes")
							check(var_to_bytes(current.states({})) == var_to_bytes(previous.states({})), "Existing camp state output is byte-identical")
							old_cases += 1
	for test_mode: bool in [true,false]:
		var current := Catalog.options(test_mode)
		current.maps.pop_back()
		check(var_to_bytes(current) == var_to_bytes(oracles.map_catalog.options(test_mode)), "Removing only appended Ginkgo restores exact released map-device option bytes/order")


func _test_fixed_descendants() -> void:
	# Roster composition never runs when the existing death queue drains. Same
	# fixed root and modifier inputs therefore retain exact children and traces.
	for special: Array in [[],["elemental_aegis"],["frost_patrol"],["storm_patrol"]]:
		var current_profile: Dictionary = Maps.compile_normal("ginkgo_arcade",2,["enemy_max_health_120","enemy_shield_from_health_20"],special).profile
		var released_profile: Dictionary = Maps.compile_normal("sunwell_terrace",2,["enemy_max_health_120","enemy_shield_from_health_20"],special).profile
		for template_id: String in ["splitter","brood_host","ember_guard"]:
			var current := Runtime.new()
			var previous := Runtime.new()
			var point: Vector2 = View.WORLD_ARENA.position + Vector2(230,150)
			var a := RootAdmission.create_root(current,current_profile,template_id,6,point,"ordinary","",[],true)
			var b := RootAdmission.create_root(previous,released_profile,template_id,6,point,"ordinary","",[],true)
			check(a.ok and b.ok and var_to_bytes(a.enemy) == var_to_bytes(b.enemy), "Fixed special-root full stats/mechanisms/rewards match same-wave released map")
			if not a.ok or not b.ok: continue
			a.enemy.health = 0.0
			b.enemy.health = 0.0
			check(var_to_bytes(current.process_death(a.enemy)) == var_to_bytes(previous.process_death(b.enemy)), "Fixed special death and queue reservation retain exact output")
			var new_children := RootAdmission.drain(current,current_profile,100,View.WORLD_ARENA)
			var old_children := RootAdmission.drain(previous,released_profile,100,View.WORLD_ARENA)
			check(var_to_bytes(new_children) == var_to_bytes(old_children), "Descendant templates, IDs, positions, stats and reward eligibility remain exact")
			check(var_to_bytes(Encounter._snapshot(current)) == var_to_bytes(Encounter._snapshot(previous)), "Death lineage and FIFO trace retain complete exact checkpoint bytes")


func _test_activation_edges() -> void:
	var geometry := Geometry.new()
	check(geometry.configure("ginkgo_arcade",View.WORLD_ARENA), "Worst-edge admission uses real geometry")
	var landmarks: Dictionary = Layout.layout("ginkgo_arcade",View.WORLD_ARENA).landmarks
	var profile: Dictionary = Maps.compile_normal("ginkgo_arcade",3,[],[]).profile
	var state := State.new()
	check(state.begin(profile,landmarks,43,Monsters.CURRENT_ROLL_POLICY).ok, "Worst-edge roster uses actual current source policy")
	var disks: Array[Dictionary] = []
	disks.assign(landmarks.camps)
	disks.append(landmarks.boss)
	var runtime := Runtime.new()
	var before := var_to_bytes(Encounter._snapshot(runtime))
	for camp: Dictionary in landmarks.camps:
		for disk: Dictionary in disks:
			var nearest: Vector2 = camp.positions[0]
			for point: Vector2 in camp.positions:
				if point.distance_to(disk.trigger_center) < nearest.distance_to(disk.trigger_center): nearest = point
			var edge: Vector2 = disk.trigger_center + Vector2(nearest-disk.trigger_center).normalized()*float(disk.trigger_radius)
			check(geometry.is_clear(edge,15.0), "Nearest activation boundary is actually reachable by the player")
			var plan := Admission.plan(runtime,profile,state.entries(camp.id),geometry,edge,100)
			check(plan.ok and plan.enemies.size() == 12, "Full camp passes authoritative admission at nearest edge of every trigger disk")
	check(var_to_bytes(Encounter._snapshot(runtime)) == before, "All detached worst-edge plans leave runtime identities/queue untouched")
	var rejected_entries: Array[Dictionary] = state.entries("camp_east")
	for entry: Dictionary in rejected_entries: entry.position -= Vector2(90,0)
	var rejected := Admission.plan(runtime,profile,rejected_entries,geometry,landmarks.camps[1].trigger_center,100)
	check(not rejected.ok and rejected.error == "营地成员距离玩家过近", "Original x1600 candidate also fails the real 230-unit admission gate")
	check(var_to_bytes(Encounter._snapshot(runtime)) == before, "Unsafe original candidate rejects atomically without consuming any identity")
