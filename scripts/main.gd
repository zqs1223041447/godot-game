extends Node2D
## First playable slice. BuildState owns progression; this node owns a single run.
## All combat positions use the 1280 × 720 logical canvas, independent of window size.

const Build = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Hud = preload("res://scripts/game_hud.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const ARENA := Rect2(42, 104, 1196, 462)
const PLAYER_RADIUS := 15.0
const MAX_ENEMIES := 55
const MAX_PROJECTILES := 180
const MAX_PARTICLES := 180

var state = Build.new()
var projectile_runtime = Projectiles.new()
var combat_trace: Array[Dictionary] = []
var damage_trace: Array[Dictionary] = []
var event_counts: Dictionary = {}
var _simulation_accumulator: float = 0.0
var hud: CanvasLayer
var health: float = 120.0
var mana: float = 100.0
var shield: float = 60.0
var kills: int = 0
var elapsed: float = 0.0
var wave: int = 1
var alive: bool = true
var auto_fire: bool = true
var cooldowns: Dictionary = {}
var player_pos := Vector2(640, 338)
var player_facing := Vector2.RIGHT
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var floating_text: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var spawn_timer: float = 0.4
var attack_timer: float = 0.0
var damage_delay: float = 0.0
var invulnerable: float = 0.0
var hurt_flash: float = 0.0
var screen_shake: float = 0.0
var total_shots: int = 0
var total_damage: float = 0.0
var _font: Font
var _stats: Dictionary = {}
var _next_enemy_id: int = 0
var _autosave_timer: float = 0.0
var _ready_complete: bool = false


func _ready() -> void:
	rng.randomize()
	_font = load("res://assets/fonts/arena_sans.otf")
	_configure_input()
	state.load_build()
	_stats = state.get_stats()
	state.changed.connect(_on_build_changed)
	hud = Hud.new()
	hud.name = "GameHUD"
	add_child(hud)
	hud.setup(self)
	_ready_complete = true
	restart_run()
	if state.migrated_from_v1 or state.migrated_from_v2:
		hud.open_panel("talents" if state.migrated_from_v1 else "combat")
		hud.notify(state.migration_message)
	else:
		hud.notify("K 配置龙卷射击 · F6 查看机制与伤害 · I 装备归航披风和终焰护符")
	print("godot-game: playable arena ready")


func _configure_input() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN]
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


func get_stats() -> Dictionary:
	return _stats


func _on_build_changed() -> void:
	_stats = state.get_stats()
	health = minf(health, float(_stats.max_health))
	mana = minf(mana, float(_stats.max_mana))
	shield = minf(shield, float(_stats.max_shield))
	if _ready_complete:
		hud.refresh_build()
		save_build()


func save_build() -> bool:
	var error: Error = state.save_build()
	if error != OK and is_instance_valid(hud):
		hud.notify("存档失败，请检查保存目录的写入权限")
	return error == OK


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_build()
		get_tree().quit()


func restart_run() -> void:
	_stats = state.get_stats()
	health = float(_stats.max_health)
	mana = float(_stats.max_mana)
	shield = float(_stats.max_shield)
	kills = 0
	elapsed = 0.0
	wave = 1
	alive = true
	player_pos = ARENA.get_center()
	player_facing = Vector2.RIGHT
	enemies.clear()
	projectile_runtime.cancel_all(projectiles)
	combat_trace.clear()
	damage_trace.clear()
	event_counts.clear()
	_simulation_accumulator = 0.0
	particles.clear()
	floating_text.clear()
	pickups.clear()
	rings.clear()
	cooldowns.clear()
	for id: String in Data.SKILLS:
		cooldowns[id] = 0.0
	spawn_timer = 1.8
	attack_timer = 0.0
	damage_delay = 0.0
	invulnerable = 1.5
	hurt_flash = 0.0
	total_shots = 0
	total_damage = 0.0
	if is_instance_valid(hud):
		hud.close_panel()
		for i: int in range(3):
			_spawn_enemy()
	queue_redraw()


func toggle_auto_fire() -> void:
	auto_fire = not auto_fire
	hud.notify("自动攻击：开启" if auto_fire else "自动攻击：关闭 · 按住鼠标左键射击")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if key == KEY_ESCAPE:
		if hud.is_blocking() and alive:
			hud.close_panel()
		elif alive:
			hud.open_panel("pause")
	elif key == KEY_I or key == KEY_B:
		if alive:
			hud.open_panel("inventory")
	elif key == KEY_T:
		if alive:
			hud.open_panel("talents")
	elif key == KEY_F6:
		if alive:
			hud.open_panel("combat")
	elif key == KEY_K:
		if alive:
			hud.open_panel("skills")
	elif key == KEY_R and not alive:
		restart_run()
	elif key == KEY_Q and not hud.is_blocking() and alive:
		toggle_auto_fire()
	elif key >= KEY_1 and key <= KEY_5:
		cast_skill(key - KEY_1)
	elif key == KEY_SPACE:
		var slot: int = state.skill_slots.find("dash")
		if slot >= 0:
			cast_skill(slot)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _ready_complete:
		return
	if not alive or hud.is_blocking():
		queue_redraw()
		return
	# Fixed world observations keep moving-target / return aiming consistent.
	_simulation_accumulator = minf(0.25, _simulation_accumulator + delta)
	while _simulation_accumulator >= 1.0 / 60.0 and alive:
		tick(1.0 / 60.0)
		_simulation_accumulator -= 1.0 / 60.0
	queue_redraw()


func tick(delta: float) -> void:
	elapsed += delta
	var new_wave: int = 1 + int(elapsed / 30.0)
	if new_wave != wave:
		wave = new_wave
		hud.notify("第 %d 波来袭 · 敌人强度提升" % wave)
		_add_ring(ARENA.get_center(), 250.0, Color("d5b77a"), 0.8)
	for id: String in cooldowns:
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	damage_delay = maxf(0.0, damage_delay - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	screen_shake = maxf(0.0, screen_shake - delta * 15.0)
	mana = minf(float(_stats.max_mana), mana + float(_stats.mana_regen) * delta)
	if damage_delay <= 0.0:
		shield = minf(float(_stats.max_shield), shield + float(_stats.shield_regen) * delta)
	_move_player(delta)
	_update_spawning(delta)
	_update_enemies(delta)
	if not alive:
		return
	_update_auto_attack()
	_update_projectiles(delta)
	_update_effects(delta)
	_update_pickups(delta)
	_autosave_timer += delta
	if _autosave_timer >= 15.0:
		_autosave_timer = 0.0
		save_build()


func _move_player(delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if movement.length_squared() > 0.01:
		player_pos += movement * float(_stats.move_speed) * delta
		player_facing = movement.normalized()
		if rng.randf() < 0.4:
			_add_particle(player_pos + Vector2(0, 10), -movement * 20.0, Color("547a83"), 2.0, 0.25)
	player_pos = _clamp_to_arena(player_pos, PLAYER_RADIUS)


func _clamp_to_arena(pos: Vector2, margin: float) -> Vector2:
	return Vector2(clampf(pos.x, ARENA.position.x + margin, ARENA.end.x - margin),
		clampf(pos.y, ARENA.position.y + margin, ARENA.end.y - margin))


func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = maxf(0.42, 1.45 - wave * 0.07)
		var count: int = mini(3, 1 + int(wave / 4))
		for i: int in range(count):
			if enemies.size() < MAX_ENEMIES:
				_spawn_enemy()


func _spawn_enemy(forced_position: Vector2 = Vector2.ZERO, forced_kind: int = -1) -> Dictionary:
	var kind: int = forced_kind
	if kind < 0:
		kind = 0
		var roll: float = rng.randf()
		if roll > 0.8 and wave >= 2:
			kind = 2
		elif roll > 0.58:
			kind = 1
	var pos: Vector2 = forced_position
	if pos == Vector2.ZERO:
		var side: int = rng.randi_range(0, 3)
		match side:
			0: pos = Vector2(ARENA.position.x + 24, rng.randf_range(140, 526))
			1: pos = Vector2(ARENA.end.x - 24, rng.randf_range(140, 526))
			2: pos = Vector2(rng.randf_range(85, 1195), ARENA.position.y + 22)
			3: pos = Vector2(rng.randf_range(85, 1195), ARENA.end.y - 22)
		# Spawns never appear directly on the player.
		if pos.distance_to(player_pos) < 230.0:
			pos = ARENA.get_center() * 2.0 - pos
	var hp: float = [38.0, 25.0, 95.0][kind] * (1.0 + (wave - 1) * 0.16)
	_next_enemy_id += 1
	var enemy: Dictionary = {
		"id": _next_enemy_id, "pos": pos, "health": hp, "max_health": hp,
		"kind": kind, "speed": [64.0, 103.0, 43.0][kind] + mini(wave, 15) * 1.4,
		"damage": [10.0, 8.0, 18.0][kind] + (wave - 1) * 0.7,
		"radius": [14.0, 10.0, 22.0][kind], "attack_timer": 0.5,
		"slow": 0.0, "flash": 0.0, "spawn": 0.6, "knockback": Vector2.ZERO
	}
	enemies.append(enemy)
	_add_ring(pos, 32.0, Color("d87d71"), 0.5)
	return enemy


func _update_enemies(delta: float) -> void:
	for enemy: Dictionary in enemies:
		if float(enemy.health) <= 0.0:
			continue
		enemy.attack_timer = maxf(0.0, float(enemy.attack_timer) - delta)
		enemy.flash = maxf(0.0, float(enemy.flash) - delta)
		enemy.slow = maxf(0.0, float(enemy.slow) - delta)
		enemy.spawn = maxf(0.0, float(enemy.spawn) - delta)
		if float(enemy.spawn) > 0.0:
			continue
		var direction: Vector2 = (player_pos - Vector2(enemy.pos)).normalized()
		var speed: float = float(enemy.speed) * (0.36 if float(enemy.slow) > 0 else 1.0)
		var separation := Vector2.ZERO
		for other: Dictionary in enemies:
			if int(other.id) == int(enemy.id):
				continue
			var offset: Vector2 = Vector2(enemy.pos) - Vector2(other.pos)
			var distance: float = offset.length()
			var separation_distance: float = float(enemy.radius) + float(other.radius) + 3.0
			if distance > 0.1 and distance < separation_distance:
				separation += offset / distance * (separation_distance - distance) * 2.5
		enemy.pos = Vector2(enemy.pos) + (direction * speed + separation + Vector2(enemy.knockback)) * delta
		enemy.pos = _clamp_to_arena(Vector2(enemy.pos), float(enemy.radius))
		enemy.knockback = Vector2(enemy.knockback).move_toward(Vector2.ZERO, 520.0 * delta)
		if Vector2(enemy.pos).distance_to(player_pos) < PLAYER_RADIUS + float(enemy.radius) + 1.0:
			if float(enemy.attack_timer) <= 0.0:
				enemy.attack_timer = 0.85
				hit_player(float(enemy.damage))
				if not alive:
					return


func _nearest_enemy(from: Vector2, max_distance: float = 800.0, excluded: Array[int] = []) -> Dictionary:
	var best: Dictionary = {}
	var distance_sq: float = max_distance * max_distance
	for enemy: Dictionary in enemies:
		if float(enemy.health) <= 0.0 or excluded.has(int(enemy.id)) or float(enemy.spawn) > 0.0:
			continue
		var candidate: float = from.distance_squared_to(Vector2(enemy.pos))
		if candidate < distance_sq:
			distance_sq = candidate
			best = enemy
	return best


func _aim_direction() -> Vector2:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_direction: Vector2 = get_global_mouse_position() - player_pos
		if mouse_direction.length_squared() > 4.0:
			return mouse_direction.normalized()
	var nearest: Dictionary = _nearest_enemy(player_pos)
	if not nearest.is_empty():
		return (Vector2(nearest.pos) - player_pos).normalized()
	return player_facing


func _update_auto_attack() -> void:
	if attack_timer > 0.0:
		return
	var manual: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not manual and (not auto_fire or _nearest_enemy(player_pos).is_empty()):
		return
	player_facing = _aim_direction()
	_shoot(player_pos, player_facing, float(_stats.damage), Color("75e5df"), 0, 0, 640.0)
	attack_timer = 1.0 / maxf(0.2, float(_stats.attack_speed))


func _shoot(origin: Vector2, direction: Vector2, damage: float, color: Color,
		pierce: int = 0, slow: float = 0.0, speed: float = 600.0,
		skill_id: String = "basic", damage_type: String = "physical", context: Dictionary = {}) -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		return
	var snapshot: Dictionary = context.get("snapshot", state.get_combat_snapshot())
	var cast_id: int = int(context.get("cast_id", 0))
	if cast_id == 0:
		cast_id = projectile_runtime.new_cast()
	var packet: Dictionary = Damage.packet({damage_type: damage},
		["hit", "projectile", "attack" if skill_id == "basic" else "spell"], skill_id)
	var spec: Dictionary = {"speed": speed, "range": 650.0, "lifetime": 1.7,
		"pierce": pierce, "slow": slow}
	projectiles.append(projectile_runtime.make_projectile(origin + direction * 19.0, direction,
		spec, packet, snapshot, cast_id, color))
	total_shots += 1
	for i: int in range(3):
		_add_particle(origin + direction * 20.0, direction.rotated(rng.randf_range(-0.6, 0.6)) * rng.randf_range(20, 90), color, 2.2, 0.16)


func cast_skill(index: int) -> bool:
	if not alive or not _ready_complete or hud.is_blocking() or index < 0 or index >= state.skill_slots.size():
		return false
	var id: String = state.skill_slots[index]
	if not Data.SKILLS.has(id):
		return false
	var skill: Dictionary = Data.SKILLS[id]
	if float(cooldowns.get(id, 0.0)) > 0.0:
		hud.notify("%s 冷却中" % skill.name)
		return false
	if mana < float(skill.mana):
		hud.notify("魔力不足 · 等待恢复或拾取补给")
		return false
	mana -= float(skill.mana)
	cooldowns[id] = float(skill.cooldown)
	player_facing = _aim_direction()
	var damage: float = float(_stats.damage)
	var color: Color = skill.color
	var context: Dictionary = {"snapshot": state.get_combat_snapshot(), "cast_id": projectile_runtime.new_cast()}
	match id:
		"tornado":
			var emitted: int = projectile_runtime.spawn_tornado(projectiles, player_pos, player_facing, context.snapshot, MAX_PROJECTILES)
			if emitted == 0:
				mana += float(skill.mana)
				cooldowns[id] = 0.0
				hud.notify("场上投射物已满，本次龙卷未消耗法力或冷却")
				return false
			total_shots += emitted
		"bolt":
			for angle: float in [-0.16, 0.0, 0.16]:
				_shoot(player_pos, player_facing.rotated(angle), damage * 1.6, color, 1, 0.0, 780.0, id, "lightning", context)
		"frost":
			for angle: float in [-0.28, -0.14, 0.0, 0.14, 0.28]:
				_shoot(player_pos, player_facing.rotated(angle), damage * 0.85, color, 2, 3.0, 520.0, id, "cold", context)
		"nova":
			_area_damage(player_pos, 155.0, damage * 2.7, color, 0.6, "nova", "lightning", context.snapshot)
			_add_ring(player_pos, 155.0, color, 0.45)
		"dash":
			var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if direction.length_squared() < 0.1:
				direction = player_facing
			var start: Vector2 = player_pos
			player_pos = _clamp_to_arena(player_pos + direction * 175.0, PLAYER_RADIUS)
			invulnerable = 0.6
			for i: int in range(14):
				_add_particle(start.lerp(player_pos, i / 14.0), Vector2.ZERO, color, 9.0 - i * 0.4, 0.38)
		"ward":
			shield = minf(float(_stats.max_shield), shield + float(_stats.max_shield) * 0.75)
			damage_delay = 0.0
			invulnerable = 0.8
			_add_ring(player_pos, 60.0, color, 0.55)
			_add_text(player_pos + Vector2(0, -32), "护盾充能", color)
		"meteor":
			var target: Dictionary = _nearest_enemy(player_pos, 700.0)
			var target_pos: Vector2 = Vector2(target.pos) if not target.is_empty() else _clamp_to_arena(player_pos + player_facing * 220.0, 20.0)
			_area_damage(target_pos, 110.0, damage * 4.3, color, 0.0, "meteor", "fire", context.snapshot)
			_add_ring(target_pos, 110.0, color, 0.7)
			for i: int in range(32):
				_add_particle(target_pos, Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(70, 270), color, rng.randf_range(3, 7), 0.6)
			screen_shake = 4.0
		"chain":
			var origin: Vector2 = player_pos
			var excluded: Array[int] = []
			for i: int in range(5):
				var target: Dictionary = _nearest_enemy(origin, 600.0 if i == 0 else 220.0, excluded)
				if target.is_empty():
					break
				excluded.append(int(target.id))
				var end: Vector2 = target.pos
				for step: int in range(12):
					_add_particle(origin.lerp(end, step / 12.0) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)), Vector2.ZERO, color, 3.0, 0.25)
				_apply_damage_packet(target, Damage.packet({"lightning": damage * (2.2 - i * 0.2)}, ["hit", "spell", "chain"], id), context.snapshot, color, 0.35)
				origin = end
	return true


func _area_damage(origin: Vector2, radius: float, damage: float, color: Color, slow: float,
		skill_id: String = "nova", type: String = "lightning", snapshot: Dictionary = {}) -> void:
	var cast_snapshot: Dictionary = state.get_combat_snapshot() if snapshot.is_empty() else snapshot
	var packet: Dictionary = Damage.packet({type: damage}, ["hit", "spell", "area"], skill_id)
	for enemy: Dictionary in enemies:
		if float(enemy.health) > 0.0 and origin.distance_to(Vector2(enemy.pos)) <= radius + float(enemy.radius):
			_apply_damage_packet(enemy, packet, cast_snapshot, color, slow)
			var direction: Vector2 = (Vector2(enemy.pos) - origin).normalized()
			enemy.knockback = direction * 190.0


func _update_projectiles(delta: float) -> void:
	var events: Array[Dictionary] = projectile_runtime.advance(projectiles, delta, enemies, player_pos, MAX_PROJECTILES)
	for event: Dictionary in events:
		event_counts[event.type] = int(event_counts.get(event.type, 0)) + 1
		var brief: Dictionary = event.duplicate(true)
		brief.erase("snapshot")
		brief.erase("payload")
		combat_trace.append(brief)
		if combat_trace.size() > 96:
			combat_trace.pop_front()
		if event.type == "hit":
			for enemy: Dictionary in enemies:
				if int(enemy.id) == int(event.target_id):
					_apply_damage_packet(enemy, event.payload, event.snapshot, event.color, float(event.slow), event)
					enemy.knockback = Vector2(event.direction) * 45.0
					break
		elif event.type == "explosion":
			var hit_targets: Dictionary = {}
			for enemy: Dictionary in enemies:
				if not hit_targets.has(enemy.id) and float(enemy.health) > 0.0 and Vector2(event.pos).distance_to(enemy.pos) <= float(event.radius) + float(enemy.radius):
					hit_targets[enemy.id] = true
					_apply_damage_packet(enemy, event.payload, event.snapshot, event.color, 0.0, event)
			_add_ring(event.pos, float(event.radius), event.color, 0.55)
		elif event.type == "return_started":
			_add_ring(event.pos, 19.0, Color("bd98ff"), 0.24)
		elif event.type == "split":
			_add_ring(event.pos, 26.0, Color("a6e8aa"), 0.28)
		elif event.type == "spawn_rejected":
			hud.notify("投射物容量不足，本次三子箭整组取消；未触发爆炸")
	enemies = enemies.filter(func(enemy: Dictionary) -> bool: return float(enemy.health) > 0.0)


func _apply_damage_packet(enemy: Dictionary, packet: Dictionary, snapshot: Dictionary, color: Color,
		slow: float = 0.0, provenance: Dictionary = {}) -> void:
	if float(enemy.health) <= 0.0:
		return
	var result: Dictionary = Damage.resolve(packet, snapshot.get("modifiers", []), enemy.get("resistances", {}))
	var record: Dictionary = {"target_id": enemy.id, "skill_id": packet.skill_id, "tags": packet.tags.duplicate(),
		"components": result.components, "details": result.details, "total": result.total,
		"projectile_id": provenance.get("projectile_id", 0), "cast_id": provenance.get("cast_id", 0),
		"phase": provenance.get("phase", "direct"), "effect_id": provenance.get("effect_id", "")}
	damage_trace.append(record)
	if damage_trace.size() > 32:
		damage_trace.pop_front()
	_damage_enemy(enemy, float(result.total), color, slow)


func equip_tornado_example() -> void:
	state.slot_skill(0, "tornado")
	for id: String in ["prism_bow", "return_mantle", "detonation_charm"]:
		state.equip(id)
	hud.notify("已装配龙卷组合：5 母箭 → 15 子箭 → 返回 → 寿命结束爆炸；关闭后按 1 释放")


func combat_preview() -> Dictionary:
	var snapshot: Dictionary = state.get_combat_snapshot()
	var result: Dictionary = {"snapshot": snapshot, "count": clampi(3 + int(snapshot.projectile_count), 1, 9)}
	for role: String in ["parent", "child", "explosion"]:
		result[role] = Damage.resolve(Combat.tornado_packet(snapshot, role), snapshot.modifiers)
	return result


func _damage_enemy(enemy: Dictionary, amount: float, color: Color, slow: float = 0.0) -> void:
	if float(enemy.health) <= 0.0:
		return
	enemy.health = float(enemy.health) - amount
	enemy.flash = 0.12
	enemy.slow = maxf(float(enemy.slow), slow)
	total_damage += amount
	_add_text(Vector2(enemy.pos) + Vector2(rng.randf_range(-8, 8), -18), str(int(amount)), color)
	for i: int in range(4):
		_add_particle(Vector2(enemy.pos), Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(40, 130), color, 2.3, 0.3)
	if float(enemy.health) <= 0.0:
		kills += 1
		var leveled: bool = state.add_xp(6 if int(enemy.kind) == 2 else 3)
		if leveled:
			health = minf(float(_stats.max_health), health + 25.0)
			mana = float(_stats.max_mana)
			hud.notify("升级！获得 1 点天赋 · 按 T 分配")
			_add_ring(player_pos, 80.0, Color("e7c98d"), 0.7)
			_add_text(player_pos + Vector2(0, -46), "LEVEL UP", Color("e7c98d"))
		if kills % 20 == 0:
			_award_kill_jewel()
		if kills % 4 == 0:
			pickups.append({"pos": Vector2(enemy.pos), "life": 22.0})
		for i: int in range(8):
			_add_particle(Vector2(enemy.pos), Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(35, 120), Color("ce8070"), 3.0, 0.45)


func _award_kill_jewel() -> void:
	var jewel_id: String = state.award_jewel(rng)
	if jewel_id.is_empty():
		hud.notify("珠宝藏品已达 64 颗上限，已有珠宝均已保留")
		return
	var jewel: Dictionary = state.jewels[jewel_id]
	hud.notify("获得珠宝：%s · 按 T 查看并镶嵌" % Jewels.display_name(jewel))
	_add_ring(player_pos, 110.0, Color("dba3f2"), 0.9)
	_add_text(player_pos + Vector2(0, -58), "+ 珠宝", Color("dba3f2"))


func hit_player(amount: float) -> void:
	if not alive or invulnerable > 0.0 or amount <= 0.0:
		return
	var absorbed: float = minf(shield, amount)
	shield -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	damage_delay = 4.0
	invulnerable = 0.32
	hurt_flash = 0.16
	screen_shake = 2.5
	_add_text(player_pos + Vector2(0, -30), "−%d" % int(amount), Color("94dafa") if absorbed >= amount else Color("fa8c83"))
	if health <= 0.0:
		alive = false
		projectile_runtime.cancel_all(projectiles, "owner_death")
		save_build()
		hud.show_death()


func _update_pickups(delta: float) -> void:
	for pickup: Dictionary in pickups:
		pickup.life = float(pickup.life) - delta
		var distance: float = Vector2(pickup.pos).distance_to(player_pos)
		if distance < 110.0:
			pickup.pos = Vector2(pickup.pos).move_toward(player_pos, 260.0 * delta)
		if distance < 23.0:
			health = minf(float(_stats.max_health), health + 18.0)
			mana = minf(float(_stats.max_mana), mana + 22.0)
			pickup.life = -1.0
			_add_text(player_pos + Vector2(0, -36), "+生命 / 魔力", Color("85dca5"))
	pickups = pickups.filter(func(pickup: Dictionary) -> bool: return float(pickup.life) > 0.0)


func _add_particle(pos: Vector2, velocity: Vector2, color: Color, radius: float, life: float) -> void:
	if particles.size() >= MAX_PARTICLES:
		return
	particles.append({"pos": pos, "velocity": velocity, "color": color, "radius": radius, "life": life, "max_life": life})


func _add_text(pos: Vector2, value: String, color: Color) -> void:
	if floating_text.size() >= 70:
		floating_text.pop_front()
	floating_text.append({"pos": pos, "text": value, "color": color, "life": 0.85})


func _add_ring(pos: Vector2, radius: float, color: Color, life: float) -> void:
	rings.append({"pos": pos, "radius": radius, "color": color, "life": life, "max_life": life})


func _update_effects(delta: float) -> void:
	for particle: Dictionary in particles:
		particle.pos = Vector2(particle.pos) + Vector2(particle.velocity) * delta
		particle.life = float(particle.life) - delta
	for text: Dictionary in floating_text:
		text.pos = Vector2(text.pos) + Vector2(0, -29.0 * delta)
		text.life = float(text.life) - delta
	for ring: Dictionary in rings:
		ring.life = float(ring.life) - delta
	particles = particles.filter(func(particle: Dictionary) -> bool: return float(particle.life) > 0.0)
	floating_text = floating_text.filter(func(text: Dictionary) -> bool: return float(text.life) > 0.0)
	rings = rings.filter(func(ring: Dictionary) -> bool: return float(ring.life) > 0.0)


func _draw() -> void:
	_draw_arena()
	if not _ready_complete:
		return
	for pickup: Dictionary in pickups:
		var pos: Vector2 = pickup.pos
		var pulse: float = 0.75 + sin(elapsed * 4.5) * 0.2
		draw_circle(pos, 14.0, Color(0.25, 0.7, 0.49, 0.10 * pulse))
		_draw_polygon_shape(pos, 7.0, 4, Color("7bd9a4"), PI / 4.0)
		draw_line(pos + Vector2(-3, 0), pos + Vector2(3, 0), Color("e8ffee"), 1.8)
		draw_line(pos + Vector2(0, -3), pos + Vector2(0, 3), Color("e8ffee"), 1.8)
	for ring: Dictionary in rings:
		var ratio: float = 1.0 - float(ring.life) / float(ring.max_life)
		var color: Color = ring.color
		color.a = (1.0 - ratio) * 0.7
		draw_arc(Vector2(ring.pos), lerpf(8.0, float(ring.radius), ratio), 0, TAU, 64, color, 2.5, true)
	for enemy: Dictionary in enemies:
		_draw_enemy(enemy)
	for shot: Dictionary in projectiles:
		var pos: Vector2 = shot.pos
		var color: Color = Color("bd98ff") if shot.state == "returning" else Color(shot.color)
		var tail: Vector2 = Vector2(shot.velocity).normalized() * 20.0
		draw_line(pos - tail, pos, Color(color, 0.28), 8.0, true)
		draw_line(pos - tail * 0.5, pos, color, 3.0, true)
		draw_circle(pos, 4.2, color)
		draw_circle(pos, 2.0, Color("f5fff4"))
	_draw_player()
	for particle: Dictionary in particles:
		var color: Color = particle.color
		color.a = float(particle.life) / float(particle.max_life)
		draw_circle(Vector2(particle.pos), float(particle.radius) * color.a, color)
	if _font:
		for text: Dictionary in floating_text:
			var color: Color = text.color
			color.a = minf(1.0, float(text.life) * 2.0)
			draw_string(_font, Vector2(text.pos) + Vector2(1, 2), str(text.text), HORIZONTAL_ALIGNMENT_CENTER, -1, 17, Color(0, 0, 0, color.a * 0.7))
			draw_string(_font, Vector2(text.pos), str(text.text), HORIZONTAL_ALIGNMENT_CENTER, -1, 17, color)


func _draw_arena() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("0b1118"))
	draw_rect(ARENA.grow(9), Color("18232c"))
	draw_rect(ARENA.grow(8), Color("263843"), false, 1.0)
	draw_rect(ARENA, Color("17232b"))
	# Fixed, deterministic floor pattern stays quiet behind gameplay.
	for x: int in range(42, 1239, 48):
		draw_line(Vector2(x, 104), Vector2(x, 566), Color("203039"), 1.0)
	for y: int in range(104, 567, 48):
		draw_line(Vector2(42, y), Vector2(1238, y), Color("203039"), 1.0)
	for x: int in range(66, 1230, 96):
		for y: int in range(128, 560, 96):
			draw_circle(Vector2(x, y), 1.0, Color("35434a"))
	var center: Vector2 = ARENA.get_center()
	for radius: float in [88.0, 96.0, 130.0]:
		draw_arc(center, radius, 0, TAU, 96, Color("2b444b"), 1.0, true)
	for i: int in range(8):
		var direction := Vector2.RIGHT.rotated(i * TAU / 8.0)
		draw_line(center + direction * 104, center + direction * 122, Color("456068"), 2.0, true)
	_draw_polygon_shape(center, 63.0, 4, Color("1d3038"), PI / 4)
	draw_rect(ARENA.grow(-12), Color("35505a"), false, 1.0)
	for corner: Vector2 in [Vector2(56, 118), Vector2(1224, 118), Vector2(56, 552), Vector2(1224, 552)]:
		draw_circle(corner, 15, Color("283c42"))
		_draw_polygon_shape(corner, 9, 4, Color("bba77d"), PI / 4)
		_draw_polygon_shape(corner, 4, 4, Color("e3d5a6"), PI / 4)
	if _font:
		draw_string(_font, Vector2(66, 140), "01  /  灰烬庭院", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("6b858c"))
		draw_string(_font, Vector2(1100, 540), "构筑试验场", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("536c74"))


func _draw_player() -> void:
	var pos: Vector2 = player_pos
	if hurt_flash > 0:
		pos += Vector2(sin(elapsed * 90) * screen_shake, cos(elapsed * 75) * screen_shake)
	draw_set_transform(pos + Vector2(0, 15), 0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 21.0, Color(0.01, 0.02, 0.03, 0.6))
	draw_set_transform(Vector2.ZERO)
	var shield_ratio: float = shield / maxf(1.0, float(_stats.max_shield))
	if shield_ratio > 0.0:
		draw_circle(pos, 25, Color(0.3, 0.7, 0.8, 0.045))
		draw_arc(pos, 25, -PI / 2, -PI / 2 + TAU * shield_ratio, 64, Color(0.45, 0.82, 0.92, 0.6), 1.6, true)
	if invulnerable > 0.0:
		draw_arc(pos, 29, elapsed * 5, elapsed * 5 + PI * 1.4, 48, Color("c7f8e6"), 1.5, true)
	var body: Color = Color("f3f8e2") if hurt_flash > 0.0 else Color("aadad2")
	# Cloak, shoulders and focus crystal; facing is readable without external sprites.
	draw_colored_polygon(PackedVector2Array([pos + Vector2(-12, -4), pos + Vector2(-17, 15), pos + Vector2(0, 10), pos + Vector2(17, 15), pos + Vector2(12, -4)]), Color("365965"))
	_draw_polygon_shape(pos, 15, 6, Color("305462"), PI / 6)
	_draw_polygon_shape(pos + Vector2(0, -3), 10, 6, body, PI / 6)
	draw_line(pos + Vector2(-5, -4), pos + Vector2(5, -4), Color("2b4a58"), 3.0)
	var staff: Vector2 = pos + player_facing * 19.0
	draw_line(pos + player_facing * 8.0, staff + player_facing * 9.0, Color("8f7655"), 4.0, true)
	_draw_polygon_shape(staff, 6.5, 4, Color("e3c792"), player_facing.angle())
	draw_circle(staff, 2.8, Color("d5fff0"))
	if not alive:
		draw_circle(pos, 20, Color(0.4, 0.1, 0.12, 0.7))


func _draw_enemy(enemy: Dictionary) -> void:
	var pos: Vector2 = enemy.pos
	var radius: float = enemy.radius
	var kind: int = enemy.kind
	var color: Color = [Color("c7786b"), Color("dbab66"), Color("b089c2")][kind]
	if float(enemy.slow) > 0.0:
		color = Color("7ac8dd")
	if float(enemy.flash) > 0.0:
		color = Color("f9efd8")
	var spawn_ratio: float = 1.0 - float(enemy.spawn) / 0.6
	color.a = 0.3 + spawn_ratio * 0.7
	draw_set_transform(pos + Vector2(0, radius * 0.7), 0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, radius + 5, Color(0.01, 0.02, 0.03, 0.4))
	draw_set_transform(Vector2.ZERO)
	var angle: float = (player_pos - pos).angle()
	_draw_polygon_shape(pos, radius, 4 if kind == 1 else 6, color.darkened(0.32), angle)
	_draw_polygon_shape(pos, radius * 0.73, 4 if kind == 1 else 6, color, angle)
	var eye_pos := pos + Vector2.RIGHT.rotated(angle) * radius * 0.4
	draw_circle(eye_pos, 2.5 if kind != 2 else 4.0, Color("ffe7bb"))
	if kind == 2:
		draw_arc(pos, radius + 3, 0, TAU, 6, color, 1.0, true)
	if float(enemy.health) < float(enemy.max_health):
		draw_rect(Rect2(pos + Vector2(-radius, -radius - 9), Vector2(radius * 2, 3)), Color("101820"))
		draw_rect(Rect2(pos + Vector2(-radius, -radius - 9), Vector2(radius * 2 * maxf(0, float(enemy.health) / float(enemy.max_health)), 3)), color)


func _draw_polygon_shape(center: Vector2, radius: float, sides: int, color: Color, angle: float = 0.0) -> void:
	var points := PackedVector2Array()
	for i: int in range(sides):
		points.append(center + Vector2.RIGHT.rotated(angle + i * TAU / sides) * radius)
	draw_colored_polygon(points, color)
