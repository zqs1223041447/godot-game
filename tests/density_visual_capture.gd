extends SceneTree
## Native-display QA. Uses production AI, casts and collision, with no actor stat edits.
## The final prolonged grouping fixture protects only the player and reports this explicitly.
const View=preload("res://scripts/visuals/world_view.gd")
const Markers=preload("res://scripts/visuals/world_markers.gd")
var arena:Node2D
var directory:String=OS.get_environment("GODOT_VISUAL_QA_DIR")
var records:Array[Dictionary]=[]
func _initialize()->void:
	call_deferred("run")
func settle()->void:
	arena.queue_redraw()
	for i:int in range(6): await process_frame
	await RenderingServer.frame_post_draw
func capture(label:String)->void:
	arena.hud._update_live()
	await settle()
	root.get_texture().get_image().save_png(directory.path_join(label+".png"))
	var wave:Label=arena.hud.find_child("WaveLabel",true,false)
	var record:Dictionary={"label":label,"alive":arena.alive,"live":arena.enemies.size(),"time":arena.elapsed,"health":arena.health,"shield":arena.shield,"shots":arena.total_shots,"damage_records":arena.damage_trace.size(),"projectiles":arena.projectiles.size(),"cues":arena.visual_cues.cues.size(),"labels":Markers.name_ids(arena,arena.enemies,arena.visual_settings).size(),"player_invulnerable":arena.invulnerable,"wave_text":wave.text,"wave_size":str(wave.size),"wave_minimum":str(wave.get_minimum_size()),"world_visible":str(View.visible_world_rect(arena))}
	records.append(record)
	print("DENSITY_CAPTURE ",JSON.stringify(record))
func steps(count:int)->void:
	for i:int in range(count): arena.tick(1.0/60.0)
func fresh()->void:
	arena.start_density_demo()
	arena.hud.close_panel()
	arena.hud._toast_left=0.0
	arena.hud._toast.hide()
	arena.rng.seed=810082
func run()->void:
	if directory.is_empty(): directory="user://density-visual-qa"
	DirAccess.make_dir_recursive_absolute(directory)
	root.position=Vector2i.ZERO
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.visual_settings.motion=false
	arena.visual_settings.ui_scale=1.0
	arena.visual_settings.font_scale=1.0
	arena.visual_settings.effects_level=2
	arena.hud._apply_presentation()
	for size:Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=size
		fresh()
		await capture("density-%d-initial-100"%size.x)
		var positions:Dictionary={}
		for enemy:Dictionary in arena.enemies: positions[enemy.id]=enemy.pos
		steps(72)
		var moved:int=0
		for enemy:Dictionary in arena.enemies:
			if Vector2(enemy.pos).distance_to(positions[enemy.id])>0.01: moved+=1
		print("DENSITY_AI_MOVED ",size," ",moved," /100; player health=",arena.health," shield=",arena.shield)
		arena.auto_fire=true
		arena.cast_skill(0)
		steps(8)
		await capture("density-%d-ai-and-projectiles"%size.x)
		arena.visual_settings.effects_level=0
		await capture("density-%d-ai-and-projectiles-low"%size.x)
		arena.visual_settings.effects_level=2
		steps(24)
		await capture("density-%d-real-hits"%size.x)
		arena.visual_settings.effects_level=0
		await capture("density-%d-real-hits-low"%size.x)
		arena.visual_settings.effects_level=2
	# Long grouping intentionally protects only the player; enemy values remain catalog values.
	fresh()
	arena.invulnerable=30.0
	steps(240)
	await capture("density-2560-grouped-100-player-protected")
	arena.visual_settings.effects_level=0
	await capture("density-2560-grouped-low-player-protected")
	arena.visual_settings.ui_scale=1.1
	arena.visual_settings.font_scale=1.2
	arena.hud._apply_presentation()
	root.size=Vector2i(1280,720)
	await capture("density-1280-max-font")
	var file:=FileAccess.open(directory.path_join("density-capture-records.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"  "))
	file.close()
	print("DENSITY_VISUAL_COMPLETE")
	quit()
