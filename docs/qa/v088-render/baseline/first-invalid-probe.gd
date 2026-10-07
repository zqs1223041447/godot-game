extends SceneTree
const Main=preload("res://scripts/main.gd")
const View=preload("res://scripts/visuals/world_view.gd")
const Visuals=preload("res://scripts/visuals/arena_visuals.gd")
var arena:Node2D
var report:Dictionary={"scope":"Read-only production CPU draw submission, actual test-town map roots frozen; no gameplay optimization, GPU/FPS or natural-play assertion", "cases":[]}
func _initialize()->void:call_deferred("run")
func signature()->PackedByteArray:
	return var_to_bytes([arena.enemies,arena.projectiles,arena.health,arena.mana,arena.shield,arena.elapsed,arena.rng.state,arena.monster_runtime.checkpoint(),arena.state.snapshot(),arena.state.successful_saves])
func require_ok(result:Dictionary)->bool:
	if not result.get("ok",false):printerr(result);quit(1);return false
	return true
func counters()->Dictionary:
	var by_id:Dictionary={}
	for id:int in arena.retained_actors._pieces:
		var row:Dictionary={}
		for piece:Node2D in arena.retained_actors._pieces[id]:row[str(piece.part)]=piece.draw_count
		by_id[id]=row
	return by_id
func draw_one()->void:
	arena.queue_redraw()
	await process_frame
	RenderingServer.force_draw(false)
func sample(label:String,position:Vector2)->void:
	arena.player_pos=position
	View.update_follow_camera(arena,position,arena.ARENA)
	for unused:int in range(3):await draw_one()
	var before:PackedByteArray=signature()
	var visible:Rect2=View.visible_world_rect(arena)
	var padded:Rect2=visible.grow(140.0)
	var inside:Array[int]=[]
	var outside:Array[int]=[]
	for enemy:Dictionary in arena.enemies:
		if padded.has_point(enemy.pos):inside.append(int(enemy.id))
		else:outside.append(int(enemy.id))
	var initial:Dictionary=counters()
	var samples:Array=[]
	for unused:int in range(24):
		await draw_one()
		var limbs:=0;var shadows:=0;var bodies:=0
		for group:Array in arena.retained_actors._pieces.values():
			for piece:Node2D in group:
				if piece.part==&"limbs":limbs+=piece.measured_usec
				elif piece.part==&"shadow":shadows+=piece.measured_usec
				else:bodies+=piece.measured_usec
		samples.append({"sync_us":arena.retained_actors.measured_sync_usec,"limbs_us":limbs,"shadows_us":shadows,"main_prefix_us":arena._render_prefix_usec,"foreground_us":arena.foreground_layer.measured_usec,"markers_us":Visuals.diagnostic_frame_usec.get("markers",-1)})
	var final:Dictionary=counters();var deltas:Dictionary={}
	for id:int in final:
		var row:Dictionary={}
		for part:String in final[id]:row[part]=int(final[id][part])-int(initial[id][part])
		deltas[id]=row
	report.cases.append({"label":label,"actors":arena.enemies.size(),"viewport":str(root.get_visible_rect()),"visible_world":str(visible),"conservative_padding_world":140.0,"inside_padded":inside,"outside_padded":outside,"draw_count_delta_by_id":deltas,"samples":samples,"authoritative_state_bytes_equal":signature()==before})
func run()->void:
	root.size=Vector2i(1280,720)
	arena=Main.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
	arena.auto_fire=false
	if not require_ok(arena.enter_town_test(arena.world_context().revision)):return
	if not require_ok(arena.craft_map("ginkgo_arcade",[],[],arena.map_draft().revision)):return
	if not require_ok(arena.start_map(arena.map_draft().revision)):return
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for unused:int in range(4):arena.hud.close_panel()
	Visuals.diagnostic_profile_enabled=true
	await sample("authored_entry",arena.player_pos)
	await sample("west_group_view",arena.ARENA.position+Vector2(950,1300))
	await sample("boss_view",arena.ARENA.position+Vector2(3180,320))
	Visuals.diagnostic_profile_enabled=false
	report.display_driver=DisplayServer.get_name();report.engine=Engine.get_version_info().string
	report.world_draw_count=arena._world_draw_count
	FileAccess.open(OS.get_environment("PROBE_OUT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("RENDER_PROBE_DONE ",report.world_draw_count)
	arena.queue_free();await process_frame;quit(0)
