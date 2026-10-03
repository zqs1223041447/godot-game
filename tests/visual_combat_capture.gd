extends SceneTree
## Real main-scene visual acceptance, using only disposable developer test state.
var arena: Node
var output: String
func _initialize() -> void:
	call_deferred("run")
func settle() -> void:
	for i: int in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
func capture(label: String) -> void:
	arena.queue_redraw()
	await settle()
	var image: Image=root.get_texture().get_image()
	var path: String=output.path_join(label+".png")
	image.save_png(path)
	print("COMBAT_CAPTURE ",path," ",image.get_size())
func prepare() -> void:
	arena.restart_run()
	arena.enemies.clear()
	arena.rings.clear()
	arena.visual_cues.reset()
	arena.particles.clear()
	arena.demo_mode=true
	arena.elapsed=15.0
	arena.auto_fire=false
	arena.spawn_timer=9999
	arena.player_pos=Vector2(360,400)
	var positions: Array[Vector2]=[Vector2(490,330),Vector2(640,270),Vector2(760,370),Vector2(930,330),Vector2(1090,390)]
	for i: int in range(positions.size()):
		var enemy: Dictionary=arena._spawn_enemy(positions[i],i%3)
		enemy.spawn=0.0
		enemy.health=1000.0
		enemy.max_health=1000.0
		if i==1:
			enemy.shield=100.0
			enemy.max_shield=100.0
		if i==2:
			enemy.slow=3.0
	arena.rings.clear()
	arena.hud._toast.hide()
	arena.hud._toast_left=0
func run() -> void:
	output=OS.get_environment("GODOT_VISUAL_QA_DIR")
	if output.is_empty(): output="user://visual-qa"
	DirAccess.make_dir_recursive_absolute(output)
	root.position=Vector2i.ZERO
	root.size=Vector2i(2560,1440)
	arena=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.visual_settings.ui_scale=1.0
	arena.visual_settings.font_scale=1.0
	arena.hud._apply_presentation()
	for level: int in [2,0]:
		prepare()
		arena.visual_settings.effects_level=level
		arena.state.slot_skill(0,"chain")
		arena.cast_skill(0)
		arena._update_effects(0.04)
		await capture("v07-chain-%s-2k"%("high" if level==2 else "low"))
		prepare()
		arena.player_pos=Vector2(640,380)
		arena.state.slot_skill(0,"nova")
		arena.state.slot_skill(1,"ward")
		arena.state.slot_skill(2,"meteor")
		arena.cast_skill(0)
		arena.cast_skill(1)
		arena.cast_skill(2)
		arena._update_effects(0.10)
		arena.invulnerable=0
		arena.shield=0
		arena.hit_player(5)
		await capture("v07-spells-%s-2k"%("high" if level==2 else "low"))
	# New skill support panel belongs to the content track; preserve its native layout.
	prepare()
	arena.state.equip("ember_wand")
	arena.state.slot_skill(0,"tornado")
	arena.state.add_skill_support("tornado","volley")
	arena.state.add_skill_support("tornado","focus")
	arena.state.slot_skill(1,"bolt")
	arena.state.slot_skill(2,"frost")
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=resolution
		for ui_scale: float in [1.0,1.1]:
			arena.visual_settings.ui_scale=ui_scale
			arena.visual_settings.font_scale=1.0 if ui_scale==1.0 else 1.2
			arena.hud._apply_presentation()
			arena.hud.open_panel("skills")
			arena.hud._select_skill_slot(0)
			await capture("v07-support-%dx%d-ui%d"%[resolution.x,resolution.y,roundi(ui_scale*100)])
	arena.visual_settings.ui_scale=1.0
	arena.visual_settings.font_scale=1.0
	arena.hud._apply_presentation()
	arena.equip_tornado_example()
	arena.hud.open_panel("skills")
	arena.hud._select_skill_slot(0)
	await capture("v07-support-full-combination-2k")
	var fixture_rng:=RandomNumberGenerator.new()
	fixture_rng.seed=701
	var focus_id: String=arena.state.award_equipment(fixture_rng,30,"rare","expanded")
	if not focus_id.is_empty():
		arena.state.equip(focus_id)
		for ui_scale: float in [1.0,1.1]:
			arena.visual_settings.ui_scale=ui_scale
			arena.visual_settings.font_scale=1.0 if ui_scale==1.0 else 1.2
			arena.hud._apply_presentation()
			arena.hud.open_panel("inventory")
			arena.hud.find_child("InventoryPanel",true,false).select_item("item:"+focus_id)
			await capture("v07-runewood-inventory-ui%d-2k"%roundi(ui_scale*100))
			arena.hud.open_panel("skills")
			arena.hud._select_skill_slot(0)
			await capture("v07-typed-support-ui%d-2k"%roundi(ui_scale*100))
			arena.hud.open_panel("combat")
			arena.hud._panel_scroll.scroll_vertical=285
			await capture("v07-typed-details-ui%d-2k"%roundi(ui_scale*100))
	arena.hud.close_panel()
	arena.visual_settings.ui_scale=1.0
	arena.visual_settings.font_scale=1.0
	arena.visual_settings.effects_level=2
	arena.hud._apply_presentation()
	root.size=Vector2i(1280,720)
	print("COMBAT_CAPTURE_DONE; native window available for interactions")
