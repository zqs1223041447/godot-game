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
const LIVE_CAP := 100


static func plan(profile: Variant, live_runtime: Variant, seed_value: Variant, bounds: Rect2,
		capacity: Variant = LIVE_CAP, monster_policy: String = Monsters.CURRENT_ROLL_POLICY,
		mechanism_config: Variant = {}) -> Dictionary:
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
	var geometry = Geometry.new()
	if not geometry.configure_exploration(profile.id, bounds): return _failure("探索地图几何无效")
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
			layout.landmarks.entry, capacity - ordinary_roots.size())
		if not group.ok: return _failure(group.error)
		# Carry each complete group's lineage checkpoint into the following group.
		Encounter._restore(staged, group.runtime_checkpoint)
		var root_ids: Array[int] = []
		var ordinal := 0
		for enemy: Dictionary in group.enemies:
			ordinal += 1
			enemy.exploration_awake = false
			enemy.map_spawn_key = "%s/%d/%s/%d" % [profile.id, seed_value, camp.id, ordinal]
			spawn_records.append(_spawn_record(enemy, camp.id, ordinal))
			ordinary_roots.append(enemy)
			root_ids.append(enemy.id)
		if not state.activate(camp.id, root_ids): return _failure("探索地图根怪分组登记失败")
	var boss_entry := {"template_id": profile.boss_id, "rarity": "", "mechanisms": [],
		"position": layout.landmarks.boss.center}
	var boss_plan: Dictionary = CampAdmission.plan(staged, profile, [boss_entry], geometry,
		layout.landmarks.entry, capacity - ordinary_roots.size(), "map_boss")
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
	return {"ok": true, "reason": "", "state": state, "landmarks": layout.landmarks,
		"roots": roots, "ordinary_roots": ordinary_roots, "boss": boss,
		"runtime_checkpoint": Encounter._snapshot(staged), "run": run,
		"geometry": geometry, "bounds": bounds, "mechanism_config": {},
		"optional_encounters": [], "spawn_records": spawn_records}


static func _spawn_record(enemy: Dictionary, source_group: String, ordinal: int) -> Dictionary:
	return {"spawn_key": enemy.map_spawn_key, "actor_id": enemy.id, "root_id": enemy.root_id,
		"source_group": source_group, "ordinal": ordinal, "template_id": enemy.template_id,
		"position": enemy.pos, "encounter_id": "", "reward_route": "standard"}


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
		if enemy.pos.distance_to(entry) < CampAdmission.PLAYER_CLEARANCE:
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
