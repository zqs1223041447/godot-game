class_name MapCampAdmission
extends RefCounted
## Plans a whole camp against a detached factory checkpoint. The caller owns
## once-only camp/run bookkeeping and commits only after all of it succeeds.
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Compiler = preload("res://scripts/world/map_compiler.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const PreparedEntry = preload("res://scripts/world/prepared_map_entry.gd")
const GROUP_COUNTS: Dictionary = {"ruins_garden": 8, "old_garden": 8, "broken_ruins": 12, "sunwell_terrace": 12, "ginkgo_arcade": 12}
const PLAYER_CLEARANCE: float = 230.0
const LIVE_CAP: int = 100


static func plan(runtime: RefCounted, profile: Variant, entries: Variant,
		geometry: RefCounted, player_pos: Variant, available: Variant,
		context: String = "ordinary", prepared: Variant = null) -> Dictionary:
	var reason: String = Compiler.profile_reason(profile)
	if not reason.is_empty(): return _failure(reason)
	# Fixed test profiles also require the factory's exact integer wave type.
	if typeof(profile.get("wave")) != TYPE_INT or profile.wave < 1:
		return _failure("营地地图波次无效")
	if not runtime is Runtime or not geometry is Geometry:
		return _failure("营地运行时或地形无效")
	if context not in ["ordinary", "map_boss"]:
		return _failure("营地生成上下文无效")
	if not player_pos is Vector2 or not player_pos.is_finite():
		return _failure("营地玩家位置无效")
	var count: int = 1 if context == "map_boss" else int(GROUP_COUNTS.get(profile.id, 0))
	if count <= 0 or not entries is Array or entries.size() != count:
		return _failure("营地必须整组生成")
	if typeof(available) != TYPE_INT or available < count or available > LIVE_CAP:
		return _failure("营地整组容量不足或无效")
	var shape: Dictionary = geometry.snapshot()
	var same_map: bool = shape.id == profile.id and profile.id != "ruins_garden"
	if not same_map and prepared is PreparedEntry:
		# The sole opt-in bridge uses the same owned collision object already
		# checked by ExplorationMapPlan. A source_map_id label alone is not enough.
		same_map = prepared.phase() == "in_use" and prepared.geometry_ref() == geometry \
			and ((shape.id == "modular_study" and profile.id == "old_garden") or (shape.id == "ruins_garden" and profile.id == "ruins_garden")) \
			and shape.get("source_map_id") == profile.id and geometry.has_method("physics_ready") and geometry.physics_ready()
	if not same_map or not shape.bounds.position.is_finite() \
		or not shape.bounds.size.is_finite() or shape.bounds.size.x <= 0.0 or shape.bounds.size.y <= 0.0:
		return _failure("营地地形与地图不符")
	var staged = Runtime.new(runtime.templates)
	if not staged.validation_errors.is_empty(): return _failure("营地怪物模板无效")
	Encounter._restore(staged, Encounter._snapshot(runtime))
	var enemies: Array[Dictionary] = []
	for entry: Variant in entries:
		if not entry is Dictionary or not entry.get("template_id") is String \
			or not entry.get("rarity") is String or not entry.get("mechanisms") is Array \
			or not entry.get("position") is Vector2 or not entry.position.is_finite():
			return _failure("营地成员格式或位置无效")
		if entry.has("admission_index") and (typeof(entry.admission_index) != TYPE_INT or entry.admission_index <= 0):
			return _failure("营地成员序号无效")
		if context == "map_boss" and entry.template_id != profile.boss_id:
			return _failure("营地首领与地图不符")
		var admitted: Dictionary = Admission.create_root(staged, profile, entry.template_id,
			profile.wave, entry.position, context, entry.rarity, entry.mechanisms, true)
		if not admitted.get("ok", false): return _failure(str(admitted.get("error", "营地成员生成失败")))
		var enemy: Dictionary = admitted.enemy
		if not _valid_stats(enemy): return _failure("营地成员数值无效")
		var radius: float = float(enemy.radius)
		var position: Vector2 = entry.position
		if enemy.pos != position or not geometry.is_clear(position, radius):
			return _failure("营地成员位置越界或受阻")
		if position.distance_to(player_pos) < PLAYER_CLEARANCE:
			return _failure("营地成员距离玩家过近")
		for previous: Dictionary in enemies:
			if position.distance_to(previous.pos) < radius + float(previous.radius):
				return _failure("营地成员发生重叠")
		enemies.append(enemy)
	return {"ok": true, "error": "", "enemies": enemies,
		"runtime_checkpoint": Encounter._snapshot(staged)}


static func _valid_stats(enemy: Dictionary) -> bool:
	for field: String in ["health", "max_health", "shield", "max_shield", "speed", "damage", "attack_speed", "radius"]:
		var value: Variant = enemy.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return false
	return float(enemy.max_health) > 0.0 and float(enemy.radius) > 0.0 \
		and float(enemy.health) <= float(enemy.max_health) and float(enemy.shield) <= float(enemy.max_shield)


static func _failure(reason: String) -> Dictionary:
	var enemies: Array[Dictionary] = []
	return {"ok": false, "error": reason, "enemies": enemies, "runtime_checkpoint": {}}
