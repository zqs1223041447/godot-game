extends SceneTree
## Focused Main consumer boundaries; settlement mechanics have separate coverage.
class TraceArena extends "res://scripts/main.gd":
	var observed: Array = []
	var on_hit: Callable
	func _apply_damage_packet(enemy: Dictionary, _packet: Dictionary, _snapshot: Dictionary,
			_color: Color, _slow: float = 0.0, _provenance: Dictionary = {}) -> void:
		observed.append([enemy.label, enemy.health])
		if on_hit.is_valid(): on_hit.call(enemy)
	func _flush_monster_spawns() -> void: pass

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func target(id: int, label: String, health: float = 10.0) -> Dictionary:
	return {"id": id, "label": label, "health": health, "knockback": Vector2.ZERO}
func events(ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in ids:
		result.append({"type": "hit", "target_id": id, "payload": {}, "snapshot": {},
			"color": Color.WHITE, "slow": 0.0, "direction": Vector2.RIGHT,
			"sequence": result.size(), "time": 0.0})
	return result
func _initialize() -> void:
	var arena := TraceArena.new()
	var first := target(1, "first", 0.0)
	var duplicate := target(1, "duplicate")
	arena.enemies.assign([first, duplicate, target(2, "second")])
	check(arena._settle_projectile_events(events([1, 99, 1, 2])), "Duplicate/missing-ID batch accepted")
	check(arena.observed == [["first", 0.0], ["first", 0.0], ["second", 10.0]], "First ID match retained, including dead entries; missing IDs skipped")
	check(first.knockback == Vector2(45, 0) and duplicate.knockback == Vector2.ZERO, "Original first-match knockback destination retained")
	arena.free()

	arena = TraceArena.new()
	arena.enemies.assign([target(1, "before")])
	# Replace the Array, rather than assigning elements into the old Array.
	arena.on_hit = func(_enemy: Dictionary) -> void:
		if arena.observed.size() == 1:
			var replacement: Array[Dictionary] = [target(1, "after")]
			arena.enemies = replacement
	check(arena._settle_projectile_events(events([1, 1])), "Roster replacement batch accepted")
	check(arena.observed == [["before", 10.0], ["after", 10.0]], "Same-size roster replacement invalidates the batch lookup")
	arena.free()

	arena = TraceArena.new()
	arena.enemies.assign([target(1, "root")])
	arena.on_hit = func(_enemy: Dictionary) -> void:
		if arena.observed.size() == 1: arena.enemies.append(target(2, "child"))
	check(arena._settle_projectile_events(events([1, 2])), "Roster resize batch accepted")
	check(arena.observed == [["root", 10.0], ["child", 10.0]], "Same-array resize invalidates the batch lookup")
	arena.free()

	arena = TraceArena.new()
	arena.enemies.assign([target(1, "live")])
	arena.on_hit = func(enemy: Dictionary) -> void: enemy.health = 0.0
	check(arena._settle_projectile_events(events([1, 1])), "Repeated live-reference batch accepted")
	check(arena.observed == [["live", 10.0], ["live", 0.0]], "Repeated hits see current target health without copying dictionaries")
	arena.enemies.assign([target(1, "next batch")])
	arena.observed.clear()
	arena.on_hit = Callable()
	check(arena._settle_projectile_events(events([1])) and arena.observed == [["next batch", 10.0]], "No target lookup survives into a later settlement call")
	arena.free()
	print("PROJECTILE_HIT_LOOKUP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
