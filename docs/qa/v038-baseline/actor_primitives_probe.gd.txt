extends SceneTree
const MeasuredMarkers=preload("/workspace/scratch/a51485f153de/v038-diagnostics/profiled_markers.gd")
const MeasuredActor=preload("/workspace/scratch/a51485f153de/v038-diagnostics/profiled_actors.gd")
const MeasuredVisual=preload("/workspace/scratch/a51485f153de/v038-diagnostics/profiled_visuals.gd")
class Arena extends "res://scripts/main.gd":
	var measuring:=false
	var cpu_us:=0
	func _draw()->void:
		var t:=Time.get_ticks_usec()
		if measuring:
			MeasuredActor.counts.clear();MeasuredActor.timings.clear();MeasuredMarkers.width_calls=0;MeasuredMarkers.width_us=0
			MeasuredVisual.draw_scene(self,visual_settings,static_environment==null)
		else:super._draw()
		cpu_us=Time.get_ticks_usec()-t
func _initialize()->void:call_deferred("run")
func hash_bytes(value:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(value);return h.finish().hex_encode()
func run()->void:
	var output:=OS.get_environment("ACTOR_PROFILE_OUT")
	if output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v023-profile-users/v038-actor") or DisplayServer.get_name()=="headless":quit(78);return
	root.size=Vector2i(1280,720);root.title="Actor primitive diagnostic"
	var arena:=Arena.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.start_density_demo()
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.elapsed=2.0;arena.auto_fire=false
	for enemy:Dictionary in arena.enemies:enemy.flash=0.0
	for i:int in range(5):await process_frame
	arena.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	var baseline:=root.get_texture().get_image();baseline.save_png(output.trim_suffix(".json")+"-baseline.png")
	var state:PackedByteArray=var_to_bytes([arena.enemies,arena.state.snapshot(),arena.rng.state,arena.elapsed])
	arena.measuring=true
	for i:int in range(5):arena.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	var inspected:=root.get_texture().get_image();inspected.save_png(output.trim_suffix(".json")+"-instrumented.png")
	var records:Array=[]
	for i:int in range(20):
		arena.queue_redraw();var t:=Time.get_ticks_usec();await process_frame;await RenderingServer.frame_post_draw
		records.append({"draw_cpu_us":arena.cpu_us,"wall_us":Time.get_ticks_usec()-t,"width_calls":MeasuredMarkers.width_calls,"width_us":MeasuredMarkers.width_us,"count":MeasuredActor.counts.duplicate(),"nested_us":MeasuredActor.timings.duplicate(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	var result={"same_rgba":baseline.get_data()==inspected.get_data(),"baseline_sha256":hash_bytes(baseline.get_data()),"measured_sha256":hash_bytes(inspected.get_data()),"same_state":state==var_to_bytes([arena.enemies,arena.state.snapshot(),arena.rng.state,arena.elapsed]),"samples":records,"scope":"Only diagnostic copies wrap primitive functions. Full100 real catalog actors frozen at elapsed2, no simulation. Nested times overlap and include wrapping overhead. SameRGBA checked against original renderer; cloud llvmpipe only."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify({"same_rgba":result.same_rgba,"same_state":result.same_state,"frames":20}));arena.queue_free();await process_frame;quit(0 if result.same_rgba and result.same_state else 1)
