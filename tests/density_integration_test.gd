extends SceneTree
## Real scene coverage for the widened world and the 100-monster combat path.
## Run under disposable XDG directories, as in tools/validate.sh.
const Model = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const View = preload("res://scripts/visuals/world_view.gd")
var checks: int = 0
var failures: int = 0
var arena: Node2D
var reference: Node2D
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fresh = Model.new()
	_expect(fresh.save_build() == OK, "Fresh build saves inside disposable fixture")
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(1280, 720)
	arena = _scene()
	reference = _scene()
	_case(_test_real_density_demo, "100 real actors, admission and pause/resume")
	_case(_test_true_projectile_radius, "unchanged projectile hitbox and mitigated damage")
	_case(_test_true_contact_radius, "unchanged player contact hitbox and damage")
	_case(_test_density_split_flow, "density to split demonstration transition")
	_case(_test_rewards, "demo reward suppression and standard restoration")
	_case(_test_spawning, "parameterized bounds and ordinary 100-actor filling")
	_case(_test_separation_differential, "scene separation differential")
	_finished = false
	await _test_camera_and_aim()
	_expect(_finished, "Camera/aim suite reaches last check without script exception")
	print("Density integration: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	reference.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func _scene() -> Node2D:
	var result: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(result)
	result.set_process(false)
	result.hud.set_process(false)
	return result


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.0001, "%s (actual %.6f, expected %.6f)" % [label, value, expected])


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Suite reaches last check without script exception: " + label)


func _reset(target: Node2D = arena) -> void:
	target.restart_run()
	target.auto_fire = false
	target.enemies.clear()
	target.monster_runtime.reset()
	target.spawn_timer = 99999.0
	target.player_pos = target.ARENA.get_center()
	target.rng.seed = 81008


func _enemy(position: Vector2, template: String = "crawler") -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster(template, position)
	enemy.spawn = 0.0
	return enemy


func _inside(enemy: Dictionary) -> bool:
	var inset: Rect2 = arena.ARENA.grow(-float(enemy.radius))
	var pos: Vector2 = enemy.pos
	return pos.x >= inset.position.x - 0.001 and pos.y >= inset.position.y - 0.001 and pos.x <= inset.end.x + 0.001 and pos.y <= inset.end.y + 0.001


func _test_real_density_demo() -> void:
	arena.start_density_demo()
	_expect(arena.MAX_ENEMIES == 100 and arena.enemies.size() == 100, "Density scenario admits exactly 100 actual enemies")
	_expect(arena.demo_mode and arena.density_demo and not arena.auto_fire, "Density scenario disables progression rewards and automatic fire")
	_expect(arena.hud.is_blocking(), "Density scenario starts paused for review")
	var ids: Dictionary = {}
	var tiers: Dictionary = {}
	var old_positions: Array[Vector2] = []
	for enemy: Dictionary in arena.enemies:
		ids[enemy.id] = true
		tiers[enemy.rarity] = int(tiers.get(enemy.rarity, 0)) + 1
		old_positions.append(enemy.pos)
		var context: String = "map_boss" if enemy.rarity == "boss" else "demo"
		var expected: Dictionary = Catalog.make_enemy(enemy.id, enemy.template_id, arena.wave, enemy.pos, context, enemy.rarity, enemy.mechanism_ids)
		_expect(not expected.is_empty() and arena.monster_runtime.roots.has(enemy.id), "Actor is a real admitted catalog lineage %d" % enemy.id)
		for field: String in ["health", "max_health", "damage", "radius", "speed", "attack_speed", "max_shield"]:
			_expect(enemy[field] == expected[field], "Density preserves catalog %s for actor %d" % [field, enemy.id])
		_expect(_inside(enemy) and not enemy.reward_eligible and enemy.spawn == 0.0, "Actor fits world with full original hitbox and no demo reward")
	_expect(ids.size() == 100 and tiers.get("boss", 0) == 1 and tiers.get("normal", 0) > 0 and tiers.get("magic", 0) > 0 and tiers.get("rare", 0) > 0, "All 100 identities are unique with white, blue, gold and one orange boss")
	_expect(arena._spawn_monster("crawler").is_empty() and arena.enemies.size() == 100, "Admission rejects the 101st enemy")
	arena._process(0.25)
	_expect(arena.elapsed == 0.0, "Open density panel pauses real simulation time")
	var unchanged: bool = true
	for index: int in range(100):
		unchanged = unchanged and arena.enemies[index].pos == old_positions[index]
	_expect(unchanged, "Open density panel pauses every enemy")
	arena.hud.close_panel()
	arena.invulnerable = 100.0
	arena._process(1.0 / 60.0)
	var moved: int = 0
	for index: int in range(100):
		if arena.enemies[index].pos != old_positions[index]:
			moved += 1
	_expect(moved == 100 and arena.elapsed > 0.0, "Closing panel resumes genuine AI movement for all 100 actors")
	_expect(arena.separation_candidate_visits < arena.separation_full_scan_visits, "Spread-out density scenario reduces separation candidates")
	var projectile_target: Dictionary = arena.enemies[2] # Ordinary brute survives an unmodified 32-damage hit.
	var health_before: float = projectile_target.health
	arena.projectiles.append(_shot(Vector2(projectile_target.pos) - Vector2(float(projectile_target.radius) + 6.5, 0)))
	arena._update_projectiles(0.02)
	_near(projectile_target.health, health_before - 32.0, "Real projectile applies exact typed damage while all 100 demo actors are alive")
	_expect(arena.enemies.size() == 100 and arena.damage_trace.size() == 1, "Dense combat fixture damages one actor without changing the 100-actor population")
	var contact_target: Dictionary = arena.enemies[1]
	contact_target.pos = arena.player_pos
	contact_target.speed = 0.0
	contact_target.attack_timer = 0.0
	arena.invulnerable = 0.0
	arena.shield = 5.0
	var player_before: float = arena.health
	arena._update_enemies(0.0)
	_near(arena.health, player_before - (float(contact_target.damage) - 5.0), "Real enemy contact damages the player normally inside the 100-actor demo")
	_finished = true


func _shot(origin: Vector2, radius: float = 5.5) -> Dictionary:
	var snapshot: Dictionary = Recipes.snapshot({"damage": 1.0}, [])
	return arena.projectile_runtime.make_projectile(origin, Vector2.RIGHT,
		{"speed": 300.0, "range": 600.0, "lifetime": 4.0, "radius": radius, "pierce": -1},
		Damage.packet({"physical": 20.0, "fire": 12.0}, ["hit", "projectile"], "basic"),
		snapshot, arena.projectile_runtime.new_cast(), Color.WHITE)


func _test_true_projectile_radius() -> void:
	for indexed: bool in [false, true]:
		for inside: bool in [false, true]:
			_reset()
			arena.projectile_runtime.use_spatial_index = indexed
			var target: Dictionary = _enemy(Vector2(600, 330))
			target.resistances = {"fire": 0.5}
			var before: float = target.health
			var radius: float = target.radius
			var offset: float = radius + 5.5 + (-0.02 if inside else 0.02)
			var shot: Dictionary = _shot(target.pos + Vector2(-100, offset))
			arena.projectiles.append(shot)
			arena._update_projectiles(0.8)
			_near(target.health, before - (26.0 if inside else 0.0), "Real projectile preserves narrowphase radius and damage indexed=%s inside=%s" % [indexed, inside])
			_expect(arena.damage_trace.size() == (1 if inside else 0), "Only true contact enters damage resolver")
			_expect(target.radius == radius and shot.radius == 5.5, "Wider camera does not scale collision data")
			if inside:
				_near(arena.damage_trace[0].components.physical, 20.0, "Physical hit component stays unchanged")
				_near(arena.damage_trace[0].components.fire, 6.0, "Live fire resistance applies once")
			arena._update_projectiles(0.1)
			_near(target.health, before - (26.0 if inside else 0.0), "Same projectile cannot repeat a hit on the same leg")
	arena.projectile_runtime.use_spatial_index = true
	_finished = true


func _test_true_contact_radius() -> void:
	for indexed: bool in [false, true]:
		_reset()
		arena.use_spatial_separation = indexed
		arena.invulnerable = 0.0
		arena.shield = 5.0
		var before: float = arena.health
		var target: Dictionary = _enemy(arena.player_pos)
		target.speed = 0.0
		target.attack_timer = 0.0
		var boundary: float = arena.PLAYER_RADIUS + target.radius + 1.0
		target.pos = arena.player_pos + Vector2(boundary + 0.001, 0)
		arena._update_enemies(0.0)
		_near(arena.health, before, "Outside actual contact radius does not damage player")
		_near(arena.shield, 5.0, "Outside actual contact radius does not consume shield")
		target.pos = arena.player_pos + Vector2(boundary - 0.001, 0)
		arena._update_enemies(0.0)
		_near(arena.health, before - (float(target.damage) - 5.0), "Actual contact applies unchanged catalog damage after shield")
		_near(arena.shield, 0.0, "Actual contact consumes exact shield amount")
		_near(arena.invulnerable, 0.32, "Player hit keeps original invulnerability interval")
		_near(arena.damage_delay, 4.0, "Player hit keeps original recharge delay")
		_near(target.attack_timer, 1.0 / target.attack_speed, "Enemy contact keeps original attack cadence")
		arena.invulnerable = 0.0
		arena._update_enemies(0.0)
		_near(arena.health, before - (float(target.damage) - 5.0), "Enemy cooldown blocks repeated same-frame contact")
	arena.use_spatial_separation = true
	_finished = true


func _kill(enemy: Dictionary) -> void:
	arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 1.0, Color.WHITE)


func _test_density_split_flow() -> void:
	arena.start_density_demo()
	var before: Dictionary = arena.state._snapshot()
	arena.trigger_demo_split()
	_expect(arena.demo_mode and not arena.density_demo and arena.hud.is_blocking(), "Density-to-split switches to paused regular mechanism demo")
	var descendants: int = 0
	var kinds: Dictionary = {}
	for enemy: Dictionary in arena.enemies:
		if int(enemy.generation) > 0:
			descendants += 1
			kinds[enemy.template_id] = int(kinds.get(enemy.template_id, 0)) + 1
	_expect(descendants == 3 and kinds.get("crawler", 0) == 2 and kinds.get("skitter", 0) == 1, "Density-to-split admits real two crawlers and one skitter despite previous full arena")
	_expect(arena.kills == 1 and arena.reward_kills == 0 and arena.state._snapshot() == before, "Density-to-split demonstration has one real kill and no progression reward")
	_finished = true


func _test_rewards() -> void:
	arena.start_density_demo()
	var before: Dictionary = arena.state._snapshot()
	for enemy: Dictionary in arena.enemies.duplicate():
		_kill(enemy)
	arena._flush_monster_spawns()
	_expect(arena.kills == 100 and arena.enemies.size() == 4, "Killing 100 real demo actors counts deaths and produces actual boss descendants")
	for child: Dictionary in arena.enemies.duplicate():
		_expect(not child.reward_eligible and child.xp_reward == 0, "Demo boss descendants remain rewardless")
		_kill(child)
	arena._flush_monster_spawns()
	_expect(arena.enemies.is_empty() and arena.kills == 104, "Demo descendants follow ordinary lifecycle to completion")
	_expect(arena.state._snapshot() == before and arena.reward_kills == 0 and arena.pickups.is_empty(), "Demo deaths change no XP, level, talents, jewels, item instances, IDs, layout or supplies")
	arena.restore_standard_run()
	_expect(not arena.demo_mode and not arena.density_demo and arena.auto_fire and not arena.hud.is_blocking(), "Restore returns to an unpaused ordinary challenge")
	_expect(arena.enemies.size() == 3 and arena.monster_runtime.queue.is_empty(), "Restore clears demo lineage and creates three ordinary roots")
	arena.enemies.clear()
	var rare: Dictionary = arena._spawn_monster("crawler", arena.ARENA.get_center(), "ordinary", "rare", ["ember_power", "aegis_capacity"])
	var xp_before: int = arena.state.xp
	var items_before: int = arena.state.inventory.size()
	_kill(rare)
	_expect(rare.reward_eligible and arena.reward_kills == 1 and arena.state.xp == xp_before + rare.xp_reward, "Restored ordinary kill awards configured rarity XP")
	_expect(arena.state.inventory.size() == items_before + 1, "Restored rare kill awards real equipment")
	_finished = true


func _test_spawning() -> void:
	for wave: int in [1, 4, 12, 35]:
		_reset()
		arena.wave = wave
		arena.spawn_timer = 0.0
		arena._update_spawning(0.0)
		_expect(arena.enemies.size() == mini(5, 2 + int(wave / 4)), "Ordinary wave %d uses configured 2–5 batch" % wave)
		for tick_index: int in range(80):
			arena._update_spawning(2.0)
		_expect(arena.enemies.size() == 100, "Ordinary spawning genuinely fills 100 actors at wave %d" % wave)
		for enemy: Dictionary in arena.enemies:
			_expect(_inside(enemy) and enemy.reward_eligible, "Random ordinary spawn fits expanded arena with complete hitbox and rewards")
		arena._update_spawning(1000.0)
		_expect(arena.enemies.size() == 100, "Large spawn delta preserves 100-actor cap")
	# Explicit positions exercise every boundary and both small/large catalog radii.
	for position: Vector2 in [arena.ARENA.position - Vector2.ONE * 1000.0, arena.ARENA.end + Vector2.ONE * 1000.0, Vector2(arena.ARENA.position.x, arena.ARENA.end.y), Vector2(arena.ARENA.end.x, arena.ARENA.position.y)]:
		for template: String in ["crawler", "skitter", "brute"]:
			_reset()
			var enemy: Dictionary = _enemy(position, template)
			_expect(_inside(enemy), "Forced %s spawn clamps full hitbox at %s" % [template, position])
	_finished = true


func _clone_preserving_aliases(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(source.size()):
		var alias: int = -1
		for previous: int in range(index):
			if is_same(source[previous], source[index]):
				alias = previous
				break
		result.append(result[alias] if alias >= 0 else source[index].duplicate(true))
	return result


func _differential_fixture(seed_value: int) -> Array[Dictionary]:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var result: Array[Dictionary] = []
	for index: int in range(99):
		var position := Vector2(random.randf_range(70, 1850), random.randf_range(130, 780))
		if index < 40:
			position = Vector2(820, 390) + Vector2(random.randf_range(-30, 30), random.randf_range(-30, 30))
		var enemy: Dictionary = Catalog.make_enemy(index + 1, ["crawler", "skitter", "brute"][index % 3], 7, position)
		enemy.spawn = 0.12 if index % 11 == 0 else 0.0
		enemy.health = -1.0 if index % 17 == 0 else 1000.0
		enemy.slow = 0.3 if index % 4 == 0 else 0.0
		enemy.flash = 0.1
		enemy.attack_timer = 0.25 if index % 2 == 0 else 0.0
		enemy.knockback = Vector2(random.randf_range(-700, 700), random.randf_range(-700, 700))
		enemy.damage_delay = 0.2 if index % 5 == 0 else 0.0
		enemy.shield = 2.0
		enemy.max_shield = 50.0
		enemy.shield_regen = 5.0
		result.append(enemy)
	result[2].id = result[1].id # Equal IDs in independent dictionaries must keep old skip semantics.
	result[5].pos = result[4].pos # Exact coincident positions exercise the zero-distance guard.
	result.append(result[3]) # One mutable dictionary in two slots, including across cell changes.
	return result


func _test_separation_differential() -> void:
	for seed_value: int in [10, 69, 481, 8118, 71201]:
		_reset(arena)
		_reset(reference)
		arena.use_spatial_separation = true
		reference.use_spatial_separation = false
		var fixture: Array[Dictionary] = _differential_fixture(seed_value)
		arena.enemies = _clone_preserving_aliases(fixture)
		reference.enemies = _clone_preserving_aliases(fixture)
		arena.health = 100000.0
		reference.health = 100000.0
		arena.invulnerable = 0.0
		reference.invulnerable = 0.0
		_expect(is_same(arena.enemies[3], arena.enemies[99]) and not is_same(arena.enemies[1], arena.enemies[2]), "Differential fixture preserves alias and duplicate-ID distinctions")
		for step: int in range(40):
			var delta: float = [0.0, 0.0166666667, 0.04, 0.13, 0.003, 0.31][step % 6]
			arena._update_enemies(delta)
			reference._update_enemies(delta)
			_expect(arena.enemies == reference.enemies, "Sequential indexed/reference enemy dictionaries match exactly seed=%d step=%d" % [seed_value, step])
			_expect(arena.health == reference.health and arena.shield == reference.shield and arena.invulnerable == reference.invulnerable and arena.damage_delay == reference.damage_delay, "Indexed/reference player damage and timers match seed=%d step=%d" % [seed_value, step])
			_expect(arena.separation_candidate_visits <= arena.separation_full_scan_visits, "Conservative broadphase never visits more targets than full scan")
	_finished = true


func _test_camera_and_aim() -> void:
	_reset()
	var camera: Camera2D = arena.get_node_or_null("WorldCamera") as Camera2D
	_expect(camera != null, "Live scene owns a native Camera2D")
	if camera == null:
		return
	camera.make_current()
	var wave_label: Label = arena.hud.find_child("WaveLabel", true, false) as Label
	var font_size: int = wave_label.get_theme_font_size("font_size")
	var hud_transform: Transform2D = arena.hud.transform
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = resolution
		for frame: int in range(3):
			await process_frame
		camera.force_update_scroll()
		_near(camera.zoom.x, 0.65, "Native camera stays genuinely zoomed out at %s" % resolution)
		_expect(arena.ARENA.size.distance_to(Vector2(1840, 462.0 / 0.65)) < 0.01, "Expanded world is 1840 × 710.769 world units")
		_expect(View.world_to_screen(arena, arena.ARENA.position).distance_to(View.SCREEN_PLAYFIELD.position) < 0.02 and View.world_to_screen(arena, arena.ARENA.end).distance_to(View.SCREEN_PLAYFIELD.end) < 0.02, "Expanded world maps exactly to unchanged logical playfield at %s" % resolution)
		_expect(arena.hud.transform == hud_transform and wave_label.get_theme_font_size("font_size") == font_size and arena.hud.get_node("HUDRoot").scale == Vector2.ONE, "World zoom leaves real HUD/font scale unchanged at %s" % resolution)
		for offset: Vector2 in [Vector2(500, 150), Vector2(-350, 170), Vector2(280, -130)]:
			var target: Vector2 = arena.player_pos + offset
			var logical: Vector2 = View.world_to_screen(arena, target)
			_expect(View.screen_to_world(arena, logical).distance_to(target) < 0.01, "Logical cursor roundtrips to real world at %s" % resolution)
			var physical: Vector2 = root.get_screen_transform() * logical
			var restored: Vector2 = View.screen_to_world(arena, root.get_screen_transform().affine_inverse() * physical)
			_expect((restored - arena.player_pos).normalized().distance_to(offset.normalized()) < 0.00001, "720p/2K physical cursor yields identical world aim direction")
		_test_manual_aim(arena.player_pos + Vector2(400, 100))
	_finished = true


func _test_manual_aim(wanted: Vector2) -> void:
	# Input.parse_input_event takes physical pixels, then the viewport applies stretch.
	# Fresh events and an explicit flush prevent deferred or leaked pressed state.
	var old_mouse: Vector2 = root.get_screen_transform() * root.get_mouse_position()
	var cursor: Vector2 = root.get_screen_transform() * View.world_to_screen(arena, wanted)
	var motion := InputEventMouseMotion.new()
	motion.position = cursor
	motion.global_position = cursor
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = cursor
	press.global_position = cursor
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var actual: Vector2 = arena._aim_direction()
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	var restore := InputEventMouseMotion.new()
	restore.position = old_mouse
	restore.global_position = old_mouse
	Input.parse_input_event(restore)
	Input.flush_buffered_events()
	_expect(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "Aim fixture releases synthetic mouse button")
	_expect(actual.distance_to((wanted - arena.player_pos).normalized()) < 0.0001, "Live manual aim uses inverse native camera transform")
