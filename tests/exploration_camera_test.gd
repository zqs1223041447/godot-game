extends SceneTree

const View=preload("res://scripts/visuals/world_view.gd")

var checks:int=0
var failures:int=0

func _initialize()->void:
	call_deferred("run")

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+message)

func near(first:Vector2,second:Vector2)->bool:
	return first.distance_to(second)<0.025

func camera_count(arena:Node2D)->int:
	var count:int=0
	for child:Node in arena.get_children():
		if child is Camera2D:count+=1
	return count

func boundary_cases(bounds:Rect2)->Array[Dictionary]:
	var center:Vector2=bounds.get_center()
	var half_view:Vector2=Vector2(1196,462)/(2.0*0.65)
	var low:Vector2=bounds.position+half_view
	var high:Vector2=bounds.end-half_view
	return [
		{"name":"left","player":Vector2(bounds.position.x-200,center.y),"camera":Vector2(low.x,center.y)},
		{"name":"right","player":Vector2(bounds.end.x+200,center.y),"camera":Vector2(high.x,center.y)},
		{"name":"top","player":Vector2(center.x,bounds.position.y-200),"camera":Vector2(center.x,low.y)},
		{"name":"bottom","player":Vector2(center.x,bounds.end.y+200),"camera":Vector2(center.x,high.y)},
		{"name":"top left","player":bounds.position,"camera":low},
		{"name":"top right","player":Vector2(bounds.end.x,bounds.position.y),"camera":Vector2(high.x,low.y)},
		{"name":"bottom left","player":Vector2(bounds.position.x,bounds.end.y),"camera":Vector2(low.x,high.y)},
		{"name":"bottom right","player":bounds.end,"camera":high},
	]

func test_geometry()->void:
	var bounds:Rect2=View.exploration_arena()
	expect(bounds.position==Vector2(42,104),"exploration keeps the original world origin")
	expect(bounds.size==Vector2(3600,2400),"exploration measures 3600 by 2400 world units")
	expect(View.default_arena()==Rect2(Vector2(42,104),Vector2(1196,462)/0.65),"legacy fixed arena dimensions are unchanged")
	expect(near(View.from_reference(Vector2(640,335)),View.WORLD_ARENA.get_center()),"legacy reference center conversion is unchanged")
	expect(near(View.reference_to_world_size(Vector2(1196,462)),View.WORLD_ARENA.size),"legacy reference size conversion is unchanged")
	var interior:Vector2=bounds.get_center()+Vector2(150,130)
	expect(near(View.follow_position(interior,bounds),interior),"interior player follows without an offset in world space")
	var small:=Rect2(Vector2(120,250),Vector2(500,300))
	expect(near(View.follow_position(Vector2(-999,9999),small),small.get_center()),"bounds smaller than view pin both axes to their center")
	var narrow:=Rect2(Vector2(80,120),Vector2(700,2200))
	expect(near(View.follow_position(Vector2(-100,1300),narrow),Vector2(430,1300)),"a narrow map pins only the axis smaller than the view")
	expect(near(View.follow_position(Vector2(-9999,9999),View.default_arena()),View.default_arena().get_center()),"legacy arena cannot drift when passed through follow geometry")
	for sample:Dictionary in boundary_cases(bounds):
		expect(near(View.follow_position(sample.player,bounds),sample.camera),"pure geometry clamps "+str(sample.name))

func run()->void:
	test_geometry()
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size=Vector2i(1280,720)
	var arena:=Node2D.new()
	root.add_child(arena)
	var hud:=CanvasLayer.new()
	root.add_child(hud)
	var label:=Label.new()
	label.text="Exploration HUD"
	label.position=Vector2(20,18)
	label.add_theme_font_size_override("font_size",17)
	hud.add_child(label)
	var camera:Camera2D=View.setup_camera(arena)
	for frame:int in range(3):await process_frame
	var hud_transform:Transform2D=label.get_global_transform_with_canvas()
	expect(root.get_camera_2d()==camera,"setup owns the active native Camera2D")
	expect(View.setup_camera(arena)==camera and camera_count(arena)==1,"repeated legacy setup reuses a single camera")
	expect(near(View.world_to_screen(arena,View.WORLD_ARENA.get_center()),Vector2(640,335)),"fixed arena retains its original combat center")
	expect(camera.zoom==Vector2(0.65,0.65),"fixed camera retains native 0.65 zoom")
	expect(not camera.position_smoothing_enabled,"fixed camera has no position smoothing")

	var bounds:Rect2=View.exploration_arena()
	var player:Vector2=bounds.get_center()+Vector2(150,130)
	var configured:Camera2D=View.configure_camera(arena,bounds,true,player)
	expect(configured==camera and camera_count(arena)==1,"enabling exploration reuses the existing camera")
	expect(near(camera.position,player),"configure follows the supplied spawn immediately")
	expect(camera.zoom==Vector2(0.65,0.65),"exploration preserves native 0.65 zoom")
	expect(near(camera.offset,Vector2(0,25)/0.65),"camera offset preserves the combat area's HUD inset")
	expect(not camera.position_smoothing_enabled and not camera.drag_horizontal_enabled and not camera.drag_vertical_enabled,"follow has no smoothing or drag dead zone")

	for resolution:Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=resolution
		for frame:int in range(3):await process_frame
		player+=Vector2(60,-40)
		View.update_follow_camera(arena,player,bounds)
		expect(near(View.world_to_screen(arena,player),View.SCREEN_PLAYFIELD.get_center()),"interior player maps to combat center at %s"%resolution)
		var cursor:Vector2=Vector2(820,255)
		var target:Vector2=View.screen_to_world(arena,cursor)
		expect(near(View.world_to_screen(arena,target),cursor),"logical cursor roundtrips through actual canvas transform at %s"%resolution)
		var physical:Vector2=root.get_screen_transform()*cursor
		var aimed:Vector2=View.screen_to_world(arena,root.get_screen_transform().affine_inverse()*physical)
		expect(near(aimed-player,Vector2(180,-80)/0.65),"physical mouse conversion retains correct world aim at %s"%resolution)
		expect(label.get_global_transform_with_canvas()==hud_transform and label.get_theme_font_size("font_size")==17 and hud.transform==Transform2D.IDENTITY,"HUD position, canvas scale and font stay fixed at %s"%resolution)

	for sample:Dictionary in boundary_cases(bounds):
		View.update_follow_camera(arena,sample.player,bounds)
		expect(near(camera.position,sample.camera),"native camera clamps "+str(sample.name))
		var first:Vector2=View.screen_to_world(arena,View.SCREEN_PLAYFIELD.position)
		var last:Vector2=View.screen_to_world(arena,View.SCREEN_PLAYFIELD.end)
		var inside:bool=first.x>=bounds.position.x-0.025 and first.y>=bounds.position.y-0.025 and last.x<=bounds.end.x+0.025 and last.y<=bounds.end.y+0.025
		var half_view:Vector2=View.SCREEN_PLAYFIELD.size/(2.0*0.65)
		expect(inside and near(first,Vector2(sample.camera)-half_view) and near(last,Vector2(sample.camera)+half_view),"combat view reaches boundary without exposing outside blank space at "+str(sample.name))

	player=bounds.get_center()
	View.update_follow_camera(arena,player,bounds)
	player+=Vector2(175,0)
	View.update_follow_camera(arena,player,bounds)
	expect(near(View.world_to_screen(arena,player),Vector2(640,335)),"dash updates the canvas before the next process frame")
	expect(near(View.screen_to_world(arena,Vector2(770,335)),player+Vector2(200,0)),"post-dash mouse aim uses the new camera transform immediately")

	var returned:Camera2D=View.configure_camera(arena,View.default_arena(),false,Vector2(-9999,9999))
	expect(returned==camera and camera_count(arena)==1,"returning to town keeps the same single camera")
	expect(near(camera.position,View.WORLD_ARENA.get_center()) and camera.zoom==Vector2(0.65,0.65),"town resets camera position and original zoom")
	expect(near(View.world_to_screen(arena,View.WORLD_ARENA.position),View.SCREEN_PLAYFIELD.position) and near(View.world_to_screen(arena,View.WORLD_ARENA.end),View.SCREEN_PLAYFIELD.end),"town restores the exact original fixed playfield mapping")
	View.update_follow_camera(arena,bounds.end,bounds)
	expect(near(camera.position,View.WORLD_ARENA.get_center()),"per-tick follow call cannot move the fixed town camera")
	expect(label.get_global_transform_with_canvas()==hud_transform and label.get_theme_font_size("font_size")==17,"returning to town leaves HUD unchanged")

	var moved_bounds:=Rect2(Vector2(400,700),View.EXPLORATION_SIZE)
	player=moved_bounds.get_center()+Vector2(-120,140)
	View.configure_camera(arena,moved_bounds,true,player)
	expect(near(View.world_to_screen(arena,player),Vector2(640,335)),"reentering exploration replaces old bounds and follows the new spawn")
	View.update_follow_camera(arena,moved_bounds.end,moved_bounds)
	expect(near(View.screen_to_world(arena,View.SCREEN_PLAYFIELD.end),moved_bounds.end),"new exploration bounds replace the previous clamp")

	arena.position=Vector2(123,67)
	View.update_follow_camera(arena,player,moved_bounds)
	expect(near(View.world_to_screen(arena,player),Vector2(640,335)),"translated arena still centers local player using native canvas transform")
	var probe:Vector2=player+Vector2(87,-46)
	expect(near(View.screen_to_world(arena,View.world_to_screen(arena,probe)),probe),"coordinate roundtrip includes the arena's actual transform")
	arena.position=Vector2.ZERO
	expect(View.setup_camera(arena)==camera and camera_count(arena)==1,"legacy setup after exploration never creates a second camera")
	View.update_follow_camera(arena,moved_bounds.end,moved_bounds)
	expect(near(View.world_to_screen(arena,View.WORLD_ARENA.position),View.SCREEN_PLAYFIELD.position),"legacy setup also disables follow and restores default bounds")

	print("exploration_camera_test: %d checks, %d failures"%[checks,failures])
	arena.queue_free()
	hud.queue_free()
	await process_frame
	quit(1 if failures else 0)
