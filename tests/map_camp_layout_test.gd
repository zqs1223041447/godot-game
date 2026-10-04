extends SceneTree
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const NormalMaps = preload("res://scripts/world/normal_map_catalog.gd")
const PLAYER_RADIUS := 15.0
const MIN_SPAWN_DISTANCE := 230.0
const EXPECTED_IDS := ["camp_west", "camp_north", "camp_east"]
const EXPECTED_NAMES := ["西侧据点", "北侧据点", "东侧据点"]
var checks := 0
var failures := 0
var profile_count := 0
var arrangement_count := 0
var route_count := 0
var minimum_root_gap := INF
var minimum_boss_gap := INF
var minimum_body_gap := INF


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	seed(430043)
	var expected_rng := randi()
	seed(430043)
	_test_current_profiles()
	_test_detachment_and_bounds()
	_test_trigger_segments()
	check(profile_count == 6 and arrangement_count == 6 and route_count == 210, "Every required profile, camp arrangement, and route reached the proof")
	check(randi() == expected_rng, "Layout, trigger intersection, and validation never consume global RNG")
	print("Map camp layout: %d checks, %d failures; %d actual normal profiles; %d distinct camp arrangements; %d navigation routes" % [checks, failures, profile_count, arrangement_count, route_count])
	print("Proof minima: root center to full activation disk %.6f >= 230; boss center to full activation disk %.6f >= 230; simultaneous root body clearance %.6f >= 0" % [minimum_root_gap, minimum_boss_gap, minimum_body_gap])
	print("Actual bounds: position=%s size=%s; player radius=15; ordinary Catalog maximum=22; Catalog boss=27.5" % [View.WORLD_ARENA.position, View.WORLD_ARENA.size])
	quit(1 if failures else 0)


func _test_current_profiles() -> void:
	for map_id: String in ["old_garden", "broken_ruins"]:
		var geometry = Geometry.new()
		check(geometry.configure(map_id, View.WORLD_ARENA), map_id + ": current geometry accepts actual bounds")
		var original_geometry: Dictionary = geometry.snapshot()
		var layout: Dictionary = Layout.layout(map_id, View.WORLD_ARENA)
		check(layout.ok and layout.reason.is_empty(), map_id + ": valid layout")
		if not layout.ok:
			continue
		var landmarks: Dictionary = layout.landmarks
		var camps: Array = landmarks.camps
		var boss: Dictionary = landmarks.boss
		var entry: Vector2 = landmarks.entry
		check(camps.size() == 3, map_id + ": three independently addressable camps")
		check(entry == View.WORLD_ARENA.position + Vector2(920, 670), map_id + ": approved entry offset")
		check(geometry.is_clear(entry, PLAYER_RADIUS), map_id + ": entry body clear of walls and bounds")
		var expected_centers := [Vector2(290, 170), Vector2(920, 130), Vector2(1550, 170)] if map_id == "old_garden" else [Vector2(270, 150), Vector2(920, 150), Vector2(1570, 150)]
		var expected_triggers := [Vector2(290, 590), Vector2(920, 550), Vector2(1550, 590)] if map_id == "old_garden" else [Vector2(270, 570), Vector2(920, 570), Vector2(1570, 570)]
		for index: int in range(camps.size()):
			var camp: Dictionary = camps[index]
			arrangement_count += 1
			check(camp.id == EXPECTED_IDS[index] and camp.name == EXPECTED_NAMES[index], map_id + ": stable camp identity/name")
			check(camp.center == View.WORLD_ARENA.position + expected_centers[index] and camp.trigger_center == View.WORLD_ARENA.position + expected_triggers[index], map_id + ": approved fixed camp/trigger offsets")
			check(camp.root_count == (8 if map_id == "old_garden" else 12) and camp.positions.size() == camp.root_count, map_id + ": full group positions present")
			check(camp.trigger_radius == 64.0, map_id + ": trigger radius 64")
			check(entry.distance_to(camp.trigger_center) > float(camp.trigger_radius), map_id + ": entry outside every camp trigger")
			check(geometry.is_clear(camp.trigger_center, PLAYER_RADIUS), map_id + ": trigger point reachable without wall overlap")
			var expected_positions: Array[Vector2] = []
			for y: float in ([-28.0, 28.0] if map_id == "old_garden" else [-56.0, 0.0, 56.0]):
				for x: float in [-84.0, -28.0, 28.0, 84.0]:
					expected_positions.append(Vector2(camp.center) + Vector2(x, y))
			check(camp.positions == expected_positions, map_id + ": exact four-column formation, not scaled")
			_test_route(geometry, entry, camp.trigger_center, PLAYER_RADIUS, map_id + ": entry can choose " + str(camp.id))
		check(boss.id == "rift_warden" and boss.name == "裂隙守卫" and boss.trigger_radius == 64.0, map_id + ": boss identity and trigger contract")
		check(boss.center == View.WORLD_ARENA.position + (Vector2(920, 355) if map_id == "old_garden" else Vector2(1530, 320)), map_id + ": approved boss center")
		check(boss.trigger_center == View.WORLD_ARENA.position + (Vector2(920, 670) if map_id == "old_garden" else Vector2(1530, 650)), map_id + ": approved boss trigger")
		check(geometry.is_clear(boss.trigger_center, PLAYER_RADIUS), map_id + ": boss trigger point clear")
		# Every ordered camp-to-camp route supports choosing any next camp while
		# previously activated camps remain active. The east ruins route detours.
		for first: Dictionary in camps:
			for second: Dictionary in camps:
				if first.id != second.id:
					_test_route(geometry, first.trigger_center, second.trigger_center, PLAYER_RADIUS, map_id + ": camp order " + str(first.id) + " -> " + str(second.id))
			_test_route(geometry, first.trigger_center, boss.trigger_center, PLAYER_RADIUS, map_id + ": camp to boss trigger")
		if map_id == "broken_ruins":
			check(not geometry.visible(entry, camps[2].trigger_center, PLAYER_RADIUS), "Ruins east choice actually exercises navigation around the second wall")
		for tier: int in range(1, 4):
			var compiled: Dictionary = Maps.compile_normal(map_id, tier, [], [])
			check(compiled.ok and Maps.profile_reason(compiled.profile).is_empty(), "%s tier %d: real canonical profile" % [map_id, tier])
			if not compiled.ok:
				continue
			profile_count += 1
			var profile: Dictionary = compiled.profile
			check(profile.wave == NormalMaps.definition(map_id, tier).wave, "Profile uses actual tier wave")
			var radii: Array[float] = []
			for template_id: String in Catalog.TEMPLATES:
				if Catalog.TEMPLATES[template_id].rarity == "boss":
					continue
				var root_enemy: Dictionary = Catalog.make_enemy(1, template_id, profile.wave, entry)
				check(not root_enemy.is_empty(), "Every ordinary/special/death template has an actual Catalog body")
				radii.append(float(root_enemy.radius))
			check(radii.max() == 22.0, "Ordinary Catalog maximum is 22 at every tier")
			var total_roots := 0
			var all_positions: Array[Vector2] = []
			for camp: Dictionary in camps:
				total_roots += int(camp.root_count)
				check(geometry.is_clear(camp.center, radii.max()), "Every formation center clears actual walls/bounds at maximum root radius")
				for position: Vector2 in camp.positions:
					all_positions.append(position)
					for radius: float in radii:
						check(geometry.is_clear(position, radius), "Each formation root with every Catalog body clears actual walls/bounds")
					var disk_gap: float = position.distance_to(camp.trigger_center) - float(camp.trigger_radius)
					minimum_root_gap = minf(minimum_root_gap, disk_gap)
					check(disk_gap >= MIN_SPAWN_DISTANCE, "Exact point-to-disk lower bound covers every activation point, not sampled angles")
					_test_route(geometry, position, camp.trigger_center, radii.max(), "Maximum root body can pursue its trigger point")
				# Cross-camp triggers also remain safe when multiple camps activate.
				for other: Dictionary in camps:
					for position: Vector2 in camp.positions:
						check(position.distance_to(other.trigger_center) - float(other.trigger_radius) >= MIN_SPAWN_DISTANCE, "Each root is safely separated from all three trigger disks")
			check(total_roots == profile.ordinary_target, "All three complete groups exactly match the actual profile root target")
			for first: int in range(all_positions.size()):
				for second: int in range(first + 1, all_positions.size()):
					var body_gap: float = all_positions[first].distance_to(all_positions[second]) - 2.0 * float(radii.max())
					minimum_body_gap = minf(minimum_body_gap, body_gap)
					check(body_gap >= 0.0, "All simultaneously active root circles are disjoint")
			var boss_enemy: Dictionary = Catalog.make_enemy(1, profile.boss_id, profile.wave, boss.center, "map_boss")
			check(not boss_enemy.is_empty() and boss_enemy.radius == 27.5, "Boss radius comes from actual tier Catalog construction")
			check(geometry.is_clear(boss.center, boss_enemy.radius), "Boss body clear of actual bounds and ruins walls")
			var boss_gap: float = Vector2(boss.center).distance_to(boss.trigger_center) - float(boss.trigger_radius)
			minimum_boss_gap = minf(minimum_boss_gap, boss_gap)
			check(boss_gap >= MIN_SPAWN_DISTANCE, "Boss safe at every point in full activation disk")
			_test_route(geometry, boss.center, boss.trigger_center, boss_enemy.radius, "Boss body can reach its trigger point")
		check(geometry.snapshot() == original_geometry, "Layout and navigation do not mutate geometry authority")
	check(profile_count == 6 and arrangement_count == 6, "All six actual normal map/tier profiles and six distinct camps checked")


func _test_route(geometry, start: Vector2, goal: Vector2, radius: float, label: String) -> void:
	var point := start
	var valid := true
	var steps := 0
	while point.distance_to(goal) > 0.05 and steps < 800:
		var direction: Vector2 = geometry.direction(point, goal, radius, 5.0)
		var next: Vector2 = geometry.move(point, point + direction * 5.0, radius)
		valid = valid and next.is_finite() and geometry.is_clear(next, radius) and geometry.visible(point, next, radius)
		if next == point:
			break
		point = next
		steps += 1
	route_count += 1
	check(valid and point.distance_to(goal) <= 0.05, label + ": real navigation converges with clear 5-unit movement segments")


func _test_detachment_and_bounds() -> void:
	for map_id: String in ["old_garden", "broken_ruins"]:
		var original: Dictionary = Layout.layout(map_id, View.WORLD_ARENA)
		var changed: Dictionary = Layout.layout(map_id, View.WORLD_ARENA)
		changed.landmarks.camps[0].positions[0] = Vector2.ZERO
		changed.landmarks.camps[0].name = "changed"
		changed.landmarks.camps[1].positions.clear()
		changed.landmarks.boss.center = Vector2.ZERO
		changed.landmarks.entry = Vector2.ZERO
		changed.landmarks.camps.clear()
		check(Layout.layout(map_id, View.WORLD_ARENA) == original, "Nested arrays/dictionaries are detached across calls")
		var same_call: Dictionary = Layout.layout(map_id, View.WORLD_ARENA)
		same_call.landmarks.camps[0].positions.clear()
		check(same_call.landmarks.camps[1].positions.size() == original.landmarks.camps[1].positions.size(), "Sibling formations do not alias")
		for shifted: Rect2 in [Rect2(Vector2(-570, -350), View.WORLD_ARENA.size), Rect2(Vector2(123.25, 456.5), Vector2(2200, 900)), Rect2(Vector2.ZERO, Vector2(1840, 710))]:
			var translated: Dictionary = Layout.layout(map_id, shifted)
			check(translated.ok, "Valid translated, expanded, and minimum bounds accepted")
			var delta := shifted.position - View.WORLD_ARENA.position
			check(translated.landmarks.entry == Vector2(original.landmarks.entry) + delta, "Entry follows origin without scaling")
			for index: int in range(3):
				check(translated.landmarks.camps[index].center == Vector2(original.landmarks.camps[index].center) + delta, "Camp follows origin without scaling")
				for member: int in range(original.landmarks.camps[index].positions.size()):
					check(translated.landmarks.camps[index].positions[member] == Vector2(original.landmarks.camps[index].positions[member]) + delta, "Every member keeps exact world-space formation")
		for bounds: Rect2 in [Rect2(), Rect2(Vector2.ZERO, Vector2(1839.0, 710.0)), Rect2(Vector2.ZERO, Vector2(1840.0, 709.0)), Rect2(Vector2.ZERO, Vector2(-1840, 710)), Rect2(Vector2(INF, 0), View.WORLD_ARENA.size), Rect2(Vector2(0, NAN), View.WORLD_ARENA.size), Rect2(Vector2.ZERO, Vector2(INF, 710)), Rect2(Vector2.ZERO, Vector2(1840, NAN)), Rect2(Vector2(3.0e38, 0), Vector2(3.0e38, 710)), Rect2(Vector2(1.0e20, 1.0e20), View.WORLD_ARENA.size)]:
			_test_rejected(Layout.layout(map_id, bounds), "Unsafe or nonfinite bounds rejected without partial landmarks")
	for map_id: Variant in [null, true, 1, 1.0, &"old_garden", [], {}, "", "normal", "town", "unknown"]:
		_test_rejected(Layout.layout(map_id, View.WORLD_ARENA), "Unknown/non-string map rejected without partial landmarks")


func _test_rejected(result: Dictionary, label: String) -> void:
	check(result.has_all(["ok", "reason", "landmarks"]) and result.ok == false and result.reason is String and not result.reason.is_empty() and result.landmarks is Dictionary and result.landmarks.is_empty(), label)


func _test_trigger_segments() -> void:
	var cases: Array[Dictionary] = [
		{"a": Vector2(-100, 0), "b": Vector2.ZERO, "hit": true, "label": "entering"},
		{"a": Vector2(-100, 0), "b": Vector2(100, 0), "hit": true, "label": "both endpoints outside crossing"},
		{"a": Vector2(-87.5, 0), "b": Vector2(87.5, 0), "hit": true, "label": "175-unit dash crosses entire disk"},
		{"a": Vector2(-100, 64), "b": Vector2(100, 64), "hit": true, "label": "inclusive exact tangent"},
		{"a": Vector2(-100, 64.01), "b": Vector2(100, 64.01), "hit": false, "label": "near tangent miss"},
		{"a": Vector2(-100, 0), "b": Vector2(-64, 0), "hit": true, "label": "inclusive endpoint boundary"},
		{"a": Vector2.ZERO, "b": Vector2(100, 0), "hit": true, "label": "leaving from inside"},
		{"a": Vector2(80, 0), "b": Vector2(100, 0), "hit": false, "label": "line hits but finite segment misses"},
		{"a": Vector2.ZERO, "b": Vector2.ZERO, "hit": true, "label": "stationary inside"},
		{"a": Vector2(64, 0), "b": Vector2(64, 0), "hit": true, "label": "stationary boundary"},
		{"a": Vector2(65, 0), "b": Vector2(65, 0), "hit": false, "label": "stationary outside"},
		{"a": Vector2(-100, -100), "b": Vector2(100, 100), "hit": true, "label": "diagonal crossing"}]
	for center: Vector2 in [Vector2.ZERO, Vector2(962, 654), Vector2(-350, -270)]:
		for row: Dictionary in cases:
			check(Layout.trigger_crossed(center + Vector2(row.a), center + Vector2(row.b), center, 64.0) == row.hit, "Segment intersection: " + str(row.label))
			check(Layout.trigger_crossed(center + Vector2(row.b), center + Vector2(row.a), center, 64.0) == row.hit, "Segment intersection symmetric: " + str(row.label))
	check(Layout.trigger_crossed(Vector2(-1, 0), Vector2(1, 0), Vector2.ZERO, 0.0), "Zero-radius trigger accepts exact point crossing")
	check(not Layout.trigger_crossed(Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO, 0.0), "Zero-radius trigger rejects offset crossing")
	for invalid: Vector2 in [Vector2(INF, 0), Vector2(0, -INF), Vector2(NAN, 0)]:
		check(not Layout.trigger_crossed(invalid, Vector2.ZERO, Vector2.ZERO, 64.0), "Invalid previous position rejected")
		check(not Layout.trigger_crossed(Vector2.ZERO, invalid, Vector2.ZERO, 64.0), "Invalid current position rejected")
		check(not Layout.trigger_crossed(Vector2.ZERO, Vector2.ZERO, invalid, 64.0), "Invalid trigger center rejected")
	for radius: float in [-1.0, NAN, INF, -INF]:
		check(not Layout.trigger_crossed(Vector2(-100, 0), Vector2(100, 0), Vector2.ZERO, radius), "Invalid radius rejected")
	check(Layout.trigger_crossed(Vector2(-1.0e30, 0), Vector2(1.0e30, 0), Vector2.ZERO, 64.0), "Large finite segment cannot overflow Vector2 squared length")
	check(not Layout.trigger_crossed(Vector2(-1.0e30, 100), Vector2(1.0e30, 100), Vector2.ZERO, 64.0), "Large finite miss stays a miss")
	check(Layout.trigger_crossed(Vector2(1.0e30, 1.0e30), Vector2(1.0e30, 1.0e30), Vector2.ZERO, 1.0e300), "Finite large radius does not need unsafe squaring")
