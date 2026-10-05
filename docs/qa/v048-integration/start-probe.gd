extends SceneTree
func _initialize()->void:call_deferred('run')
func run()->void:
 var a:Node=load('res://scenes/main.tscn').instantiate();root.add_child(a);await process_frame;a.set_process(false);a.hud.set_process(false)
 var enter:Dictionary=a.enter_town_test(a.world_context().revision)
 var craft:Dictionary=a.craft_map('sunwell_terrace',[],[],a.map_draft().revision)
 var started:Dictionary=a.start_map(a.map_draft().revision)
 print(JSON.stringify({'enter':enter.ok,'craft':craft.ok,'start':started.ok,'reason':started.get('reason',''),'schema':a.state.snapshot().version,'walls':a.world_geometry().walls.size(),'landmarks':a.world_geometry().landmarks.camps.size()}))
 var ok:bool=enter.ok and craft.ok and started.ok;a.queue_free();await process_frame;quit(0 if ok else 1)
