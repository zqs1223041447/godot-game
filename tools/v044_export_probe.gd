extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V044_PACK_QA");var expected_font:=OS.get_environment("V044_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64 or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.44.0" and directory=="godot-game-preview-v021" and model.snapshot().version==27 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	for index:int in "正式宝石交易购买回收校准碎片".length():ok=ok and font.has_char("正式宝石交易购买回收校准碎片".unicode_at(index))
	ok=ok and arena.save_build() and arena.world_context().normal_town
	var candidate:Dictionary=model.snapshot();ok=ok and model._set_bag_currency_balance(candidate,12).ok;candidate.revision+=1;ok=ok and model._commit(candidate,arena.NORMAL_BUILD_PATH).ok
	var offers:Array=arena.town_stock("skill_merchant");ok=ok and offers.size()==26
	var counts:Dictionary={"skill_gem":0,"support_gem":0}
	for row:Dictionary in offers:
		counts[row.kind]+=1
		ok=ok and row.paid and row.available and row.cost==(8 if row.kind=="skill_gem" else 4)
	var quote:Dictionary=arena.normal_gem_trade_quote("buy","skill:shade_bolt",model.revision());ok=ok and quote.ok
	var buy:Dictionary=arena.execute_normal_gem_trade(quote.get("handle",""),"skill:shade_bolt");ok=ok and buy.ok and model.crafting_balance()==4
	var active_uid:String=buy.get("uid","")
	quote=arena.normal_gem_trade_quote("buy","support:efficiency",model.revision());ok=ok and quote.ok
	var support_buy:Dictionary=arena.execute_normal_gem_trade(quote.get("handle",""),"support:efficiency");ok=ok and support_buy.ok and model.crafting_balance()==0
	var support_uid:String=support_buy.get("uid","")
	var owned:Dictionary=model.item(active_uid);ok=ok and owned.get("definition_id")=="skill:shade_bolt" and owned.get("payload")=={"level":1,"quality":0}
	quote=arena.normal_gem_trade_quote("recycle",support_uid,model.revision());ok=ok and quote.ok
	var recycled:Dictionary=arena.execute_normal_gem_trade(quote.get("handle",""),support_uid);ok=ok and recycled.ok and model.crafting_balance()==1 and model.item(support_uid).is_empty() and not model.item(active_uid).is_empty()
	var before:PackedByteArray=var_to_bytes(model.snapshot());var disk:PackedByteArray=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	ok=ok and not arena.execute_normal_gem_trade(quote.get("handle",""),support_uid).ok and before==var_to_bytes(model.snapshot())
	ok=ok and arena.enter_town_test(arena.world_context().revision).ok
	var denied:Dictionary=arena.normal_gem_trade_quote("buy","support:efficiency",arena.state.revision());ok=ok and not denied.ok and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==disk
	ok=ok and arena.leave_town_test(arena.world_context().revision).ok and var_to_bytes(arena.state.snapshot())==before
	var result:Dictionary={"ok":ok,"version":version,"schema":arena.state.snapshot().version,"save_directory":directory,"user_dir":OS.get_user_data_dir(),"bag_layout":arena.state.bag_layout(),"font_sha256":font_hash,"font_characters":font.get_supported_chars().length(),"offer_counts":counts,"active_buy":buy,"support_buy":support_buy,"recycled":recycled,"currency":arena.state.crafting_balance(),"test_paid_rejection":denied,"normal_snapshot_restored":var_to_bytes(arena.state.snapshot())==before}
	var file:=FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Packed v44 gem trade probe: ","PASS" if ok else "FAIL");arena.queue_free();await process_frame;quit(0 if ok else 1)
