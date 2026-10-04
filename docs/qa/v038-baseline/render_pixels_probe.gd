extends SceneTree
class Arena extends "res://scripts/main.gd":
	var draw_us:=0
	func _draw()->void:
		var t:=Time.get_ticks_usec();super._draw();draw_us=Time.get_ticks_usec()-t
func _initialize()->void:call_deferred("run")
func materials(node:Node,result:Dictionary)->void:
	if node is CanvasItem and node.material!=null:
		var key:=str(node.material.get_rid());result.all[key]=true
		if node.is_visible_in_tree():result.visible[key]=true
	for child:Node in node.get_children():materials(child,result)
func run()->void:
	var output:=OS.get_environment("PIXEL_PROFILE_OUT")
	if output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v023-profile-users/v038-pixel") or DisplayServer.get_name()=="headless":quit(78);return
	root.title="Actual viewport pixel diagnostic"
	var arena:=Arena.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.start_density_demo()
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.elapsed=2.0;arena.auto_fire=false
	var rows:Array=[]
	for dimensions:Vector2i in [Vector2i(1280,720),Vector2i(640,360)]:
		root.size=dimensions
		for i:int in range(5):arena.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		var image:Image=root.get_texture().get_image();var actual:=image.get_size()
		var m:Dictionary={"all":{},"visible":{}};materials(arena,m)
		var samples:Array=[]
		for i:int in range(20):
			arena.queue_redraw();var t:=Time.get_ticks_usec();await process_frame;await RenderingServer.frame_post_draw
			samples.append({"draw_cpu_us":arena.draw_us,"wall_us":Time.get_ticks_usec()-t,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		rows.append({"requested_size":[dimensions.x,dimensions.y],"actual_render_pixels":[actual.x,actual.y],"custom_materials_total":m.all.size(),"custom_materials_visible":m.visible.size(),"samples":samples})
	var result={"source":"f074c2614540f0842964ced961b3430871adce57","scope":"Same frozen100 actors; actual viewport image dimensions verified, 20frames per1280x720 and640x360. Software renderer/driver wait confounds remain; no hardware GPU/FPS inference. Custom material count includes only explicit material resources, not engine default materials.","samples":rows}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify({"pixel_probe_complete":true}));arena.queue_free();await process_frame;quit()
