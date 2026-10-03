extends Node2D
## First playable slice. BuildState owns progression; this node owns a single run.
## Combat uses world units; a native camera widens the view while HUD stays 1280 × 720.

const View = preload("res://scripts/visuals/world_view.gd")
const SpatialTargets = preload("res://scripts/combat/spatial_target_index.gd")
const VisualCueRuntime = preload("res://scripts/visuals/combat_cues.gd")
const Visuals = preload("res://scripts/visuals/arena_visuals.gd")
const Presentation = preload("res://scripts/visuals/visual_settings.gd")
const Build = preload("res://scripts/build_state.gd")
const AreaRules = preload("res://scripts/combat/area_support_rules.gd")
const Data = preload("res://scripts/game_data.gd")
const Hud = preload("res://scripts/game_hud.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const MonsterLifecycle = preload("res://scripts/monsters/monster_runtime.gd")
const TelegraphRuntime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const EncounterCompiler = preload("res://scripts/encounters/encounter_compiler.gd")
const EncounterCatalog = preload("res://scripts/encounters/encounter_catalog.gd")
const EncounterAdmission = preload("res://scripts/encounters/encounter_admission.gd")
const ARENA := View.WORLD_ARENA
const PLAYER_RADIUS := 15.0
const MAX_ENEMIES := 100
const MAX_PROJECTILES := 180
const MAX_PARTICLES := 180
const MAX_PROGRESS_FLUSH_PASSES := 8

var visual_cues = VisualCueRuntime.new()
var visual_settings = Presentation.new()
var monster_runtime = MonsterLifecycle.new()
var telegraphs = TelegraphRuntime.new()
var telegraph_trace: Array[Dictionary] = []
var _encounter_profile: Dictionary = EncounterCompiler.compile([]).profile
var _encounter_ids: Array[String] = []
var _encounter_error: String = ""
var run_revision: int = 0
var reward_kills: int = 0
var ordinary_admissions: int = 0
var demo_mode: bool = false
var density_demo: bool = false
var use_spatial_separation: bool = true
# Developer comparison switch: false preserves per-signal HUD/save work.
var use_progress_batching: bool = true
# Cumulative main-owned refreshes and Model.save_build calls, not file writes.
var progress_hud_refresh_count: int = 0
var progress_save_attempt_count: int = 0
var progress_save_success_count: int = 0
var enemy_spatial = SpatialTargets.new()
var separation_candidate_visits: int = 0
var separation_full_scan_visits: int = 0
var boss_wave_pending: int = 0
var state = Build.new()
var projectile_runtime = Projectiles.new()
var combat_trace: Array[Dictionary] = []
var damage_trace: Array[Dictionary] = []
var incoming_damage_trace: Array[Dictionary] = []
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
var _autosave_timer: float = 0.0
var _ready_complete: bool = false
var _progress_transaction_depth: int = 0
var _progress_revision: int = 0
var _progress_hud_dirty: bool = false
var _progress_save_dirty: bool = false
var _progress_save_requested: bool = false
var _progress_flushing: bool = false
var _progress_saving: bool = false


func _ready() -> void:
	visual_settings.load_settings()
	rng.randomize()
	_font = load("res://assets/fonts/arena_sans.otf")
	_configure_input()
	state.load_build()
	_stats = state.get_stats()
	state.changed.connect(_on_build_changed)
	View.setup_camera(self, ARENA)
	hud = Hud.new()
	hud.name = "GameHUD"
	add_child(hud)
	hud.setup(self)
	_ready_complete = true
	restart_run()
	if not state.last_load_error.is_empty():
		hud.open_panel("pause")
		hud.notify(state.last_load_error)
	elif state.migrated_from_v1 or state.migrated_from_v2 or state.migrated_from_v3 or state.migrated_from_v4 or state.migrated_from_v5 or state.migrated_from_v6 or state.migrated_from_v7 or state.migrated_from_v8 or state.migrated_from_v9 or state.migrated_from_v10 or state.migrated_from_v11:
		hud.open_panel("talents" if state.migrated_from_v1 or state.migrated_from_v6 else "skills" if state.migrated_from_v4 or state.migrated_from_v5 or state.migrated_from_v9 or state.migrated_from_v11 else "inventory" if state.migrated_from_v3 or state.migrated_from_v7 or state.migrated_from_v8 or state.migrated_from_v10 else "combat")
		hud.notify(state.migration_message)
	else:
		hud.notify("F7 怪物机制与分裂试验 · F6 龙卷组合 · T 天赋星图")
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
		_progress_revision += 1
		_progress_hud_dirty = true
		# Crafting commits the complete validated snapshot to disk before emitting.
		# Reentrant changes fail its exact receipt and use normal persistence.
		var already_saved: bool = state.crafting_change_already_saved()
		_progress_save_dirty = not already_saved
		_progress_save_requested = not already_saved
		if not use_progress_batching or _progress_transaction_depth == 0:
			_flush_progress()


func _begin_progress_transaction() -> void:
	_progress_transaction_depth += 1


func _end_progress_transaction() -> void:
	_progress_transaction_depth -= 1
	if _progress_transaction_depth == 0:
		_flush_progress()


func _flush_progress(force_save: bool = false) -> bool:
	if force_save:
		_progress_save_dirty = true
		_progress_save_requested = true
	if _progress_flushing:
		# Explicit saves during a HUD callback still attempt the current state.
		# A model-save callback cannot recursively enter the same disk writer.
		if force_save and not _progress_saving:
			_attempt_progress_save()
		return not _progress_save_dirty and not _progress_hud_dirty
	_progress_flushing = true
	var passes: int = 0
	while (_progress_hud_dirty or _progress_save_requested) and passes < MAX_PROGRESS_FLUSH_PASSES:
		passes += 1
		if _progress_hud_dirty:
			# Consume before calling out: reentrant changes schedule another pass.
			_progress_hud_dirty = false
			if _ready_complete and is_instance_valid(hud):
				progress_hud_refresh_count += 1
				hud.refresh_build()
		if _progress_save_requested and not _attempt_progress_save():
			break
	# A callback that mutates on every refresh/save must not loop forever.
	# Any remaining work stays dirty; explicit save reports that it is not clean.
	_progress_flushing = false
	return not _progress_save_dirty and not _progress_hud_dirty


func _attempt_progress_save() -> bool:
	_progress_save_requested = false
	var revision: int = _progress_revision
	_progress_saving = true
	progress_save_attempt_count += 1
	var error: Error = state.save_build()
	if error == OK:
		progress_save_success_count += 1
		_progress_save_dirty = _progress_revision != revision
		if _progress_save_dirty:
			_progress_save_requested = true
	else:
		_progress_save_dirty = true
		if is_instance_valid(hud):
			hud.notify(state.save_block_reason() if not state.save_block_reason().is_empty() else "存档失败，请检查保存目录的写入权限")
		# Keep the latest state pending without retrying on every empty tick.
		# A later mutation, the existing autosave or an explicit save can retry.
		_progress_save_requested = false
	_progress_saving = false
	return error == OK


func save_build() -> bool:
	return _flush_progress(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_build()
		_quit_game()


func _quit_game() -> void:
	get_tree().quit()


func restart_run() -> void:
	run_revision += 1
	_stats = state.get_stats()
	health = float(_stats.max_health)
	mana = float(_stats.max_mana)
	shield = float(_stats.max_shield)
	kills = 0
	reward_kills = 0
	ordinary_admissions = 0
	demo_mode = false
	density_demo = false
	boss_wave_pending = 0
	monster_runtime.reset()
	telegraphs.reset()
	telegraph_trace.clear()
	elapsed = 0.0
	wave = 1
	alive = true
	player_pos = ARENA.get_center()
	player_facing = Vector2.RIGHT
	enemies.clear()
	projectile_runtime.cancel_all(projectiles)
	combat_trace.clear()
	damage_trace.clear()
	incoming_damage_trace.clear()
	event_counts.clear()
	_simulation_accumulator = 0.0
	particles.clear()
	floating_text.clear()
	pickups.clear()
	rings.clear()
	visual_cues.reset()
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
	elif key == KEY_F7:
		if alive:
			hud.open_panel("monsters")
	elif key == KEY_F6:
		if alive:
			hud.open_panel("combat")
	elif key == KEY_F8:
		open_reference_catalog()
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
	_begin_progress_transaction()
	_tick(delta)
	_end_progress_transaction()


func _tick(delta: float) -> void:
	elapsed += delta
	var new_wave: int = 1 + int(elapsed / 30.0)
	if new_wave != wave:
		wave = new_wave
		if wave % 5 == 0 and not demo_mode:
			boss_wave_pending = wave
		hud.notify("第 %d 波来袭 · 敌人强度提升" % wave)
		_add_ring(ARENA.get_center(), 250.0, Color("d5b77a"), 0.8)
	for id: String in cooldowns:
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	var shield_recovery_time: float = maxf(0.0, delta - damage_delay)
	damage_delay = maxf(0.0, damage_delay - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	screen_shake = maxf(0.0, screen_shake - delta * 15.0)
	mana = minf(float(_stats.max_mana), mana + float(_stats.mana_regen) * delta)
	if damage_delay <= 0.0:
		shield = minf(float(_stats.max_shield), shield + float(_stats.shield_regen) * shield_recovery_time)
	_move_player(delta)
	_update_spawning(delta)
	_update_enemies(delta)
	if not alive:
		return
	_update_auto_attack()
	_update_projectiles(delta)
	_update_effects(delta)
	_update_pickups(delta)
	_start_enemy_telegraphs()
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
	if not _encounter_ready():
		return
	_flush_monster_spawns()
	if demo_mode or not monster_runtime.queue.is_empty():
		return
	if boss_wave_pending > 0 and enemies.size() < MAX_ENEMIES:
		var boss: Dictionary = _spawn_monster("rift_warden", Vector2.ZERO, "level_boss")
		if not boss.is_empty():
			boss_wave_pending = 0
			hud.notify("橙色首领：裂隙守卫 · 击败后生成四只普通巡游体")
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = maxf(0.42, 1.45 - wave * 0.07)
		var count: int = mini(5, 2 + int(wave / 4))
		for i: int in range(count):
			if enemies.size() < MAX_ENEMIES:
				_spawn_enemy()


func _spawn_enemy(forced_position: Vector2 = Vector2.ZERO, forced_kind: int = -1) -> Dictionary:
	if not _encounter_ready():
		return {}
	if enemies.size() >= MAX_ENEMIES:
		return {}
	if forced_kind >= 0:
		if forced_kind >= Monsters.SPECIES.size():
			return {}
		return _spawn_monster(["crawler", "skitter", "brute"][forced_kind], forced_position)
	var natural: bool = forced_position == Vector2.ZERO and not demo_mode
	var random_before: int = rng.state
	var encounter: String = Monsters.encounter_for_admission(wave, ordinary_admissions + 1) if natural else ""
	var enemy: Dictionary
	if not encounter.is_empty():
		enemy = _spawn_monster(encounter)
	else:
		var roll: Dictionary = Monsters.ordinary_roll(rng, wave)
		enemy = _spawn_monster(roll.template, forced_position, "ordinary", roll.rarity, roll.mechanisms)
	if natural and not enemy.is_empty():
		ordinary_admissions += 1
	if enemy.is_empty() and not _encounter_ids.is_empty():
		rng.state = random_before
	return enemy


func _spawn_monster(template_id: String, forced_position: Vector2 = Vector2.ZERO, context: String = "ordinary",
		rarity: String = "", mechanisms: Array = [], rewards: bool = true) -> Dictionary:
	if not _encounter_ready():
		return {}
	if enemies.size() >= MAX_ENEMIES:
		return {}
	var random_before: int = rng.state
	var pos: Vector2 = forced_position
	if pos == Vector2.ZERO:
		var side: int = rng.randi_range(0, 3)
		match side:
			0: pos = Vector2(ARENA.position.x + 24, rng.randf_range(ARENA.position.y + 36.0, ARENA.end.y - 40.0))
			1: pos = Vector2(ARENA.end.x - 24, rng.randf_range(ARENA.position.y + 36.0, ARENA.end.y - 40.0))
			2: pos = Vector2(rng.randf_range(ARENA.position.x + 43.0, ARENA.end.x - 43.0), ARENA.position.y + 22)
			3: pos = Vector2(rng.randf_range(ARENA.position.x + 43.0, ARENA.end.x - 43.0), ARENA.end.y - 22)
		if pos.distance_to(player_pos) < 230.0:
			pos = ARENA.get_center() * 2.0 - pos
	var enemy: Dictionary
	if _encounter_ids.is_empty():
		enemy = monster_runtime.create_root(template_id, wave, pos, context, rarity, mechanisms, rewards and not demo_mode)
	else:
		var admitted: Dictionary = EncounterAdmission.create_root(monster_runtime,_encounter_profile,
			template_id,wave,pos,context,rarity,mechanisms,rewards and not demo_mode)
		if not admitted.ok:
			rng.state = random_before
			_encounter_failed(str(admitted.error))
			return {}
		enemy = admitted.enemy
	if enemy.is_empty():
		return {}
	enemy.pos = _clamp_to_arena(enemy.pos, float(enemy.radius))
	enemies.append(enemy)
	_add_ring(enemy.pos, 32.0, Monsters.RARITIES[enemy.rarity].color, 0.5)
	return enemy


func _flush_monster_spawns() -> void:
	if not _encounter_ready():
		return
	enemies = enemies.filter(func(enemy: Dictionary) -> bool: return float(enemy.health) > 0.0)
	if not alive:
		return
	var children: Array[Dictionary]
	if _encounter_ids.is_empty():
		children = monster_runtime.drain(MAX_ENEMIES - enemies.size(), ARENA)
	else:
		var admitted: Dictionary = EncounterAdmission.drain(monster_runtime,_encounter_profile,MAX_ENEMIES - enemies.size(),ARENA)
		if not admitted.ok:
			_encounter_failed(str(admitted.error))
			return
		children.assign(admitted.enemies)
	for child: Dictionary in children:
		enemies.append(child)
		_add_ring(child.pos, 26.0, Monsters.RARITIES[child.rarity].color, 0.45)
	monster_runtime.collect_lineages(enemies)


func start_monster_demo() -> void:
	_clear_encounter()
	restart_run()
	enemies.clear()
	monster_runtime.reset()
	demo_mode = true
	auto_fire = false
	spawn_timer = 99999.0
	player_pos = View.from_reference(Vector2(640, 420))
	var examples: Array[Dictionary] = [
		{"id": "crawler", "pos": Vector2(180, 245), "rarity": "normal", "mechanisms": []},
		{"id": "skitter", "pos": Vector2(410, 245), "rarity": "magic", "mechanisms": ["gale_stride"]},
		{"id": "brute", "pos": Vector2(650, 245), "rarity": "rare", "mechanisms": ["ember_power", "aegis_capacity"]},
		{"id": "splitter", "pos": Vector2(900, 250), "rarity": "", "mechanisms": []},
		{"id": "brood_host", "pos": Vector2(1080, 430), "rarity": "", "mechanisms": []},
	]
	for example: Dictionary in examples:
		_spawn_monster(example.id, View.from_reference(example.pos), "demo", example.rarity, example.mechanisms, false)
	_spawn_monster("rift_warden", View.from_reference(Vector2(190, 440)), "map_boss", "", [], false)
	hud.open_panel("monsters")
	hud.notify("试验场已就绪，全部怪物无成长奖励。关闭面板可战斗；也可点击演示分裂")


func start_density_demo() -> void:
	# Real catalog monsters, AI, collision and damage. Only progression rewards are disabled.
	_clear_encounter()
	restart_run()
	enemies.clear()
	monster_runtime.reset()
	demo_mode = true
	density_demo = true
	auto_fire = false
	spawn_timer = 99999.0
	player_pos = ARENA.get_center()
	var inner: Rect2 = ARENA.grow(-60.0)
	for index: int in range(MAX_ENEMIES):
		var column: int = index % 10
		var row: int = int(index / 10)
		var pos: Vector2 = inner.position + Vector2((column + 0.5) / 10.0, (row + 0.5) / 10.0) * inner.size
		var template: String = ["crawler", "skitter", "brute"][index % 3]
		var rarity: String = "normal"
		var mechanisms: Array = []
		if index % 20 == 0:
			rarity = "rare"
			mechanisms = ["ember_power", "aegis_capacity"]
		elif index % 10 == 0:
			rarity = "magic"
			mechanisms = ["gale_stride"]
		var enemy: Dictionary
		if index == MAX_ENEMIES - 1:
			enemy = _spawn_monster("rift_warden", pos, "map_boss", "", [], false)
		else:
			enemy = _spawn_monster(template, pos, "demo", rarity, mechanisms, false)
		if not enemy.is_empty():
			enemy.spawn = 0.0
	hud.open_panel("monsters")
	hud.notify("百怪试验：100 只真实怪物，关闭面板后移动、攻击与受击均正常；无成长奖励")


func trigger_demo_split() -> void:
	if not demo_mode or density_demo:
		start_monster_demo()
	var target: Dictionary = {}
	for enemy: Dictionary in enemies:
		if enemy.template_id == "splitter" and float(enemy.health) > 0.0:
			target = enemy
			break
	if target.is_empty():
		target = _spawn_monster("splitter", View.from_reference(Vector2(910, 280)), "demo", "", [], false)
	if not target.is_empty():
		_damage_enemy(target, float(target.health) + float(target.shield) + 1.0, Color("6cafff"))
		_flush_monster_spawns()
		hud.open_panel("monsters")
		hud.notify("裂殖巡游体 → 2 普通巡游体 + 1 掠行体；子怪没有死亡生成词缀")


func restore_standard_run() -> void:
	_clear_encounter()
	restart_run()
	auto_fire = true
	hud.notify("已恢复常规挑战：白蓝金普通池，每五波出现橙色首领")


func encounter_selection() -> Array[String]:
	return _encounter_ids.duplicate()


func encounter_summary() -> String:
	var names: PackedStringArray = []
	for id: String in _encounter_ids:
		names.append(str(EncounterCatalog.get_definition(id).name))
	return "、".join(names) if not names.is_empty() else "常规（无挑战）"


func start_encounter(ids: Variant, expected_revision: Variant) -> bool:
	# UI holds a run revision while its confirmation is open. A newer run or
	# another confirmation cannot accidentally be restarted by a stale request.
	if not expected_revision is int or expected_revision != run_revision:
		return false
	var compiled: Dictionary = EncounterCompiler.compile(ids)
	if not compiled.ok:
		return false
	_encounter_profile = compiled.profile
	_encounter_ids.assign(compiled.profile.modifier_ids)
	_encounter_error = ""
	restart_run()
	return true


func _clear_encounter() -> void:
	_encounter_profile = EncounterCompiler.compile([]).profile
	_encounter_ids.clear()
	_encounter_error = ""


func _encounter_ready() -> bool:
	var reason: String = EncounterCompiler.profile_error(_encounter_profile)
	if reason.is_empty() and _encounter_profile.modifier_ids != _encounter_ids:
		reason = "本轮选择与挑战配置不匹配"
	if reason.is_empty():
		return true
	_encounter_failed(reason)
	return false


func _encounter_failed(reason: String) -> void:
	if _encounter_error == reason:
		return
	_encounter_error = reason
	if is_instance_valid(hud):
		hud.notify("挑战入场失败：" + reason)


func _update_enemies(delta: float) -> void:
	# Existing actions advance against the complete source set before birth
	# protection changes. Admission happens only at the end of the whole tick.
	_advance_enemy_telegraphs(delta)
	if not alive:
		return
	separation_candidate_visits = 0
	separation_full_scan_visits = 0
	if use_spatial_separation:
		enemy_spatial.rebuild(enemies)
	for enemy_index: int in range(enemies.size()):
		var enemy: Dictionary = enemies[enemy_index]
		if float(enemy.health) <= 0.0:
			continue
		var shield_recovery_time: float = maxf(0.0, delta - float(enemy.get("damage_delay", 0.0)))
		enemy.damage_delay = maxf(0.0, float(enemy.get("damage_delay", 0.0)) - delta)
		if float(enemy.damage_delay) <= 0.0:
			enemy.shield = minf(float(enemy.get("max_shield", 0.0)), float(enemy.get("shield", 0.0)) + float(enemy.get("shield_regen", 0.0)) * shield_recovery_time)
		enemy.attack_timer = maxf(0.0, float(enemy.attack_timer) - delta)
		enemy.flash = maxf(0.0, float(enemy.flash) - delta)
		enemy.slow = maxf(0.0, float(enemy.slow) - delta)
		enemy.spawn = maxf(0.0, float(enemy.spawn) - delta)
		if float(enemy.spawn) > 0.0:
			continue
		var uses_telegraph: bool = Monsters.TELEGRAPH_TEMPLATES.has(str(enemy.get("template_id", "")))
		var performing: bool = not telegraphs.state_for(int(enemy.id)).is_empty()
		var direction: Vector2 = Vector2.ZERO if performing else (player_pos - Vector2(enemy.pos)).normalized()
		var speed: float = float(enemy.speed) * (0.36 if float(enemy.slow) > 0 else 1.0)
		var separation := Vector2.ZERO
		var candidates: Array = enemy_spatial.query_circle(enemy.pos, float(enemy.radius) + 3.0) if use_spatial_separation else range(enemies.size())
		separation_candidate_visits += candidates.size()
		separation_full_scan_visits += enemies.size()
		for other_index: int in candidates:
			var other: Dictionary = enemies[other_index]
			if int(other.id) == int(enemy.id):
				continue
			var offset: Vector2 = Vector2(enemy.pos) - Vector2(other.pos)
			var distance: float = offset.length()
			var separation_distance: float = float(enemy.radius) + float(other.radius) + 3.0
			if distance > 0.1 and distance < separation_distance:
				separation += offset / distance * (separation_distance - distance) * 2.5
		enemy.pos = Vector2(enemy.pos) + (direction * speed + separation + Vector2(enemy.knockback)) * delta
		enemy.pos = _clamp_to_arena(Vector2(enemy.pos), float(enemy.radius))
		if use_spatial_separation:
			enemy_spatial.update(enemy_index)
		enemy.knockback = Vector2(enemy.knockback).move_toward(Vector2.ZERO, 520.0 * delta)
		if not uses_telegraph and Vector2(enemy.pos).distance_to(player_pos) < PLAYER_RADIUS + float(enemy.radius) + 1.0:
			if float(enemy.attack_timer) <= 0.0:
				enemy.attack_timer = 1.0 / maxf(0.2, float(enemy.get("attack_speed", 1.0 / 0.85)))
				hit_player_components(Monsters.contact_components(enemy), int(enemy.id))
				if not alive:
					return


func _start_enemy_telegraphs() -> void:
	if not alive:
		return
	for enemy: Dictionary in enemies:
		if float(enemy.health) <= 0.0 or float(enemy.spawn) > 0.0 or float(enemy.attack_timer) > 0.0:
			continue
		if not telegraphs.state_for(int(enemy.id)).is_empty():
			continue
		var policy: Dictionary = Monsters.telegraph_policy(enemy)
		if policy.is_empty() or Vector2(enemy.pos).distance_squared_to(player_pos) > float(policy.trigger_distance) * float(policy.trigger_distance):
			continue
		var result: Dictionary = telegraphs.start(enemy, player_pos, policy.profile)
		if result.ok:
			event_counts["enemy_telegraph_started"] = int(event_counts.get("enemy_telegraph_started", 0)) + 1


func _advance_enemy_telegraphs(delta: float) -> void:
	var events: Array[Dictionary] = telegraphs.advance(delta, enemies)
	for event: Dictionary in events:
		if not alive:
			telegraphs.reset()
			break
		var inside: bool = TelegraphRuntime.overlaps(event, player_pos, PLAYER_RADIUS)
		var applied: bool = hit_player_components(event.packet.base, int(event.source_id)) if inside else false
		var record: Dictionary = event.duplicate(true)
		record["player_position"] = player_pos
		record["inside"] = inside
		record["applied"] = applied
		telegraph_trace.append(record)
		if telegraph_trace.size() > 32:
			telegraph_trace.pop_front()
		event_counts["enemy_telegraph_resolved"] = int(event_counts.get("enemy_telegraph_resolved", 0)) + 1


func telegraph_visual_states() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	if telegraphs.active_count() == 0:
		return snapshots
	for enemy: Dictionary in enemies:
		var copied: Dictionary = telegraphs.state_for(int(enemy.id))
		if not copied.is_empty():
			snapshots.append(copied)
	return snapshots


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
	var snapshot: Dictionary = state.get_combat_snapshot()
	var packet: Dictionary = Combat.event_packet(snapshot, "basic", "projectile")
	var secondary: Dictionary = Combat.secondary_packet(snapshot, "basic")
	if packet.is_empty() or secondary.is_empty():
		return
	# Basic attacks share typed assembly, while remaining outside support eligibility.
	snapshot["compiled_skill_id"] = "basic"
	snapshot["compiled_packets"] = {"projectile": packet.duplicate(true), "secondary": secondary}
	if _shoot(player_pos, player_facing, packet, Color("75e5df"), 0, 0, 640.0, {"snapshot": snapshot}):
		attack_timer = 1.0 / maxf(0.2, float(_stats.attack_speed))


func _shoot(origin: Vector2, direction: Vector2, packet: Dictionary, color: Color,
		pierce: int = 0, slow: float = 0.0, speed: float = 600.0, context: Dictionary = {}) -> bool:
	if projectiles.size() >= MAX_PROJECTILES or packet.is_empty():
		return false
	var snapshot: Dictionary = context["snapshot"] if context.has("snapshot") else state.get_combat_snapshot()
	var cast_id: int = int(context.get("cast_id", 0))
	if cast_id == 0:
		cast_id = projectile_runtime.new_cast()
	var spec: Dictionary = {"speed": speed, "range": 650.0, "lifetime": 1.7,
		"pierce": pierce, "slow": slow}
	projectiles.append(projectile_runtime.make_projectile(origin + direction * 19.0, direction,
		spec, packet, snapshot, cast_id, color))
	total_shots += 1
	for i: int in range(3):
		_add_particle(origin + direction * 20.0, direction.rotated(rng.randf_range(-0.6, 0.6)) * rng.randf_range(20, 90), color, 2.2, 0.16)
	return true


func cast_skill(index: int) -> bool:
	_begin_progress_transaction()
	var accepted: bool = _cast_skill(index)
	_end_progress_transaction()
	return accepted


func _cast_skill(index: int) -> bool:
	if not alive or not _ready_complete or hud.is_blocking() or index < 0 or index >= state.skill_slots.size():
		return false
	var id: String = state.skill_slots[index]
	if not Data.SKILLS.has(id):
		return false
	var skill: Dictionary = Data.SKILLS[id]
	# Compile once before admission: preview, payment and execution share this result.
	var compiled: Dictionary = state.get_skill_cast(id)
	if not compiled.get("ok", false):
		hud.notify("技能辅助配置无效：" + str(compiled.get("error", "未知配置")))
		return false
	var mana_cost: float = float(compiled.mana)
	if float(cooldowns.get(id, 0.0)) > 0.0:
		hud.notify("%s 冷却中" % skill.name)
		return false
	if mana < mana_cost:
		hud.notify("魔力不足 · 等待恢复或拾取补给")
		return false
	var volley_size: int = int(compiled.initial_count)
	if volley_size > 0 and projectiles.size() + volley_size > MAX_PROJECTILES:
		hud.notify("投射物空间不足以发射完整技能，本次未消耗法力或冷却")
		return false
	mana -= mana_cost
	cooldowns[id] = float(compiled.cooldown)
	player_facing = _aim_direction()
	var color: Color = skill.color
	var context: Dictionary = {"snapshot": compiled.snapshot, "cast_id": 0 if id == "tornado" else projectile_runtime.new_cast()}
	match id:
		"tornado":
			var emitted: int = projectile_runtime.spawn_tornado(projectiles, player_pos, player_facing, context.snapshot, MAX_PROJECTILES, int(compiled.initial_count))
			if emitted == 0:
				mana += mana_cost
				cooldowns[id] = 0.0
				hud.notify("场上投射物已满，本次龙卷未消耗法力或冷却")
				return false
			total_shots += emitted
		"bolt", "frost":
			var recipe: Dictionary = compiled.recipe
			for shot_index: int in range(int(compiled.initial_count)):
				var angle: float = (shot_index - (int(compiled.initial_count) - 1) * 0.5) * float(recipe.spread)
				_shoot(player_pos, player_facing.rotated(angle), compiled.packets.projectile, color,
					int(recipe.pierce), float(recipe.slow), float(recipe.speed), context)
		"nova":
			_area_damage(player_pos, float(compiled.recipe.radius), compiled.packets.direct, color, 0.6, context.snapshot)
			visual_cues.emit_cue("nova", player_pos, {"radius": float(compiled.recipe.radius), "color": color})
		"dash":
			var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if direction.length_squared() < 0.1:
				direction = player_facing
			var start: Vector2 = player_pos
			player_pos = _clamp_to_arena(player_pos + direction * 175.0, PLAYER_RADIUS)
			visual_cues.emit_cue("dash", start, {"destination": player_pos, "color": color})
			invulnerable = 0.6
			for i: int in range(14):
				_add_particle(start.lerp(player_pos, i / 14.0), Vector2.ZERO, color, 9.0 - i * 0.4, 0.38)
		"ward":
			shield = minf(float(_stats.max_shield), shield + float(_stats.max_shield) * 0.75)
			damage_delay = 0.0
			invulnerable = 0.8
			visual_cues.emit_cue("ward", player_pos, {"radius": 60.0, "color": color})
			_add_text(player_pos + Vector2(0, -32), "护盾充能", color)
		"meteor":
			var target: Dictionary = _nearest_enemy(player_pos, 700.0)
			var target_pos: Vector2 = Vector2(target.pos) if not target.is_empty() else _clamp_to_arena(player_pos + player_facing * 220.0, 20.0)
			_area_damage(target_pos, float(compiled.recipe.radius), compiled.packets.direct, color, 0.0, context.snapshot)
			visual_cues.emit_cue("meteor", target_pos, {"radius": float(compiled.recipe.radius), "color": color})
			for i: int in range(32):
				_add_particle(target_pos, Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(70, 270), color, rng.randf_range(3, 7), 0.6)
			screen_shake = 4.0
		"chain":
			var origin: Vector2 = player_pos
			var excluded: Array[int] = []
			for i: int in range(compiled.packets.bounces.size()):
				var target: Dictionary = _nearest_enemy(origin, 600.0 if i == 0 else 220.0, excluded)
				if target.is_empty():
					break
				excluded.append(int(target.id))
				var end: Vector2 = target.pos
				visual_cues.emit_cue("chain", origin, {"destination": end, "target_id": int(target.id), "color": color})
				for step: int in range(12):
					_add_particle(origin.lerp(end, step / 12.0) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)), Vector2.ZERO, color, 3.0, 0.25)
				_apply_damage_packet(target, compiled.packets.bounces[i], context.snapshot, color, 0.35, {"cast_id": context.cast_id})
				origin = end
	if id in ["tornado", "bolt", "frost"]:
		visual_cues.emit_cue("cast", player_pos, {"direction": player_facing, "skill": id, "color": color})
	return true


func _area_damage(origin: Vector2, radius: float, packet: Dictionary, color: Color, slow: float,
		snapshot: Dictionary = {}) -> void:
	if packet.is_empty():
		return
	var cast_snapshot: Dictionary = state.get_combat_snapshot() if snapshot.is_empty() else snapshot
	for enemy: Dictionary in enemies:
		if float(enemy.health) > 0.0 and float(enemy.spawn) <= 0.0 and AreaRules.contains_target(origin, Vector2(enemy.pos), radius, float(enemy.radius)):
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
			visual_cues.emit_cue("explosion", event.pos, {"radius": float(event.radius), "color": event.color})
		elif event.type == "return_started":
			visual_cues.emit_cue("return", event.pos, {"radius": 19.0, "color": Color("bd98ff")})
		elif event.type == "split":
			visual_cues.emit_cue("split", event.pos, {"radius": 26.0, "color": Color("a6e8aa")})
		elif event.type == "spawn_rejected":
			hud.notify("投射物容量不足，本次三子箭整组取消；未触发爆炸")
	_flush_monster_spawns()


func _apply_damage_packet(enemy: Dictionary, packet: Dictionary, snapshot: Dictionary, color: Color,
		slow: float = 0.0, provenance: Dictionary = {}) -> void:
	if float(enemy.health) <= 0.0 or float(enemy.get("spawn", 0.0)) > 0.0:
		return
	var result: Dictionary = Damage.resolve(packet, snapshot.get("modifiers", []), enemy.get("resistances", {}))
	var settlement: Dictionary = Defense.settle_resolved(result, float(enemy.get("shield", 0.0)), float(enemy.health))
	if not settlement.ok:
		return
	var record: Dictionary = {"target_id": enemy.id, "skill_id": packet.skill_id, "tags": packet.tags.duplicate(),
		"components": result.components, "details": result.details, "total": result.total,
		"before_defense_components": settlement.raw_components, "prevented_components": settlement.mitigated_components,
		"shield_spent": settlement.shield_spent, "health_lost": settlement.health_lost,
		"assembly": packet.get("assembly", {}).duplicate(true),
		"projectile_id": provenance.get("projectile_id", 0), "cast_id": provenance.get("cast_id", 0),
		"phase": provenance.get("phase", "direct"), "effect_id": provenance.get("effect_id", "")}
	damage_trace.append(record)
	if damage_trace.size() > 32:
		damage_trace.pop_front()
	_apply_enemy_settlement(enemy, settlement, color, slow)


func equip_tornado_example() -> void:
	state.slot_skill(0, "tornado")
	for id: String in ["prism_bow", "return_mantle", "detonation_charm"]:
		state.equip(id)
	var compiled: Dictionary = state.get_skill_cast("tornado")
	var parents: int = int(compiled.get("initial_count", 0))
	hud.notify("已装配龙卷组合：%d 母箭 → %d 子箭 → 返回 → 寿命结束爆炸；关闭后按 1 释放" % [parents, parents * 3])


func combat_preview() -> Dictionary:
	var compiled: Dictionary = state.get_skill_cast("tornado")
	var snapshot: Dictionary = compiled.get("snapshot", state.get_combat_snapshot())
	var result: Dictionary = {"snapshot": snapshot, "count": int(compiled.get("initial_count", 0)),
		"mana": float(compiled.get("mana", 0.0)), "supports": compiled.get("support_ids", []),
		"packets": compiled.get("packets", {})}
	for role: String in ["parent", "child", "explosion"]:
		result[role] = Damage.resolve(Combat.tornado_packet(snapshot, role), snapshot.modifiers)
	return result


func _damage_enemy(enemy: Dictionary, amount: float, color: Color, slow: float = 0.0) -> void:
	if float(enemy.health) <= 0.0 or amount <= 0.0 or not is_finite(amount):
		return
	# Compatibility helper receives damage already resolved by its caller.
	var settlement: Dictionary = Defense.incoming_hit({"physical": amount}, {}, float(enemy.get("shield", 0.0)), float(enemy.health), "monster")
	if settlement.ok:
		_apply_enemy_settlement(enemy, settlement, color, slow)


func _apply_enemy_settlement(enemy: Dictionary, settlement: Dictionary, color: Color, slow: float = 0.0) -> void:
	var amount: float = float(settlement.damage_total)
	if float(enemy.health) <= 0.0 or amount <= 0.0:
		return
	var absorbed: float = float(settlement.shield_spent)
	enemy.shield = float(settlement.remaining_shield)
	enemy.damage_delay = 4.0
	# Keep the historical signed corpse value; actual life loss is bounded in the trace.
	enemy.health = float(settlement.remaining_health) - float(settlement.overkill)
	visual_cues.emit_cue("impact", Vector2(enemy.pos), {"radius": clampf(7.0 + sqrt(amount) * 0.65, 8.0, 24.0), "color": color, "shielded": absorbed >= amount, "target_id": int(enemy.id)})
	enemy.flash = 0.12
	enemy.slow = maxf(float(enemy.slow), slow)
	total_damage += amount
	_add_text(Vector2(enemy.pos) + Vector2(rng.randf_range(-8, 8), -18), str(int(amount)), color)
	for i: int in range(4):
		_add_particle(Vector2(enemy.pos), Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(40, 130), color, 2.3, 0.3)
	if float(enemy.health) <= 0.0:
		telegraphs.cancel(int(enemy.id))
		var death: Dictionary = monster_runtime.process_death(enemy)
		if not death.processed:
			return
		visual_cues.emit_cue("death", Vector2(enemy.pos), {"radius": float(enemy.radius), "color": Monsters.RARITIES[enemy.rarity].color, "target_id": int(enemy.id)})
		kills += 1
		var eligible: bool = bool(death.reward) and not demo_mode
		if eligible:
			reward_kills += 1
		var leveled: bool = state.add_xp(int(enemy.get("xp_reward", 0))) if eligible else false
		if leveled:
			health = minf(float(_stats.max_health), health + 25.0)
			mana = float(_stats.max_mana)
			hud.notify("升级！获得 1 点天赋 · 按 T 分配")
			_add_ring(player_pos, 80.0, Color("e7c98d"), 0.7)
			_add_text(player_pos + Vector2(0, -46), "LEVEL UP", Color("e7c98d"))
		if eligible and (reward_kills % 8 == 0 or enemy.get("rarity", "") in ["rare", "boss"]):
			_award_kill_equipment(enemy)
		if eligible and reward_kills % 20 == 0:
			_award_kill_jewel()
		if eligible and enemy.get("rarity", "") == "boss":
			_award_kill_special_jewel()
		if eligible and reward_kills % 4 == 0:
			pickups.append({"pos": Vector2(enemy.pos), "life": 22.0})
		for i: int in range(8):
			_add_particle(Vector2(enemy.pos), Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(35, 120), Color("ce8070"), 3.0, 0.45)


func _award_kill_equipment(enemy: Dictionary) -> void:
	# Exactly one decision per eligible root death. Descendants/demo never enter here.
	var rarity: String = "rare" if enemy.get("rarity", "") in ["rare", "boss"] else ""
	var item_level: int = clampi(wave * 2 - 1, 1, 30)
	var pool: String = str(enemy.get("equipment_pool", ""))
	var item_id: String = state.award_equipment(rng, item_level, rarity, "current" if pool.is_empty() else pool)
	if item_id.is_empty():
		hud.notify("背包保留空间不足，无法领取新装备；已有物品完整保留，可在 I 中清理随机装备")
		return
	var definition: Dictionary = state.get_item_definition(item_id)
	hud.notify("获得装备：%s · 物品等级 %d · 按 I 比较和穿戴" % [definition.name, item_level])
	_add_ring(player_pos, 90.0, Color("eac976"), 0.7)
	_add_text(player_pos + Vector2(0, -76), "+ 装备", Color("eac976"))


func _award_kill_jewel() -> void:
	var jewel_id: String = state.award_jewel(rng)
	if jewel_id.is_empty():
		hud.notify("珠宝上限或背包保留空间不足，已有珠宝均已保留")
		return
	var jewel: Dictionary = state.jewels[jewel_id]
	hud.notify("获得珠宝：%s · 按 T 查看并镶嵌" % Jewels.display_name(jewel))
	_add_ring(player_pos, 110.0, Color("dba3f2"), 0.9)
	_add_text(player_pos + Vector2(0, -58), "+ 珠宝", Color("dba3f2"))


func _award_kill_special_jewel() -> void:
	# Boss roots use the same once-only death gate; legacy random rolls are untouched.
	var jewel_id: String = state.award_special_jewel()
	if jewel_id.is_empty():
		hud.notify("首领珠宝未领取：背包保留空间不足；已有物品完整保留")
		return
	hud.notify("获得寻枝晶玉 · 在 T 中选择已连通的珠宝孔查看覆盖")
	_add_ring(player_pos, 100.0, Color("d8b577"), 0.8)
	_add_text(player_pos + Vector2(0, -58), "+ 寻枝晶玉", Color("d8b577"))


func reference_catalog_path() -> String:
	# Documentation is outside the PCK so a standard browser can open it offline.
	var paths: Array[String] = [
		ProjectSettings.globalize_path("res://docs/reference/index.html"),
		OS.get_executable_path().get_base_dir().path_join("docs/reference/index.html"),
	]
	for path: String in paths:
		if path.is_absolute_path() and FileAccess.file_exists(path):
			return path
	return ""


func open_reference_catalog() -> bool:
	if not hud.is_blocking() and alive:
		hud.open_panel("pause")
	var path: String = reference_catalog_path()
	if path.is_empty():
		hud.notify("未找到离线图鉴，请保留游戏包中的 docs/reference 文件夹")
		return false
	var error: Error = OS.shell_open(path)
	if error != OK:
		hud.notify("图鉴未能打开，可手动双击 docs/reference/index.html")
		return false
	return true


func hit_player(amount: float) -> void:
	if not alive or invulnerable > 0.0 or amount <= 0.0 or not is_finite(amount):
		return
	hit_player_components({"physical": amount})


func player_defense_profile() -> Dictionary:
	return Defense.defense_profile({"fire_resistance": _stats.get("fire_resistance", 0.0)}, "player")


func hit_player_components(components: Variant, source_id: int = 0) -> bool:
	if not alive or invulnerable > 0.0:
		return false
	var settlement: Dictionary = Defense.incoming_hit(components, {"fire_resistance": _stats.get("fire_resistance", 0.0)}, shield, health, "player")
	if not settlement.ok or float(settlement.damage_total) <= 0.0:
		return false
	var amount: float = float(settlement.damage_total)
	var absorbed: float = float(settlement.shield_spent)
	shield = float(settlement.remaining_shield)
	health = float(settlement.remaining_health)
	var record: Dictionary = settlement.duplicate(true)
	record["source_id"] = source_id
	incoming_damage_trace.append(record)
	if incoming_damage_trace.size() > 32:
		incoming_damage_trace.pop_front()
	visual_cues.emit_cue("hurt", player_pos, {"shielded": absorbed >= amount})
	damage_delay = 4.0
	invulnerable = 0.32
	hurt_flash = 0.16
	screen_shake = 2.5
	_add_text(player_pos + Vector2(0, -30), "−%d" % int(amount), Color("94dafa") if absorbed >= amount else Color("fa8c83"))
	if health <= 0.0:
		alive = false
		telegraphs.reset()
		monster_runtime.cancel_pending("player_death")
		projectile_runtime.cancel_all(projectiles, "owner_death")
		save_build()
		hud.show_death()
	return true


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
	visual_cues.advance(delta)
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
	Visuals.draw_scene(self, visual_settings)
