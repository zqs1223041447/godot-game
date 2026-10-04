extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V038_PACK_QA");var expected_font:=OS.get_environment("V038_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64:quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var arena:Node2D=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.38.0" and directory=="godot-game-preview-v021" and model.snapshot().version==23 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	var before:PackedByteArray=var_to_bytes([model.snapshot(),arena.enemies,arena.rng.state]);arena.retained_actors.sync(arena);var first:Dictionary=arena.retained_actors.diagnostics();arena.retained_actors.sync(arena);var second:Dictionary=arena.retained_actors.diagnostics()
	ok=ok and arena.use_retained_actors and first.actors==arena.enemies.size() and first.pieces==arena.enemies.size()*3 and first.body_rebuild_requests==second.body_rebuild_requests and var_to_bytes([model.snapshot(),arena.enemies,arena.rng.state])==before
	var items=load("res://scripts/items/unified_item_catalog.gd");var uid:String=model.snapshot().items.keys()[0];var item:Dictionary=model.item(uid)
	var original:Dictionary=items.metadata_for_instance(item);var copy:Dictionary=items.metadata_for_instance(item);copy.size[0]=999
	var invalid:Dictionary=item.duplicate(true);invalid.payload={"invalid":true}
	var metadata_ok:bool=items.metadata_for_instance(item)==original and items.metadata_for_instance(invalid).is_empty() and items._METADATA_CACHE_LIMIT==2048
	var runtime=load("res://scripts/combat/projectile_runtime.gd");var hit:float=runtime._segment_circle(Vector2.ZERO,Vector2(100,0),Vector2(50,0),10.0)
	ok=ok and metadata_ok and is_equal_approx(hit,0.4)
	var report:Dictionary={"ok":ok,"game_version":version,"schema":model.snapshot().version,"save_directory":directory,"actual_user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"retained_actor_count":first.actors,"retained_piece_count":first.pieces,"static_body_rebuild_requests":second.body_rebuild_requests,"repeated_sync_no_rebuild":first.body_rebuild_requests==second.body_rebuild_requests,"model_rng_unchanged":var_to_bytes([model.snapshot(),arena.enemies,arena.rng.state])==before,"metadata_readonly_invalid_miss":metadata_ok,"metadata_cache_bound":2048,"projectile_contact":hit,"scope":"Packed renderer layer resources and readonly admission/cache/math smoke; native visual and full90tick combat evidence reused, not replayed"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE).store_string(Engine.get_license_text());FileAccess.open(output.path_join("GODOT_COPYRIGHT.txt"),FileAccess.WRITE).store_string(JSON.stringify(Engine.get_copyright_info(),"\t",true,true))
	var licenses:Dictionary=Engine.get_license_info();var names:=licenses.keys();names.sort();var text:="Godot 4.6.3 third-party license texts\n\n"
	for name:String in names:text+=name+"\n"+str(licenses[name])+"\n\n"
	FileAccess.open(output.path_join("GODOT_THIRD_PARTY_LICENSES.txt"),FileAccess.WRITE).store_string(text)
	arena.queue_free();await process_frame;print(JSON.stringify(report));quit(0 if ok else 1)
