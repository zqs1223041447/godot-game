extends "res://tests/formal_boss_equipment_recovery_test.gd"
const Renderer = preload("res://scripts/visuals/telegraph_renderer.gd")
const BaselineRenderer = preload("res://docs/qa/ember-warning-readability/baseline_renderer.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
var output := OS.get_environment("EMBER_WARNING_OUT")
var baseline := OS.get_environment("EMBER_WARNING_BASELINE") == "1"
var guard: Dictionary = {}
var frames: Array[Dictionary] = []
func capture(label: String) -> void:
	var states: Array = arena.telegraph_visual_states()
	var before := var_to_bytes([model.snapshot(), disk(), arena.rng.state, arena.telegraphs._states, arena.health, arena.shield, arena.burn_runtime._states])
	var primitives: Array = Renderer.primitives(states,arena.visual_settings)
	check(primitives.size() <= Renderer.MAX_PRIMITIVES_PER_SOURCE,"Bounded primitive count: " + label)
	check(var_to_bytes([model.snapshot(), disk(), arena.rng.state, arena.telegraphs._states, arena.health, arena.shield, arena.burn_runtime._states])==before,"Rendering does not mutate combat/save/RNG: " + label)
	arena.hud._refresh_world(); arena.hud._update_live()
	if DisplayServer.get_name() != "headless":
		for unused: int in range(3):
			arena.queue_redraw(); await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output+"/"+label+".png")==OK,"Native screenshot: " + label)
	frames.append({"label":label,"states":states,"primitives":primitives,"trace":arena.telegraph_trace.duplicate(true)})
func verify_art() -> void:
	var original: Dictionary=frames[1].states[0].duplicate(true)
	var untouched := 0
	for pattern: String in ["", "garden_slam", "ruins_mark", "ember_burn", "sunwell_echo", "ginkgo_shelter_slam", "ruins_garden_slam", "chaos_guard"]:
		for element: String in ["", "cold", "lightning"]:
			for effects: int in [0,1,2]:
				var state := original.duplicate(true);state.visual_pattern=pattern;state.visual_element=element
				var settings := Settings.new();settings.effects_level=effects
				var before: Array=BaselineRenderer.primitives([state],settings)
				var after: Array=Renderer.primitives([state],settings)
				check(after.size()<=before.size(),"No new primitive count: %s/%s/%d"%[pattern,element,effects])
				if pattern!="ember_burn":
					check(var_to_bytes(after)==var_to_bytes(before),"Other warning artwork byte-identical: %s/%s/%d"%[pattern,element,effects]); untouched+=1
				else:
					check(var_to_bytes(after.slice(0,3))==var_to_bytes(before.slice(0,3)),"Actual circle center, radius, fill and boundary unchanged")
					for mark: Dictionary in after:
						if mark.role not in ["rune_base","rune_charge"]:continue
						for point: Vector2 in mark.points:
							check(point.distance_to(state.center)<float(state.profile.radius),"Ember glyph stays inside true danger circle")
							if not baseline:check(point.y>state.center.y+arena.PLAYER_RADIUS,"Ember glyph leaves the central player footprint clear")
	var crowded: Array=[]
	for id: int in range(1,101):
		var state:=original.duplicate(true);state.source_id=id;crowded.append(state)
	check(Renderer.primitives(crowded).size()<=800,"Existing 100-source / 800-primitive ceiling retained")
	crowded.append(original)
	check(Renderer.primitives(crowded).is_empty(),"Oversized input still rejected as a whole")
	print("Unaffected warning combinations: ",untouched)

func prepare(offset: Vector2 = Vector2(125,0)) -> void:
	arena.enemies.clear(); arena.telegraphs.reset(); arena.telegraph_trace.clear(); arena.burn_runtime.reset()
	arena.projectiles.clear(); arena.visual_cues.reset(); arena.rings.clear(); arena.particles.clear(); arena.floating_text.clear()
	arena.invulnerable=0.0; arena.health=float(arena.get_stats().max_health); arena.shield=float(arena.get_stats().max_shield)
	guard=arena._spawn_monster("ember_guard",arena.player_pos+offset,"demo","rare",[],false)
	guard.spawn=0.0; guard.attack_timer=0.0;guard.exploration_awake=true
	arena.hud._toast.hide();arena.hud._toast_left=0.0
	arena._start_enemy_telegraphs()
	check(arena.telegraphs.active_count()==1,"Actual rare ember guard starts original locked attack")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-ember-warning-") or output.is_empty():quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	if not await fresh("ember warning visual and settlement"):quit(1);return
	arena.demo_mode=true
	arena.visual_settings.effects_level=0
	prepare()
	var policy: Dictionary=arena.Monsters.telegraph_policy(guard)
	check(guard.rarity=="rare" and policy.visual_pattern=="ember_burn", "Original rare template carries existing burn telegraph policy")
	var windup: float=policy.profile.windup_seconds
	arena._advance_enemy_telegraphs(windup*0.15)
	await capture("low-early")
	arena._advance_enemy_telegraphs(windup*0.70)
	await capture("low-late")
	arena.visual_settings.effects_level=2
	await capture("full-late")
	verify_art()
	var before: float=arena.health+arena.shield
	arena._advance_enemy_telegraphs(windup*0.15)
	check(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].applied and arena.health+arena.shield<before,"Original real impact applies once at unchanged windup")
	check(not arena.burn_runtime.is_empty(),"Original hit still attaches burn")
	await capture("impact")
	arena._advance_enemy_telegraphs(0.01)
	check(arena.telegraph_trace.size()==1,"Recovery never reapplies hit")
	prepare();var center:Vector2=arena.player_pos;arena.player_pos+=Vector2(220,0)
	arena._advance_enemy_telegraphs(windup)
	check(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].inside and arena.burn_runtime.is_empty(),"Dodge out of frozen circle avoids original hit and burn")
	arena.player_pos=center
	prepare()
	var paused: Dictionary=arena.telegraphs.state_for(guard.id)
	arena._advance_enemy_telegraphs(0.2,{guard.id:0.2})
	check(arena.telegraphs.state_for(guard.id)==paused,"Existing freeze pause keeps artwork tied to unchanged attack clock")
	guard.spawn=1.0;arena._advance_enemy_telegraphs(0.01)
	check(Renderer.primitives(arena.telegraph_visual_states()).is_empty(),"Spawn protection cancels warning without ghost mark")
	prepare();guard.health=0.0
	arena._advance_enemy_telegraphs(0.01)
	check(arena.telegraphs.active_count()==0 and Renderer.primitives(arena.telegraph_visual_states()).is_empty() and arena.telegraph_trace.is_empty(),"Dead source cancels all warning marks and hit")
	prepare();arena.enemies.clear();arena._advance_enemy_telegraphs(0.01)
	check(arena.telegraphs.active_count()==0 and Renderer.primitives(arena.telegraph_visual_states()).is_empty(),"Removed source leaves no orphan warning")
	prepare();arena.restart_run()
	check(arena.telegraphs.active_count()==0 and Renderer.primitives(arena.telegraph_visual_states()).is_empty(),"Restart clears all source warnings")
	var report := {"baseline":baseline,"checks":checks,"failures":failures,"frames":frames,"renderer":DisplayServer.get_name()}
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("Ember warning: %d checks, %d failures" % [checks,failures.size()])
	await dispose();quit(0 if failures.is_empty() else 1)
