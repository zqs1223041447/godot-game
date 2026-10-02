extends SceneTree
## Developer-only 2K visibility fixture at the existing enemy/projectile/cue caps.
var arena: Node
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var output: String=OS.get_environment("GODOT_VISUAL_QA_DIR")
	if output.is_empty(): output="user://visual-qa"
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(2560,1440)
	root.position=Vector2i.ZERO
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.close_panel()
	arena.hud._toast_left=0
	arena.hud._toast.hide()
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.rings.clear()
	arena.particles.clear()
	arena.visual_cues.reset()
	arena.demo_mode=false
	arena.auto_fire=false
	arena.elapsed=12.0
	arena.player_pos=Vector2(640,350)
	for i: int in range(arena.MAX_ENEMIES):
		var pos:=Vector2(95+(i%11)*107,165+(i/11)*79)
		if pos.distance_to(arena.player_pos)<65: pos+=Vector2(40,-30)
		var enemy: Dictionary=arena._spawn_enemy(pos,i%3)
		enemy.spawn=0.0
		if i%9==0: enemy.slow=2.0
	arena.rings.clear()
	var snapshot: Dictionary=arena.state.get_combat_snapshot()
	var packet: Dictionary=preload("res://scripts/combat/combat_data.gd").event_packet(snapshot,"basic","projectile")
	for i: int in range(arena.MAX_PROJECTILES):
		var origin:=Vector2(76+(i%20)*58,147+(i/20)*42)
		var direction:=Vector2.RIGHT.rotated(float(i%8)*TAU/8)
		arena._shoot(origin,direction,packet,Color("ddd0ab"),0,0,600,{"snapshot":snapshot})
	arena.particles.clear()
	for i: int in range(96):
		arena.visual_cues.emit_cue("explosion",Vector2(90+(i%16)*73,151+(i/16)*66),{"radius":76.0,"color":Color("dca269")})
	arena.visual_cues.advance(0.12)
	for level: int in [2,0]:
		arena.visual_settings.effects_level=level
		arena.queue_redraw()
		for i: int in range(16): await process_frame
		await RenderingServer.frame_post_draw
		var path: String=output.path_join("v07-stress-%s-2k.png"%("high" if level==2 else "low"))
		root.get_texture().get_image().save_png(path)
		print("VISUAL_STRESS ",path," enemies=",arena.enemies.size()," projectiles=",arena.projectiles.size()," cues=",arena.visual_cues.cues.size())
	arena.queue_free()
	await process_frame
	quit()
