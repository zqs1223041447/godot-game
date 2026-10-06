extends SceneTree
const Catalog = preload("res://scripts/world/map_catalog.gd")
const Normal = preload("res://scripts/world/normal_map_catalog.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const State = preload("res://scripts/world/map_camp_state.gd")
const Rules = preload("res://scripts/world/sunwell_roster_rules.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const Camps = preload("res://scripts/world/map_camp_admission.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Modifiers = preload("res://scripts/encounters/encounter_catalog.gd")
const BOUNDS := Rect2(Vector2(42, 104), Vector2(1196, 462) / 0.65)
const ORDERS: Array = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
const EXPECTED_PATTERNS: Array = [
	["brute", "frost_guard", "brute", "crawler", "frost_guard", "skitter"],
	["crawler", "brute", "skitter", "frost_guard", "crawler", "storm_skitter"],
	["skitter", "storm_skitter", "skitter", "crawler", "storm_skitter", "brute"],
]
var checks := 0
var failures := 0
var profiles := 0
var admitted_groups := 0
var admitted_roots := 0
var minimum_player_distance := INF
var minimum_body_gap := INF
var maximum_radius := 0.0
var coverage: Dictionary = {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	_catalog_and_layout()
	_patterns_and_rng()
	_all_profile_admissions()
	_maximum_bodies_and_transactions()
	_activation_orders()
	_geometry_routes()
	var report := {"checks": checks, "failures": failures, "profiles": profiles,
		"admitted_groups": admitted_groups, "admitted_roots": admitted_roots,
		"minimum_player_distance": minimum_player_distance, "minimum_body_gap": minimum_body_gap,
		"maximum_radius": maximum_radius, "template_coverage": coverage.keys()}
	var output := FileAccess.open("res://docs/qa/v048-layout/layout-report.json", FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(report, "\t") + "\n")
	print("Sunwell layout/roster: %d checks, %d failures; %d profiles; %d groups, %d roots" % [checks, failures, profiles, admitted_groups, admitted_roots])
	quit(1 if failures else 0)


func _catalog_and_layout() -> void:
	check(Catalog.MAPS.keys() == ["old_garden", "broken_ruins", "sunwell_terrace"], "New map is the third catalog entry")
	var fixed: Dictionary = Maps.compile("sunwell_terrace", [], []).profile
	check(fixed.wave == 6 and fixed.ordinary_target == 36 and fixed.boss_id == "rift_warden" and fixed.boss_attack_id == "sunwell_echo", "Fixed map contract")
	for tier: int in range(1, 4):
		var row := Normal.definition("sunwell_terrace", tier)
		check(row.wave == [3, 6, 10][tier - 1] and row.cost == [0, 4, 8][tier - 1] and row.base_reward == [4, 8, 12][tier - 1], "New normal tier preserves cost/reward ladder")
	check(not Maps.compile_normal("sunwell_terrace", 1, [], ["frost_patrol"]).ok and not Maps.compile_normal("sunwell_terrace", 1, [], ["storm_patrol"]).ok, "Tier I obeys elemental gates")
	for origin: Vector2 in [BOUNDS.position, Vector2(-317, 801)]:
		var layout := Layout.layout("sunwell_terrace", Rect2(origin, BOUNDS.size))
		check(layout.ok, "Offset sunwell layout is valid")
		var marks: Dictionary = layout.landmarks
		check(marks.entry == origin + Vector2(920, 670) and marks.boss.center == origin + Vector2(920, 355) and marks.boss.trigger_center == origin + Vector2(920, 670), "Entry and boss landmarks are exact")
		for index: int in range(3):
			var camp: Dictionary = marks.camps[index]
			check(camp.id == Layout.CAMP_IDS[index] and camp.name == ["西泉据点", "北门据点", "东阶据点"][index] and camp.root_count == 12, "Stable IDs, new names, twelve roots")
			check(camp.center == origin + [Vector2(290, 160), Vector2(920, 130), Vector2(1550, 540)][index], "Exact camp center")
			check(camp.trigger_center == origin + [Vector2(290, 590), Vector2(920, 550), Vector2(1550, 120)][index], "Exact remote trigger center")
			for ordinal: int in range(12):
				check(camp.positions[ordinal] == camp.center + Vector2(-84 + (ordinal % 4) * 56, -56 + (ordinal / 4) * 56), "Unscaled four by three formation")
	check(not Layout.layout("sunwell_terrace", Rect2(Vector2.ZERO, Vector2(1839, 710))).ok, "Undersized sunwell layout rejects without compressing roots")


func _expected_template(wave: int, camp_index: int, ordinal: int, original: String) -> String:
	if original not in ["crawler", "skitter", "brute"]: return original
	var selected: String = EXPECTED_PATTERNS[camp_index][ordinal % 6]
	if selected == "frost_guard" and wave < 4: return "brute"
	if selected == "storm_skitter" and wave < 5: return "skitter"
	return selected


func _patterns_and_rng() -> void:
	for wave: int in [1, 3, 4, 5, 6, 10]:
		for camp_index: int in range(3):
			for ordinal: int in range(12):
				for source: String in ["crawler", "brute", "skitter", "splitter", "brood_host"]:
					var roll := {"template": source, "rarity": "rare", "mechanisms": ["ember_power", "gale_stride"]}
					var before := var_to_bytes(roll)
					check(Rules.template_for_roll(wave, Layout.CAMP_IDS[camp_index], ordinal + 1, roll) == _expected_template(wave, camp_index, ordinal, source), "Small pattern and wave gate are exact")
					check(var_to_bytes(roll) == before, "Composition never mutates original roll")
	for tier: int in [0, 1, 2, 3]:
		for special: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
			var compiled := Maps.compile("sunwell_terrace", [], special) if tier == 0 else Maps.compile_normal("sunwell_terrace", tier, [], special)
			if not compiled.ok: continue
			var profile: Dictionary = compiled.profile
			for seed_value: int in range(16):
				var state := State.new()
				check(state.begin(profile, Layout.layout(profile.id, BOUNDS).landmarks, seed_value).ok, "New roster freezes")
				var rng := RandomNumberGenerator.new()
				rng.seed = seed_value
				var index := 0
				for camp_index: int in range(3):
					var entries: Array[Dictionary] = state.entries(Layout.CAMP_IDS[camp_index])
					var mist_selected := false
					for ordinal: int in range(entries.size()):
						index += 1
						var entry: Dictionary = entries[ordinal]
						check(entry.admission_index == index, "Global admission ordinal is unchanged")
						if index % 8 == 0:
							check(entry.template_id == "ember_guard" and entry.rarity == "" and entry.mechanisms.is_empty(), "Reserved ember slots consume no ordinary roll")
						else:
							var roll := Monsters.ordinary_roll(rng, profile.wave)
							var expected := _expected_template(profile.wave, camp_index, ordinal, roll.template)
							var species: String = {"frost_guard": "brute", "storm_skitter": "skitter"}.get(expected, expected)
							if special.has("frost_patrol") and species == "brute": expected = "frost_guard"
							if special.has("storm_patrol") and species == "skitter": expected = "storm_skitter"
							if tier in [2, 3] and not mist_selected and expected == "skitter" and roll.rarity == "normal":
								expected = "mist_skitter"
								mist_selected = true
							check(entry.template_id == expected and entry.rarity == roll.rarity and entry.mechanisms == roll.mechanisms, "Independent original RNG stream, unchanged rarity/mechanisms, composed species and final special precedence")
						coverage[entry.template_id] = true
	for id: String in ["crawler", "brute", "skitter", "mist_skitter", "splitter", "brood_host", "ember_guard", "frost_guard", "storm_skitter"]:
		check(coverage.has(id), "Natural new-map seeds cover " + id)


func _normal_selections() -> Array:
	# Every modifier appears; none changes radius. Cover the largest health/shield
	# package, faster movement/attacks, and damage/armour without a full matrix.
	return [[], ["enemy_max_health_120", "enemy_shield_from_health_20"],
		["enemy_move_speed_110", "enemy_attack_speed_110"], ["enemy_damage_115", "enemy_armour_80"]]


func _all_profile_admissions() -> void:
	for tier: int in [0, 1, 2, 3]:
		for normal: Array in _normal_selections():
			for special: Array in [[], ["elemental_aegis"], ["frost_patrol"], ["storm_patrol"]]:
				var compiled := Maps.compile("sunwell_terrace", normal, special) if tier == 0 else Maps.compile_normal("sunwell_terrace", tier, normal, special)
				if compiled.ok: _admit_profile(compiled.profile)


func _trigger_edge(mark: Dictionary, positions: Array) -> Vector2:
	var nearest: Vector2 = positions[0]
	for position: Vector2 in positions:
		if position.distance_squared_to(mark.trigger_center) < nearest.distance_squared_to(mark.trigger_center): nearest = position
	return mark.trigger_center + (nearest - Vector2(mark.trigger_center)).normalized() * float(mark.trigger_radius)


func _admit_profile(profile: Dictionary) -> void:
	profiles += 1
	var layout := Layout.layout(profile.id, BOUNDS)
	var geometry := Geometry.new()
	check(layout.ok and geometry.configure(profile.id, BOUNDS), "Every profile uses its actual static geometry")
	var state := State.new()
	check(state.begin(profile, layout.landmarks, 4348).ok, "Every profile freezes a real roster")
	var runtime := Runtime.new()
	var all_roots: Array[Dictionary] = []
	for mark: Dictionary in layout.landmarks.camps:
		var player := _trigger_edge(mark, mark.positions)
		var before := var_to_bytes(Encounter._snapshot(runtime))
		var result := Camps.plan(runtime, profile, state.entries(mark.id), geometry, player, 100 - all_roots.size())
		check(result.ok, "Actual camp admission at closest trigger edge: " + profile.summary + " / " + mark.id + " / " + str(result.error))
		check(var_to_bytes(Encounter._snapshot(runtime)) == before, "Camp planning remains transactional")
		if not result.ok: continue
		admitted_groups += 1
		for enemy: Dictionary in result.enemies:
			admitted_roots += 1
			maximum_radius = maxf(maximum_radius, enemy.radius)
			var safe_distance: float = enemy.pos.distance_to(mark.trigger_center) - mark.trigger_radius
			minimum_player_distance = minf(minimum_player_distance, safe_distance)
			check(safe_distance >= 230.0 and enemy.spawn == 0.6, "Every point of trigger disk preserves clearance and birth protection")
			check(geometry.is_clear(enemy.pos, enemy.radius), "Every actual final body is outside basins and bounds")
			for previous: Dictionary in all_roots:
				var gap: float = enemy.pos.distance_to(previous.pos) - enemy.radius - previous.radius
				minimum_body_gap = minf(minimum_body_gap, gap)
				check(gap >= 0.0, "All three groups can coexist without fixed body overlap")
			all_roots.append(enemy)
		Encounter._restore(runtime, result.runtime_checkpoint)
	check(all_roots.size() == profile.ordinary_target, "Entire 24/36 roster is admitted with 100 live cap")
	var boss: Dictionary = layout.landmarks.boss
	var entries: Array[Dictionary] = [{"template_id": profile.boss_id, "rarity": "", "mechanisms": [], "position": boss.center}]
	var admitted := Camps.plan(Runtime.new(), profile, entries, geometry, _trigger_edge(boss, [boss.center]), 100, "map_boss")
	check(admitted.ok, "Actual boss admission at closest edge: " + profile.summary)
	if admitted.ok:
		check(admitted.enemies[0].radius == 27.5 and admitted.enemies[0].spawn == 0.6, "Largest boss radius and protection remain exact")
		maximum_radius = maxf(maximum_radius, admitted.enemies[0].radius)
		minimum_player_distance = minf(minimum_player_distance, boss.center.distance_to(boss.trigger_center) - boss.trigger_radius)


func _maximum_bodies_and_transactions() -> void:
	var profile: Dictionary = Maps.compile_normal("sunwell_terrace", 3, ["enemy_max_health_120", "enemy_shield_from_health_20"], ["elemental_aegis"]).profile
	var marks: Dictionary = Layout.layout(profile.id, BOUNDS).landmarks
	var geometry := Geometry.new()
	geometry.configure(profile.id, BOUNDS)
	for mark: Dictionary in marks.camps:
		var entries: Array[Dictionary] = []
		for position: Vector2 in mark.positions:
			entries.append({"template_id": "brute", "rarity": "rare", "mechanisms": ["grove_vitality", "aegis_capacity"], "position": position})
		var runtime := Runtime.new()
		var before := var_to_bytes(Encounter._snapshot(runtime))
		var player := _trigger_edge(mark, mark.positions)
		var result := Camps.plan(runtime, profile, entries, geometry, player, 100)
		check(result.ok and result.enemies.size() == 12, "All twelve maximum ordinary bodies fit every sunwell camp")
		if result.ok:
			for enemy: Dictionary in result.enemies: check(enemy.radius == 22.0, "Worst-case body retains actual catalog radius")
		check(not Camps.plan(runtime, profile, entries, geometry, player, 11).ok, "Insufficient whole-group capacity rejects")
		check(not Camps.plan(runtime, profile, entries, geometry, entries[0].position + Vector2(229, 0), 100).ok, "Below 230 player clearance rejects")
		var obstructed := entries.duplicate(true)
		obstructed[11].position = BOUNDS.position + Vector2(620, 210)
		check(not Camps.plan(runtime, profile, obstructed, geometry, player, 100).ok, "Final obstructed member rejects entire group")
		check(var_to_bytes(Encounter._snapshot(runtime)) == before, "All positive and negative plans leave live factory unchanged")


func _activation_orders() -> void:
	var profile: Dictionary = Maps.compile("sunwell_terrace", [], []).profile
	var marks: Dictionary = Layout.layout(profile.id, BOUNDS).landmarks
	var baseline := PackedByteArray()
	for order: Array in ORDERS:
		var state := State.new()
		state.begin(profile, marks, 4348)
		var initial := var_to_bytes(state.checkpoint())
		if baseline.is_empty(): baseline = initial
		check(initial == baseline, "Activation order never changes frozen composition")
		var root_ids: Array[int] = []
		var defeated: Dictionary = {}
		for index: int in order:
			root_ids.clear()
			for ordinal: int in range(12): root_ids.append(1 + index * 12 + ordinal)
			check(state.activate(Layout.CAMP_IDS[index], root_ids), "Any dormant camp can activate next")
		var active := 0
		for row: Dictionary in state.states({}):
			if row.state == "active": active += 1
		check(active == 3, "All 36 roots stay active together without clearing other camps")
		for root_id: int in range(1, 37): defeated[root_id] = true
		for row: Dictionary in state.states(defeated): check(row.state == "cleared" and row.roots_defeated == 12, "All six orders complete the same root memberships")


func _geometry_routes() -> void:
	var geometry := Geometry.new()
	geometry.configure("sunwell_terrace", BOUNDS)
	var shape := geometry.snapshot()
	check(shape.obstacle_style == "spring_basin" and shape.walls.size() == 4, "Only new map supplies basin style")
	var offsets: Array[Vector2] = [Vector2(520, 140), Vector2(1080, 140), Vector2(520, 430), Vector2(1080, 430)]
	for index: int in range(4):
		var expected := Rect2(BOUNDS.position + offsets[index], Vector2(240, 140))
		check(shape.walls[index] == expected and not geometry.is_clear(expected.get_center(), 0.0), "Basin rectangle blocks its entire interior")
		var left := expected.get_center() - Vector2(170, 0)
		var right := expected.get_center() + Vector2(170, 0)
		check(not geometry.visible(left, right) and geometry.sweep(left, right, 6.0).hit, "Each basin blocks LOS and projectile sweep")
		check(geometry.move(left, right, 22.0).x <= expected.position.x - 22.0, "Each basin blocks actual body motion")
	var marks: Dictionary = Layout.layout("sunwell_terrace", BOUNDS).landmarks
	var points: Array[Vector2] = [marks.entry, marks.boss.center]
	for camp: Dictionary in marks.camps: points.append_array([camp.center, camp.trigger_center])
	for radius: float in [10.0, 14.0, 22.0, 27.5]:
		for start: Vector2 in points:
			for goal: Vector2 in points:
				var position := start
				for step: int in range(600):
					if position.distance_to(goal) <= 1.0: break
					var direction := geometry.direction(position, goal, radius, 8.0)
					if direction == Vector2.ZERO: break
					position = geometry.move(position, position + direction * 8.0, radius)
				check(position.distance_to(goal) <= 1.0, "Every camp/trigger/entry/boss pair has a traversable route at radius %.1f" % radius)
	for map_id: String in ["normal", "town", "old_garden", "broken_ruins"]:
		geometry.configure(map_id, BOUNDS)
		check(not geometry.snapshot().has("obstacle_style"), "Legacy geometry snapshots gain no metadata field")
