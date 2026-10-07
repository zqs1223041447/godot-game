extends SceneTree
const Session = preload("res://scripts/studies/modular_study_session.gd")
const Ground = preload("res://scripts/visuals/study_ground_layer.gd")
const PROFILE := "res://assets/environment/studies/natural_ground/profile.json"
var arena: Node2D
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures += 1; push_error(label)
	return value
func pause_main() -> void:
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	for unused in 4: arena.hud.close_panel()
func snapshot() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(),arena.enemies,arena.world_geometry(),arena.map_spawn_records(),arena._map_run.snapshot(),arena.player_pos,arena.player_facing,arena.rng.state,arena.rng.seed,arena.elapsed,arena.kills,arena.reward_kills,arena.projectiles,arena.health,arena.mana,arena.shield,FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)])
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v113-") or FileAccess.file_exists("user://build_save.json"):
		printerr("Fresh isolated /tmp/godot-m1-v113-* XDG required"); quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena)
	await process_frame; pause_main()
	if not check(arena.save_build(),"Save lawful isolated starter"): await finish(); return
	if not check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok,"Prepare ordinary map"): await finish(); return
	if not check(arena.start_map(arena.map_draft().revision).ok,"Enter original25-root map"): await finish(); return
	pause_main()
	var installed: Dictionary = await Session.install(arena)
	if not check(installed.ok,"Install unchanged four-contour research area"): await finish(); return
	await process_frame
	var static_layer: Node2D = arena.static_environment
	var ground: Node2D = static_layer._study_ground
	if not check(is_instance_valid(ground) and ground.diagnostics().ready,"Natural ground activates on actual research area"): await finish(); return
	var diagnostic: Dictionary = ground.diagnostics()
	check(diagnostic.build_count==1 and diagnostic.texture_count==4 and ground.material is ShaderMaterial,"Single cached material and four resources")
	check(not ground.is_processing() and not ground.is_physics_processing(),"No perframe CPU generation callbacks")
	check(static_layer.material==null and static_layer._camp_signs.material==null and static_layer._study_marks.material==null,"Parent, flags and ground marks keep ordinary materials")
	check(ground.get_index()<static_layer._study_marks.get_index() and static_layer._study_marks.get_index()<static_layer._camp_signs.get_index(),"Ground quad precedes ordinary markings and flags")
	check(static_layer.get_index()<arena.world_depth.get_index(),"Ground subtree precedes module shadows and bodies")
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	check(FileAccess.get_sha256(profile.mask_path)==profile.mask_sha256,"Frozen mask matches recorded hash")
	var sources: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/studies/natural_ground/sources.json"))
	for source: Dictionary in sources.files:
		check(FileAccess.get_sha256("res://assets/environment/studies/natural_ground/"+str(source.file))==source.sha256,"Original CC0 diffuse bytes: "+str(source.asset))
	var mask: Image = ground._textures.mask.get_image().duplicate()
	if mask.is_compressed(): mask.decompress()
	var alpha_ok := true
	for point: Vector2i in [Vector2i(0,0),Vector2i(511,0),Vector2i(0,383),Vector2i(511,383),Vector2i(255,191)]: alpha_ok = alpha_ok and mask.get_pixelv(point).a==1.0
	check(alpha_ok and mask.get_size()==Vector2i(512,384),"Mask has opaque data edges and authored dimensions")
	var routes_clear := true
	for route: Dictionary in profile.route_segments:
		var start:=Vector2(route["from"][0],route["from"][1]); var end:=Vector2(route["to"][0],route["to"][1])
		routes_clear = routes_clear and arena._geometry.is_clear(start,float(profile.paint_validation_radius_world)) and arena._geometry.is_clear(end,float(profile.paint_validation_radius_world)) and not arena._geometry.sweep(start,end,float(profile.paint_validation_radius_world)).hit
	check(routes_clear and profile.route_segments.size()==10,"Every baked stone route plus foot/filter margin clears current native contours")
	var shader: String = ground._shader.code
	check(not shader.contains("TIME") and not shader.contains("SCREEN_UV") and not shader.contains("for (") and not shader.contains("sin("),"Shader has no time, screen-space UV, route loops or animated randomization")
	check(shader.contains("repeat_enable") and shader.contains("COLOR = vec4") and shader.contains("1.0);"),"Diffuse wraps are continuous samplers and ground remains opaque")
	var frozen := snapshot()
	var ground_id: int = ground.get_instance_id()
	var material_id: int = ground.material.get_instance_id()
	var count: int = static_layer.get_child_count()
	var initial_draws: int = ground.draw_count
	var camera: Camera2D = arena.get_node("WorldCamera")
	var saved_position:=camera.position; var saved_zoom:=camera.zoom
	var point: Vector2 = arena.player_pos + Vector2(160,-120)
	var stable_local: Vector2 = ground.to_local(arena.to_global(point))
	var transforms_ok := true
	for index in 4:
		camera.position=saved_position+Vector2(index*137,index*-61)
		camera.zoom=Vector2.ONE*(0.65 if index%2==0 else 1.3)
		camera.force_update_scroll()
		var projected: Vector2 = ground.get_global_transform_with_canvas()*stable_local
		var inverse: Vector2 = ground.get_global_transform_with_canvas().affine_inverse()*projected
		transforms_ok = transforms_ok and inverse.distance_to(stable_local)<0.001 and ground.to_local(arena.to_global(point))==stable_local
		static_layer.set_geometry(arena.world_geometry())
		await process_frame
	camera.position=saved_position; camera.zoom=saved_zoom; camera.force_update_scroll()
	check(transforms_ok and ground.scale==Vector2.ONE and static_layer.scale==Vector2.ONE,"World-local texture point is independent of actual camera translation/zoom")
	check(ground.get_instance_id()==ground_id and ground.material.get_instance_id()==material_id and ground.build_count==1 and ground.draw_count==initial_draws and static_layer.get_child_count()==count,"Camera motion reuses quad, material, textures and retained draw commands")
	check(snapshot()==frozen,"Presentation updates preserve map, roster, collisions, game state, RNG and save bytes")
	var original: Dictionary = arena.world_geometry()
	var detached: Dictionary = original.duplicate(true); detached.module_polygons[0][0]+=Vector2(1,0)
	var probe := Ground.new()
	check(not probe.configure(detached) and not probe.diagnostics().ready,"Different contour fingerprint cannot use stale ground mask")
	probe.free()
	static_layer.set_geometry(detached)
	check(not is_instance_valid(static_layer._study_ground) and not static_layer._study_ground_error.is_empty() and static_layer.material==null,"Invalid ground selection restores complete ordinary floor rendering")
	static_layer.set_geometry(original)
	check(is_instance_valid(static_layer._study_ground) and static_layer._study_ground.diagnostics().ready,"Valid study selection can recreate ground after fallback")
	var old_ground: WeakRef = weakref(static_layer._study_ground)
	var old_marks: WeakRef = weakref(static_layer._study_marks)
	if not check(arena.return_to_town(arena.world_context().revision).ok,"Actual return to town"):await finish();return
	pause_main();await process_frame;await process_frame
	check(old_ground.get_ref()==null and old_marks.get_ref()==null and not is_instance_valid(static_layer._study_ground) and not is_instance_valid(static_layer._study_marks),"Town releases study ground, marks and material bindings")
	check(static_layer.material==null and static_layer._camp_signs.material==null and static_layer.world_geometry().id=="town","Town restores original ordinary materials and geometry")
	await finish()
func finish() -> void:
	if is_instance_valid(arena):arena.queue_free();await process_frame;await process_frame
	print("NATURAL_GROUND_STUDY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
