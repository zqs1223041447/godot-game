extends SceneTree
## Controlled CPU/render diagnostic. 200/400 actors are test-only over-cap loads.
## Catalog stats, collision radii, projectile limits and reward logic are unchanged.
const Visuals = preload("res://scripts/visuals/arena_visuals.gd")

class TimedArena extends "res://scripts/main.gd":
	var phases: Dictionary = {}
	var measure := false
	var draw_us := 0
	func mark(label: String, began: int) -> void:
		if measure: phases[label] = int(phases.get(label,0)) + Time.get_ticks_usec()-began
	func _update_enemies(delta: float) -> void:
		var t := Time.get_ticks_usec(); super._update_enemies(delta); mark("enemy_ai",t)
	func _update_projectiles(delta: float) -> void:
		var t := Time.get_ticks_usec(); super._update_projectiles(delta); mark("projectiles",t)
	func _update_effects(delta: float) -> void:
		var t := Time.get_ticks_usec(); super._update_effects(delta); mark("effects",t)
	func _update_pickups(delta: float) -> void:
		var t := Time.get_ticks_usec(); super._update_pickups(delta); mark("pickups",t)
	func _update_spawning(delta: float) -> void:
		var t := Time.get_ticks_usec(); super._update_spawning(delta); mark("spawn_cleanup",t)
	func _start_enemy_telegraphs() -> void:
		var t := Time.get_ticks_usec(); super._start_enemy_telegraphs(); mark("telegraph_start",t)
	func _on_build_changed() -> void:
		var t := Time.get_ticks_usec(); super._on_build_changed(); mark("build_changed_nested",t)
	func _flush_progress(force_save: bool = false) -> bool:
		var t := Time.get_ticks_usec(); var ok := super._flush_progress(force_save); mark("progress_flush",t); return ok
	func _attempt_progress_save() -> bool:
		var t := Time.get_ticks_usec(); var ok := super._attempt_progress_save(); mark("save_nested",t); return ok
	func _draw() -> void:
		var t := Time.get_ticks_usec(); super._draw(); draw_us = Time.get_ticks_usec()-t

var arena: TimedArena
var output := OS.get_environment("COMBAT_PROFILE_OUT")
var mode := OS.get_environment("COMBAT_PROFILE_MODE")
var count := int(OS.get_environment("COMBAT_PROFILE_COUNT"))
var seconds := int(OS.get_environment("COMBAT_PROFILE_SECONDS"))
var native := false
var failures: Array[String] = []
var buckets: Array = []
var deaths: Array = []
var frames: Dictionary = {}
var draw_phases: Dictionary = {}
var refill_serial := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/workspace/scratch/a51485f153de/v023-profile-users/") \
			or not OS.get_user_data_dir().begins_with(isolated+"/") or output.is_empty() \
			or count not in [100,200,400] or seconds not in [10,120] or mode not in ["crowd","combat"]:
		quit(78); return
	native = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280,720)
	root.title = "Combat diagnostic %d %s" % [count,mode]
	arena = TimedArena.new()
	root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false)
	for unused: int in range(5): await process_frame
	arena.enemies.clear(); arena.monster_runtime.reset(); arena.telegraphs.reset()
	arena.projectiles.clear(); arena.particles.clear(); arena.rings.clear(); arena.floating_text.clear()
	arena.demo_mode = mode == "crowd"
	arena.auto_fire = mode == "combat"; arena.spawn_timer = 1000000; arena.invulnerable = 1000000
	arena.rng.seed = 230023
	if mode == "combat": arena.equip_tornado_example()
	while arena.hud.is_blocking(): arena.hud.close_panel()
	fill()
	var initial := sample("initial",0)
	arena.measure = true
	Visuals.diagnostic_profile_enabled = native
	var total_ticks := seconds*60
	var began := Time.get_ticks_usec()
	for index: int in range(total_ticks):
		arena.phases.clear()
		var frame_begin := Time.get_ticks_usec()
		var old_kills: int = arena.kills
		var tick_begin := Time.get_ticks_usec()
		arena.tick(1.0/60.0)
		append(frames,"tick",Time.get_ticks_usec()-tick_begin)
		if mode == "combat" and arena.group_cooldown_remaining("group_000001") <= 0.0 and arena.mana >= 18.0:
			var cast_begin := Time.get_ticks_usec()
			arena.cast_group("group_000001")
			append(frames,"cast_attempt",Time.get_ticks_usec()-cast_begin)
		# A controlled batch invokes the real death/reward path once per target.
		# It is labelled separately from natural projectile kills, not presented as normal DPS.
		if index > 0 and index % 600 == 0:
			var burst_begin := Time.get_ticks_usec()
			arena._begin_progress_transaction()
			var killed := 0
			for enemy: Dictionary in arena.enemies:
				if killed >= int(count/5): break
				if float(enemy.health)>0:
					arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1.0,Color.WHITE)
					killed += 1
			arena._end_progress_transaction()
			deaths.append({"tick":index,"controlled_targets":killed,"cpu_ms":(Time.get_ticks_usec()-burst_begin)/1000.0,"phases":arena.phases.duplicate(true)})
		var refill_begin := Time.get_ticks_usec(); fill(); append(frames,"refill",Time.get_ticks_usec()-refill_begin)
		var ui_begin := Time.get_ticks_usec(); arena.hud._process(1.0/60.0); append(frames,"hud",Time.get_ticks_usec()-ui_begin)
		for label: String in arena.phases: append(frames,label,int(arena.phases[label]))
		var step_us := Time.get_ticks_usec()-frame_begin
		append(frames,"step",step_us)
		if arena.kills>old_kills: append(frames,"kill_step",step_us)
		append(frames,"separation_visits",arena.separation_candidate_visits)
		if native:
			arena.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			append(frames,"draw_submission",arena.draw_us)
			append(frames,"wall_frame",Time.get_ticks_usec()-frame_begin)
			for label: String in Visuals.diagnostic_frame_usec: append(draw_phases,label,int(Visuals.diagnostic_frame_usec[label]))
		elif index % 60 == 0: await process_frame
		if (index+1)%600 == 0:
			buckets.append(sample("active",index+1))
			write_progress(initial,began,false)
	# Expire the 22-second pickups and short-lived presentation pools naturally.
	if not native:
		arena.auto_fire = false
		for index: int in range(1800):
			arena.tick(1.0/60.0)
			if index%60==0: await process_frame
		buckets.append(sample("drain_30_seconds",total_ticks+1800))
	if not arena.alive: failures.append("Protected diagnostic actor died unexpectedly")
	if arena.projectiles.size()>180 or arena.particles.size()>180: failures.append("Existing bounded pool exceeded")
	if native: root.get_texture().get_image().save_png(output.trim_suffix(".json")+".png")
	write_progress(initial,began,true)
	print("COMBAT_PROFILE_COMPLETE ",count," ",mode," ",seconds,"s native=",native," failures=",failures.size())
	arena.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func fill() -> void:
	# Direct factory admission is limited to this fixture. Shipping MAX_ENEMIES stays100.
	var living := 0
	for enemy: Dictionary in arena.enemies:
		if float(enemy.health)>0: living+=1
	for unused: int in range(count-living):
		var columns := ceili(sqrt(float(count)*arena.ARENA.size.x/arena.ARENA.size.y))
		var rows := ceili(float(count)/columns)
		var col := (refill_serial%count) % columns
		var row := int((refill_serial%count)/columns)
		var point := arena.ARENA.position+Vector2(70+col*(arena.ARENA.size.x-140)/maxi(1,columns-1),50+row*(arena.ARENA.size.y-100)/maxi(1,rows-1))
		var species: String = "ember_guard" if refill_serial%10==0 else ["crawler","skitter","brute"][refill_serial%3]
		var enemy: Dictionary = arena.monster_runtime.create_root(species,arena.wave,point,"ordinary","",[],mode=="combat")
		if enemy.is_empty(): failures.append("Catalog root creation rejected");return
		arena._apply_source_actor_profile(enemy); enemy.spawn=0.0
		arena.enemies.append(enemy); refill_serial+=1

func sample(stage: String,tick: int) -> Dictionary:
	var live := 0
	for enemy: Dictionary in arena.enemies:
		if float(enemy.health)>0: live+=1
	var result := {"stage":stage,"tick":tick,"live":live,"enemy_array":arena.enemies.size(),"projectiles":arena.projectiles.size(),
		"particles":arena.particles.size(),"rings":arena.rings.size(),"text":arena.floating_text.size(),"pickups":arena.pickups.size(),
		"visual_cues":arena.visual_cues.cues.size(),"lineages":arena.monster_runtime.roots.size(),"death_queue":arena.monster_runtime.queue.size(),
		"kills":arena.kills,"reward_kills":arena.reward_kills,"inventory_items":arena.state.snapshot().items.size(),"save_success":arena.state.successful_saves,
		"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"cpu_usec":summaries(frames),"draw_cpu_usec":summaries(draw_phases)}
	frames.clear();draw_phases.clear()
	return result

func append(target: Dictionary,label: String,value: int) -> void:
	if not target.has(label): target[label]=[]
	target[label].append(value)

func summaries(source: Dictionary) -> Dictionary:
	var result := {}
	for label: String in source:
		var values: Array = source[label].duplicate(); values.sort()
		if values.is_empty():continue
		var total := 0.0
		for value: Variant in values:total+=float(value)
		result[label]={"n":values.size(),"mean":total/values.size(),"p50":values[int(values.size()*0.5)],"p95":values[mini(values.size()-1,int(values.size()*0.95))],"p99":values[mini(values.size()-1,int(values.size()*0.99))],"max":values.back()}
	return result

func write_progress(initial: Dictionary,began: int,complete: bool) -> void:
	var record := {"complete":complete,"count":count,"mode":mode,"sim_seconds":seconds,"native":native,"display":DisplayServer.get_name(),
		"shipping_cap":arena.MAX_ENEMIES,"above_cap_test_only":count>arena.MAX_ENEMIES,"player_invulnerable_fixture":true,
		"native_driver":"One fixed simulation tick per rendered frame; production catch-up-loop feedback is deliberately excluded from this isolating probe",
		"wall_seconds":(Time.get_ticks_usec()-began)/1000000.0,"initial":initial,"buckets":buckets,"controlled_deaths":deaths,"failures":failures,
		"timing_scope":"Microseconds; nested build/save labels overlap their enclosing tick/projectile/burst phases. Software/native results are not Windows FPS."}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(record,"\t",true,true))
