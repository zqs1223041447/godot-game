extends SceneTree
## Focused UI integration: actual Viewport input, canonical UID and runtime charge.
var arena: Node
var checks := 0
var failures := 0
var last_pointer := Vector2.ZERO
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func frames(count: int = 3) -> void:
	for unused: int in range(count): await process_frame
func center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas()*(control.size*0.5)
func button(pos: Vector2,which: int,pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=pos;event.global_position=pos;event.button_index=which;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events();last_pointer=pos
	await process_frame
func motion(pos: Vector2,mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position=pos;event.global_position=pos;event.button_mask=mask;event.relative=pos-last_pointer
	Input.parse_input_event(event);Input.flush_buffered_events();last_pointer=pos
	await process_frame
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-root-flask-ui-"): quit(78);return
	root.size=Vector2i(1280,720)
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
	arena.set_process(false);arena.set_physics_process(false);arena.auto_fire=false;arena.demo_mode=true;arena.spawn_timer=9999.0;arena.enemies.clear()
	await frames(6);arena.hud.set_process(false)
	while arena.hud.is_blocking(): arena.hud.close_panel()
	arena.hud.open_panel("inventory");await frames()
	var panel: Control=arena.hud._inventory_panel
	check(panel._flask_targets.size()==5,"Five real inventory flask targets")
	var slots: Array=arena.state.flask_slots();var uid: String=slots[0].uid
	check(not uid.is_empty() and panel._flask_targets.flask_1.status.uid==uid,"Initial bottle uses authoritative UID")
	check(panel._flask_targets.flask_1._icon!=null,"Transparent bottle texture resolves")
	await button(center(panel._flask_targets.flask_1),MOUSE_BUTTON_RIGHT,true)
	await button(center(panel._flask_targets.flask_1),MOUSE_BUTTON_RIGHT,false)
	await frames()
	check(arena.state.location(uid).kind=="bag","Actual right click unequips to bag")
	var grid: Control=panel._grid
	var source: Vector2=grid.get_global_transform_with_canvas()*grid.item_rect(uid).get_center()
	check(grid.item_rect(uid).size.y>grid.item_rect(uid).size.x*1.8,"Bottle occupies real 1x2 footprint")
	var target: Vector2=center(panel._flask_targets.flask_3)
	await button(source,MOUSE_BUTTON_LEFT,true);await motion(target,MOUSE_BUTTON_MASK_LEFT);await frames(2)
	check(root.gui_is_dragging(),"Viewport starts an actual bottle drag")
	await button(target,MOUSE_BUTTON_LEFT,false);await frames()
	check(arena.state.location(uid)=={"kind":"flask_slot","slot_id":"flask_3"},"Drop equips same UID in third slot")
	check(not root.gui_is_dragging(),"Drop releases drag state")
	check(not panel._flask_targets.flask_1._can_drop_data(Vector2.ZERO,{"type":"unified_item","uid":"migration_gem_000001","revision":arena.state.revision(),"grab_offset":Vector2i.ZERO}),"Skill gems rejected by flask target")
	while arena.hud.is_blocking(): arena.hud.close_panel()
	arena.health=10.0;arena.mana=0.0;arena.hud._update_live();await frames()
	var hot: Control=arena.hud._flask_buttons.flask_3
	check(not hot.disabled,"Live bottle can be used when health is missing")
	var before: Dictionary=arena.state.snapshot();var saves: int=arena.state.successful_saves
	await button(center(hot),MOUSE_BUTTON_LEFT,true);await button(center(hot),MOUSE_BUTTON_LEFT,false)
	arena.hud._update_live();await frames()
	check(arena.flask_runtime.snapshot().charges_by_uid[uid]==20,"Actual HUD click spends exactly ten charge")
	check(hot.status.active and hot.disabled,"Active recovery shown and duplicate use disabled")
	check(arena.state.snapshot()==before and arena.state.successful_saves==saves,"HUD use does not write persistent state")
	check(arena.projectiles.is_empty(),"Potion click does not leak through to an attack")
	arena.tick(1.0);check(arena.health>10.0,"Clicked potion restores real health")
	var data: Dictionary=preload("res://scripts/ui/unified_item_presentation.gd").view(arena.state,uid)
	check(data.kind_label=="药剂" and data.base_stats[1].value=="10","Tooltip derives canonical use cost")
	var original: Dictionary=arena.state.snapshot()
	for viewport_size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=viewport_size;arena.hud._apply_presentation();await frames()
		var visible_rect: Rect2=root.get_visible_rect()
		var actual: Rect2=arena.hud._flask_hud_panel.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,arena.hud._flask_hud_panel.size)
		check(visible_rect.encloses(actual),"Five flask controls fit viewport %s"%viewport_size)
	check(arena.state.snapshot()==original,"Resizing flask UI leaves model untouched")
	print("Flask UI: %d checks, %d failures"%[checks,failures])
	arena.queue_free();await frames(1);quit(1 if failures else 0)
