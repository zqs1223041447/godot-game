extends SceneTree
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
var arena: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func near(a: float, b: float, label: String) -> void:
	check(absf(a-b) <= 0.000001 * maxf(1.0, absf(b)), label)
func clean() -> void:
	arena._world_mode = "normal"; arena.restart_run(); arena.auto_fire = false
	arena.spawn_timer = 1000.0; arena.invulnerable = 0.0; arena.player_pos = arena.ARENA.get_center()
	arena._stats.life_regen = 0.0; arena._stats.shield_recharge_rate = 0.0
	arena.health = 1000.0; arena.mana = 1000.0; arena.shield = 1000.0
	# With automatic HUD processing disabled, execute its normal latch reset.
	arena.hud._process(0.0)
	for index: int in range(4):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	check(not arena.hud.is_blocking(), "Fixture restored live HUD after restart")
func target() -> Dictionary:
	var e: Dictionary = arena._spawn_monster("brute", arena.player_pos + Vector2(100, 0), "ordinary", "", [], false)
	e.spawn = 0.0; e.health = 10000.0; e.max_health = 10000.0; e.shield = 0.0; e.max_shield = 0.0
	e.armour = 0.0; e.evasion = 0.0; e.speed = 0.0; e.attack_timer = 1000.0
	e.resistances = {}; e.shield_recharge_rate = 0.0; e.shield_regen = 0.0
	return e
func cast(critical: bool, ignite: bool = false) -> Dictionary:
	return Compiler.compile_group("meteor", Combat.snapshot({"damage":10.0,"crit_base_chance":1.0 if critical else 0.0,"crit_base_multiplier":2.0}, []), ["ignite"] if ignite else [])
func hit(e: Dictionary, recipe: Dictionary) -> void:
	var frozen: Dictionary = arena.critical_runtime.freeze(recipe.snapshot)
	check(frozen.ok, "Real critical runtime admits compiled snapshot")
	arena._apply_damage_packet(e, recipe.packets.direct, frozen.snapshot, Color.ORANGE)
func row(kind: String, target_kind: String = "monster") -> Dictionary:
	for entry: Dictionary in arena.damage_feedback():
		if entry.kind == kind and entry.target_kind == target_kind: return entry
	return {}
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"): quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	check(arena.save_build(), "Isolated live model saved")
	clean(); var e := target(); e.shield = 3.0
	var saved: Dictionary = arena.state.snapshot(); var saves: int = arena.state.successful_saves
	hit(e, cast(false)); var first: Dictionary = arena.damage_trace.back().duplicate(true)
	hit(e, cast(true)); var second: Dictionary = arena.damage_trace.back().duplicate(true)
	hit(e, cast(false)); var third: Dictionary = arena.damage_trace.back().duplicate(true)
	check(arena.damage_feedback().is_empty(), "Accepted hits wait for their fixed short window")
	arena.feedback_runtime.advance(0.2)
	check(arena.damage_feedback().size() == 2, "Mixed ordinary and critical produce separate buckets")
	near(row("hit").amount, first.shield_spent+first.health_lost+third.shield_spent+third.health_lost, "Ordinary total is actual shield plus life loss")
	near(row("critical").amount, second.shield_spent+second.health_lost, "Only actual critical damage enters critical bucket")
	check(row("hit").hit_count == 2 and row("critical").hit_count == 1, "Critical count excludes ordinary hits")
	check(arena.state.snapshot() == saved and arena.state.successful_saves == saves, "Presentation records do not mutate or persist build")
	var detached: Array = arena.damage_feedback(); detached[0].amount = -999.0
	check(arena.damage_feedback()[0].amount > 0.0, "Main accessor returns detached presentation data")
	var paused: PackedByteArray = var_to_bytes(arena.damage_feedback())
	arena.hud.open_panel("inventory"); arena._process(0.8)
	check(var_to_bytes(arena.damage_feedback()) == paused, "Menu pause freezes display clock"); arena.hud.close_panel()
	arena._world_mode = "map_complete"; var elapsed: float = arena.elapsed; arena.tick(0.8)
	check(arena.elapsed == elapsed and arena.damage_feedback().is_empty(), "Completed map expires labels while combat elapsed stays fixed")
	clean(); e = target(); e.health = 3.0; e.shield = 2.0
	arena._damage_enemy(e, 1000.0, Color.WHITE)
	check(e.health <= 0.0 and arena.damage_feedback().size() == 1, "Lethal hit immediately flushes target receipt")
	near(row("hit").amount, 5.0, "Lethal receipt excludes 995 overkill")
	near(row("hit").shield_spent, 2.0, "Lethal receipt preserves shield component")
	near(row("hit").health_lost, 3.0, "Lethal receipt preserves life component")
	var once: PackedByteArray = var_to_bytes(arena.damage_feedback()); arena._finish_enemy_death(e)
	check(var_to_bytes(arena.damage_feedback()) == once, "Duplicate death does not add feedback")
	clean(); e = target(); e.spawn = 0.6; hit(e, cast(true)); arena.feedback_runtime.advance(0.3)
	check(arena.damage_feedback().is_empty(), "Birth protection creates no positive feedback")
	e.spawn = 0.0; var tornado: Dictionary = Compiler.compile_group("tornado", Combat.snapshot({"damage":10.0}, []), [])
	tornado.snapshot.accuracy = 1.0; e.evasion = 1000000000.0; e.evasion_entropy = 0.0
	arena._apply_damage_packet(e, tornado.packets.parent, tornado.snapshot, Color.WHITE)
	arena.feedback_runtime.advance(0.3)
	check(arena.damage_feedback().is_empty() and not arena.attack_admission_trace.back().hit, "Evaded attack emits no damage")
	clean(); e = target(); hit(e, cast(true, true))
	check(not arena.burn_runtime.is_empty(), "Real critical fire hit attached burning")
	var rng_before: int = arena.rng.state; var crit_before: Dictionary = arena.critical_runtime.checkpoint()
	arena.feedback_runtime.advance(0.2); arena.elapsed = 0.5; arena._advance_monster_burns(0.5)
	var burn_spent: float = arena.burn_trace.back().settlement.shield_spent + arena.burn_trace.back().settlement.health_lost
	arena.feedback_runtime.advance(0.2)
	check(not row("critical").is_empty() and not row("burn").is_empty(), "Critical ignition and burning remain separate")
	near(row("burn").amount, burn_spent, "Burn label sums settled segment only")
	check(row("burn").hit_count == 0, "Burn samples are not hit counts")
	check(arena.rng.state == rng_before and arena.critical_runtime.checkpoint() == crit_before, "Burn feedback adds no random draws")
	clean(); arena.shield = 3.0; arena.health = 4.0
	check(arena.hit_player_components({"chaos":1000.0}), "Real lethal incoming hit accepted")
	check(not arena.alive and not row("hit", "player").is_empty(), "Lethal incoming hit flushes player receipt")
	near(row("hit", "player").amount, 7.0, "Incoming receipt excludes overkill")
	clean(); arena.invulnerable = 1.0
	check(not arena.hit_player_components({"physical":20.0}), "Immunity rejects incoming hit")
	arena.feedback_runtime.advance(0.3); check(arena.damage_feedback().is_empty(), "Immune hit has no feedback")
	arena.burn_runtime.apply("player",0,999,10.0,3.0,0.0)
	arena.tick(0.5); check(row("burn", "player").is_empty(), "Immune burn interval emits no fictional loss")
	arena.tick(0.6); arena.feedback_runtime.advance(0.2)
	near(row("burn", "player").amount, 1.0, "Only post-immunity burn interval is displayed")
	var observations: Array = []
	for enabled: bool in [true, false]:
		clean(); arena.visual_settings.damage_numbers = enabled; arena.monster_runtime.next_id = 0; arena.rng.seed = 846294; e = target()
		for index: int in range(70): arena._add_text(Vector2.ZERO, "notification", Color.WHITE)
		arena.particles.resize(arena.MAX_PARTICLES)
		for index: int in range(arena.MAX_PARTICLES): arena.particles[index] = {"pos":Vector2.ZERO,"velocity":Vector2.ZERO,"color":Color.WHITE,"radius":1.0,"life":1.0,"max_life":1.0}
		var expected := RandomNumberGenerator.new(); expected.state = arena.rng.state
		for index: int in range(80):
			expected.randf_range(-8,8)
			for particle: int in range(4): expected.randf(); expected.randf_range(40,130)
			arena._damage_enemy(e, 1.0, Color.WHITE)
		check(arena.rng.state == expected.state, "Legacy draws survive full queues and visibility switch")
		arena.feedback_runtime.advance(0.2)
		near(row("hit").amount, 80.0, "Eighty hits aggregate without lost actual damage")
		check(row("hit").hit_count == 80 and arena.floating_text.size() == 70, "Numeric receipts preserve gameplay notifications")
		observations.append([arena.rng.state,e.duplicate(true)])
	check(observations[0] == observations[1], "Visibility never changes target or loot generator")
	clean(); check(arena.damage_feedback().is_empty(), "Restart clears prior receipts")
	print("Combat feedback gameplay: %d checks, %d failures" % [checks, failures])
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
