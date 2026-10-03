extends SceneTree
const Passives=preload("res://scripts/passive_data.gd")
const Model=preload("res://scripts/build_state.gd")
var arena:Node2D
var panel:PassivePanel
var directory:String=OS.get_environment("GODOT_VISUAL_QA_DIR")
func _initialize()->void: call_deferred("run")
func path_to(target:String)->Array[String]:
	var queue:Array[String]=["origin"]
	var previous:Dictionary={"origin":""}
	while not queue.is_empty():
		var id:String=queue.pop_front()
		if id==target:
			var path:Array[String]=[]
			while id!="":
				path.push_front(id)
				id=previous[id]
			return path
		for next:String in Passives.get_neighbors(id):
			if not previous.has(next): previous[next]=id; queue.append(next)
	return []
func capture(label:String)->void:
	arena.queue_redraw()
	for i:int in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label+".png"))
	print("SPECIAL_CAPTURE ",label," remote=",panel.tree_view._analysis.remote_nodes," names=",panel._node_type.text," remove_disabled=",panel._remove_button.disabled)
func run()->void:
	if directory.is_empty(): directory="user://special-jewel-qa"
	DirAccess.make_dir_recursive_absolute(directory)
	root.position=Vector2i.ZERO
	root.size=Vector2i(2560,1440)
	# Run only with disposable user data, as all scene QA harnesses do.
	assert(Model.new().save_build()==OK)
	arena=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.state.refund_talents()
	arena.state.talent_points=60
	var special:String=arena.state.award_special_jewel()
	arena.visual_settings.ui_scale=1.0
	arena.visual_settings.font_scale=1.0
	arena.hud._apply_presentation()
	arena.hud.open_panel("talents")
	panel=arena.hud.find_child("PassiveTreePanel",true,false)
	panel.select_node("ember_3_0")
	panel.select_jewel(special)
	panel.tree_view.center_on_node("ember_3_0")
	await capture("special-2k-inactive-preview")
	for id:String in path_to("ember_3_0"):
		if id!="origin": assert(arena.state.allocate_passive(id))
	panel.select_node("ember_3_0")
	panel.select_jewel(special)
	assert(panel.insert_selected_jewel())
	var remote:String=""
	for id:String in panel.tree_view._analysis.granted_by:
		if arena.state.allocated_nodes.has(id): continue
		var touches:bool=false
		for neighbor:String in Passives.get_neighbors(id):
			if panel.tree_view._analysis.connected.has(neighbor): touches=true
		if not touches: remote=id; break
	assert(not remote.is_empty())
	panel.select_node(remote)
	assert(panel.allocate_selected())
	await capture("special-2k-remote-allocated")
	panel.select_node("ember_3_0")
	await capture("special-2k-protected-removal")
	for size:Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=size
		arena.visual_settings.ui_scale=1.1
		arena.visual_settings.font_scale=1.2
		arena.hud._apply_presentation()
		await capture("special-%d-maxfont"%size.x)
	print("SPECIAL_VISUAL_COMPLETE")
	if OS.get_environment("GODOT_VISUAL_QA_INTERACTIVE")=="1":
		root.size=Vector2i(1280,720)
		arena.visual_settings.ui_scale=1.0
		arena.visual_settings.font_scale=1.0
		arena.hud._apply_presentation()
		print("SPECIAL_INTERACTIVE_READY remote=",remote)
	else:
		quit()
