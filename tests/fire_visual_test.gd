extends SceneTree
const View=preload("res://scripts/visuals/world_view.gd")
const Markers=preload("res://scripts/visuals/world_markers.gd")
const Catalog=preload("res://scripts/monsters/monster_catalog.gd")
const Preferences=preload("res://scripts/visuals/visual_settings.gd")
class Surface extends Node2D:
	const ARENA=View.WORLD_ARENA
	var player_pos:Vector2=ARENA.get_center()
	var demo_mode:bool=false
	var _font:Font=load("res://assets/fonts/arena_sans.otf")
var checks:int=0
var failures:int=0
func _initialize()->void: call_deferred("run")
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: ",label)
func run()->void:
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var arena:=Surface.new()
	root.add_child(arena)
	View.setup_camera(arena)
	var prefs:=Preferences.new()
	var enemy:Dictionary=Catalog.make_enemy(1,"ember_guard",3,View.from_reference(Vector2(640,340)),"ordinary")
	expect(enemy.radius==22.0,"art retains actual 22-unit collision radius")
	expect(Markers.caption(enemy).contains("火抗25%"),"effective catalog fire resistance is visible")
	var counterfactual:Dictionary=enemy.duplicate(true)
	counterfactual.resistances.fire=0.4
	expect(Markers.caption(counterfactual).contains("火抗40%"),"marker reads effective data without template hardcode")
	counterfactual.resistances={}
	expect(not Markers.caption(counterfactual).contains("火抗"),"no fire marker is claimed without effective resistance")
	var before:Dictionary=enemy.duplicate(true)
	for resolution:Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=resolution
		for i:int in range(4): await process_frame
		for font_scale:float in [1.0,1.2]:
			prefs.font_scale=font_scale
			for point:Vector2 in [Vector2(43,105),Vector2(1237,105),Vector2(43,565),Vector2(1237,565),Vector2(640,335)]:
				var copy:Dictionary=enemy.duplicate(true)
				copy.pos=View.from_reference(point)
				var rect:Rect2=Markers.name_rect(arena,copy,prefs)
				expect(rect.position.x>=View.SCREEN_PLAYFIELD.position.x-0.1 and rect.end.x<=View.SCREEN_PLAYFIELD.end.x+0.1,"expanded fire name stays horizontally in world viewport")
				expect(rect.position.y>=View.SCREEN_PLAYFIELD.position.y-0.1,"fire name top clamp")
			var crowd:Array=[]
			for i:int in range(100):
				var copy:Dictionary=enemy.duplicate(true)
				copy.id=i+1
				copy.pos=View.from_reference(Vector2(100+i%10*112,170+int(i/10)*38))
				crowd.append(copy)
			var names:Dictionary=Markers.name_ids(arena,crowd,prefs)
			expect(names.size()<=Markers.MAX_FULL_NAMES,"fire names preserve eight-name crowd budget")
			var accepted:Array[Rect2]=[]
			for actor:Dictionary in crowd:
				if not names.has(actor.id): continue
				var rect:Rect2=Markers.name_rect(arena,actor,prefs)
				for previous:Rect2 in accepted: expect(not previous.grow(2).intersects(rect),"fire-resistance captions never overlap accepted names")
				accepted.append(rect)
	expect(enemy==before,"readability layer leaves catalog instance untouched")
	print("fire_visual_test: %d checks, %d failures"%[checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
