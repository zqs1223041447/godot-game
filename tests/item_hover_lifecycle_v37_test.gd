extends SceneTree
## Real main/HUD using synthetic engine mouse events; not native desktop input.
var arena:Node
var checks:=0
var failures:=0
var pointer:=Vector2.ZERO
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func frames(n:int=3)->void:
	for i:int in range(n):await process_frame
func motion(at:Vector2,mask:int=0)->void:
	var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.relative=at-pointer;event.button_mask=mask
	Input.parse_input_event(event);Input.flush_buffered_events();pointer=at;await frames()
func button(at:Vector2,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events();pointer=at;await frames()
func center(control:Control)->Vector2:return control.get_global_transform_with_canvas()*(control.size*0.5)
func bag_center(grid:Control,uid:String)->Vector2:return grid.get_global_transform_with_canvas()*grid.item_rect(uid).get_center()
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	root.size=Vector2i(1280,720);arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);await frames(6)
	var model=arena.state;var source:String=model.award_gem("support:chain_extension");var other:String=model.award_gem("skill:bolt")
	check(not source.is_empty() and not other.is_empty(),"Two real independent item identities created in isolated fixture")
	check(model.move_item(source,{"kind":"bag","page":1,"x":11,"y":6},model.revision(),"user://build_save.json").ok and model.move_item(other,{"kind":"bag","page":1,"x":8,"y":6},model.revision(),"user://build_save.json").ok,"Real source and potential underlying UID placed through canonical transfer")
	arena.hud.handle_menu_key(KEY_I,true,false);await frames(5)
	var panel:Control=arena.hud._inventory_panel;var grid:Control=panel._grid;var next:Control=panel.find_child("NextBagPage",true,false)
	await motion(center(next));await button(center(next),true);await button(center(next),false);check(grid.bag_page()==1,"Actual page control shows the fixture bag page")
	var before:Dictionary=model.snapshot();var source_point:=bag_center(grid,source);var other_point:=bag_center(grid,other)
	await motion(source_point);check(arena.hud._hover_uid==source and arena.hud._item_hover.visible,"Real bag mouse-enter opens the source UID card")
	# The card can sit above the source; choose a real empty cell under its BODY,
	# rather than assuming another item on the same row is covered.
	var body:Control=arena.hud._item_hover.find_child("ItemDetailsScroll",true,false)
	var rectangle:Rect2=grid.grid_rect();var cell:Vector2=rectangle.size/Vector2(grid.grid_columns(),grid.grid_rows());var placed:=false
	for y:int in range(grid.grid_rows()):
		for x:int in range(grid.grid_columns()):
			var at:Vector2=grid.get_global_transform_with_canvas()*(rectangle.position+Vector2(x+0.5,y+0.5)*cell)
			var in_body:bool=Rect2(Vector2.ZERO,body.size).has_point(body.get_global_transform_with_canvas().affine_inverse()*at)
			if in_body and arena.hud._item_hover.contains_viewport_point(at) and model.move_item(other,{"kind":"bag","page":1,"x":x,"y":y},model.revision(),"user://build_save.json").ok:
				placed=true;break
		if placed:break
	check(placed,"Fixture placed a real second UID under the currently measured card body")
	await motion(Vector2(30,650));await create_timer(0.24).timeout;await motion(source_point)
	before=model.snapshot();other_point=bag_center(grid,other)
	check(arena.hud._item_hover.contains_viewport_point(other_point),"Underlying other UID is physically inside the displayed transparent card")
	await motion(other_point);check(grid._hovered_uid==other,"Engine pointer really enters the different underlying bag item")
	check(arena.hud._hover_uid==source and arena.hud._item_hover._last_view.uid==source,"Transparent card prevents underlying enter from replacing its stable UID")
	await create_timer(0.24).timeout;check(arena.hud._item_hover.visible and arena.hud._hover_uid==source,"Pointer staying over card survives source exit delay")
	await motion(Vector2(30,650));await create_timer(0.24).timeout
	check(not arena.hud._item_hover.visible and arena.hud._hover_uid.is_empty(),"Leaving both source/card clears old identity after the normal delay")
	await motion(source_point);check(arena.hud._hover_uid==source,"Source can open a fresh view after dismissal")
	await button(source_point,true);await motion(source_point+Vector2(-24,-18),MOUSE_BUTTON_MASK_LEFT)
	check(root.gui_is_dragging(),"Real engine press-motion crosses the item drag threshold")
	check(not arena.hud._item_hover.visible and arena.hud._hover_uid.is_empty(),"Drag start clears hover rather than retaining stale content")
	await motion(Vector2(30,650),MOUSE_BUTTON_MASK_LEFT);await button(Vector2(30,650),false)
	check(not root.gui_is_dragging() and model.snapshot()==before,"Canceling the outside drop preserves every owned location and snapshot field")
	await motion(source_point);check(arena.hud._item_hover.visible and arena.hud._hover_uid==source,"A new hover works after drag end")
	arena.hud.handle_menu_key(KEY_I,true,false);await frames()
	check(not arena.hud._item_hover.visible and arena.hud._hover_uid.is_empty(),"Closing inventory clears shared card and UID")
	check(model.snapshot()==before,"Hover lifecycle and canceled drag do not mutate gameplay state")
	print("Item hover lifecycle v37: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
