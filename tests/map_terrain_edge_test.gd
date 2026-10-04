extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	arena.enter_town_test(arena.world_context().revision);arena.craft_map("broken_ruins",[],[],arena.map_draft().revision);arena.start_map(arena.map_draft().revision)
	arena.enemies.clear();arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var wall:Rect2=arena.world_geometry().walls[0]
	arena.player_pos=Vector2(wall.position.x-30,wall.position.y+60);arena.player_facing=Vector2(1,-0.5).normalized()
	check(arena._execute_compiled(Compiler.compile_skill("meteor",arena.state.get_combat_snapshot(),[])),"No-target meteor still admits normally")
	var found:=false
	for cue:Dictionary in arena.visual_cues.cues:
		if cue.kind=="meteor":
			found=true;check(arena._geometry.visible(arena.player_pos,cue.origin),"Meteor fallback stops on original visible ray instead of sliding to an occluded endpoint")
	check(found,"Actual cast emitted meteor at settled center")
	var revision:int=arena.world_geometry().revision
	arena.restart_run();check(arena.world_geometry().revision==revision,"Same-map retry keeps geometry revision and does not invalidate drawing cache")
	arena._map_run.admitted.clear();arena._map_run.defeated.clear()
	check(arena.return_to_town(arena.world_context().revision).ok,"Return uses existing save gate")
	check(arena.world_geometry().revision>revision and arena.static_environment.world_geometry()==arena.world_geometry(),"Return invalidates retained obstacle drawing")
	print("Map terrain edges: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
