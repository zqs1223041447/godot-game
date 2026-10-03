extends SceneTree
## Exact native raster comparison against the frozen v0.22 actor renderer.
const Before = preload("res://tests/fixtures/performance/fantasy_actors_v022.gd")
const After = preload("res://scripts/visuals/fantasy_actors.gd")
const Preferences = preload("res://scripts/visuals/visual_settings.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
class Sheet extends Node2D:
	var renderer: Script
	var fixtures: Array = []
	var elapsed := 0.0
	var player_pos := Vector2.ZERO
	var demo_mode := false
	var preferences := Preferences.new()
	func _draw() -> void:
		for i: int in fixtures.size():
			var fixture: Dictionary = fixtures[i]
			var enemy: Dictionary = fixture.enemy.duplicate(true)
			enemy.pos = Vector2(64+(i%10)*128,64+int(i/10)*128)
			player_pos = enemy.pos + Vector2.RIGHT.rotated(fixture.angle)*100
			elapsed = fixture.elapsed
			preferences.motion = fixture.motion
			renderer.draw_enemy(self,enemy,preferences,false)
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("This test requires real raster rendering; headless is not a pixel pass");quit(78);return
	var output := OS.get_environment("ACTOR_PIXEL_OUT")
	if output.is_empty(): quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,768);root.title="Exact actor contour comparison"
	var views: Array[SubViewport]=[]
	var sheets: Array[Sheet]=[]
	for side: int in 2:
		var viewport := SubViewport.new();viewport.size=Vector2i(1280,768)
		viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(viewport);views.append(viewport)
		var sheet:=Sheet.new();sheet.renderer=Before if side==0 else After
		viewport.add_child(sheet);sheets.append(sheet)
		var image:=TextureRect.new();image.texture=viewport.get_texture()
		image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.position=Vector2(side*640,0);image.size=Vector2(640,768);root.add_child(image)
	var fixtures: Array=[]
	for species: String in ["crawler","skitter","brute","ember_guard","rift_warden"]:
		for radius: float in [12.0,22.0,36.125]:
			for motion: bool in [false,true]:
				for hurt: bool in [false,true]:
					for angle: int in 6:
						var enemy:=Monsters.make_enemy(fixtures.size()+1,species,1,Vector2.ZERO,"map_boss" if species=="rift_warden" else "demo","boss" if species=="rift_warden" else ("rare" if species=="ember_guard" else "normal"),[])
						if enemy.is_empty(): push_error("Catalog fixture rejected: "+species);quit(1);return
						enemy.radius=radius;enemy.flash=0.1 if hurt else 0.0
						fixtures.append({"enemy":enemy,"motion":motion,"angle":angle*TAU/6.0,"elapsed":0.137*fixtures.size()})
	var records: Array=[]
	# Two passes exercise reuse as well as first population. The independent source
	# renderer receives identical copies and does not share the new contour cache.
	for iteration: int in 2:
		for first: int in range(0,fixtures.size(),60):
			var page: Array=fixtures.slice(first,mini(first+60,fixtures.size()))
			var original:=var_to_bytes(page)
			for sheet: Sheet in sheets: sheet.fixtures=page;sheet.queue_redraw()
			seed(230023);var expected_rng:=randi();seed(230023)
			await process_frame;await RenderingServer.frame_post_draw
			var a:=views[0].get_texture().get_image();var b:=views[1].get_texture().get_image()
			expect(a.get_data()==b.get_data(),"Exact RGBA equality page %d pass %d"%[first,iteration])
			expect(var_to_bytes(page)==original and randi()==expected_rng,"No input or RNG mutation")
			expect(After._contour_cache.size()<=After.CONTOUR_CACHE_LIMIT,"Cache size is bounded")
			var record:={"first":first,"iteration":iteration,"equal":a.get_data()==b.get_data(),"before_sha":sha(a.get_data()),"after_sha":sha(b.get_data()),"cache_entries":After._contour_cache.size()}
			records.append(record)
			if iteration==0:
				a.save_png(output+"/before-%03d.png"%first);b.save_png(output+"/after-%03d.png"%first)
	# Force more exact radii than the bound. The result must still match after FIFO eviction.
	for index: int in 300:
		var item: Dictionary=fixtures[index%fixtures.size()].duplicate(true)
		item.enemy.radius=12.0+index*0.06125
		sheets[1].fixtures=[item];sheets[1].queue_redraw()
		await process_frame
	expect(After._contour_cache.size()==After.CONTOUR_CACHE_LIMIT,"Distinct radii cannot grow the cache beyond its hard bound")
	for sheet: Sheet in sheets:sheet.fixtures=fixtures.slice(0,60);sheet.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	expect(views[0].get_texture().get_image().get_data()==views[1].get_texture().get_image().get_data(),"Eviction preserves exact raster output")
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"fixtures":fixtures.size(),"checks":checks,"failures":failures,"records":records},"\t"))
	print("Actor contour pixels: %d fixtures, %d checks, %d failures"%[fixtures.size(),checks,failures])
	quit(1 if failures else 0)
func sha(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
