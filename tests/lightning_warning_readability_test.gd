extends "res://tests/ginkgo_west_storm_main_test.gd"
## Controlled formal-map snapshots and semantic probes, not natural combat footage.
const Renderer=preload("res://scripts/visuals/telegraph_renderer.gd")
var output:=OS.get_environment("LIGHTNING_QA_OUT")
var frames:Array=[]
func empty_art(label:String)->void:
	check(arena.telegraphs.active_count()==0 and Renderer.primitives(arena.telegraph_visual_states()).is_empty(),label)
func verify_art()->void:
	var original:Dictionary=frames[0].states[0].duplicate(true)
	var settings=arena.visual_settings
	for radius:float in [8.0,65.0,4096.0]:
		for effects:int in [0,1,2]:
			settings.effects_level=effects
			for fraction:float in [0.15,0.85]:
				var state:=original.duplicate(true);state.profile.radius=radius;state.elapsed=0.7*fraction
				var copied:PackedByteArray=var_to_bytes(state)
				var art:Array=Renderer.primitives([state],settings)
				check(var_to_bytes(state)==copied and art.size()<=8,"Read-only bounded artwork")
				for primitive:Dictionary in art:
					if primitive.kind=="circle":check(primitive.center==state.center and primitive.radius==radius,"Exact authoritative circle")
					elif primitive.role in ["rune_base","rune_charge"]:
						for point:Vector2 in primitive.points:
							check(point.distance_to(state.center)+primitive.width*0.5<radius,"Entire rune stroke stays inside true circle")
							check(point.y>state.center.y,"Rune below center")
	settings.effects_level=2
func verify_semantics()->void:
	for enemy:Dictionary in arena.enemies:enemy.speed=0.0;enemy.attack_timer=1000.0
	prepare()
	arena.tick(0.699)
	check(arena.telegraph_trace.is_empty() and arena.health==10000.0,"No early damage")
	arena.tick(0.0011)
	check(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].applied and arena.health<10000.0,"Actual strike after protection cleared")
	var shock:Dictionary=arena.shock_runtime.status_at("player",0,arena.elapsed)
	check(shock.ok and shock.active and shock.hit_damage_taken_increased==0.15,"Existing shock applied")
	arena.tick(0.01);check(arena.telegraph_trace.size()==1,"No duplicate strike")
	prepare();var start:Vector2=arena.player_pos
	Input.action_press("move_down")
	for step:int in range(30):arena.tick(1.0/60.0)
	Input.action_release("move_down")
	check(arena.player_pos.distance_to(start)>65.0+arena.PLAYER_RADIUS,"Actual input exits locked circle")
	arena.tick(0.201)
	check(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].applied and arena.health==10000.0,"Outside circle avoids damage")
	for cause:String in ["cancel","birth","death","remove"]:
		prepare()
		match cause:
			"cancel":arena.telegraphs.cancel(selected.id)
			"birth":selected.spawn=1.0
			"death":selected.health=0.0
			"remove":arena.enemies.erase(selected)
		arena._advance_enemy_telegraphs(0.01)
		empty_art("No residual artwork after "+cause)
		check(arena.telegraph_trace.is_empty(),"Cancelled attack does not hit: "+cause)
		selected.health=100.0;selected.spawn=0.0
		if cause=="remove":arena.enemies.append(selected)
	prepare();var paused:Dictionary=arena.telegraphs.state_for(selected.id)
	arena._advance_enemy_telegraphs(0.2,{selected.id:0.2})
	check(arena.telegraphs.state_for(selected.id)==paused,"Freeze preserves original charge clock")
	arena.telegraphs.reset();empty_art("Reset clears artwork")
	prepare();check(arena.telegraphs.active_count()==1,"Repeat start has one source")
	arena.health=0.0;arena._finish_player_death();empty_art("Actual player death clears artwork")
func capture(label:String)->void:
	var states:Array=arena.telegraph_visual_states()
	var before:PackedByteArray=var_to_bytes([states,arena.rng.state,arena.state.snapshot(),arena.health,arena.shield])
	var primitives:Array=Renderer.primitives(states,arena.visual_settings)
	check(before==var_to_bytes([states,arena.rng.state,arena.state.snapshot(),arena.health,arena.shield]),"Drawing does not mutate state")
	arena.hud._refresh_world();arena.hud._update_live()
	arena.View.update_follow_camera(arena,arena.player_pos,arena.ARENA)
	if DisplayServer.get_name()!="headless":
		for unused:int in range(4):arena.queue_redraw();await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"Native capture "+label)
	frames.append({"label":label,"states":states,"primitives":primitives,"traces":arena.telegraph_trace.duplicate(true)})
func enter_formal()->void:
	var ready:Dictionary=Fixture.prepare(arena.state,arena.build_save_path,2)
	check(ready.ok,"Real fixture transactions")
	for seed_value:int in range(1,17):
		arena.rng.seed=seed_value
		var plan:Dictionary=arena._prepare_camp_run(ready.profile,arena.state.normal_journey().next_run_id)
		if plan.ok and plan.spawn_records[2].template_id=="storm_skitter" and plan.roots[2].rarity=="normal":break
	check(arena.craft_normal_map("ginkgo_arcade",2,[],[],arena.map_draft().revision).ok,"Formal tier II draft")
	check(arena.start_map(arena.map_draft().revision).ok,"Formal entry")
	arena.set_process(false);arena.hud.set_process(false)
	for unused:int in range(4):arena.hud.close_panel()
	selected=actor(arena.map_spawn_records()[2].actor_id)
	check(selected.template_id=="storm_skitter","Actual formal third west root")
	arena.player_pos=selected.pos+Vector2(0,100)
	selected.spawn=0.0;selected.attack_timer=0.0;selected.exploration_awake=true
	arena.hud._toast.hide();arena.hud._toast_left=0.0
	arena._start_enemy_telegraphs()
	check(arena.telegraphs.active_count()==1,"Actual selected attack starts alone")
	var initial:Dictionary=arena.telegraphs.state_for(selected.id)
	check(initial.profile.radius==65.0 and initial.profile.windup_seconds==0.7,"Unchanged authoritative timing and radius")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-lightning-readability-") or output.is_empty():quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720);root.title="Lightning readability QA: controlled formal-map snapshots"
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	enter_formal()
	arena.visual_settings.effects_level=0
	arena._advance_enemy_telegraphs(0.105);await capture("low-early")
	arena.visual_settings.effects_level=2;await capture("full-early")
	arena.visual_settings.effects_level=0
	arena._advance_enemy_telegraphs(0.49);await capture("low-late")
	arena.visual_settings.effects_level=2;await capture("full-late")
	arena._advance_enemy_telegraphs(0.105);await capture("impact")
	check(arena.telegraph_trace.size()==1,"Exactly one settled strike")
	arena._advance_enemy_telegraphs(0.05)
	check(arena.telegraph_trace.size()==1,"No repeated recovery strike")
	verify_art()
	check(arena.telegraphs.active_count()==1,"Live warning present before town return")
	var leaving:Dictionary=arena.return_to_town(arena.world_context().revision)
	check(leaving.ok and arena.telegraphs.active_count()==0 and arena.telegraph_visual_states().is_empty(),"Actual town return clears warnings")
	enter_formal();verify_semantics()
	check(arena.return_to_town(arena.world_context().revision).ok,"Final isolated fixture cleanup")
	var report_data:Dictionary={"checks":checks,"failures":failures,"frames":frames,"renderer":DisplayServer.get_name(),"method":"Controlled snapshots in actual formal tier II Ginkgo map. Genuine fixture/prior-tier transactions and bounded seed search. Player moved next to actual third west root, birth/initial delay skipped, simulation held and existing attack advanced. Visual snapshots keep entry protection; their impact frame is not a damage proof. Later semantic probes clear protection, set QA health, and hold other actors still. No production model, damage, timing, radius or actor-art edits. Not natural combat footage."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report_data,"\t",true,true))
	print("LIGHTNING_QA checks=%d failures=%d"%[checks,failures]);arena.queue_free();quit(1 if failures else 0)
