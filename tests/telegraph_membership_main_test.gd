extends SceneTree
## Actual Main movement/admission routines, paired with the released boolean oracle.
const Main = preload("res://scripts/main.gd")
class SnapshotOracle:
	extends "res://scripts/combat/telegraphed_area_runtime.gd"
	func has_state(source_id: int) -> bool:
		return not state_for(source_id).is_empty()
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func setup(oracle: bool) -> Node2D:
	# Do not enter the scene tree, initialize UI or touch a player save.
	var arena := Main.new()
	if oracle: arena.telegraphs = SnapshotOracle.new()
	arena.rng.seed = 18271
	arena.invulnerable = 999.0
	arena.player_pos = arena.ARENA.get_center()
	for id: int in range(1, 101):
		arena.enemies.append({"id": id, "template_id": "ember_guard" if id % 2 else "crawler",
			"health": 100.0, "spawn": 0.2 if id % 5 == 0 else 0.0,
			"attack_timer": 0.0, "flash": 0.0, "slow": 0.0, "speed": 30.0,
			"pos": arena.player_pos + Vector2((id % 10) * 15.0 + 40.0, (id / 10) * 15.0 - 70.0),
			"radius": 10.0, "knockback": Vector2(2, 0), "damage": 20.0,
			"attack_speed": 1.0, "contact_weights": {"physical": 1.0}})
	return arena

func capture(arena: Node2D) -> PackedByteArray:
	return var_to_bytes([arena.enemies, arena.telegraphs._states, arena.telegraphs._next_attack_id,
		arena.telegraph_trace, arena.event_counts, arena.rng.state, arena.health, arena.shield,
		arena.mana, arena.burn_runtime._states, arena.damage_trace,
		arena.separation_candidate_visits, arena.separation_full_scan_visits])

func _initialize() -> void:
	var old := setup(true)
	var current := setup(false)
	check(capture(old) == capture(current), "Identical initial states")
	for frame: int in range(180):
		for arena: Node2D in [old, current]:
			if frame == 50:
				arena.enemies[0].health = 0.0
				arena.enemies.remove_at(2)
			if frame == 80: arena.telegraphs.cancel(5)
			if frame == 100: arena.telegraphs.reset()
			arena.elapsed += 1.0 / 60.0
			arena._update_enemies(1.0 / 60.0)
			arena._start_enemy_telegraphs()
		check(capture(old) == capture(current), "Frame %d exact movement/admission/state equivalence" % frame)
	check(int(current.event_counts.get("enemy_telegraph_started", 0)) > 0, "Actual Main admitted attacks")
	check(int(current.event_counts.get("enemy_telegraph_resolved", 0)) > 0, "Actual Main resolved attacks")
	old.free(); current.free()
	print("Telegraph membership Main: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
