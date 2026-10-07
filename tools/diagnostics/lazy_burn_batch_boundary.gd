extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const STEP:=1.0/60.0
var out:=OS.get_environment("V097_BOUNDARY_OUT")
var candidate:=OS.get_environment("V097_CANDIDATE")=="1"
var observations:Array=[]
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	if out.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v097-boundary-"):quit(78);return
	var klass=load("res://tools/diagnostics/lazy_burn_batch_main.gd" if candidate else "res://scripts/main.gd")
	for mode:String in ["eligible","lethal","shield","expiry","future_gate"]:
		var arena=klass.new();var state=Model.new();arena.state=state
		var folder:String="user://boundary_"+mode
		assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))==OK)
		arena.build_save_path=folder+"/build_save.json"
		assert(state.save_build(arena.build_save_path)==OK,"Fresh legal model must save before scene entry")
		root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
		arena._world_mode="normal";arena.restart_run();arena.auto_fire=false;arena.spawn_timer=100000.0
		arena.rng.seed=97000;arena.critical_runtime.reset(97001)
		arena.enemies.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.projectiles.clear()
		arena.rings.clear();arena.particles.clear();arena.floating_text.clear();arena.pickups.clear()
		arena.burn_runtime.reset();arena.feedback_runtime.reset()
		arena.invulnerable=1000.0;arena.player_pos=arena.ARENA.get_center()+Vector2(0,210)
		while arena.hud.is_blocking():arena.hud.close_panel()
		for index:int in range(3):
			var body:Dictionary=arena.monster_runtime.create_root("brute",6,arena.ARENA.get_center()+Vector2(index*40,0),"ordinary","",[],true)
			assert(not body.is_empty());arena._apply_source_actor_profile(body);body.spawn=0.0;body.shield=0.0;body.health=100.0;arena.enemies.append(body)
		var cast:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":0.1,"crit_base_chance":0.0},[]),["ember_proliferation"])
		assert(cast.ok)
		if mode=="future_gate":cast.snapshot["future_gate"]={"enabled":true}
		if mode=="shield":arena.enemies[0].shield=1.0
		if mode=="lethal":arena.enemies[1].health=0.05
		for body:Dictionary in arena.enemies:
			var duration:float=STEP if mode=="expiry" else 3.0
			var burn:Dictionary=arena.burn_runtime.apply("monster",int(body.id),0,8.0,duration,0.0,{"skill_id":"meteor","cast_id":1,"projectile_id":0,"phase":"direct","ember_generation":0,"ember_expiry":duration})
			assert(burn.ok)
		var events:Array[Dictionary]=[]
		for index:int in range(3):
			var body:Dictionary=arena.enemies[index]
			events.append({"type":"hit","sequence":index+1,"time":float(index+1)/256.0,"target_id":int(body.id),"payload":cast.packets.parent.duplicate(true),"snapshot":cast.snapshot.duplicate(true),"color":Color.ORANGE,"slow":0.0,"direction":Vector2.RIGHT,"pos":body.pos,"projectile_id":index+1,"cast_id":2,"phase":"outbound","accuracy_checked":true})
		arena.elapsed=STEP;arena._burn_step_active=true;arena._burn_step_start=0.0
		arena._begin_progress_transaction()
		assert(arena._settle_projectile_events(events,STEP))
		arena._advance_monster_burns(STEP)
		arena._burn_step_active=false;arena._end_progress_transaction()
		assert(arena.save_build())
		var observation:Dictionary=observe(arena);observations.append(observation)
		var decisions:Array=arena.shadow_batches.duplicate(true) if candidate else []
		rows.append({"mode":mode,"kills":arena.kills,"decisions":decisions})
		if candidate:
			assert(decisions.size()==1,"One actual projectile batch")
			assert(bool(decisions[0].eligible)==(mode=="eligible"),"Expected whole-batch guard choice: "+mode+" "+str(decisions))
			assert(not arena._shadow_active,"No lazy state survives the original batch exit")
		print("V097_BOUNDARY ",mode," ",rows.back())
		arena.queue_free();await process_frame
	var f:=FileAccess.open(out+".bin",FileAccess.WRITE);f.store_buffer(var_to_bytes(observations));f.close()
	f=FileAccess.open(out+".json",FileAccess.WRITE);f.store_string(JSON.stringify({"candidate":candidate,"rows":rows,"scope":"Controlled actual Main boundaries using catalog actors and legal fresh Model; explicit resource setup is a fixture, not natural encounter balance."},"\t",true,true));f.close()
	print("V097_BOUNDARY_COMPLETE");quit(0)

func observe(arena:Node)->Dictionary:
	var original:Dictionary={"enemies":arena.enemies.duplicate(true),"projectiles":arena.projectiles.duplicate(true),
		"queue":arena.monster_runtime.queue.duplicate(true),"roots":arena.monster_runtime.roots.duplicate(true),"monster_trace":arena.monster_runtime.trace.duplicate(true),
		"rng":arena.rng.state,"state":arena.state.snapshot(),"stats":arena._stats.duplicate(true),"resources":[arena.health,arena.mana,arena.shield],
		"combat":arena.combat_trace.duplicate(true),"hits":arena.damage_trace.duplicate(true),"incoming":arena.incoming_damage_trace.duplicate(true),"admission":arena.attack_admission_trace.duplicate(true),
		"burn_trace":arena.burn_trace.duplicate(true),"burns":arena.burn_runtime._states.duplicate(true),"burn_keys":arena.burn_runtime._status_keys.duplicate(),"burn_order_dirty":arena.burn_runtime._status_order_dirty,
		"ember_deaths":arena._ember_deaths.duplicate(true),"ember_projectile_clock":arena._ember_projectile_clock.duplicate(true),
		"timers":[arena.attack_timer,arena.spawn_timer,arena.damage_delay,arena.invulnerable,arena.elapsed],"cooldowns":arena.cooldowns.duplicate(true),"groups":arena.group_cooldowns.snapshot(),
		"flasks":arena.flask_runtime.snapshot(),"shock":arena.shock_runtime.statuses(arena.elapsed),"critical":arena.critical_runtime.checkpoint(),"leech":arena.leech_runtime.snapshot(),"events":arena.event_counts.duplicate(true),
		"feedback":[arena.feedback_runtime._time,arena.feedback_runtime._pending.duplicate(true),arena.feedback_runtime._visible.duplicate(true)],
		"particles":arena.particles.duplicate(true),"text":arena.floating_text.duplicate(true),"pickups":arena.pickups.duplicate(true),"rings":arena.rings.duplicate(true),
		"kills":arena.kills,"reward_kills":arena.reward_kills,"total_damage":arena.total_damage,"shots":arena.total_shots,"saves":arena.state.successful_saves,
		"disk":FileAccess.get_file_as_bytes(arena.build_save_path)}

	original["v095_latest_state"]={
		"freeze":[arena.freeze_runtime._states.duplicate(true),arena.freeze_runtime._last_settlement_at],
		"chill":[arena.chill_runtime._state.duplicate(true),arena.chill_runtime._last_settlement_at],
		"trap":[arena.trap_runtime._entries.duplicate(true),arena.trap_runtime._next_id,arena.trap_runtime._clock,arena.trap_trace.duplicate(true)],
		"telegraphs":[arena.telegraphs._states.duplicate(true),arena.telegraphs._next_attack_id,arena.telegraph_trace.duplicate(true)],
		"feedback_ids":[arena.feedback_runtime._epoch,arena.feedback_runtime._next_sequence,arena.feedback_runtime._next_id,arena.feedback_runtime._next_outcome_id,arena.feedback_runtime._next_observation_id],
		"observation_queues":[arena.feedback_runtime._outcomes.duplicate(true),arena.feedback_runtime._observation_pending.duplicate(true),arena.feedback_runtime._observation_visible.duplicate(true)],
		"shock_internal":[arena.shock_runtime._states.duplicate(true),arena.shock_runtime._previous_intervals.duplicate(true),arena.shock_runtime._discarded_until,arena.shock_runtime._status_keys.duplicate(),arena.shock_runtime._status_order_dirty],
		"leech_internal":[arena.leech_runtime._time,arena.leech_runtime._heaps.duplicate(true),arena.leech_runtime._rates.duplicate(true),arena._leech_caps.duplicate(true)],
		"flask_internal":[arena.flask_runtime._charges.duplicate(true),arena.flask_runtime._active.duplicate(true),arena.flask_runtime._charge_remainders_micro.duplicate(true)],
		"burn_flags":[arena._ember_advancing,arena._ember_defer_deaths,arena._ember_flushing,arena._burn_step_active,arena._burn_step_start,arena._burn_immunity_until,arena._burn_incoming_time],
		"projectile_ids":[arena.projectile_runtime.next_projectile_id,arena.projectile_runtime.next_cast_id,arena.projectile_runtime._sequence,arena._projectile_targets.duplicate(true)],
		"monster_next_id":arena.monster_runtime.next_id,
		"player":[arena.player_pos,arena.player_facing,arena._player_evasion_entropy,arena.hurt_flash,arena.screen_shake,arena.alive,arena.wave],
		"progress":[arena._progress_transaction_depth,arena._progress_revision,arena._progress_hud_dirty,arena._progress_save_dirty,arena._progress_save_requested,arena._progress_flushing,arena._progress_saving,arena.progress_hud_refresh_count,arena.progress_save_attempt_count,arena.progress_save_success_count],
		"world":[arena._world_mode,arena._world_revision,arena._normal_run_id,arena._normal_completion_pending,arena.run_revision,arena._simulation_accumulator,arena._autosave_timer,arena.ordinary_admissions,arena.boss_wave_pending],
		"map_queues":[arena._map_spawn_records.duplicate(true),arena._map_mechanism_config.duplicate(true),arena._map_optional_encounters.duplicate(true),arena._camp_movement.duplicate(true),arena._camp_requested.duplicate(true),arena._camp_wait_reasons.duplicate(true),arena._boss_requested],
	}
	return original
