class_name ExplorationMapPlan
extends RefCounted
## Fully detached entry transaction. The caller commits this checkpoint only
## after admission succeeds and any entry fee has been accepted.
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const CampState = preload("res://scripts/world/map_camp_state.gd")
const CampAdmission = preload("res://scripts/world/map_camp_admission.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Compiler = preload("res://scripts/world/map_compiler.gd")
const RunState = preload("res://scripts/world/map_run_state.gd")
const PreparedEntry = preload("res://scripts/world/prepared_map_entry.gd")
const LIVE_CAP := 100


static func plan(profile: Variant, live_runtime: Variant, seed_value: Variant, bounds: Rect2,
		capacity: Variant = LIVE_CAP, monster_policy: String = Monsters.CURRENT_ROLL_POLICY,
		mechanism_config: Variant = {}, prepared: Variant = null) -> Dictionary:
	var reason := Compiler.profile_reason(profile)
	if not reason.is_empty(): return _failure(reason)
	# Future mechanisms require an explicit implementation and reward route.
	# Unknown options are never silently turned into standard encounters.
	if not mechanism_config is Dictionary or not mechanism_config.is_empty():
		return _failure("此版本仅支持空探索机制配置")
	if not live_runtime is Runtime or not live_runtime.validation_errors.is_empty() or live_runtime.next_id < 0:
		return _failure("探索地图怪物运行时无效")
	var total: int = int(profile.ordinary_target) + 1
	if typeof(capacity) != TYPE_INT or capacity < total or capacity > LIVE_CAP:
		return _failure("探索地图必须容纳全部根怪与首领")
	if live_runtime.next_id > 0x7fffffffffffffff - total:
		return _failure("探索地图怪物标识空间不足")
	var layout: Dictionary = Layout.layout(profile.id, bounds)
	if not layout.ok: return _failure(layout.reason)
	var geometry: RefCounted
	if prepared == null:
		geometry = Geometry.new()
		if not geometry.configure_exploration(profile.id, bounds): return _failure("探索地图几何无效")
	else:
		reason = _prepared_reason(prepared, profile, bounds, layout.landmarks)
		if not reason.is_empty(): return _failure(reason)
		geometry = prepared.geometry_ref()
		layout.landmarks = prepared.landmarks()
	reason = _routes_reason(layout.landmarks, geometry)
	if not reason.is_empty(): return _failure(reason)
	for outpost: Dictionary in layout.landmarks.outposts: outpost["root_ids"] = []
	var state = CampState.new()
	var selected: Dictionary = state.begin(profile, layout.landmarks, seed_value, monster_policy)
	if not selected.ok: return _failure(selected.reason)
	# Only template definitions and the monotonic ID cursor cross map boundaries.
	# Old roots, deferred descendants and traces belong to the previous run.
	var staged = Runtime.new(live_runtime.templates)
	if not staged.validation_errors.is_empty(): return _failure("探索地图怪物模板无效")
	staged.next_id = live_runtime.next_id
	var ordinary_roots: Array[Dictionary] = []
	var spawn_records: Array[Dictionary] = []
	for camp: Dictionary in layout.landmarks.camps:
		var group: Dictionary = CampAdmission.plan(staged, profile, state.entries(camp.id), geometry,
			layout.landmarks.entry, capacity - ordinary_roots.size(), "ordinary", prepared)
		if not group.ok: return _failure(group.error)
		# Carry each complete group's lineage checkpoint into the following group.
		Encounter._restore(staged, group.runtime_checkpoint)
		var root_ids: Array[int] = []
		var ordinal := 0
		for enemy: Dictionary in group.enemies:
			ordinal += 1
			enemy.exploration_awake = false
			enemy.map_spawn_key = "%s/%d/%s/%d" % [profile.id, seed_value, camp.id, ordinal]
			for outpost: Dictionary in layout.landmarks.outposts:
				if outpost.source_group == camp.id and outpost.ordinals.has(ordinal):
					enemy["map_outpost_id"] = outpost.id
					outpost.root_ids.append(int(enemy.id))
					break
			if not enemy.has("map_outpost_id"): return _failure("探索驻点成员没有对应位置")
			spawn_records.append(_spawn_record(enemy, camp.id, ordinal))
			ordinary_roots.append(enemy)
			root_ids.append(enemy.id)
		if not state.activate(camp.id, root_ids): return _failure("探索地图根怪分组登记失败")
	var boss_entry := {"template_id": profile.boss_id, "rarity": "", "mechanisms": [],
		"position": layout.landmarks.boss.center}
	var boss_plan: Dictionary = CampAdmission.plan(staged, profile, [boss_entry], geometry,
		layout.landmarks.entry, capacity - ordinary_roots.size(), "map_boss", prepared)
	if not boss_plan.ok: return _failure(boss_plan.error)
	Encounter._restore(staged, boss_plan.runtime_checkpoint)
	var boss: Dictionary = boss_plan.enemies[0]
	boss.exploration_awake = false
	boss.map_spawn_key = "%s/%d/boss" % [profile.id, seed_value]
	spawn_records.append(_spawn_record(boss, "boss", 1))
	var roots: Array[Dictionary] = []
	roots.append_array(ordinary_roots)
	roots.append(boss)
	reason = _roots_reason(roots, total, geometry, layout.landmarks.entry)
	if not reason.is_empty(): return _failure(reason)
	var run = RunState.new()
	if not run.begin(profile) or not run.register_initial_group(ordinary_roots, boss):
		return _failure("探索地图全体根怪登记失败")
	var result: Dictionary = {"ok": true, "reason": "", "state": state, "landmarks": layout.landmarks,
		"roots": roots, "ordinary_roots": ordinary_roots, "boss": boss,
		"runtime_checkpoint": Encounter._snapshot(staged), "run": run,
		"geometry": geometry, "bounds": bounds, "mechanism_config": {},
		"optional_encounters": [], "spawn_records": spawn_records}
	if prepared != null: result["prepared_geometry"] = true
	return result


static func _prepared_reason(prepared: Variant, profile: Dictionary, bounds: Rect2, original: Dictionary) -> String:
	if not prepared is PreparedEntry or prepared.phase() != "in_use":
		return "Prepared geometry must belong to an active entry transaction"
	var geometry: RefCounted = prepared.geometry_ref()
	if not geometry is Geometry or not geometry.has_method("physics_ready") or not geometry.physics_ready():
		return "Prepared native collision is not ready"
	var snapshot: Dictionary = geometry.snapshot()
	if prepared.bounds() != bounds or snapshot.get("bounds") != bounds \
		or snapshot.get("source_map_id") != profile.id or snapshot.get("spawn") != original.entry:
		return "Prepared geometry does not match this map, bounds or entry"
	var supplied: Dictionary = prepared.landmarks()
	var wanted: Dictionary = original.duplicate(true)
	var routes: Variant = supplied.get("route_segments")
	# This first adapter may only reroute paths. Identities, counts, positions,
	# entry and every source group remain the ordinary catalogue definition.
	supplied.erase("route_segments")
	wanted.erase("route_segments")
	if var_to_bytes(supplied) != var_to_bytes(wanted):
		return "Prepared landmarks changed a non-route map field"
	if not routes is Array or routes.is_empty() or routes.size() > 32:
		return "Prepared route list is invalid"
	var cursor := 0
	for source: Dictionary in original.route_segments:
		var from: Vector2 = source.from
		var chain: Array[Dictionary] = []
		# Every original route is represented, in order, by a continuous chain
		# with unchanged endpoints. Dropping a blocked connector is not valid.
		while cursor < routes.size():
			var route: Variant = routes[cursor]
			if not route is Dictionary or not route.get("from") is Vector2 or not route.get("to") is Vector2 \
				or not route.from.is_finite() or not route.to.is_finite() or route.from != from \
				or typeof(route.get("width")) not in [TYPE_INT, TYPE_FLOAT] or float(route.width) != 72.0:
				return "Prepared route width, order or endpoints are invalid"
			chain.append(route)
			cursor += 1
			from = route.to
			if from == source.to: break
		if chain.is_empty() or from != source.to:
			return "Prepared route chain omitted an original connection"
		# Preserve original width checks for untouched routes. New bends must
		# additionally clear the real player's radius, without narrowing paint.
		var radius := 36.0 if chain.size() == 1 else 51.0
		for route: Dictionary in chain:
			if not geometry.is_clear(route.from, radius) or not geometry.is_clear(route.to, radius) \
				or geometry.sweep(route.from, route.to, radius).hit or geometry.sweep(route.to, route.from, radius).hit:
				return "Prepared route lacks required width or player clearance"
	if cursor != routes.size():
		return "Prepared route list has extra disconnected segments"
	return ""


static func _spawn_record(enemy: Dictionary, source_group: String, ordinal: int) -> Dictionary:
	return {"spawn_key": enemy.map_spawn_key, "actor_id": enemy.id, "root_id": enemy.root_id,
		"source_group": source_group, "ordinal": ordinal, "template_id": enemy.template_id,
		"position": enemy.pos, "encounter_id": "", "reward_route": "standard",
		"outpost_id": str(enemy.get("map_outpost_id", ""))}


static func _routes_reason(landmarks: Dictionary, geometry: RefCounted) -> String:
	# Route paint cannot promise passage through a physical obstacle. Sweep the
	# complete width, not only a sampled centerline or the player's smaller body.
	for segment: Dictionary in landmarks.get("route_segments", []):
		var radius: float = float(segment.width) * 0.5
		if not geometry.is_clear(segment.from, radius) or not geometry.is_clear(segment.to, radius) or geometry.sweep(segment.from, segment.to, radius).hit:
			return "探索路线与实体障碍或边界相交"
	for outpost: Dictionary in landmarks.get("outposts", []):
		if not geometry.is_clear(outpost.center, 27.5) or not geometry.is_clear(outpost.sign_position, 15.0):
			return "探索驻点中心或路标受阻"
	return ""


static func _roots_reason(roots: Array[Dictionary], total: int, geometry: RefCounted, entry: Vector2) -> String:
	if roots.size() != total or not geometry.is_clear(entry, 15.0):
		return "探索地图全体数量或入口无效"
	var seen: Dictionary = {}
	for index: int in range(roots.size()):
		var enemy: Dictionary = roots[index]
		if not RunState._initial_root_valid(enemy) or seen.has(enemy.id) or not CampAdmission._valid_stats(enemy):
			return "探索地图根怪标识或数值无效"
		seen[enemy.id] = true
		if not enemy.get("pos") is Vector2 or not enemy.pos.is_finite() or not geometry.is_clear(enemy.pos, enemy.radius):
			return "探索地图成员位置越界或受阻"
		if enemy.pos.distance_to(entry) < maxf(CampAdmission.PLAYER_CLEARANCE, Layout.ENTRY_CLEARANCE):
			return "探索地图成员距离入口过近"
		for previous: int in range(index):
			if enemy.pos.distance_to(roots[previous].pos) < float(enemy.radius) + float(roots[previous].radius):
				return "探索地图成员发生重叠"
	return ""


static func _failure(reason: String) -> Dictionary:
	var roots: Array[Dictionary] = []
	var ordinary_roots: Array[Dictionary] = []
	return {"ok": false, "reason": reason, "state": null, "landmarks": {}, "roots": roots,
		"ordinary_roots": ordinary_roots, "boss": {}, "runtime_checkpoint": {},
		"run": null, "geometry": null, "bounds": Rect2(), "mechanism_config": {},
		"optional_encounters": [], "spawn_records": []}
