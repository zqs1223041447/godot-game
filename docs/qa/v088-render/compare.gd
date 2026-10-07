extends SceneTree
const Main=preload("res://scripts/main.gd")
const View=preload("res://scripts/visuals/world_view.gd")
const Visuals=preload("res://scripts/visuals/arena_visuals.gd")
const Before=preload("res://docs/qa/v088-render/retained_actor_before.gd")
const After=preload("res://scripts/visuals/retained_actor_layer.gd")
var arena:Node2D
var before_layer:Node2D
var after_layer:Node2D
var original_positions:Array[Vector2]=[]
var report:Dictionary={"scope":"Serial AB then BA CPU command-submission comparison using real Main map roots frozen; all-visible case repositions the same 37 bodies as a rendering control; no GPU/FPS or natural-play claim", "cases":[]}
func _initialize()->void:call_deferred("run")
func signature()->PackedByteArray:
	return var_to_bytes([arena.enemies,arena.projectiles,arena.health,arena.mana,arena.shield,arena.elapsed,arena.rng.state,[arena.monster_runtime.roots,arena.monster_runtime.queue,arena.monster_runtime.trace,arena.monster_runtime.next_id],arena.state.snapshot(),arena.state.successful_saves])
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
func sample(label:String,position:Vector2,candidate:bool,round_index:int)->void:
	before_layer.hide();after_layer.hide()
	arena.retained_actors=after_layer if candidate else before_layer
	arena.player_pos=position
	View.update_follow_camera(arena,position,arena.ARENA)
	for i:int in range(arena.enemies.size()):arena.enemies[i].pos=original_positions[i]
	if label=="all_visible_control":
		var center:Vector2=View.visible_world_rect(arena).get_center()
		for i:int in range(arena.enemies.size()):arena.enemies[i].pos=center+Vector2((i%7-3)*115,(int(i/7)-2.5)*105)
	for unused:int in range(3):await draw_one()
	var before:PackedByteArray=signature()
	var frame:Dictionary=After._visibility_frame(arena)
	var outside:Array[int]=[]
	for enemy:Dictionary in arena.enemies:
		if not After._actor_visible(enemy,frame):outside.append(int(enemy.id))
	var initial:Dictionary=counters()
	var previous:Dictionary=initial.duplicate(true)
	var samples:Array=[]
	for unused:int in range(24):
		await draw_one()
		var limbs:=0;var shadows:=0;var bodies:=0
		var current:Dictionary=counters()
		for id:int in arena.retained_actors._pieces:
			for piece:Node2D in arena.retained_actors._pieces[id]:
				if int(current[id][str(piece.part)])==int(previous[id][str(piece.part)]):continue
				if piece.part==&"limbs":limbs+=piece.measured_usec
				elif piece.part==&"shadow":shadows+=piece.measured_usec
				else:bodies+=piece.measured_usec
		previous=current
		samples.append({"sync_us":arena.retained_actors.measured_sync_usec,"limbs_us":limbs,"shadows_us":shadows,"bodies_us":bodies,"main_prefix_us":arena._render_prefix_usec,"foreground_us":arena.foreground_layer.measured_usec})
	var final:Dictionary=counters();var deltas:Dictionary={}
	for id:int in final:
		var row:Dictionary={}
		for part:String in final[id]:row[part]=int(final[id][part])-int(initial[id][part])
		deltas[id]=row
	var hash_context:=HashingContext.new();hash_context.start(HashingContext.HASH_SHA256);hash_context.update(before)
	report.cases.append({"label":label,"candidate":candidate,"round":round_index,"actors":arena.enemies.size(),"visible_world":str(frame.rect),"outside":outside,"draw_count_delta_by_id":deltas,"samples":samples,"authoritative_state_bytes_equal":signature()==before,"state_sha256":hash_context.finish().hex_encode()})
func run()->void:
	root.size=Vector2i(1280,720)
	arena=Main.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
	arena.auto_fire=false
	if not require_ok(arena.enter_town_test(arena.world_context().revision)):return
	if not require_ok(arena.craft_map("ginkgo_arcade",[],[],arena.map_draft().revision)):return
	if not require_ok(arena.start_map(arena.map_draft().revision)):return
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	for unused:int in range(4):arena.hud.close_panel()
	after_layer=arena.retained_actors
	before_layer=Before.new();arena.add_child(before_layer);arena.move_child(before_layer,after_layer.get_index())
	for enemy:Dictionary in arena.enemies:original_positions.append(enemy.pos)
	var entry:Vector2=arena.player_pos
	Visuals.diagnostic_profile_enabled=true
	for round_index:int in range(2):
		for candidate:bool in ([false,true] if round_index==0 else [true,false]):
			await sample("authored_entry",entry,candidate,round_index)
			await sample("west_group_view",arena.ARENA.position+Vector2(950,1300),candidate,round_index)
			await sample("boss_view",arena.ARENA.position+Vector2(3180,320),candidate,round_index)
			await sample("all_visible_control",arena.ARENA.get_center(),candidate,round_index)
	Visuals.diagnostic_profile_enabled=false
	report.display_driver=DisplayServer.get_name();report.engine=Engine.get_version_info().string
	report.world_draw_count=arena._world_draw_count
	FileAccess.open(OS.get_environment("PROBE_OUT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("RENDER_PROBE_DONE ",report.world_draw_count)
	arena.queue_free();await process_frame;quit(0)
