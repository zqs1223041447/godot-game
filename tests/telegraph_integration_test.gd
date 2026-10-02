extends SceneTree
## Actual main-loop admission, cancellation, collision and settlement contracts.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
var arena: Node2D
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")
func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _near(value: float, expected: float, label: String) -> void:
	_expect(is_finite(value) and absf(value - expected) < 0.00001, "%s: %.8f / %.8f" % [label, value, expected])

func _run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Run only with isolated Linux XDG storage under /tmp/godot-*")
		quit(2)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_test_admission_and_policy()
	_test_actual_ticks()
	_test_motion_and_dodge()
	_test_boundary_and_snapshot()
	_test_cancel_and_pause()
	_test_capacity_and_death()
	arena.free()
	print("Telegraph integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fresh() -> void:
	arena.restart_run()
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.auto_fire = false
	arena.demo_mode = true
	arena.spawn_timer = 99999.0
	arena.player_pos = arena.ARENA.get_center()
	arena.health = 1000.0 # Test headroom only; native captures retain actual stats.
	arena.shield = 0.0
	arena.damage_delay = 99999.0
	arena.invulnerable = 0.0
	arena._autosave_timer = 0.0

func _guard(offset: Vector2 = Vector2(100, 0)) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("ember_guard", arena.player_pos + offset, "demo", "", [], false)
	enemy.spawn = 0.0
	enemy.attack_timer = 0.0
	return enemy

func _test_admission_and_policy() -> void:
	_fresh()
	var enemy: Dictionary = _guard(Vector2(151, 0))
	var policy: Dictionary = Monsters.telegraph_policy(enemy)
	_expect(policy.replaces_contact and policy.hold_pursuit_during_action, "Only explicit guard policy replaces contact and holds pursuit")
	_expect(policy.profile == Profiles.DEFAULTS, "Unmodified real guard uses the authoritative default profile")
	var random_state: int = arena.rng.state
	arena._start_enemy_telegraphs()
	_expect(arena.telegraphs.active_count() == 0, "Target outside 150 world units does not start")
	enemy.pos = arena.player_pos + Vector2(150, 0)
	arena._start_enemy_telegraphs()
	_expect(arena.telegraphs.active_count() == 1, "Inclusive trigger boundary admits one action")
	_expect(arena.rng.state == random_state, "Starting a telegraph does not consume arena RNG")
	var original: Dictionary = arena.telegraphs.state_for(enemy.id)
	arena._start_enemy_telegraphs()
	_expect(arena.telegraphs.state_for(enemy.id) == original, "Repeated admission does not restart warning or retarget")
	for template: String in Monsters.TEMPLATES:
		if template == "ember_guard": continue
		var context: String = "level_boss" if template == "rift_warden" else "demo"
		_expect(Monsters.telegraph_policy(Monsters.make_enemy(100, template, 3, Vector2.ZERO, context)).is_empty(), "Other template retains original action: " + template)
	enemy.attack_speed *= 2.0
	_near(Monsters.telegraph_policy(enemy).profile.recovery_seconds, 0.6, "Attack speed scales future recovery")
	_near(Monsters.telegraph_policy(enemy).profile.windup_seconds, 0.7, "Attack speed never shortens warning")
	_expect(arena.telegraphs.state_for(enemy.id) == original, "In-progress timing is a snapshot")
	for invalid: Variant in [NAN, INF, -1.0, 0.0, true, "fast"]:
		enemy.attack_speed = invalid
		_expect(Monsters.telegraph_policy(enemy).is_empty(), "Invalid action speed is refused")
	_fresh()
	enemy = _guard(Vector2.ZERO)
	enemy.attack_speed = 0.0
	arena._update_enemies(0.0)
	_expect(arena.incoming_damage_trace.is_empty(), "Invalid guard profile never falls back to instant contact")

func _test_actual_ticks() -> void:
	_fresh()
	var enemy: Dictionary = _guard()
	enemy.spawn = 0.2
	arena.tick(0.2)
	var admitted: Dictionary = arena.telegraphs.state_for(enemy.id)
	_expect(not admitted.is_empty(), "Birth expires before end-of-tick admission")
	_near(admitted.elapsed, 0.0, "New action never reuses elapsed birth tick")
	_expect(arena.incoming_damage_trace.is_empty(), "Birth/admission tick deals no contact or heavy hit")
	for frame: int in range(41):
		arena.tick(1.0 / 60.0)
	_expect(arena.incoming_damage_trace.is_empty(), "Full warning remains harmless before 42 fixed ticks")
	arena.tick(1.0 / 60.0)
	_expect(arena.incoming_damage_trace.size() == 1 and arena.telegraph_trace.size() == 1, "Exact default warning produces one settled hit")
	var hit: Dictionary = arena.incoming_damage_trace.back()
	_near(hit.raw_components.physical, float(enemy.damage) * 0.7, "Actual heavy hit keeps physical half and 1.4 multiplier")
	_near(hit.raw_components.fire, float(enemy.damage) * 0.7, "Actual heavy hit keeps fire half and 1.4 multiplier")
	_expect(hit.source_id == enemy.id and arena.telegraph_trace.back().applied, "Trace retains actual source and successful consumption")
	for frame: int in range(71):
		arena.tick(1.0 / 60.0)
	_expect(arena.incoming_damage_trace.size() == 1, "Recovery does not deal a second contact hit")
	arena.tick(1.0 / 60.0)
	_expect(arena.telegraphs.state_for(enemy.id).phase == "windup", "Recovered source may explicitly start next action at tick end")
	_near(arena.telegraphs.state_for(enemy.id).elapsed, 0.0, "Next warning also starts with a full duration")


func _test_motion_and_dodge() -> void:
	_fresh()
	var enemy: Dictionary = _guard()
	var source: Vector2 = enemy.pos
	var locked: Vector2 = arena.player_pos
	arena._start_enemy_telegraphs()
	arena.player_pos += Vector2(240, 0)
	arena._update_enemies(0.2)
	_expect(Vector2(enemy.pos).is_equal_approx(source), "Busy guard does not chase moving player")
	_expect(arena.telegraphs.state_for(enemy.id).center == locked, "Ground center stays where player stood at admission")
	enemy.knockback = Vector2(100, 0)
	arena._update_enemies(0.1)
	_expect(Vector2(enemy.pos).x > source.x, "Holding pursuit does not suppress knockback")
	arena._update_enemies(0.4)
	_expect(arena.incoming_damage_trace.is_empty() and not arena.telegraph_trace.back().inside, "Moving outside locked range avoids actual damage")
	_expect(arena.telegraphs.state_for(enemy.id).phase == "recovery", "A missed action still recovers normally")
	var stopped: Vector2 = enemy.pos
	arena._update_enemies(0.5)
	_expect(Vector2(enemy.pos).is_equal_approx(stopped), "Recovery also leaves player a stationary-source window")
	arena._update_enemies(0.7)
	_expect(arena.telegraphs.active_count() == 0 and Vector2(enemy.pos).x > stopped.x, "Guard resumes pursuit only after action finishes")

func _test_boundary_and_snapshot() -> void:
	for offset: float in [105.0, 105.001]:
		_fresh()
		var enemy: Dictionary = _guard()
		var damage: float = enemy.damage
		var locked: Vector2 = arena.player_pos
		arena._start_enemy_telegraphs()
		enemy.damage = 999.0
		enemy.contact_weights = {"cold": 1.0}
		arena.player_pos = locked + Vector2(offset, 0)
		arena._advance_enemy_telegraphs(0.7)
		_expect(arena.incoming_damage_trace.size() == (1 if offset == 105.0 else 0), "Collision includes player radius and exact boundary: " + str(offset))
		_near(arena.telegraph_trace.back().packet.base.physical, damage * 0.7, "Damage is frozen at start despite source stat mutation")
		_near(arena.telegraph_trace.back().packet.base.fire, damage * 0.7, "Frozen typed component never turns into new cold damage")
		var count: int = arena.telegraph_trace.size()
		arena._advance_enemy_telegraphs(99.0)
		_expect(arena.telegraph_trace.size() == count and arena.telegraphs.active_count() == 0, "Huge recovery step never replays consumed event")
	var collision = preload("res://scripts/combat/telegraphed_area_runtime.gd")
	for bad: Dictionary in [{}, {"shape":"circle","center":Vector2.ZERO,"radius":-1.0}, {"shape":"circle","center":Vector2.ZERO,"radius":INF}, {"shape":"circle","center":Vector2(INF,0),"radius":90.0}]:
		_expect(not collision.overlaps(bad, Vector2.ZERO, 15.0), "Malformed event has no geometric hit")
	var event: Dictionary = {"shape":"circle","center":Vector2.ZERO,"radius":90.0}
	_expect(not collision.overlaps(event, Vector2.ZERO, 1e308), "Overflowing target radius cannot become an always-hit area")
	_expect(not collision.overlaps(event, Vector2(INF,0), 15.0), "Nonfinite target position cannot be hit")
	_fresh()
	var crawler: Dictionary = arena._spawn_monster("crawler", arena.player_pos, "demo", "", [], false)
	crawler.spawn = 0.0
	crawler.attack_timer = 0.0
	arena._update_enemies(0.0)
	_expect(arena.incoming_damage_trace.size() == 1, "Original crawler still uses immediate contact")
	_near(arena.incoming_damage_trace.back().damage_total, float(crawler.damage), "Original contact amount is unchanged")

func _test_cancel_and_pause() -> void:
	for cause: String in ["death", "remove", "birth", "processed"]:
		_fresh()
		var enemy: Dictionary = _guard()
		arena._start_enemy_telegraphs()
		match cause:
			"death": arena._damage_enemy(enemy, enemy.health + enemy.shield + 1.0, Color.WHITE)
			"remove": arena.enemies.clear()
			"birth": enemy.spawn = 0.1
			"processed": enemy.death_processed = true
		if cause == "death": _expect(arena.telegraphs.active_count() == 0, "Actual damage death cancels immediately, before drawing")
		arena._advance_enemy_telegraphs(0.7)
		_expect(arena.telegraphs.active_count() == 0 and arena.incoming_damage_trace.is_empty(), "No terminal hit after source " + cause)
	_fresh()
	var enemy: Dictionary = _guard()
	arena._start_enemy_telegraphs()
	var before: Dictionary = arena.telegraphs.state_for(enemy.id)
	arena.hud.open_panel("pause")
	arena._process(1.0)
	_expect(arena.telegraphs.state_for(enemy.id) == before, "Actual blocking menu freezes warning clock")
	arena.hud.close_panel()
	for reset: String in ["restart_run", "start_monster_demo", "start_density_demo"]:
		_fresh()
		_guard()
		arena._start_enemy_telegraphs()
		arena.call(reset)
		_expect(arena.telegraphs.active_count() == 0 and arena.telegraph_visual_states().is_empty(), "Scene reset discards old actions: " + reset)

func _test_capacity_and_death() -> void:
	_fresh()
	arena.health = 10000.0
	for index: int in range(100): _guard(Vector2.ZERO)
	arena._start_enemy_telegraphs()
	_expect(arena.telegraphs.active_count() == 100 and arena.telegraph_visual_states().size() == 100, "100 real catalog sources have bounded live visual states")
	var copies: Array = arena.telegraph_visual_states()
	copies[0].center = Vector2(-999, -999)
	_expect(arena.telegraph_visual_states()[0].center == arena.player_pos, "Render snapshots cannot mutate live action state")
	arena._advance_enemy_telegraphs(0.7)
	_expect(arena.incoming_damage_trace.size() == 1, "Simultaneous heavy hits share existing player invulnerability")
	_expect(arena.event_counts.enemy_telegraph_resolved == 100 and arena.telegraph_trace.size() == 32, "Each event consumed once with bounded diagnostic history")
	arena._advance_enemy_telegraphs(1.2)
	_expect(arena.telegraphs.active_count() == 0, "100 recovered actions release all slots")
	_fresh()
	arena.health = 1.0
	for index: int in range(3): _guard(Vector2.ZERO)
	arena._start_enemy_telegraphs()
	arena._advance_enemy_telegraphs(0.7)
	_expect(not arena.alive and arena.telegraphs.active_count() == 0, "Player death resets pending actions")
	_expect(arena.event_counts.enemy_telegraph_resolved == 1 and arena.incoming_damage_trace.size() == 1, "Already returned events are discarded after player death")
