extends SceneTree
const View=preload("res://scripts/visuals/world_view.gd")
const Markers=preload("res://scripts/visuals/world_markers.gd")
const Preferences=preload("res://scripts/visuals/visual_settings.gd")
class ArenaStub extends Node2D:
	const ARENA=View.WORLD_ARENA
	var player_pos:Vector2=ARENA.get_center()
	var demo_mode:bool=false
	var _font:Font=load("res://assets/fonts/arena_sans.otf")
var checks:int=0
var failures:int=0
func _initialize()->void:
	call_deferred("run")
func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+message)
func run()->void:
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var arena:=ArenaStub.new()
	root.add_child(arena)
	var hud:=CanvasLayer.new()
	root.add_child(hud)
	var label:=Label.new()
	label.text="UI 字号不变"
	label.add_theme_font_size_override("font_size",17)
	label.position=Vector2(20,18)
	hud.add_child(label)
	var camera:Camera2D=View.setup_camera(arena,View.default_arena())
	var baseline:Rect2=label.get_global_rect()
	var preferences:=Preferences.new()
	for resolution:Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=resolution
		camera.force_update_scroll()
		for i:int in range(5): await process_frame
		expect(root.get_visible_rect().size.is_equal_approx(View.REFERENCE_SIZE),"logical viewport stays fixed %s"%resolution)
		expect(label.position==Vector2(20,18) and label.get_theme_font_size("font_size")==17,"HUD position/font independent %s"%resolution)
		expect(is_equal_approx(camera.zoom.x,0.65),"native world camera zoom %s"%resolution)
		var first:Vector2=View.world_to_screen(arena,View.WORLD_ARENA.position)
		var last:Vector2=View.world_to_screen(arena,View.WORLD_ARENA.end)
		expect(first.distance_to(View.SCREEN_PLAYFIELD.position)<0.02 and last.distance_to(View.SCREEN_PLAYFIELD.end)<0.02,"real arena maps to unchanged playfield %s %s %s"%[resolution,first,last])
		var visible:Rect2=View.visible_world_rect(arena)
		expect(visible.size.distance_to(View.REFERENCE_SIZE/0.65)<0.02,"world field of view expands %s"%resolution)
		for x:int in range(9):
			for y:int in range(7):
				var point:=View.WORLD_ARENA.position+Vector2(x*241-40,y*139-60)
				var screen:Vector2=View.world_to_screen(arena,point)
				expect(View.screen_to_world(arena,screen).distance_to(point)<0.02,"screen/world roundtrip %s"%resolution)
		var enemies:Array=[]
		for i:int in range(100):
			var pos:=View.from_reference(Vector2(100+(i%10)*114,160+(i/10)*39))
			enemies.append({"id":i+1,"pos":pos,"radius":22.0,"rarity":"rare","name":"重壳体","health":100.0,"max_health":100.0})
		var before:Array=enemies.duplicate(true)
		var names:Dictionary=Markers.name_ids(arena,enemies,preferences)
		expect(names.size()<=Markers.MAX_FULL_NAMES,"100 enemies do not flood full names")
		var rectangles:Array[Rect2]=[]
		for enemy:Dictionary in enemies:
			if not names.has(enemy.id): continue
			var rect:Rect2=Markers.name_rect(arena,enemy,preferences)
			for other:Rect2 in rectangles:
				expect(not other.grow(2).intersects(rect),"accepted full names do not overlap")
			rectangles.append(rect)
		expect(enemies==before,"name planning never mutates enemies")
		preferences.font_scale=1.2
		var big_names:Dictionary=Markers.name_ids(arena,enemies,preferences)
		expect(big_names.size()<=Markers.MAX_FULL_NAMES,"large font preserves name budget")
		preferences.font_scale=1.0
	var before_label:Rect2=label.get_global_rect()
	camera.position+=Vector2(123,67)
	camera.force_update_scroll()
	await process_frame
	expect(label.get_global_rect()==before_label,"camera movement cannot move HUD")
	expect(View.from_reference(View.SCREEN_PLAYFIELD.get_center()).distance_to(View.WORLD_ARENA.get_center())<0.02,"reference center mapping exact")
	expect(is_equal_approx(View.WORLD_ARENA.get_area()/View.SCREEN_PLAYFIELD.get_area(),1.0/(0.65*0.65)),"world area is 2.3669 times original")
	print("world_view_test: %d checks, %d failures"%[checks,failures])
	arena.queue_free()
	hud.queue_free()
	await process_frame
	quit(1 if failures else 0)
