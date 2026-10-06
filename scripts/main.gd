extends Node2D
## First playable slice. BuildState owns progression; this node owns a single run.
## Combat uses world units; a native camera widens the view while HUD stays 1280 × 720.

const View = preload("res://scripts/visuals/world_view.gd")
const SpatialTargets = preload("res://scripts/combat/spatial_target_index.gd")
const VisualCueRuntime = preload("res://scripts/visuals/combat_cues.gd")
const Visuals = preload("res://scripts/visuals/arena_visuals.gd")
const RetainedActors = preload("res://scripts/visuals/retained_actor_layer.gd")
const ForegroundLayer = preload("res://scripts/visuals/foreground_arena_layer.gd")
var retained_actors: Node2D
var foreground_layer: Node2D
# Diagnostic reference path; runtime state and simulation do not consult it.
var use_retained_actors: bool = true
var _render_measured_frame := -1
var _render_prefix_usec := 0
const Presentation = preload("res://scripts/visuals/visual_settings.gd")
const Build = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const GroupCooldowns = preload("res://scripts/combat/skill_cooldown_ledger.gd")
const AreaRules = preload("res://scripts/combat/area_support_rules.gd")
const Data = preload("res://scripts/game_data.gd")
const Hud = preload("res://scripts/game_hud.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const CriticalRuntime = preload("res://scripts/combat/critical_strike_runtime.gd")
const Resolute = preload("res://scripts/combat/resolute_technique_rules.gd")
var critical_runtime = CriticalRuntime.new()
const FeedbackRuntime = preload("res://scripts/combat/combat_feedback_runtime.gd")
var feedback_runtime = FeedbackRuntime.new()
const BurnRuntime=preload("res://scripts/combat/burn_runtime.gd")
const BurnRules=preload("res://scripts/combat/burn_rules.gd")
const EmberRules=preload("res://scripts/combat/ember_proliferation_rules.gd")
const EmberClock=preload("res://scripts/combat/ember_event_clock.gd")
var _ember_projectile_clock:Dictionary={}
var burn_runtime=BurnRuntime.new()
const ShockRules=preload("res://scripts/combat/shock_rules.gd")
const ShockRuntime=preload("res://scripts/combat/shock_runtime.gd")
var shock_runtime=ShockRuntime.new()
var burn_trace:Array[Dictionary]=[]
var _ember_advancing:=false
var _ember_defer_deaths:=false
var _ember_flushing:=false
var _ember_deaths:Array[Dictionary]=[]
var _burn_step_active:=false
var _burn_step_start:=0.0
var _burn_immunity_until:=0.0
var _burn_incoming_time:float=-1.0
const LeechRuntime = preload("res://scripts/combat/leech_runtime.gd")
const LeechRules = preload("res://scripts/combat/leech_rules.gd")
var leech_runtime = LeechRuntime.new()
var _leech_caps: Dictionary = {"health": 0.0, "mana": 0.0}
const AttackHit = preload("res://scripts/combat/attack_hit_rules.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const MonsterLifecycle = preload("res://scripts/monsters/monster_runtime.gd")
const FlaskRuntime = preload("res://scripts/combat/flask_runtime.gd")
const FlaskCatalog = preload("res://scripts/items/flask_catalog.gd")
var flask_runtime = FlaskRuntime.new()
var _flask_owner_identity: int = -1
var _flask_synced_revision: int = -1
const TelegraphRuntime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const EncounterCompiler = preload("res://scripts/encounters/encounter_compiler.gd")
const EncounterCatalog = preload("res://scripts/encounters/encounter_catalog.gd")
const EncounterAdmission = preload("res://scripts/encounters/encounter_admission.gd")
const ARENA := View.WORLD_ARENA
const PLAYER_RADIUS := 15.0
const Geometry = preload("res://scripts/world/map_geometry.gd")
var _geometry = Geometry.new()
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
var enemy_spatial = SpatialTargets.new(64.0)
var separation_candidate_visits: int = 0
var separation_full_scan_visits: int = 0
var boss_wave_pending: int = 0
var state = Build.new()
var projectile_runtime = Projectiles.new()
var combat_trace: Array[Dictionary] = []
var damage_trace: Array[Dictionary] = []
var incoming_damage_trace: Array[Dictionary] = []
var attack_admission_trace: Array[Dictionary] = []
var _player_evasion_entropy := 50.0
var _projectile_targets: Dictionary = {}
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
var group_cooldowns = GroupCooldowns.new()
var _group_cast_busy := false
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
var static_environment: Node2D
var _world_draw_count: int = 0
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
	var supply_config:Variant=ProjectSettings.get_setting("testing/town_supply_enabled",true)
	test_supply_enabled=supply_config is bool and supply_config
	visual_settings.load_settings()
	rng.randomize()
	_font = load("res://assets/fonts/arena_sans.otf")
	_configure_input()
	state.load_build(build_save_path)
	var recovered: Dictionary = _recover_normal_active()
	_stats = state.get_stats()
	state.changed.connect(_on_build_changed)
	static_environment = preload("res://scripts/visuals/static_arena_layer.gd").new()
	static_environment.name = "StaticArenaBackground"
	static_environment.z_index = -1
	static_environment.show_behind_parent = true
	static_environment.configure(ARENA, _font)
	add_child(static_environment)
	View.setup_camera(self, ARENA)
	retained_actors = RetainedActors.new()
	retained_actors.name = "RetainedActors"
	add_child(retained_actors)
	foreground_layer = ForegroundLayer.new()
	foreground_layer.name = "ForegroundWorld"
	foreground_layer.source = self
	add_child(foreground_layer)
	hud = Hud.new()
	hud.name = "GameHUD"
	add_child(hud)
	hud.setup(self)
	world_context_changed.connect(_sync_camp_presentation)
	world_context_changed.connect(_invalidate_normal_gem_quotes)
	_ready_complete = true
	restart_run()
	if not recovered.ok:
		hud.notify(recovered.reason)
	elif int(recovered.get("abandoned_run_id",0))>0:
		hud.notify("上次未完成地图已按离场保存；已得进度保留，入场碎片不退还")
	elif not state.last_load_error.is_empty():
		hud.open_panel("pause")
		hud.notify(state.last_load_error)
	elif state.has_method("passive_analysis"):
		if state.migrated_from_legacy:
			hud.open_panel("inventory")
			hud.notify(state.migration_message)
		else: hud.notify("I / B 行囊 · T 源天赋树 · K 技能宝石")
	elif state.migrated_from_v1 or state.migrated_from_v2 or state.migrated_from_v3 or state.migrated_from_v4 or state.migrated_from_v5 or state.migrated_from_v6 or state.migrated_from_v7 or state.migrated_from_v8 or state.migrated_from_v9 or state.migrated_from_v10 or state.migrated_from_v11 or state.migrated_from_v12:
		hud.open_panel("talents" if state.migrated_from_v1 or state.migrated_from_v6 else "skills" if state.migrated_from_v4 or state.migrated_from_v5 or state.migrated_from_v9 or state.migrated_from_v11 or state.migrated_from_v12 else "inventory" if state.migrated_from_v3 or state.migrated_from_v7 or state.migrated_from_v8 or state.migrated_from_v10 else "combat")
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
	_sync_flasks()
	_stats = state.get_stats()
	health = minf(health, float(_stats.max_health))
	mana = minf(mana, float(_stats.max_mana))
	shield = minf(shield, float(_stats.max_shield))
	_refresh_leech_caps()
	_clear_full_leech()
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
	var error: Error = state.save_build(build_save_path)
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


func restart_run(camp_plan: Dictionary = {}) -> void:
	if _world_mode in ["map", "map_complete"] and not _is_test_profile() and not _normal_reset_authorized:
		var retried: Dictionary = retry_normal_map(_world_revision)
		if not retried.ok and is_instance_valid(hud): hud.notify(retried.reason)
		return
	if _world_mode in ["map","map_complete"]:
		if camp_plan.is_empty():camp_plan=_prepare_camp_run(_map_run.profile,run_revision+1)
		if not camp_plan.get("ok",false):
			if is_instance_valid(hud):hud.notify(str(camp_plan.get("reason","地图据点不可用")))
			return
		var profile:Dictionary=_map_run.profile.duplicate(true)
		if not _map_run.begin(profile):
			if is_instance_valid(hud):hud.notify("地图配置无效，不能重开")
			return
		_world_mode="map";_world_revision+=1
	if _world_mode=="map":
		_map_camps=camp_plan.state
		_camp_landmarks=camp_plan.landmarks.duplicate(true)
	else:
		_map_camps.clear();_camp_landmarks.clear()
	_camp_movement.clear();_camp_requested.clear();_camp_wait_reasons.clear();_boss_requested=false
	_normal_reset_authorized = false
	_sync_flasks(true)
	run_revision += 1
	critical_runtime.reset(rng.seed ^ run_revision)
	leech_runtime.clear()
	_stats = state.get_stats()
	_refresh_leech_caps()
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
	wave = int(_map_run.profile.wave) if _world_mode=="map" else 1
	alive = true
	_refresh_world_geometry()
	player_pos = Vector2(_camp_landmarks.entry) if _world_mode=="map" else ARENA.get_center()
	player_facing = Vector2.RIGHT
	enemies.clear()
	if is_instance_valid(retained_actors): retained_actors.clear()
	projectile_runtime.cancel_all(projectiles)
	combat_trace.clear()
	damage_trace.clear()
	incoming_damage_trace.clear()
	event_counts.clear()
	_simulation_accumulator = 0.0
	particles.clear()
	floating_text.clear()
	feedback_runtime.reset()
	pickups.clear()
	rings.clear()
	visual_cues.reset()
	cooldowns.clear()
	group_cooldowns.reset()
	_player_evasion_entropy = 50.0
	attack_admission_trace.clear()
	burn_runtime.reset();burn_trace.clear();_ember_deaths.clear()
	shock_runtime.reset()
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
		if _world_mode=="normal":
			for i: int in range(3):
				_spawn_enemy()
	queue_redraw()
	world_context_changed.emit()


func _sync_flasks(reset_run: bool=false) -> void:
	var owner: int=state.get_instance_id()
	var revision: int=int(state.revision()) if state.has_method("revision") else 0
	if not reset_run and owner==_flask_owner_identity and revision==_flask_synced_revision:return
	var owned: Dictionary=state.owned_flasks() if state.has_method("owned_flasks") else {}
	if reset_run or owner!=_flask_owner_identity:flask_runtime.reset(owned)
	else:flask_runtime.sync_owned(owned)
	_flask_owner_identity=owner;_flask_synced_revision=revision


func _refresh_leech_caps() -> void:
	var profile: Dictionary = LeechRules.profile(_stats)
	assert(profile.ok, "Validated build must provide a finite leech profile")
	_leech_caps = {"health": float(profile.health.total_rate_cap), "mana": float(profile.mana.total_rate_cap)} if profile.ok else {"health": 0.0, "mana": 0.0}


func _clear_full_leech() -> void:
	if leech_runtime.is_empty(): return
	leech_runtime.clear_full({"health": health, "mana": mana}, {"health": float(_stats.max_health), "mana": float(_stats.max_mana)})


func _advance_leech(delta: float) -> void:
	if leech_runtime.is_empty(): return
	var recovered: Dictionary = leech_runtime.advance(delta, {"health": health, "mana": mana},
		{"health": float(_stats.max_health), "mana": float(_stats.max_mana)}, _leech_caps)
	if not recovered.ok: return
	health = minf(float(_stats.max_health), health + float(recovered.health))
	mana = minf(float(_stats.max_mana), mana + float(recovered.mana))
	_clear_full_leech()

func flask_statuses() -> Array[Dictionary]:
	_sync_flasks()
	var result: Array[Dictionary]=[]
	if not state.has_method("flask_slots"):return result
	for slot:Dictionary in state.flask_slots():
		var row:Dictionary=slot.duplicate(true)
		if slot.uid.is_empty():row.merge({"charges":0,"max_charges":FlaskCatalog.MAX_CHARGES,"cost":FlaskCatalog.USE_COST,"active":false,"resource_active":false,"remaining_seconds":0.0,"can_use":false,"code":"empty_slot","reason":"药剂槽为空"})
		else:
			var resource:String=slot.resource
			row.merge(flask_runtime.status(slot.uid,health if resource=="health" else mana,float(_stats.max_health) if resource=="health" else float(_stats.max_mana)),true)
			if not alive:row.can_use=false;row.code="dead";row.reason="角色已死亡"
			elif is_instance_valid(hud) and hud.is_blocking():row.can_use=false;row.code="paused";row.reason="暂停时不能使用药剂"
			elif _world_mode in ["town","map_complete"]:row.can_use=false;row.code="safe_area";row.reason="安全区域不使用药剂"
		result.append(row)
	return result

func use_flask(slot_id: Variant) -> Dictionary:
	if not slot_id is String:return {"ok":false,"code":"invalid_slot","reason":"药剂槽无效"}
	for entry:Dictionary in flask_statuses():
		if entry.slot_id!=slot_id:continue
		if not entry.can_use:
			entry.ok=false
			return entry
		var resource:String=entry.resource
		var result:Dictionary=flask_runtime.use(entry.uid,health if resource=="health" else mana,float(_stats.max_health) if resource=="health" else float(_stats.max_mana),_stats)
		if result.ok:
			var definition:Dictionary=FlaskCatalog.definition(entry.definition_id)
			_add_ring(player_pos,30.0,definition.color,0.35)
			_add_text(player_pos+Vector2(0,-38),"生命恢复" if resource=="health" else "魔力恢复",definition.color)
		return result
	return {"ok":false,"code":"invalid_slot","reason":"药剂槽无效"}


func toggle_auto_fire() -> void:
	auto_fire = not auto_fire
	hud.notify("自动攻击：开启" if auto_fire else "自动攻击：关闭 · 按住鼠标左键攻击")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if event.alt_pressed and not event.ctrl_pressed and not event.meta_pressed and key>=KEY_1 and key<=KEY_5:
		use_flask("flask_%d"%(key-KEY_1+1))
		get_viewport().set_input_as_handled()
		return
	if hud.handle_menu_key(key, event.pressed, event.echo):
		get_viewport().set_input_as_handled()
		return
	if state.has_method("group_for_key"):
		var group_id: String = state.group_for_key(key)
		if not group_id.is_empty():
			cast_group(group_id)
			get_viewport().set_input_as_handled()
			return
	if key == KEY_F8:
		open_reference_catalog()
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
		return
	# Fixed world observations keep moving-target / return aiming consistent.
	_simulation_accumulator = minf(0.25, _simulation_accumulator + delta)
	while _simulation_accumulator >= 1.0 / 60.0 and alive:
		tick(1.0 / 60.0)
		_simulation_accumulator -= 1.0 / 60.0
	queue_redraw()


func tick(delta: float) -> void:
	# Display time continues after map completion; menus pause the tick entry.
	var feedback_step: Dictionary = feedback_runtime.advance(delta)
	assert(feedback_step.ok, "Validated feedback clock: " + str(feedback_step.reason))
	_burn_step_active=true;_burn_step_start=elapsed;_burn_immunity_until=elapsed+invulnerable
	_begin_progress_transaction()
	_tick(delta)
	_burn_step_active=false
	_end_progress_transaction()


func _tick(delta: float) -> void:
	if _world_mode=="town" or _world_mode=="map_complete":
		_move_player(delta)
		_update_effects(delta)
		return
	elapsed += delta
	var new_wave: int = int(_map_run.profile.wave) if _world_mode=="map" else 1 + int(elapsed / 30.0)
	if new_wave != wave:
		wave = new_wave
		if wave % 5 == 0 and not demo_mode:
			boss_wave_pending = wave
		hud.notify("第 %d 波来袭 · 敌人强度提升" % wave)
		_add_ring(ARENA.get_center(), 250.0, Color("d5b77a"), 0.8)
	group_cooldowns.advance(delta)
	for id: String in cooldowns:
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	var shield_recovery_time: float = maxf(0.0, delta - damage_delay)
	damage_delay = maxf(0.0, damage_delay - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	screen_shake = maxf(0.0, screen_shake - delta * 15.0)
	mana = minf(float(_stats.max_mana), mana + float(_stats.mana_regen) * delta)
	health = minf(float(_stats.max_health),health+float(_stats.get("life_regen",0.0))*delta)
	var flask_gain: Dictionary = flask_runtime.advance(delta,{"health":health,"mana":mana},{"health":float(_stats.max_health),"mana":float(_stats.max_mana)})
	health = minf(float(_stats.max_health),health+float(flask_gain.health))
	mana = minf(float(_stats.max_mana),mana+float(flask_gain.mana))
	_clear_full_leech()
	_advance_leech(delta)
	if damage_delay <= 0.0:
		shield = minf(float(_stats.max_shield), shield + float(_stats.get("shield_recharge_rate",_stats.shield_regen)) * shield_recovery_time)
	_move_player(delta)
	_update_spawning(delta)
	_update_enemies(delta)
	if not alive:
		return
	_update_auto_attack()
	_update_projectiles(delta)
	_advance_monster_burns(elapsed)
	_update_effects(delta)
	_update_pickups(delta)
	_start_enemy_telegraphs()
	if _world_mode=="map":_check_map_complete()
	_autosave_timer += delta
	if _autosave_timer >= 15.0:
		_autosave_timer = 0.0
		save_build()


func _move_player(delta: float) -> void:
	var before := player_pos
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if movement.length_squared() > 0.01:
		player_pos += movement * float(_stats.move_speed) * delta
		player_facing = movement.normalized()
		if rng.randf() < 0.4:
			_add_particle(player_pos + Vector2(0, 10), -movement * 20.0, Color("547a83"), 2.0, 0.25)
	player_pos = _clamp_to_arena(player_pos, PLAYER_RADIUS)
	if _geometry.has_walls(): player_pos = _geometry.move(before,player_pos,PLAYER_RADIUS,_camp_movement if _world_mode=="map" else null)
	elif _world_mode=="map":_camp_movement.append([before,player_pos])


func _clamp_to_arena(pos: Vector2, margin: float) -> Vector2:
	return Vector2(clampf(pos.x, ARENA.position.x + margin, ARENA.end.x - margin),
		clampf(pos.y, ARENA.position.y + margin, ARENA.end.y - margin))


func _update_spawning(delta: float) -> void:
	if _world_mode=="map":
		_update_map_spawning(delta)
		return
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
	if _world_mode in ["town","map","map_complete"]:return {}
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
		var elemental: String = Monsters.elemental_template_for_roll(wave, ordinary_admissions + 1, roll) if natural else ""
		if natural and _world_mode=="map":
			var special:String=MapCompiler.special_template(_map_run.profile,roll)
			if not special.is_empty():elemental=special
		enemy = _spawn_monster(roll.template if elemental.is_empty() else elemental, forced_position, "ordinary", roll.rarity, roll.mechanisms)
	if natural and not enemy.is_empty():
		ordinary_admissions += 1
		if _world_mode=="map" and not _map_run.register_root(enemy):_encounter_failed("地图根怪登记失败")
	if enemy.is_empty() and (not _encounter_ids.is_empty() or _world_mode=="map"):
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
	var previous_monster_id:int=monster_runtime.next_id
	if _world_mode=="map" and (MapDefense.active(_map_run.profile) or context=="map_boss"):
		var admitted:Dictionary=MapEnemyAdmission.create_root(monster_runtime,_map_run.profile,template_id,wave,pos,context,rarity,mechanisms,rewards and not demo_mode)
		if not admitted.ok:
			rng.state=random_before;_encounter_failed(str(admitted.error));return {}
		enemy=admitted.enemy
	elif _encounter_ids.is_empty():
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
		if _world_mode=="map":monster_runtime.next_id=previous_monster_id;rng.state=random_before
		return {}
	_apply_source_actor_profile(enemy)
	enemy.pos = _clamp_to_arena(enemy.pos, float(enemy.radius))
	if _geometry.has_walls(): enemy.pos = _geometry.legal_point(enemy.pos,float(enemy.radius))
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
	if _world_mode=="map" and MapDefense.active(_map_run.profile):
		var admitted:Dictionary=MapEnemyAdmission.drain(monster_runtime,_map_run.profile,MAX_ENEMIES-enemies.size(),ARENA)
		if not admitted.ok:_encounter_failed(str(admitted.error));return
		children.assign(admitted.enemies)
	elif _encounter_ids.is_empty():
		children = monster_runtime.drain(MAX_ENEMIES - enemies.size(), ARENA)
	else:
		var admitted: Dictionary = EncounterAdmission.drain(monster_runtime,_encounter_profile,MAX_ENEMIES - enemies.size(),ARENA)
		if not admitted.ok:
			_encounter_failed(str(admitted.error))
			return
		children.assign(admitted.enemies)
	for child: Dictionary in children:
		_apply_source_actor_profile(child)
		if _geometry.has_walls(): child.pos = _geometry.legal_point(child.pos,float(child.radius))
		enemies.append(child)
		_add_ring(child.pos, 26.0, Monsters.RARITIES[child.rarity].color, 0.45)
	monster_runtime.collect_lineages(enemies)


func _apply_source_actor_profile(enemy: Dictionary) -> void:
	if not state.has_method("passive_analysis"):return
	for stat:String in AttackHit.monster_profile(int(enemy.kind)):
		if not enemy.has(stat):enemy[stat]=AttackHit.monster_profile(int(enemy.kind))[stat]


func start_monster_demo() -> void:
	if _world_mode!="normal":
		hud.notify("旧试验入口仅在正常游戏可用；请先离开城镇测试")
		return
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
	if _world_mode!="normal":
		hud.notify("旧试验入口仅在正常游戏可用；请先离开城镇测试")
		return
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
	if _world_mode!="normal":
		hud.notify("旧试验入口仅在正常游戏可用；请先离开城镇测试")
		return
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
	if _world_mode!="normal":
		hud.notify("旧试验入口仅在正常游戏可用；请先离开城镇测试")
		return
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
	if _world_mode!="normal":return false
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
	if _world_mode=="map":
		var map_error:String=MapCompiler.profile_reason(_map_run.profile)
		if not map_error.is_empty():_encounter_failed(map_error);return false
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
	_advance_player_burn(elapsed)
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
			enemy.shield = minf(float(enemy.get("max_shield", 0.0)), float(enemy.get("shield", 0.0)) + float(enemy.get("shield_recharge_rate",enemy.get("shield_regen",0.0))) * shield_recovery_time)
		enemy.attack_timer = maxf(0.0, float(enemy.attack_timer) - delta)
		enemy.flash = maxf(0.0, float(enemy.flash) - delta)
		enemy.slow = maxf(0.0, float(enemy.slow) - delta)
		enemy.spawn = maxf(0.0, float(enemy.spawn) - delta)
		if float(enemy.spawn) > 0.0:
			continue
		var uses_telegraph: bool = Monsters.uses_telegraph(enemy)
		var performing: bool = not telegraphs.state_for(int(enemy.id)).is_empty()
		var speed: float = float(enemy.speed) * (0.36 if float(enemy.slow) > 0 else 1.0)
		var direction: Vector2 = Vector2.ZERO if performing else (player_pos - Vector2(enemy.pos)).normalized()
		if not performing and _geometry.has_walls(): direction = _geometry.direction(enemy.pos,player_pos,float(enemy.radius),speed*delta)
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
		var previous: Vector2 = enemy.pos
		enemy.pos = Vector2(enemy.pos) + (direction * speed + separation + Vector2(enemy.knockback)) * delta
		enemy.pos = _clamp_to_arena(Vector2(enemy.pos), float(enemy.radius))
		if _geometry.has_walls(): enemy.pos = _geometry.move(previous,enemy.pos,float(enemy.radius))
		if use_spatial_separation:
			enemy_spatial.update(enemy_index)
		enemy.knockback = Vector2(enemy.knockback).move_toward(Vector2.ZERO, 520.0 * delta)
		if not uses_telegraph and Vector2(enemy.pos).distance_to(player_pos) < PLAYER_RADIUS + float(enemy.radius) + 1.0 and _terrain_visible(enemy.pos,player_pos):
			if float(enemy.attack_timer) <= 0.0:
				enemy.attack_timer = 1.0 / maxf(0.2, float(enemy.get("attack_speed", 1.0 / 0.85)))
				hit_player_components(Monsters.contact_components(enemy), int(enemy.id), ["hit","attack","melee"])
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
		if not _terrain_visible(enemy.pos,player_pos): continue
		var target_center:Vector2=enemy.pos if policy.get("target_rule","")=="self_at_start" else player_pos
		var result: Dictionary = telegraphs.start(enemy,target_center,policy.profile,policy.get("visual_pattern",""))
		if result.ok:
			event_counts["enemy_telegraph_started"] = int(event_counts.get("enemy_telegraph_started", 0)) + 1


func _advance_enemy_telegraphs(delta: float) -> void:
	var sequence_batch:bool=telegraphs.has_timed_sequence_actions()
	var events: Array[Dictionary] = telegraphs.advance(delta, enemies,sequence_batch or not burn_runtime.is_empty() or telegraphs.has_burning_actions())
	for event: Dictionary in events:
		if not alive:
			telegraphs.reset()
			break
		var event_time:float=_burn_event_time(event.get("step_time",delta))
		_advance_player_burn(event_time)
		if not alive:telegraphs.reset();break
		var inside: bool = TelegraphRuntime.overlaps(event, player_pos, PLAYER_RADIUS) and _terrain_visible(event.center,player_pos)
		if sequence_batch:invulnerable=maxf(0.0,_burn_immunity_until-event_time)
		_burn_incoming_time=event_time
		var hit_context:Dictionary={}
		if event.has("shock_policy"):
			hit_context={"shock_policy":event.shock_policy,"at":event_time,"cast_id":int(event.attack_id),"skill_id":"storm_shock","phase":"telegraph"}
		var applied: bool = hit_player_components(event.packet.base, int(event.source_id),event.packet.tags,hit_context) if inside else false
		_burn_incoming_time=-1.0
		if sequence_batch:invulnerable=maxf(0.0,_burn_immunity_until-elapsed)
		if applied and alive and event.has("burn_policy"):
			var burn:Dictionary=BurnRules.from_fire_hit(float(event.packet.base.get("fire",0.0)),event.burn_policy)
			if burn.ok:
				var attached:Dictionary=burn_runtime.apply("player",0,int(event.source_id),burn.raw_dps,burn.duration,event_time,{"skill_id":"ember_burn","cast_id":int(event.attack_id),"phase":"telegraph"})
				_assert_burn_result(attached)
				_settle_burn_segments(attached.segments)
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
			# Derive presentation only from the already frozen packet, never live stats.
			var components: Dictionary = copied.get("packet", {}).get("base", {})
			if components.size() == 1:
				if components.has("cold"): copied["visual_element"] = "cold"
				elif components.has("lightning"): copied["visual_element"] = "lightning"
			snapshots.append(copied)
	return snapshots


func _nearest_enemy(from: Vector2, max_distance: float = 800.0, excluded: Array[int] = []) -> Dictionary:
	var best: Dictionary = {}
	var distance_sq: float = max_distance * max_distance
	for enemy: Dictionary in enemies:
		if float(enemy.health) <= 0.0 or excluded.has(int(enemy.id)) or float(enemy.spawn) > 0.0:
			continue
		if not _terrain_visible(from,enemy.pos): continue
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
	if not manual and not auto_fire: return
	var delivery: Dictionary = state.get_basic_attack_profile() if state.has_method("get_basic_attack_profile") else {}
	if delivery.get("delivery", "") == "melee":
		_update_basic_melee(delivery, manual)
		return
	if not manual and (not auto_fire or _nearest_enemy(player_pos).is_empty()):
		return
	player_facing = _aim_direction()
	var basic:Dictionary=state.get_basic_cast() if state.has_method("get_basic_cast") else Build.Compiler.compile_basic(state.get_combat_snapshot())
	if not basic.ok:
		return
	if _shoot(player_pos, player_facing, basic.packets.projectile, Color("75e5df"), 0, 0, float(basic.recipe.speed), {"snapshot": basic.snapshot}):
		attack_timer = 1.0 / maxf(0.2, float(_stats.attack_speed))


## Automatic melee turns toward the nearest body in actual reach. Manual
## swings keep mouse-facing and select only one body in that sector. Equal
## distances preserve the existing enemies-array order, as _nearest_enemy does.
func _nearest_basic_melee_target(profile: Dictionary, facing: Vector2, automatic: bool) -> Dictionary:
	var best: Dictionary = {}
	var distance_sq: float = INF
	for enemy: Dictionary in enemies:
		if float(enemy.health) <= 0.0 or float(enemy.spawn) > 0.0: continue
		var offset: Vector2 = Vector2(enemy.pos) - player_pos
		var direction: Vector2 = facing
		if automatic and not offset.is_zero_approx(): direction = offset.normalized()
		if direction.is_zero_approx(): direction = Vector2.RIGHT
		if not AreaRules.contains_sector_target(player_pos, direction, Vector2(enemy.pos), float(profile.radius), float(profile.half_angle), float(enemy.radius)): continue
		if not _terrain_visible(player_pos, enemy.pos): continue
		var candidate: float = offset.length_squared()
		if candidate < distance_sq:
			distance_sq = candidate
			best = enemy
	return best


func _update_basic_melee(profile: Dictionary, manual: bool) -> void:
	if not alive or not _ready_complete or _world_mode in ["town", "map_complete"] or hud.is_blocking(): return
	var direction: Vector2 = _aim_direction() if manual else player_facing
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	var target: Dictionary = _nearest_basic_melee_target(profile, direction, not manual)
	if not manual and target.is_empty(): return
	if not manual:
		var offset: Vector2 = Vector2(target.pos) - player_pos
		if not offset.is_zero_approx(): direction = offset.normalized()
	var basic: Dictionary = state.get_basic_cast()
	if not basic.get("ok", false) or basic.recipe.get("delivery", "") != "melee": return
	var critical: Dictionary = critical_runtime.freeze(basic.snapshot)
	if not critical.ok: return
	var cast_id: int = projectile_runtime.new_cast()
	player_facing = direction
	# Freeze the current attack interval before a kill can grant level-up stats.
	attack_timer = 1.0 / maxf(0.2, float(_stats.attack_speed))
	if not target.is_empty():
		_apply_damage_packet(target, basic.packets.direct, critical.snapshot, Color("d3c3a2"), 0.0, {"cast_id":cast_id})
	visual_cues.emit_cue("cleave", player_pos, {"radius":float(basic.recipe.radius), "half_angle":float(basic.recipe.half_angle), "direction":direction, "color":Color("d3c3a2"), "skill":"basic"})


func _shoot(origin: Vector2, direction: Vector2, packet: Dictionary, color: Color,
		pierce: int = 0, slow: float = 0.0, speed: float = 600.0, context: Dictionary = {}) -> bool:
	if projectiles.size() >= MAX_PROJECTILES or packet.is_empty():
		return false
	var snapshot: Dictionary = context["snapshot"] if context.has("snapshot") else state.get_combat_snapshot()
	if not snapshot.has("critical_roll"):
		var critical:Dictionary=critical_runtime.freeze(snapshot)
		if not critical.ok:return false
		snapshot=critical.snapshot
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


func cast_group(group_id: String) -> bool:
	if _world_mode in ["town","map_complete"]:return false
	if _group_cast_busy or not state.has_method("get_group_cast"):
		return false
	_group_cast_busy = true
	_begin_progress_transaction()
	var compiled: Dictionary = state.get_group_cast(group_id)
	var accepted: bool = _execute_compiled(compiled, group_id, str(compiled.get("main_uid", "")))
	_end_progress_transaction()
	_group_cast_busy = false
	return accepted


func group_cooldown_remaining(group_id: String) -> float:
	if not state.has_method("skill_group"): return 0.0
	return group_cooldowns.remaining(group_id, state.skill_group(group_id).main_uid)


func _cast_skill(index: int) -> bool:
	if index < 0 or index >= 5: return false
	if state.has_method("group_for_key"):
		var group_id: String = state.group_for_key(KEY_1 + index)
		return cast_group(group_id) if not group_id.is_empty() else false
	if index < 0 or index >= state.skill_slots.size(): return false
	var id: String = state.skill_slots[index]
	if not Data.SKILLS.has(id): return false
	return _execute_compiled(state.get_skill_cast(id))


func _execute_compiled(compiled: Dictionary, group_id: String = "", main_uid: String = "") -> bool:
	if _world_mode in ["town","map_complete"]:return false
	if not alive or not _ready_complete or hud.is_blocking(): return false
	if not compiled.get("ok", false):
		hud.notify("技能辅助配置无效：" + str(compiled.get("error", "未知配置")))
		return false
	var id: String = str(compiled.skill_id)
	if not Data.SKILLS.has(id): return false
	var skill: Dictionary = Data.SKILLS[id]
	var mana_cost: float = float(compiled.mana)
	var remaining: float = group_cooldowns.remaining(group_id, main_uid) if not group_id.is_empty() else float(cooldowns.get(id, 0.0))
	if remaining > 0.0:
		hud.notify("%s 冷却中" % skill.name)
		return false
	if mana < mana_cost:
		hud.notify("魔力不足 · 等待恢复或拾取补给")
		return false
	var volley_size: int = int(compiled.initial_count)
	if volley_size > 0 and projectiles.size() + volley_size > MAX_PROJECTILES:
		hud.notify("投射物空间不足以发射完整技能，本次未消耗法力或冷却")
		return false
	var critical_checkpoint:Dictionary=critical_runtime.checkpoint()
	var critical:Dictionary=critical_runtime.freeze(compiled.snapshot)
	if not critical.ok:return false
	mana -= mana_cost
	if group_id.is_empty(): cooldowns[id] = float(compiled.cooldown)
	player_facing = _aim_direction()
	var color: Color = skill.color
	var context: Dictionary = {"snapshot": critical.snapshot, "cast_id": 0 if id == "tornado" else projectile_runtime.new_cast()}
	match id:
		"tornado":
			var emitted: int = projectile_runtime.spawn_tornado(projectiles, player_pos, player_facing, context.snapshot, MAX_PROJECTILES, int(compiled.initial_count))
			if emitted == 0:
				critical_runtime.restore(critical_checkpoint)
				mana += mana_cost
				_clear_full_leech()
				if group_id.is_empty(): cooldowns[id] = 0.0
				hud.notify("场上投射物已满，本次龙卷未消耗法力或冷却")
				return false
			total_shots += emitted
		"bolt", "frost", "shade_bolt":
			var recipe: Dictionary = compiled.recipe
			for shot_index: int in range(int(compiled.initial_count)):
				var angle: float = (shot_index - (int(compiled.initial_count) - 1) * 0.5) * float(recipe.spread)
				_shoot(player_pos, player_facing.rotated(angle), compiled.packets.projectile, color,
					int(recipe.pierce), float(recipe.slow), float(recipe.speed), context)
		"cleave":
			# Damage admission, direction and geometry are frozen once for this cast.
			for enemy: Dictionary in enemies:
				if float(enemy.health)>0.0 and float(enemy.spawn)<=0.0 and AreaRules.contains_sector_target(player_pos,player_facing,Vector2(enemy.pos),float(compiled.recipe.radius),float(compiled.recipe.half_angle),float(enemy.radius)) and _terrain_visible(player_pos,enemy.pos):
					_apply_damage_packet(enemy,compiled.packets.direct,context.snapshot,color,0.0,{"cast_id":context.cast_id})
			visual_cues.emit_cue("cleave",player_pos,{"radius":float(compiled.recipe.radius),"half_angle":float(compiled.recipe.half_angle),"direction":player_facing,"color":color})
		"nova":
			_area_damage(player_pos, float(compiled.recipe.radius), compiled.packets.direct, color, 0.6, context.snapshot)
			visual_cues.emit_cue("nova", player_pos, {"radius": float(compiled.recipe.radius), "color": color})
		"dash":
			var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if direction.length_squared() < 0.1:
				direction = player_facing
			var start: Vector2 = player_pos
			player_pos = _clamp_to_arena(player_pos + direction * 175.0, PLAYER_RADIUS)
			if _geometry.has_walls(): player_pos = _geometry.move(start,player_pos,PLAYER_RADIUS,_camp_movement if _world_mode=="map" else null)
			elif _world_mode=="map":_camp_movement.append([start,player_pos])
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
			if _geometry.has_walls() and target.is_empty():
				var terrain: Dictionary = _geometry.sweep(player_pos,target_pos)
				if terrain.hit: target_pos = Vector2(terrain.point)+Vector2(terrain.normal)*Geometry.SKIN
			_area_damage(target_pos, float(compiled.recipe.radius), compiled.packets.direct, color, 0.0, context.snapshot)
			visual_cues.emit_cue("meteor", target_pos, {"radius": float(compiled.recipe.radius), "color": color})
			for i: int in range(32):
				_add_particle(target_pos, Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(70, 270), color, rng.randf_range(3, 7), 0.6)
			screen_shake = 4.0
		"chain":
			var origin: Vector2 = player_pos
			var excluded: Array[int] = []
			for i: int in range(compiled.packets.bounces.size()):
				var target: Dictionary = _nearest_enemy(origin, float(compiled.recipe.first_range) if i == 0 else float(compiled.recipe.followup_range), excluded)
				if target.is_empty():
					break
				excluded.append(int(target.id))
				var end: Vector2 = target.pos
				visual_cues.emit_cue("chain", origin, {"destination": end, "target_id": int(target.id), "color": color})
				for step: int in range(12):
					_add_particle(origin.lerp(end, step / 12.0) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)), Vector2.ZERO, color, 3.0, 0.25)
				_apply_damage_packet(target, compiled.packets.bounces[i], context.snapshot, color, 0.35, {"cast_id": context.cast_id})
				origin = end
	if not group_id.is_empty() and alive:
		var began: bool = group_cooldowns.begin(group_id, main_uid, float(compiled.cooldown))
		assert(began, "Admitted group cast must own a ready cooldown")
	if id in ["tornado", "bolt", "frost", "shade_bolt"]:
		visual_cues.emit_cue("cast", player_pos, {"direction": player_facing, "skill": id, "color": color})
	return true


func _area_damage(origin: Vector2, radius: float, packet: Dictionary, color: Color, slow: float,
		snapshot: Dictionary = {}) -> void:
	if packet.is_empty():
		return
	var cast_snapshot: Dictionary = state.get_combat_snapshot() if snapshot.is_empty() else snapshot
	for enemy: Dictionary in enemies:
		if float(enemy.health) > 0.0 and float(enemy.spawn) <= 0.0 and AreaRules.contains_target(origin, Vector2(enemy.pos), radius, float(enemy.radius)) and _terrain_visible(origin,enemy.pos):
			_apply_damage_packet(enemy, packet, cast_snapshot, color, slow)
			var direction: Vector2 = (Vector2(enemy.pos) - origin).normalized()
			enemy.knockback = direction * 190.0


func _update_projectiles(delta: float) -> void:
	_ember_projectile_clock.clear()
	_projectile_targets.clear()
	for enemy: Dictionary in enemies: _projectile_targets[int(enemy.id)] = enemy
	var terrain_query: Callable = _geometry.sweep if _geometry.has_walls() else Callable()
	var events: Array[Dictionary] = projectile_runtime.advance(projectiles, delta, enemies, player_pos, MAX_PROJECTILES, _projectile_contact_admitted, terrain_query)
	var settled:bool=_settle_projectile_events(events,delta)
	assert(settled,"Projectile batch must fit the retained shock event window")


func _settle_projectile_events(events:Array[Dictionary],original_delta:float=0.0)->bool:
	var ember_batch:bool=burn_runtime.has_ember_states()
	var shock_batch:bool=not shock_runtime.is_empty()
	if not ember_batch or not shock_batch:
		for event:Dictionary in events:
			if event.get("snapshot",{}).has("burn_proliferation"):
				ember_batch=true
			if event.get("snapshot",{}).has("shock_policy"):shock_batch=true
			if ember_batch and shock_batch:break
	# Validate the complete original batch before the first hit, admission,
	# critical roll, feedback, death or reward. Production ticks are 1/60 s;
	# ordered larger batches remain valid if their raw tie rewind fits one
	# shortest policy interval. No cumulative elapsed-time tolerance is used.
	if shock_batch:
		var start:float=_burn_step_start if _burn_step_active else elapsed
		var reason:String=ShockRules.projectile_batch_error(events,start,elapsed,shock_runtime.read_floor(),original_delta)
		if not reason.is_empty():return false
	var offsets:Array=[]
	if ember_batch:
		var prepared:Dictionary=EmberClock.offsets(events)
		assert(prepared.ok,"Validated original projectile event tie chains: "+str(prepared.reason))
		if not prepared.ok:return false
		offsets=prepared.offsets
	var event_index:int=0
	for event: Dictionary in events:
		if ember_batch:_ember_projectile_clock={"sequence":event.sequence,"raw":float(event.time),"offset":float(offsets[event_index])}
		event_index+=1
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
			# One independent roll per actual secondary event, shared by its AoE.
			var secondary:Dictionary=critical_runtime.freeze(event.snapshot,"secondary")
			if not secondary.ok:continue
			var hit_targets: Dictionary = {}
			for enemy: Dictionary in enemies:
				if not hit_targets.has(enemy.id) and float(enemy.health) > 0.0 and Vector2(event.pos).distance_to(enemy.pos) <= float(event.radius) + float(enemy.radius) and _terrain_visible(event.pos,enemy.pos):
					hit_targets[enemy.id] = true
					_apply_damage_packet(enemy, event.payload, secondary.snapshot, event.color, 0.0, event)
			visual_cues.emit_cue("explosion", event.pos, {"radius": float(event.radius), "color": event.color})
		elif event.type == "return_started":
			visual_cues.emit_cue("return", event.pos, {"radius": 19.0, "color": Color("bd98ff")})
		elif event.type == "split":
			visual_cues.emit_cue("split", event.pos, {"radius": 26.0, "color": Color("a6e8aa")})
		elif event.type == "spawn_rejected":
			hud.notify("投射物容量不足，本次三子箭整组取消；未触发爆炸")
	_ember_projectile_clock.clear()
	_flush_monster_spawns()
	return true


func _apply_damage_packet(enemy: Dictionary, packet: Dictionary, snapshot: Dictionary, color: Color,
		slow: float = 0.0, provenance: Dictionary = {}) -> void:
	if snapshot.has("resolute_technique") and not Resolute.snapshot_error(snapshot).is_empty(): return
	var burn_at:float=_burn_event_time(float(provenance.time)) if provenance.has("time") else elapsed
	# Shock queries the raw event instant, never the later normalized burn clock.
	# An approximate-sort tie cannot make an earlier hit use a future status.
	var shock_at:float=burn_at
	if (not shock_runtime.is_empty() or snapshot.has("shock_policy")) and shock_at<shock_runtime.read_floor():return
	if snapshot.has("shock_policy") and not ShockRules.policy_error(snapshot.shock_policy).is_empty():return
	var ember_hit:bool=snapshot.has("burn_proliferation") and packet.get("role","") in ["direct","parent","child"] and packet.skill_id in ["meteor","tornado"]
	if burn_runtime.has_ember_states() or ember_hit:
		burn_at=_ember_event_time(burn_at,provenance)
	if not burn_runtime.is_empty():
		var previous:float=burn_runtime.last_time_for("monster",int(enemy.id))
		# The existing projectile scheduler treats near-equal relative times as
		# one instant ordered by identity. Preserve that established hit order;
		# only its tied burn applications share the latest processed timestamp.
		if _burn_step_active and provenance.has("time") and previous>burn_at and previous<=elapsed and is_equal_approx(float(provenance.time),previous-_burn_step_start):burn_at=previous
		if ember_hit:_advance_proliferating_burns(burn_at)
		else:_advance_monster_burn(enemy,burn_at)
	if float(enemy.health) <= 0.0 or float(enemy.get("spawn", 0.0)) > 0.0:
		return
	if not provenance.get("accuracy_checked",false) and not _attack_admitted(enemy,packet,snapshot): return
	var critical:Dictionary=snapshot.get("critical_roll",{})
	# Read only this hit's frozen policy, never the currently equipped build.
	if snapshot.has("resolute_technique") and Resolute.active(snapshot): critical={}
	var result: Dictionary = Damage.resolve(packet, snapshot.get("modifiers", []), enemy.get("resistances", {}),float(critical.get("multiplier",1.0)))
	result = Defense.apply_armour(result,float(enemy.get("armour",0.0)))
	var shock_increase:float=_shock_hit_increase("monster",int(enemy.id),shock_at)
	if shock_increase>0.0:result=Defense.apply_hit_damage_taken(result,shock_increase)
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
	if not critical.is_empty():record.critical=critical.duplicate(true)
	if shock_increase>0.0:record.shock={"hit_damage_taken_increased":shock_increase,"at":shock_at}
	if snapshot.has("leech"):
		var admitted: Dictionary = leech_runtime.admit(packet, snapshot, settlement,
			{"health": health, "mana": mana}, {"health": float(_stats.max_health), "mana": float(_stats.max_mana)})
		if admitted.ok and (float(admitted.health) > 0.0 or float(admitted.mana) > 0.0):
			record.leech = {"health": admitted.health, "mana": admitted.mana}
	damage_trace.append(record)
	if damage_trace.size() > 32:
		damage_trace.pop_front()
	_apply_enemy_settlement(enemy, settlement, color, slow, bool(critical.get("critical", false)), burn_at)
	if float(enemy.health)>0.0 and snapshot.has("burn_policy") and packet.get("role","") in ["direct","parent","child"] and packet.skill_id in ["meteor","tornado"]:
		var fire:float=float(settlement.raw_components.get("fire",0.0))
		if fire>0.0 and float(settlement.components.get("fire",0.0))>0.0:
			var burn:Dictionary=BurnRules.from_fire_hit(fire,snapshot.burn_policy,snapshot.get("fire_dot_multiplier",0.0),snapshot.get("burn_faster",0.0))
			if burn.ok:
				var burn_origin:Dictionary={"skill_id":str(packet.skill_id),"cast_id":int(provenance.get("cast_id",0)),"projectile_id":int(provenance.get("projectile_id",0)),"phase":str(provenance.get("phase","direct"))}
				if snapshot.has("burn_proliferation"):
					burn_origin["ember_generation"]=0;burn_origin["ember_expiry"]=burn_at+float(burn.duration)
				var attached:Dictionary=burn_runtime.apply("monster",int(enemy.id),0,burn.raw_dps,burn.duration,burn_at,burn_origin)
				_assert_burn_result(attached)
				_settle_burn_segments(attached.segments)
	if float(enemy.health)>0.0 and snapshot.has("shock_policy") and packet.get("role","") in ["direct","projectile","bounce"] and packet.skill_id in ["bolt","nova","chain"] and packet.tags.has("hit"):
		var origin:Dictionary={"skill_id":str(packet.skill_id),"cast_id":int(provenance.get("cast_id",0)),"projectile_id":int(provenance.get("projectile_id",0)),"phase":str(provenance.get("phase","direct"))}
		var attached:Dictionary=_attach_shock("monster",int(enemy.id),0,shock_at,snapshot.shock_policy,settlement,origin)
		if attached.get("applied",false):record.shock_applied={"at":shock_at,"duration":float(snapshot.shock_policy.duration)}


func _projectile_contact_admitted(shot: Dictionary,target_id: int) -> bool:
	if not _projectile_targets.has(target_id): return false
	return _attack_admitted(_projectile_targets[target_id],shot.payload,shot.snapshot)


func _attack_admitted(enemy: Dictionary,packet: Dictionary,snapshot: Dictionary) -> bool:
	if snapshot.has("resolute_technique") and not Resolute.snapshot_error(snapshot).is_empty(): return false
	var unerring: bool = snapshot.has("resolute_technique") and Resolute.active(snapshot)
	if not packet.get("tags",[]).has("attack") or (not snapshot.has("accuracy") and not unerring): return true
	var result: Dictionary
	if unerring:
		result=AttackHit.resolve(float(snapshot.get("accuracy",0.0)),float(enemy.get("evasion",0.0)),float(enemy.get("evasion_entropy",50.0)),true)
	else:
		result=AttackHit.resolve(float(snapshot.accuracy),float(enemy.get("evasion",0.0)),float(enemy.get("evasion_entropy",50.0)))
	if not result.ok: return false
	enemy.evasion_entropy = result.entropy
	_record_attack_admission("monster",int(enemy.id),result)
	return bool(result.hit)


func _record_attack_admission(actor: String,target_id: int,result: Dictionary) -> void:
	attack_admission_trace.append({"actor":actor,"target_id":target_id,"hit":result.hit,"chance":result.chance})
	if attack_admission_trace.size() > 32: attack_admission_trace.pop_front()


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
	if burn_runtime.has_ember_states():_advance_proliferating_burns(elapsed)
	if float(enemy.health) <= 0.0 or amount <= 0.0 or not is_finite(amount):
		return
	# Compatibility helper receives damage already resolved by its caller.
	var settlement: Dictionary = Defense.incoming_hit({"physical": amount}, {}, float(enemy.get("shield", 0.0)), float(enemy.health), "monster",_shock_hit_increase("monster",int(enemy.id),elapsed))
	if settlement.ok:
		_apply_enemy_settlement(enemy, settlement, color, slow)


func _apply_enemy_settlement(enemy: Dictionary, settlement: Dictionary, color: Color, slow: float = 0.0, critical: bool = false, at: float = -1.0) -> void:
	var amount: float = float(settlement.damage_total)
	if not _apply_enemy_resources(enemy,settlement):return
	var absorbed: float = float(settlement.shield_spent)
	visual_cues.emit_cue("impact", Vector2(enemy.pos), {"radius": clampf(7.0 + sqrt(amount) * 0.65, 8.0, 24.0), "color": color, "shielded": absorbed >= amount, "target_id": int(enemy.id)})
	enemy.flash = 0.12
	enemy.slow = maxf(float(enemy.slow), slow)
	# Preserve the original draw at exactly its old event position, even when
	# number display is disabled or a presentation queue is full.
	var _legacy_text_position := Vector2(enemy.pos) + Vector2(rng.randf_range(-8, 8), -18)
	_record_damage_feedback("monster", int(enemy.id), "critical" if critical else "hit", settlement, Vector2(enemy.pos))
	for i: int in range(4):
		_add_particle(Vector2(enemy.pos), Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(40, 130), color, 2.3, 0.3)
	_finish_enemy_death(enemy,true,at)


func _apply_enemy_resources(enemy:Dictionary,settlement:Dictionary)->bool:
	var amount:float=float(settlement.damage_total)
	if float(enemy.health)<=0.0 or amount<=0.0:return false
	enemy.shield=float(settlement.remaining_shield)
	enemy.damage_delay=float(enemy.get("shield_recharge_delay",Defense.RECHARGE_BASE_DELAY))
	enemy.health=float(settlement.remaining_health)-float(settlement.overkill)
	total_damage+=amount
	return true


func _finish_enemy_death(enemy:Dictionary,legacy_particles:bool=true,at:float=-1.0,source_burn:Dictionary={})->void:
	if float(enemy.health)>0.0:return
	if not shock_runtime.is_empty():shock_runtime.remove("monster",int(enemy.id))
	var ember_source:Dictionary=burn_runtime.status_for("monster",int(enemy.id)) if source_burn.is_empty() else source_burn
	feedback_runtime.flush_target("monster", int(enemy.id))
	if not burn_runtime.is_empty():burn_runtime.remove("monster",int(enemy.id))
	telegraphs.cancel(int(enemy.id))
	var death: Dictionary = monster_runtime.process_death(enemy)
	if not death.processed:
		return
	if not ember_source.is_empty() and ember_source.provenance.get("ember_generation",-1)==0:
		_ember_deaths.append({"id":int(enemy.id),"origin":Vector2(enemy.pos),"at":elapsed if at<0.0 else at,"status":ember_source.duplicate(true)})
	visual_cues.emit_cue("death", Vector2(enemy.pos), {"radius": float(enemy.radius), "color": Monsters.RARITIES[enemy.rarity].color, "target_id": int(enemy.id)})
	kills += 1
	var eligible: bool = bool(death.reward) and not demo_mode
	if _world_mode=="map" and eligible and _map_run.record_death(enemy):world_context_changed.emit()
	if eligible:
		reward_kills += 1
		_sync_flasks()
		var equipped_flasks: Array=[]
		if state.has_method("flask_slots"):
			for slot:Dictionary in state.flask_slots():
				if not slot.uid.is_empty():equipped_flasks.append(slot.uid)
		flask_runtime.charge_rewarded_kill(equipped_flasks,_stats)
	var leveled: bool = false
	if eligible:
		leveled = state.add_xp(int(enemy.get("xp_reward", 0))) if _is_test_profile() else state.add_normal_root_xp(int(enemy.get("xp_reward", 0)))
	if leveled:
		health = minf(float(_stats.max_health), health + 25.0)
		mana = float(_stats.max_mana)
		_clear_full_leech()
		hud.notify("升级！获得 1 点天赋 · 按 T 分配")
		_add_ring(player_pos, 80.0, Color("e7c98d"), 0.7)
		_add_text(player_pos + Vector2(0, -46), "LEVEL UP", Color("e7c98d"))
	if eligible and (reward_kills % 8 == 0 or enemy.get("rarity", "") in ["rare", "boss"]):
		_award_kill_equipment(enemy)
	if eligible and reward_kills % 20 == 0:
		_award_kill_jewel()
	if eligible and _is_test_profile() and reward_kills % 30 == 0 and state.has_method("award_random_gem"):
		var gem_uid:String=state.award_random_gem(rng)
		hud.notify("获得宝石："+str(state.item_definition(gem_uid).name)+" · 按 K 装配" if not gem_uid.is_empty() else "背包空间不足，无法领取宝石；可在 I 中整理或丢弃重复宝石")
	if eligible and _is_test_profile() and reward_kills % FlaskCatalog.REWARD_INTERVAL == 0 and state.has_method("award_flask"):
		var flask_uid: String = state.award_flask(FlaskCatalog.reward_definition(reward_kills))
		hud.notify("获得药剂："+str(state.item_definition(flask_uid).name) if not flask_uid.is_empty() else "背包空间不足，未领取药剂；已有物品保留")
	if eligible and not _is_test_profile() and int(state.normal_journey().normal_root_kills) % 30 == 0:
		var milestone: Dictionary = state.normal_claim_rewards(state.revision(), build_save_path, false)
		if milestone.ok: hud.notify("正式击杀里程碑：获得宝石 %d、药剂 %d" % [milestone.claimed_gems, milestone.claimed_flasks])
		else: hud.notify("里程碑奖励仍待领取，返回正式城镇整理后领取")
		_world_revision += 1; world_context_changed.emit()
	if eligible and enemy.get("rarity", "") == "boss":
		_award_kill_special_jewel()
	if eligible and reward_kills % 4 == 0:
		pickups.append({"pos": Vector2(enemy.pos), "life": 22.0})
	if legacy_particles:
		for i: int in range(8):
			_add_particle(Vector2(enemy.pos), Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(35, 120), Color("ce8070"), 3.0, 0.45)
	if not _ember_defer_deaths:_flush_ember_deaths()


func _award_kill_equipment(enemy: Dictionary) -> void:
	# Exactly one decision per eligible root death. Descendants/demo never enter here.
	var rarity: String = "rare" if enemy.get("rarity", "") in ["rare", "boss"] else ""
	var item_level: int = clampi(wave * 2 - 1, 1, 30)
	var pool: String = str(enemy.get("equipment_pool", ""))
	# A live encounter requests today's defense supply. Explicit historical
	# catalog/model pool calls retain the immutable original defense sequence.
	if pool == "defense": pool = Gear.CURRENT_DEFENSE_POOL_ID
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
	if _stats.has("armour"): return Defense.source_profile(_stats,"player")
	return Defense.defense_profile({"fire_resistance": _stats.get("fire_resistance", 0.0)}, "player")


func hit_player_components(components: Variant, source_id: int = 0, delivery_tags: Array = [], hit_context:Dictionary={}) -> bool:
	if not alive or invulnerable > 0.0:
		return false
	var at:float=float(hit_context.get("at",_burn_incoming_time if _burn_incoming_time>=0.0 else elapsed))
	if not is_finite(at) or at<shock_runtime.read_floor():return false
	if hit_context.has("shock_policy") and not ShockRules.policy_error(hit_context.shock_policy).is_empty():return false
	var shock_increase:float=_shock_hit_increase("player",0,at)
	var mana_ratio:Variant=_stats.get("damage_taken_from_mana_before_life",0.0)
	var settlement: Dictionary
	if typeof(mana_ratio) not in [TYPE_INT,TYPE_FLOAT] or float(mana_ratio)!=0.0:
		settlement=Defense.incoming_source_hit(components,_stats,shield,health,"player",shock_increase,mana,mana_ratio) if _stats.has("armour") else Defense.incoming_hit(components,{"fire_resistance":_stats.get("fire_resistance",0.0)},shield,health,"player",shock_increase,mana,mana_ratio)
	else:
		settlement=Defense.incoming_source_hit(components,_stats,shield,health,"player",shock_increase) if _stats.has("armour") else Defense.incoming_hit(components, {"fire_resistance": _stats.get("fire_resistance", 0.0)}, shield, health, "player",shock_increase)
	if not settlement.ok or float(settlement.damage_total) <= 0.0:
		return false
	if delivery_tags.has("attack") and _stats.has("evasion"):
		var accuracy := 100.0
		for enemy: Dictionary in enemies:
			if int(enemy.id) == source_id:
				accuracy = float(enemy.get("accuracy",100.0))
				break
		var admission := AttackHit.resolve(accuracy,float(_stats.evasion),_player_evasion_entropy)
		if not admission.ok: return false
		_player_evasion_entropy = admission.entropy
		_record_attack_admission("player",source_id,admission)
		if not admission.hit: return false
	var amount: float = float(settlement.damage_total)
	var absorbed: float = float(settlement.shield_spent)
	if settlement.has("remaining_mana"):mana=float(settlement.remaining_mana)
	shield = float(settlement.remaining_shield)
	health = float(settlement.remaining_health)
	var record: Dictionary = settlement.duplicate(true)
	record["source_id"] = source_id
	if shock_increase>0.0:record.shock={"hit_damage_taken_increased":shock_increase,"at":at}
	incoming_damage_trace.append(record)
	if incoming_damage_trace.size() > 32:
		incoming_damage_trace.pop_front()
	visual_cues.emit_cue("hurt", player_pos, {"shielded": absorbed >= amount})
	damage_delay = float(_stats.get("shield_recharge_delay",Defense.RECHARGE_BASE_DELAY))
	invulnerable = 0.32
	_burn_immunity_until=(_burn_incoming_time if _burn_incoming_time>=0.0 else elapsed)+0.32
	hurt_flash = 0.16
	screen_shake = 2.5
	_record_damage_feedback("player", 0, "hit", settlement, player_pos)
	if health>0.0 and hit_context.has("shock_policy") and delivery_tags.has("hit"):
		var origin:Dictionary={"skill_id":str(hit_context.get("skill_id","storm_shock")),"cast_id":int(hit_context.get("cast_id",0)),"phase":str(hit_context.get("phase","telegraph"))}
		var attached:Dictionary=_attach_shock("player",0,source_id,at,hit_context.shock_policy,settlement,origin)
		if attached.get("applied",false):record.shock_applied={"at":at,"duration":float(hit_context.shock_policy.duration)}
	_finish_player_death()
	return true


func _finish_player_death()->void:
	if health>0.0:return
	feedback_runtime.flush_target("player", 0)
	burn_runtime.reset()
	shock_runtime.reset()
	_ember_deaths.clear()
	flask_runtime.clear_effects()
	leech_runtime.clear()
	alive = false
	group_cooldowns.reset()
	telegraphs.reset()
	monster_runtime.cancel_pending("player_death")
	projectile_runtime.cancel_all(projectiles, "owner_death")
	save_build()
	hud.show_death()

func _burn_event_time(offset:float)->float:
	return clampf(_burn_step_start+offset,_burn_step_start,elapsed) if _burn_step_active else elapsed


func _assert_burn_result(result:Dictionary)->void:
	assert(result.ok,"Validated burning timeline: "+str(result.reason))


func _shock_hit_increase(kind:String,id:int,at:float)->float:
	if shock_runtime.is_empty():return 0.0
	var result:Dictionary=shock_runtime.status_at(kind,id,at)
	assert(result.ok,"Validated shock query: "+str(result.reason))
	return float(result.hit_damage_taken_increased) if result.ok and result.active else 0.0


func _attach_shock(kind:String,id:int,source_id:int,at:float,policy:Dictionary,settlement:Dictionary,provenance:Dictionary)->Dictionary:
	var actual_loss:float=float(settlement.get("shield_spent",0.0))+float(settlement.get("health_lost",0.0))
	var lightning:float=float(settlement.get("components",{}).get("lightning",0.0))
	if actual_loss<=0.0 or lightning<=0.0:return {"ok":true,"applied":false,"reason":"no_actual_lightning_hit"}
	var checked:Dictionary=ShockRules.from_lightning_hit(lightning,policy)
	assert(checked.ok,"Validated lightning shock policy: "+str(checked.reason))
	if not checked.ok:return {"ok":false,"applied":false,"reason":checked.reason}
	var result:Dictionary=shock_runtime.apply(kind,id,source_id,at,policy,provenance)
	assert(result.ok,"Validated shock attachment: "+str(result.reason))
	return result


func shock_statuses()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if shock_runtime.is_empty():return result
	var targets:Dictionary={}
	for enemy:Dictionary in enemies:targets[int(enemy.id)]=enemy
	for status:Dictionary in shock_runtime.statuses(elapsed):
		var position:Vector2=player_pos
		if status.target_kind=="player":
			if not alive:continue
		else:
			var target:Dictionary=targets.get(int(status.target_id),{})
			if target.is_empty() or float(target.health)<=0.0:continue
			position=target.pos
		result.append({"target_kind":status.target_kind,"target_id":status.target_id,"source_id":status.source_id,
			"position":position,"remaining_seconds":status.remaining_seconds,"expires_at":status.expires_at,
			"hit_damage_taken_increased":status.hit_damage_taken_increased})
	return result


func _ember_event_time(at:float,event:Dictionary)->float:
	# The current batch's clock is derived only from adjacent original raw
	# offsets; the event dictionary and ordering remain untouched for RNG/trace.
	if not _ember_projectile_clock.is_empty() and event.get("sequence",-1)==_ember_projectile_clock.sequence and event.get("time",-1.0)==_ember_projectile_clock.raw:
		at=_burn_event_time(float(_ember_projectile_clock.offset))
	var latest:float=maxf(at,burn_runtime.latest_monster_time())
	if latest>at:
		# Same tie contract as the projectile scheduler, relative to this tick.
		assert(_burn_step_active and event.has("time") and latest<=elapsed and is_equal_approx(float(event.time),latest-_burn_step_start),"Ember events cannot reverse time outside an existing projectile tie")
		return latest
	return at


## Only the new mechanism needs a shared monster burn clock. Ordinary ignite
## keeps its historical per-target path byte for byte when no ember is active.
func _advance_proliferating_burns(to_time:float)->void:
	if _ember_advancing:return
	_ember_advancing=true
	var iterations:int=0
	while true:
		iterations+=1
		assert(iterations<=BurnRuntime.MAX_TARGETS+1,"One burn-death boundary per living target")
		var targets:Dictionary={}
		for enemy:Dictionary in enemies:targets[int(enemy.id)]=enemy
		# A complete current-clock proof avoids copying/sorting every status for
		# repeated contacts at the same instant. Still remove stale bodies and
		# retain the original empty-settlement/deferred-death flush sequence.
		var current_ids:Array[int]=burn_runtime.monster_ids_at_time(to_time)
		if not current_ids.is_empty():
			var living:bool=false
			for id:int in current_ids:
				var body:Dictionary=targets.get(id,{})
				if body.is_empty() or float(body.health)<=0.0:burn_runtime.remove("monster",id)
				else:living=true
			if living:
				_ember_defer_deaths=true
				_settle_burn_segments([],targets)
				_ember_defer_deaths=false
				_flush_ember_deaths()
			break
		var states:Array[Dictionary]=[]
		var death_times:Dictionary={}
		var cut:float=to_time
		for status:Dictionary in burn_runtime.statuses():
			if status.target_kind!="monster":continue
			var target:Dictionary=targets.get(int(status.target_id),{})
			if target.is_empty() or float(target.health)<=0.0:
				burn_runtime.remove("monster",int(status.target_id));continue
			assert(float(status.last_time)<=to_time,"Monster burn timeline cannot move backwards")
			states.append(status)
			var expiry:float=float(status.provenance.get("ember_expiry",float(status.last_time)+float(status.remaining)))
			var end:float=minf(to_time,expiry)
			if end<=float(status.last_time):continue
			var rate:Dictionary=Defense.incoming_burn(float(status.raw_dps),target.get("resistances",{}).get("fire",0.0),0.0,1.0,"monster")
			assert(rate.ok,"Validated burn defense")
			if float(rate.damage_total)<=0.0:continue
			var death_at:float=float(status.last_time)+(float(target.get("shield",0.0))+float(target.health))/float(rate.damage_total)
			if death_at<=float(status.last_time):
				# A positive lifetime smaller than one clock ULP still needs the
				# next representable instant; never spin at a zero-width boundary.
				var bits:=PackedByteArray();bits.resize(8);bits.encode_double(0,float(status.last_time))
				bits.encode_u64(0,bits.decode_u64(0)+1);death_at=bits.decode_double(0)
			if death_at<=end:
				death_times[int(status.target_id)]=death_at
				cut=minf(cut,death_at)
		if states.is_empty():break
		var segments:Array[Dictionary]=[]
		var sources:Dictionary={}
		var exact:Dictionary={}
		for status:Dictionary in states:
			# All currently burning actors reach the same causal boundary before
			# any death can spread to them or select them as still alive.
			if float(status.last_time)>cut:continue
			var advanced:Dictionary=burn_runtime.advance_target("monster",int(status.target_id),cut)
			_assert_burn_result(advanced)
			if advanced.segments.is_empty():continue
			segments.append_array(advanced.segments)
			sources[int(status.target_id)]=status
			if death_times.get(int(status.target_id),-1.0)==cut:exact[int(status.target_id)]=true
		_ember_defer_deaths=true
		_settle_burn_segments(segments,targets,sources,exact)
		_ember_defer_deaths=false
		_flush_ember_deaths()
		if cut>=to_time:break
	_ember_advancing=false


func _flush_ember_deaths()->void:
	if _ember_flushing or _ember_defer_deaths or _ember_deaths.is_empty():return
	_ember_flushing=true
	while not _ember_deaths.is_empty():
		_ember_deaths.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.id)<int(b.id) if float(a.at)==float(b.at) else float(a.at)<float(b.at))
		var event:Dictionary=_ember_deaths.pop_front()
		var transfer:Dictionary=EmberRules.transfer(event.status,event.at)
		assert(transfer.ok,"Validated ember death lineage")
		if transfer.burn.is_empty():continue
		var selection:Dictionary=EmberRules.select_targets(event.origin,event.id,enemies,_terrain_visible)
		assert(selection.ok,"Validated live ember targets")
		for target_id:int in selection.target_ids:
			var attached:Dictionary=burn_runtime.apply("monster",target_id,0,transfer.burn.raw_dps,transfer.burn.duration,event.at,transfer.burn.provenance)
			_assert_burn_result(attached)
			assert(attached.segments.is_empty(),"Recipients must already be at the transfer time")
	_ember_flushing=false


func _advance_monster_burn(enemy:Dictionary,to_time:float)->void:
	if burn_runtime.is_empty():return
	if burn_runtime.has_ember_states():
		_advance_proliferating_burns(to_time)
		return
	var result:Dictionary=burn_runtime.advance_target("monster",int(enemy.id),to_time)
	_assert_burn_result(result)
	_settle_burn_segments(result.segments,{int(enemy.id):enemy})


func _advance_monster_burns(to_time:float)->void:
	if burn_runtime.is_empty():return
	if burn_runtime.has_ember_states():
		_advance_proliferating_burns(to_time)
		_flush_monster_spawns()
		return
	var targets:Dictionary={}
	for enemy:Dictionary in enemies:targets[int(enemy.id)]=enemy
	for status:Dictionary in burn_runtime.statuses():
		if status.target_kind!="monster":continue
		var result:Dictionary=burn_runtime.advance_target("monster",status.target_id,to_time)
		_assert_burn_result(result);_settle_burn_segments(result.segments,targets)
	_flush_monster_spawns()


func _advance_player_burn(to_time:float)->void:
	if burn_runtime.is_empty() or not alive:return
	var result:Dictionary=burn_runtime.advance_target("player",0,to_time)
	_assert_burn_result(result);_settle_burn_segments(result.segments)


func _settle_burn_segments(segments:Array,targets:Dictionary={},death_states:Dictionary={},exact_deaths:Dictionary={})->void:
	for segment:Dictionary in segments:
		var raw:float=segment.raw_amount
		var settlement:Dictionary={}
		if segment.target_kind=="player":
			if not alive:continue
			var immune_until:float=_burn_immunity_until if _burn_step_active else elapsed+invulnerable if invulnerable>0.0 else 0.0
			raw=float(segment.raw_dps)*maxf(0.0,float(segment.to_time)-maxf(float(segment.from_time),immune_until))
			if raw<=0.0:continue
			var mana_ratio:Variant=_stats.get("damage_taken_from_mana_before_life",0.0)
			var maximum_fire_bonus:Variant=_stats.get("maximum_fire_resistance_add",0.0)
			if typeof(maximum_fire_bonus) not in [TYPE_INT,TYPE_FLOAT] or float(maximum_fire_bonus)!=0.0:
				settlement=Defense.incoming_burn(raw,_stats.get("fire_resistance",0.0),shield,health,"player",mana,mana_ratio,maximum_fire_bonus)
			elif typeof(mana_ratio) not in [TYPE_INT,TYPE_FLOAT] or float(mana_ratio)!=0.0:
				settlement=Defense.incoming_burn(raw,_stats.get("fire_resistance",0.0),shield,health,"player",mana,mana_ratio)
			else:
				settlement=Defense.incoming_burn(raw,_stats.get("fire_resistance",0.0),shield,health,"player")
			if not settlement.ok:continue
			if settlement.has("remaining_mana"):mana=float(settlement.remaining_mana)
			shield=settlement.remaining_shield;health=settlement.remaining_health
			if float(settlement.damage_total)>0.0:damage_delay=float(_stats.get("shield_recharge_delay",Defense.RECHARGE_BASE_DELAY))
			_record_damage_feedback("player", 0, "burn", settlement, player_pos)
			_finish_player_death()
		else:
			var target:Dictionary=targets.get(int(segment.target_id),{})
			if target.is_empty():
				for enemy:Dictionary in enemies:
					if int(enemy.id)==int(segment.target_id):target=enemy;break
			if target.is_empty() or float(target.health)<=0.0:
				burn_runtime.remove("monster",int(segment.target_id));continue
			settlement=Defense.incoming_burn(raw,target.get("resistances",{}).get("fire",0.0),target.get("shield",0.0),target.health,"monster")
			if not settlement.ok:continue
			if exact_deaths.has(int(target.id)) and float(settlement.remaining_health)>0.0:
				# The analytic event boundary can round just below the final ULP.
				# Settle exactly the remaining resources at that proven boundary.
				var fraction:float=1.0-float(settlement.details[0].resistance)
				assert(float(settlement.remaining_health)<=0.000000001*maxf(1.0,float(target.health)+float(target.get("shield",0.0))),"Only floating point residuals may be clamped at a planned death")
				raw=(float(target.get("shield",0.0))+float(target.health))/fraction
				settlement=Defense.incoming_burn(raw,target.get("resistances",{}).get("fire",0.0),target.get("shield",0.0),target.health,"monster")
				settlement.damage_total=float(target.get("shield",0.0))+float(target.health)
				settlement.shield_spent=float(target.get("shield",0.0));settlement.health_lost=float(target.health)
				settlement.remaining_shield=0.0;settlement.remaining_health=0.0;settlement.overkill=0.0
			if _apply_enemy_resources(target,settlement):
				_record_damage_feedback("monster", int(target.id), "burn", settlement, Vector2(target.pos))
				_finish_enemy_death(target,false,float(segment.to_time),death_states.get(int(target.id),{}))
		if settlement.is_empty():continue
		var record:Dictionary=segment.duplicate(true);record.settlement=settlement;record.effective_raw_amount=raw
		burn_trace.append(record)
		if burn_trace.size()>32:burn_trace.pop_front()


func _record_damage_feedback(target_kind: String, target_id: int, kind: String, settlement: Dictionary, position: Vector2) -> void:
	var result: Dictionary = feedback_runtime.record({"target_kind":target_kind, "target_id":target_id, "kind":kind,
		"shield_spent":float(settlement.shield_spent), "health_lost":float(settlement.health_lost), "position":position})
	assert(result.ok, "Validated settled damage feedback: " + str(result.reason))


func damage_feedback() -> Array[Dictionary]:
	return feedback_runtime.entries()


func burn_statuses()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if burn_runtime.is_empty():return result
	var targets:Dictionary={}
	for enemy:Dictionary in enemies:targets[int(enemy.id)]=enemy
	for status:Dictionary in burn_runtime.statuses():
		var position:Vector2=player_pos
		var resistance:float=float(_stats.get("fire_resistance",0.0))
		var immune:bool=invulnerable>0.0 if status.target_kind=="player" else false
		if status.target_kind=="monster":
			var enemy:Dictionary=targets.get(int(status.target_id),{})
			if enemy.is_empty() or float(enemy.health)<=0.0:continue
			position=enemy.pos;resistance=float(enemy.get("resistances",{}).get("fire",0.0))
		elif not alive:continue
		var maximum_fire_bonus:Variant=_stats.get("maximum_fire_resistance_add",0.0) if status.target_kind=="player" else 0.0
		var profile:Dictionary
		if typeof(maximum_fire_bonus) not in [TYPE_INT,TYPE_FLOAT] or float(maximum_fire_bonus)!=0.0:
			profile=Defense.resistance_profile({"fire_resistance":resistance,"maximum_fire_resistance_add":maximum_fire_bonus},status.target_kind)
		else:
			profile=Defense.defense_profile({"fire_resistance":resistance},status.target_kind)
		if not profile.ok:continue
		result.append({"target_kind":status.target_kind,"target_id":status.target_id,"source_id":status.source_id,"position":position,"remaining_seconds":status.remaining,"raw_dps":status.raw_dps,"effective_dps":0.0 if immune else float(status.raw_dps)*(1.0-float(profile.effective_resistances.fire)),"immune":immune})
	return result


func _update_pickups(delta: float) -> void:
	for pickup: Dictionary in pickups:
		pickup.life = float(pickup.life) - delta
		var distance: float = Vector2(pickup.pos).distance_to(player_pos)
		if distance < 110.0:
			pickup.pos = Vector2(pickup.pos).move_toward(player_pos, 260.0 * delta)
		if distance < 23.0:
			health = minf(float(_stats.max_health), health + 18.0)
			mana = minf(float(_stats.max_mana), mana + 22.0)
			_clear_full_leech()
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
	if not shock_runtime.is_empty():shock_runtime.prune(elapsed)
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
	var began: int = Time.get_ticks_usec() if Visuals.diagnostic_profile_enabled else 0
	_world_draw_count += 1
	if _ready_complete and is_instance_valid(retained_actors) and is_instance_valid(foreground_layer):
		retained_actors.visible = use_retained_actors
		foreground_layer.visible = use_retained_actors
		if use_retained_actors:
			retained_actors.sync(self)
			foreground_layer.queue_redraw()
			Visuals.draw_before_actors(self, visual_settings, static_environment == null)
		else: Visuals.draw_scene(self, visual_settings, static_environment == null)
	else: Visuals.draw_scene(self, visual_settings, static_environment == null)
	if Visuals.diagnostic_profile_enabled:
		_render_measured_frame = Engine.get_process_frames()
		_render_prefix_usec = Time.get_ticks_usec() - began


func visual_submission_diagnostics() -> Dictionary:
	var result: Dictionary = retained_actors.diagnostics() if is_instance_valid(retained_actors) else {}
	var frame: int = Engine.get_process_frames()
	result["draw_usec"] = _render_prefix_usec if _render_measured_frame == frame else 0
	if use_retained_actors:
		result.draw_usec += int(result.get("current_draw_usec", 0))
		if is_instance_valid(foreground_layer) and foreground_layer.measured_frame == frame:
			result.draw_usec += int(foreground_layer.measured_usec)
	result["retained"] = use_retained_actors
	return result


# Region flow owns only runtime state. Canonical item operations persist to the
# selected profile; entering the test profile is explicit and never overwrites normal.
signal world_context_changed
signal build_state_replaced
const TownCatalog=preload("res://scripts/town/town_catalog.gd")
const MapCatalog=preload("res://scripts/world/map_catalog.gd")
const MapCompiler=preload("res://scripts/world/map_compiler.gd")
const NormalMaps=preload("res://scripts/world/normal_map_catalog.gd")
const MapDefense=preload("res://scripts/world/map_defense_rules.gd")
const MapEnemyAdmission=preload("res://scripts/world/map_admission.gd")
const MapRun=preload("res://scripts/world/map_run_state.gd")
const NORMAL_BUILD_PATH:="user://build_save.json"
const TOWN_TEST_BUILD_PATH:="user://town_test_build_save.json"
var build_save_path:String=NORMAL_BUILD_PATH
var _world_mode:="town"
var _world_revision:=0
var _map_draft_revision:=0
var _map_draft_profile:Dictionary=MapCompiler.compile_normal("old_garden",1,[],[]).profile
var _normal_draft_profile:Dictionary=_map_draft_profile.duplicate(true)
var _test_draft_profile:Dictionary=MapCompiler.compile("old_garden",[],[]).profile
const CampLayout=preload("res://scripts/world/map_camp_layout.gd")
const CampState=preload("res://scripts/world/map_camp_state.gd")
const CampAdmission=preload("res://scripts/world/map_camp_admission.gd")
var _map_camps=CampState.new()
var _camp_landmarks:Dictionary={}
var _camp_movement:Array=[]
var _camp_requested:Dictionary={}
var _camp_wait_reasons:Dictionary={}
var _boss_requested:=false
var _map_run=MapRun.new()
var _normal_state:RefCounted
var _normal_run_id:int=0
var _normal_reset_authorized:bool=false
var _normal_completion_pending:bool=false
var test_supply_enabled:=true
var _normal_gem_receipts: Dictionary = {}

func world_geometry() -> Dictionary:
	var result: Dictionary = _geometry.snapshot()
	if _world_mode in ["map","map_complete"] and not _camp_landmarks.is_empty():
		result["landmarks"]=_camp_landmarks.duplicate(true)
		result.spawn=_camp_landmarks.entry
	return result

func _camp_states()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if _world_mode not in ["map","map_complete"]:return result
	result.assign(_map_camps.states(_map_run.defeated))
	for entry:Dictionary in result:entry.reason=str(_camp_wait_reasons.get(entry.id,""))
	return result

func _boss_phase()->String:
	if _world_mode not in ["map","map_complete"]:return "sealed"
	if _map_run.boss_defeated:return "defeated"
	if _map_run.boss_id>0:return "active"
	return "ready" if _map_run.ready_for_boss() else "sealed"

func _sync_camp_presentation()->void:
	if is_instance_valid(static_environment) and static_environment.has_method("set_encounter_state"):
		static_environment.set_encounter_state(_camp_states(),_boss_phase())

func _refresh_world_geometry() -> void:
	var id: String = str(_map_run.profile.get("id","old_garden")) if _world_mode in ["map","map_complete"] else _world_mode
	var configured: bool = _geometry.configure(id,ARENA)
	assert(configured,"Current map must have an authoritative geometry definition")
	if not configured: return
	if is_instance_valid(static_environment) and static_environment.has_method("set_geometry"):
		static_environment.set_geometry(world_geometry())
func _terrain_visible(from: Vector2, to: Vector2) -> bool:
	return not _geometry.has_walls() or _geometry.visible(from,to)


func _is_test_profile() -> bool:
	return Build.Legacy._save_paths_match(build_save_path, TOWN_TEST_BUILD_PATH)

func _recover_normal_active() -> Dictionary:
	if _is_test_profile(): return {"ok":true,"reason":""}
	var active:Dictionary=state.normal_journey().active_run
	if active.is_empty():return {"ok":true,"reason":""}
	var result:Dictionary=state.normal_abandon_map(active.run_id,state.revision(),build_save_path)
	if result.ok:result["abandoned_run_id"]=int(active.run_id)
	return result

func world_context()->Dictionary:
	var run:Dictionary=_map_run.snapshot()
	var test:bool=_is_test_profile()
	var pending:Dictionary={"pending_map_reward":{},"pending_gems":0,"pending_flasks":0,"normal_root_kills":0} if test else state.normal_pending_rewards()
	var normal_town:bool=_world_mode=="town" and not test
	var has_reward:bool=not pending.pending_map_reward.is_empty() or pending.pending_gems>0 or pending.pending_flasks>0
	var active:Dictionary={} if test else state.normal_journey().active_run
	return {"mode":_world_mode,"test_mode":test,"save_path":build_save_path,"revision":_world_revision,"run_revision":run_revision,
		"map_id":str(_map_run.profile.get("id","")),"map_name":str(_map_run.profile.get("name","")),
		"camp_states":_camp_states(),"boss_phase":_boss_phase(),
		"ordinary_kills":run.ordinary_kills,"ordinary_target":run.ordinary_target,"boss_defeated":run.boss_defeated,
		"can_return":_world_mode in ["map","map_complete"],"supply_enabled":test and test_supply_enabled,
		"normal_town":normal_town,"can_enter_normal_town":not test and _world_mode=="normal","can_leave_normal_town":normal_town,
		"completion_save_pending":_normal_completion_pending,
		"map_tier":int(_map_run.profile.get("journey_tier",0)),"fee_paid":int(active.get("fee_paid",_map_run.profile.get("fee",0))),"retry_cost":int(_map_run.profile.get("fee",0)),
		"pending_map_reward":pending.pending_map_reward,"pending_gems":int(pending.pending_gems),"pending_flasks":int(pending.pending_flasks),"normal_root_kills":int(pending.normal_root_kills),
		"can_claim_normal_rewards":normal_town and has_reward,"claim_reason":"请先返回正式城镇" if not normal_town else "" if has_reward else "没有待领取奖励",
		"description":"城镇测试 · 独立测试进度，免费测试供应不进入正常存档" if test else "正式城镇" if normal_town else "竞技练习" if _world_mode=="normal" else "正式地图挑战"}
func _world_failure(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason}
func _world_ok()->Dictionary:return {"ok":true,"code":"","reason":"","world":world_context()}
func _world_revision_ok(value:Variant)->bool:return value is int and value==_world_revision
func _replace_build(next:RefCounted,path:String)->void:
	if state.changed.is_connected(_on_build_changed):state.changed.disconnect(_on_build_changed)
	state.retire_profile()
	shock_runtime.reset()
	state=next;build_save_path=path;state.changed.connect(_on_build_changed)
	_stats=state.get_stats();_progress_hud_dirty=false;_progress_save_dirty=false;_progress_save_requested=false
	build_state_replaced.emit()
func enter_normal_town(expected_revision:Variant)->Dictionary:
	if not _world_revision_ok(expected_revision) or _is_test_profile() or _world_mode!="normal":return _world_failure("stale_world","正式城镇入口已变化")
	if not save_build():return _world_failure("save_failed","正式进度未保存，暂不能进入城镇")
	_world_mode="town";_world_revision+=1;_map_draft_revision+=1;_map_run.clear();_clear_encounter();restart_run();world_context_changed.emit()
	return _world_ok()
func leave_normal_town(expected_revision:Variant)->Dictionary:
	if not _world_revision_ok(expected_revision) or _is_test_profile() or _world_mode!="town":return _world_failure("stale_world","请先返回正式城镇")
	var recovered:Dictionary=_recover_normal_active()
	if not recovered.ok:return _world_failure("save_failed",recovered.reason)
	if not save_build():return _world_failure("save_failed","正式进度未保存，暂不能进入竞技练习")
	_world_mode="normal";_world_revision+=1;_map_draft_revision+=1;_map_run.clear();_clear_encounter();restart_run();world_context_changed.emit()
	return _world_ok()
func enter_town_test(expected_revision:Variant)->Dictionary:
	if not _world_revision_ok(expected_revision) or _is_test_profile() or _world_mode not in ["normal","town"]:return _world_failure("stale_world","请先返回正式城镇或竞技练习")
	var recovered:Dictionary=_recover_normal_active()
	if not recovered.ok:return _world_failure("save_failed",recovered.reason)
	if not save_build():return _world_failure("save_failed","正常进度未保存，暂不能进入城镇测试")
	var test:=Build.new()
	if FileAccess.file_exists(TOWN_TEST_BUILD_PATH):
		if not test.load_build(TOWN_TEST_BUILD_PATH):return _world_failure("test_save_invalid",test.last_error)
	else:
		var copied:Dictionary=state.snapshot();copied.journey=Build.Journey.empty()
		test._accept_memory(copied)
		if test.save_build(TOWN_TEST_BUILD_PATH)!=OK:return _world_failure("test_save_failed",test.last_error)
	_normal_draft_profile=_map_draft_profile.duplicate(true);_map_draft_profile=_test_draft_profile.duplicate(true)
	_normal_state=state;_world_mode="town";_world_revision+=1;_map_draft_revision+=1;_normal_run_id=0
	_replace_build(test,TOWN_TEST_BUILD_PATH);_map_run.clear();_clear_encounter();restart_run();world_context_changed.emit()
	if test.migrated_from_legacy:hud.notify(test.migration_message)
	return _world_ok()
func leave_town_test(expected_revision:Variant)->Dictionary:
	if not _world_revision_ok(expected_revision) or not _is_test_profile() or _world_mode!="town":return _world_failure("stale_world","请先返回测试城镇")
	if not save_build():return _world_failure("save_failed","测试进度未保存")
	var normal:=Build.new()
	if not normal.load_build(NORMAL_BUILD_PATH):return _world_failure("normal_save_invalid",normal.last_error)
	_test_draft_profile=_map_draft_profile.duplicate(true);_map_draft_profile=_normal_draft_profile.duplicate(true)
	_world_mode="town";_world_revision+=1;_map_draft_revision+=1;_map_run.clear();_clear_encounter();_normal_run_id=0
	_replace_build(normal,NORMAL_BUILD_PATH);_normal_state=null;restart_run();world_context_changed.emit()
	if normal.migrated_from_legacy:hud.notify(normal.migration_message)
	return _world_ok()
func town_services()->Array[Dictionary]:
	var rows:=TownCatalog.services()
	for row:Dictionary in rows:
		row.available=_world_mode=="town" and (_is_test_profile() or row.id in ["skill_merchant","crafter","passive_reset","map_device"])
		row.reason="" if row.available else "测试商人仅在独立测试城镇供应" if _world_mode=="town" else "请先返回城镇"
		if not _is_test_profile() and row.id=="skill_merchant":row.description="用校准碎片购买已实现主动与辅助宝石；背包中的宝石可回收。"
		elif not _is_test_profile() and row.id=="crafter":row.description="使用正式背包内的真实校准碎片进行六项现有工艺。"
		elif not _is_test_profile() and row.id=="map_device":row.description="选择地图与挑战档位；成功入图才扣费，完整完成后领取结算。"
	return rows
func town_stock(service_id:String)->Array[Dictionary]:
	var rows:=TownCatalog.offers(service_id)
	if service_id=="skill_merchant" and not _is_test_profile():
		var prices:Dictionary={}
		for offer:Dictionary in normal_gem_offers():prices[offer.definition_id]=offer
		for row:Dictionary in rows:
			var offer:Dictionary=prices.get(row.definition_id,{})
			row.cost=int(offer.get("cost",0));row.paid=true
			row.price_label="%d 校准碎片"%row.cost
			row.available=bool(offer.get("available",false));row.reason=str(offer.get("reason","未知宝石"))
		return rows
	for row:Dictionary in rows:
		row.available=_world_mode=="town" and _is_test_profile() and test_supply_enabled
		row.reason="" if row.available else "测试供应不能领取到正式存档" if not _is_test_profile() else "测试供应已关闭" if not test_supply_enabled else "请先返回测试城镇"
	return rows
func _normal_gem_service_reason() -> String:
	return "" if _world_mode=="town" and not _is_test_profile() else "请返回正式城镇进行宝石交易"

func normal_gem_offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = state.normal_gem_offers(build_save_path)
	var reason: String = _normal_gem_service_reason()
	if not reason.is_empty():
		for row: Dictionary in result: row.available=false; row.reason=reason
	return result

func normal_gem_recycle_info(uid: Variant) -> Dictionary:
	var result: Dictionary = state.gem_recycle_info(uid,build_save_path)
	var reason: String = _normal_gem_service_reason()
	if not reason.is_empty(): result.available=false; result.reason=reason
	return result

func normal_gem_trade_quote(operation: Variant,target: Variant,expected_revision: Variant) -> Dictionary:
	var reason: String = _normal_gem_service_reason()
	if not reason.is_empty(): return _world_failure("service_unavailable",reason)
	var result: Dictionary = state.gem_trade_quote(operation,target,expected_revision,build_save_path)
	if result.ok:
		while _normal_gem_receipts.size()>=8:
			cancel_normal_gem_trade_quote(_normal_gem_receipts.keys()[0])
		_normal_gem_receipts[result.handle]={"model":state.get_instance_id(),"world_revision":_world_revision}
	return result

func cancel_normal_gem_trade_quote(handle: String) -> void:
	_normal_gem_receipts.erase(handle)
	state.cancel_gem_trade_quote(handle)

func _invalidate_normal_gem_quotes() -> void:
	_normal_gem_receipts.clear()
	state.invalidate_gem_trade_quotes()

func execute_normal_gem_trade(handle: Variant,current_target: Variant) -> Dictionary:
	if not handle is String or not _normal_gem_receipts.has(handle): return _world_failure("unknown_quote","宝石报价已失效")
	var receipt: Dictionary = _normal_gem_receipts[handle]
	_normal_gem_receipts.erase(handle)
	var reason: String = _normal_gem_service_reason()
	if not reason.is_empty() or receipt.model!=state.get_instance_id() or receipt.world_revision!=_world_revision:
		state.cancel_gem_trade_quote(handle)
		return _world_failure("stale_world","城镇或存档已切换，请重新获取报价")
	var result: Dictionary = state.execute_gem_trade(handle,current_target)
	if result.ok: world_context_changed.emit()
	return result

func town_buy(offer_id:Variant,expected_revision:Variant)->Dictionary:
	if _world_mode!="town" or not _is_test_profile() or not test_supply_enabled:return _world_failure("service_unavailable","当前不能领取测试供应")
	var result:Dictionary=state.town_claim_offer(offer_id,expected_revision,build_save_path)
	result.code=str(result.get("code",result.get("error_code","")))
	if result.ok:world_context_changed.emit()
	return result
func town_reset_passives(expected_revision:Variant)->Dictionary:
	if _world_mode!="town":return _world_failure("service_unavailable","请先返回城镇")
	var result:Dictionary=state.reset_all_passives(expected_revision,build_save_path)
	result.code=str(result.get("code",result.get("error_code","")))
	if result.ok:world_context_changed.emit()
	return result
func map_options()->Dictionary:
	var options:Dictionary=MapCatalog.options(_is_test_profile())
	options.test_mode=_is_test_profile()
	if not _is_test_profile():
		options.tiers=[]
		var completed:Dictionary=state.normal_journey().best_tiers
		for id:String in MapCatalog.MAPS:options.tiers.append_array(NormalMaps.tiers(id,int(completed[id])))
		options.cost_policy={"id":"normal_shards_v1","enabled":true,"label":"入图消耗背包校准碎片","affects_legacy_currency":true}
	return options
func _normal_start_reason()->String:
	if _is_test_profile():return ""
	var journey:Dictionary=state.normal_journey()
	if not journey.pending_map_reward.is_empty():return "尚有地图结算待领取，请整理背包后领取再开启新图"
	# A loaded unfinished run is abandoned by start_map before charging a new one.
	# Keep that retry reachable if the startup save was temporarily unavailable.
	if not _map_draft_profile.get("normal_map",false):return "请先制作正式地图草案"
	if int(_map_draft_profile.journey_tier)>mini(int(journey.best_tiers[_map_draft_profile.id])+1,3):return "此地图档位尚未解锁"
	if state.crafting_balance()<int(_map_draft_profile.fee):return "背包内校准碎片不足"
	if not state.pending_items().is_empty():return "请先安置已有待安置物品"
	return ""
func map_draft()->Dictionary:
	var valid:bool=MapCompiler.profile_reason(_map_draft_profile).is_empty()
	var reason:String="地图草案无效" if not valid else _normal_start_reason()
	return {"revision":_map_draft_revision,"map_id":_map_draft_profile.id,"normal_ids":_map_draft_profile.normal_ids.duplicate(),"special_ids":_map_draft_profile.special_ids.duplicate(),
		"tier":int(_map_draft_profile.get("journey_tier",0)),"cost":int(_map_draft_profile.get("fee",0)),"completion_reward":int(_map_draft_profile.get("completion_reward",0)),
		"valid":valid,"reason":reason,"can_start":valid and reason.is_empty() and _world_mode=="town","summary":_map_draft_profile.summary,"cost_label":"测试模式免费" if _is_test_profile() else "入图 %d 碎片 · 完成 %d 碎片"%[_map_draft_profile.get("fee",0),_map_draft_profile.get("completion_reward",0)]}
func craft_map(map_id:Variant,normal_ids:Variant,special_ids:Variant,expected_revision:Variant)->Dictionary:
	if _world_mode!="town" or not _is_test_profile():return _world_failure("not_in_test_town","请先进入独立测试城镇")
	if not expected_revision is int or expected_revision!=_map_draft_revision:return _world_failure("stale_map","地图草案已变化")
	var compiled:=MapCompiler.compile(map_id,normal_ids,special_ids)
	if not compiled.ok:return compiled
	_map_draft_profile=compiled.profile;_map_draft_revision+=1;world_context_changed.emit()
	return {"ok":true,"code":"","reason":"","draft":map_draft()}
func craft_normal_map(map_id:Variant,tier:Variant,normal_ids:Variant,special_ids:Variant,expected_revision:Variant)->Dictionary:
	if _world_mode!="town" or _is_test_profile():return _world_failure("not_in_normal_town","请先返回正式城镇")
	if not expected_revision is int or expected_revision!=_map_draft_revision:return _world_failure("stale_map","地图草案已变化")
	var compiled:=MapCompiler.compile_normal(map_id,tier,normal_ids,special_ids)
	if not compiled.ok:return compiled
	if int(tier)>mini(int(state.normal_journey().best_tiers[map_id])+1,3):return _world_failure("tier_locked","请先完成本地图前一档挑战")
	_map_draft_profile=compiled.profile;_map_draft_revision+=1;world_context_changed.emit()
	return {"ok":true,"code":"","reason":"","draft":map_draft()}
func start_map(expected_revision:Variant)->Dictionary:
	if _world_mode!="town" or not expected_revision is int or expected_revision!=_map_draft_revision:return _world_failure("stale_map","地图草案或所在区域已变化")
	var reason:String=MapCompiler.profile_reason(_map_draft_profile)
	if not reason.is_empty():return _world_failure("invalid_map",reason)
	var camp_plan:Dictionary=_prepare_camp_run(_map_draft_profile,int(state.normal_journey().next_run_id) if not _is_test_profile() else run_revision+1)
	if not camp_plan.ok:return _world_failure("invalid_camp",camp_plan.reason)
	if not _is_test_profile():
		var recovered:Dictionary=_recover_normal_active()
		if not recovered.ok:return _world_failure("save_failed",recovered.reason)
		reason=_normal_start_reason()
		if not reason.is_empty():return _world_failure("cannot_start",reason)
		var began:Dictionary=state.normal_start_map(_map_draft_profile,state.revision(),build_save_path)
		if not began.ok:return _world_failure(str(began.get("error_code","save_failed")),began.reason)
		_normal_run_id=int(began.run_id);_normal_reset_authorized=true
	elif not save_build():return _world_failure("save_failed","测试构筑未保存，未启动地图")
	if not _map_run.begin(_map_draft_profile):return _world_failure("invalid_map","地图配置无效")
	_normal_completion_pending=false
	_encounter_profile=_map_draft_profile.encounter_profile;_encounter_ids.assign(_map_draft_profile.normal_ids);_encounter_error=""
	_world_mode="map";_world_revision+=1;_map_draft_revision+=1;restart_run(camp_plan);world_context_changed.emit()
	return _world_ok()
func retry_normal_map(expected_revision:Variant)->Dictionary:
	if not _world_revision_ok(expected_revision) or _is_test_profile() or _world_mode!="map" or _normal_run_id<=0:return _world_failure("stale_run","当前不能重新开启正式地图，请返回城镇")
	var camp_plan:Dictionary=_prepare_camp_run(_map_run.profile,int(state.normal_journey().next_run_id))
	if not camp_plan.ok:return _world_failure("invalid_camp",camp_plan.reason)
	var began:Dictionary=state.normal_start_map(_map_run.profile,state.revision(),build_save_path,_normal_run_id)
	if not began.ok:return _world_failure(str(began.get("error_code","save_failed")),began.reason)
	_normal_run_id=int(began.run_id);_normal_reset_authorized=true;_normal_completion_pending=false
	restart_run(camp_plan);world_context_changed.emit();return _world_ok()
func _finish_normal_map()->Dictionary:
	if _is_test_profile() or not _normal_completion_pending:return {"ok":true,"reason":""}
	var result:Dictionary=state.normal_complete_map(_normal_run_id,state.revision(),build_save_path)
	if result.ok:_normal_completion_pending=false;_world_revision+=1;world_context_changed.emit()
	return result
func return_to_town(expected_revision:Variant)->Dictionary:
	if not _world_revision_ok(expected_revision) or _world_mode not in ["map","map_complete"]:return _world_failure("stale_world","本轮地图已变化")
	if not _is_test_profile():
		var finished:Dictionary=_finish_normal_map()
		if not finished.ok:return _world_failure("save_failed",finished.reason)
		if not state.normal_journey().active_run.is_empty():
			var abandoned:Dictionary=state.normal_abandon_map(_normal_run_id,state.revision(),build_save_path)
			if not abandoned.ok:return _world_failure("save_failed",abandoned.reason)
	if not save_build():return _world_failure("save_failed","已得进度未保存，暂不能返城")
	_world_mode="town";_world_revision+=1;_normal_run_id=0;_map_run.clear();_clear_encounter();restart_run();world_context_changed.emit()
	return _world_ok()
func claim_normal_rewards(expected_revision:Variant)->Dictionary:
	if not _world_revision_ok(expected_revision) or _is_test_profile() or _world_mode!="town":return _world_failure("stale_world","请先返回正式城镇领取")
	var result:Dictionary=state.normal_claim_rewards(state.revision(),build_save_path,true)
	if not result.ok:return _world_failure(str(result.get("error_code","claim_failed")),result.reason)
	_world_revision+=1;world_context_changed.emit()
	var response:Dictionary=_world_ok()
	for key:String in ["claimed_shards","claimed_gems","claimed_flasks"]:response[key]=int(result[key])
	return response
func _prepare_camp_run(profile:Dictionary,sequence:int)->Dictionary:
	var layout:Dictionary=CampLayout.layout(profile.get("id"),ARENA)
	if not layout.ok:return {"ok":false,"reason":layout.reason}
	var state_plan:=CampState.new()
	var seed_text:String=JSON.stringify([rng.seed,sequence,profile.id,profile.get("journey_tier",0),"map-camps-v1"])
	var seed_value:int=seed_text.sha256_text().substr(0,15).hex_to_int()
	var prepared:Dictionary=state_plan.begin(profile,layout.landmarks,seed_value)
	if not prepared.ok:return prepared
	var geometry:=Geometry.new()
	if not geometry.configure(profile.id,ARENA):return {"ok":false,"reason":"地图几何无效"}
	# Prove every frozen formation before any real cost, ID, effect or scene change.
	var fixture_runtime:=MonsterLifecycle.new()
	for camp:Dictionary in layout.landmarks.camps:
		var group:Dictionary=CampAdmission.plan(fixture_runtime,profile,state_plan.entries(camp.id),geometry,layout.landmarks.entry,MAX_ENEMIES)
		if not group.ok:return {"ok":false,"reason":group.error}
	return {"ok":true,"reason":"","state":state_plan,"landmarks":layout.landmarks}

func _camp_triggered(marker:Dictionary)->bool:
	if CampLayout.trigger_crossed(player_pos,player_pos,marker.trigger_center,float(marker.trigger_radius)):return true
	for segment:Array in _camp_movement:
		if CampLayout.trigger_crossed(segment[0],segment[1],marker.trigger_center,float(marker.trigger_radius)):return true
	return false

func _camp_wait(id:String,reason:String)->void:
	if str(_camp_wait_reasons.get(id,""))==reason:return
	if reason.is_empty():_camp_wait_reasons.erase(id)
	else:_camp_wait_reasons[id]=reason
	world_context_changed.emit()

func _activate_camp(id:String)->Dictionary:
	var entries:Array=_map_camps.entries(id)
	var planned:Dictionary=CampAdmission.plan(monster_runtime,_map_run.profile,entries,_geometry,player_pos,MAX_ENEMIES-enemies.size())
	if not planned.ok:return {"ok":false,"reason":planned.error}
	var roots:Array=planned.enemies;var ids:Array=[]
	for enemy:Dictionary in roots:ids.append(enemy.id)
	var before:Dictionary=_map_run.admitted.duplicate()
	if not _map_run.register_group(roots):return {"ok":false,"reason":"地图根怪整组登记失败"}
	if not _map_camps.activate(id,ids):
		_map_run.admitted=before
		return {"ok":false,"reason":"据点已经激活或登记无效"}
	EncounterAdmission._restore(monster_runtime,planned.runtime_checkpoint)
	for enemy:Dictionary in roots:
		_apply_source_actor_profile(enemy);enemies.append(enemy)
		_add_ring(enemy.pos,32.0,Monsters.RARITIES[enemy.rarity].color,0.6)
	ordinary_admissions+=roots.size()
	_camp_wait_reasons.erase(id)
	world_context_changed.emit()
	return {"ok":true,"reason":""}

func _activate_camp_boss()->Dictionary:
	if not _map_run.ready_for_boss():return {"ok":false,"reason":"先击败全部据点根怪"}
	var entry:Dictionary={"template_id":_map_run.profile.boss_id,"rarity":"","mechanisms":[],"position":_camp_landmarks.boss.center}
	var planned:Dictionary=CampAdmission.plan(monster_runtime,_map_run.profile,[entry],_geometry,player_pos,MAX_ENEMIES-enemies.size(),"map_boss")
	if not planned.ok:return {"ok":false,"reason":planned.error}
	var boss:Dictionary=planned.enemies[0]
	if not _map_run.register_root(boss,true):return {"ok":false,"reason":"地图首领登记失败"}
	EncounterAdmission._restore(monster_runtime,planned.runtime_checkpoint)
	_apply_source_actor_profile(boss);enemies.append(boss)
	_add_ring(boss.pos,32.0,Monsters.RARITIES[boss.rarity].color,0.6)
	hud.notify("地图首领已出现：裂隙守卫");world_context_changed.emit()
	return {"ok":true,"reason":""}

func _update_map_spawning(_delta:float)->void:
	_flush_monster_spawns()
	if not alive or _camp_landmarks.is_empty():_camp_movement.clear();return
	for camp:Dictionary in _camp_landmarks.camps:
		var status:String=""
		for current:Dictionary in _camp_states():
			if current.id==camp.id:status=current.state;break
		if status!="dormant":continue
		if _camp_triggered(camp):_camp_requested[camp.id]=true
		if _camp_requested.has(camp.id):
			var result:Dictionary=_activate_camp(camp.id)
			if not result.ok:_camp_wait(camp.id,result.reason)
	if _map_run.ready_for_boss():
		if _camp_triggered(_camp_landmarks.boss):_boss_requested=true
		if _boss_requested:
			var result:Dictionary=_activate_camp_boss()
			if not result.ok:_camp_wait("boss",result.reason)
	_camp_movement.clear()
func _check_map_complete()->void:
	var living:=0
	for enemy:Dictionary in enemies:
		if float(enemy.health)>0.0:living+=1
	if _map_run.check_complete(living,monster_runtime.queue.size()):
		projectile_runtime.cancel_all(projectiles);telegraphs.reset()
		_world_mode="map_complete";_world_revision+=1;burn_runtime.reset();shock_runtime.reset()
		var message:String="地图完成，可以返回城镇" if _is_test_profile() else "地图完成，返回正式城镇领取结算"
		if not _is_test_profile():
			_normal_completion_pending=true
			var completed:Dictionary=_finish_normal_map()
			if not completed.ok:message="地图完成，但结算保存失败；返回城镇时可重试："+str(completed.reason)
		world_context_changed.emit();hud.notify(message)
