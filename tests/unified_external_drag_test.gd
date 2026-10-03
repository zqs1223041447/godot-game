extends SceneTree
const Grid = preload("res://scripts/ui/unified_bag_grid.gd")
var checks := 0
var failures := 0
var emissions := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var grid := Grid.new()
	root.add_child(grid)
	grid.size = Vector2(520,352)
	grid.set_items([],7)
	var external := {"uid":"gear_external","size":Vector2i(2,3)}
	grid.set_external_item_resolver(func(uid: String) -> Dictionary: return external if uid == "gear_external" else {})
	grid.set_drop_validator(func(_uid: String,_destination: Dictionary,_revision: int)->bool: return true)
	grid.move_requested.connect(func(_uid: String,_destination: Dictionary,_revision: int): emissions += 1)
	await process_frame
	var data := {"type":"unified_item","uid":"gear_external","revision":7,"grab_offset":Vector2i(1,2)}
	var point := grid.cell_rect(Vector2i(6,4)).get_center()
	check(grid._can_drop_data(point,data),"equipment UID absent from bag can resolve authoritative footprint")
	check(grid._preview_destination == Vector2i(5,2),"external multi-cell offset remains exact")
	grid._notification(Control.NOTIFICATION_DRAG_BEGIN)
	grid._drop_data(point,data)
	grid._drop_data(point,data)
	check(emissions == 1,"single external drag emits once")
	grid._notification(Control.NOTIFICATION_DRAG_END)
	grid._notification(Control.NOTIFICATION_DRAG_BEGIN)
	grid._drop_data(point,data)
	check(emissions == 2,"subsequent external drag does not inherit previous one-shot latch")
	var invalid := data.duplicate()
	invalid.grab_offset = Vector2i.ZERO
	check(not grid._can_drop_data(grid.cell_rect(Vector2i(11,7)).get_center(),invalid),"external footprint bounds checked before owner")
	grid.set_items([],8)
	check(not grid._can_drop_data(point,data),"external old revision rejected")
	invalid.revision = 8
	grid.set_external_item_resolver(func(_uid: String)->Dictionary: return {"uid":"wrong","size":Vector2i.ONE})
	check(not grid._can_drop_data(point,invalid),"resolver cannot alias other UID")
	grid.set_external_item_resolver(func(_uid: String)->Dictionary: return {"uid":"gear_external","size":Vector2i(13,1)})
	check(not grid._can_drop_data(point,invalid),"invalid external dimensions rejected")
	check(external == {"uid":"gear_external","size":Vector2i(2,3)},"resolver input unchanged")
	print("Unified external drag: %d checks, %d failures" % [checks,failures])
	grid.queue_free()
	await process_frame
	quit(1 if failures else 0)
func check(ok: bool,label: String)->void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
