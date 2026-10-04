extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V037_PACK_QA");var expected_font:=OS.get_environment("V037_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64:quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var model=load("res://scripts/canonical_game_state.gd").new();var presenter=load("res://scripts/ui/unified_item_presentation.gd")
	var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.37.0" and directory=="godot-game-preview-v021" and model.snapshot().version==23 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	var before:PackedByteArray=var_to_bytes(model.snapshot());var rows:Array=[];var support:Dictionary={};var fixed:=0
	for uid:String in model.snapshot().items:
		var item:Dictionary=model.item(uid);var view:Dictionary=presenter.view(model,uid)
		ok=ok and not view.is_empty() and view.has("rarity")
		if item.kind=="equipment":
			ok=ok and view.function.is_empty() and view.description.is_empty() and not JSON.stringify(view).contains("装备合计")
			if item.payload.is_empty():fixed+=1;ok=ok and view.rarity=="unique" and view.affix_lines.is_empty()
		if item.kind=="support_gem":
			ok=ok and view.requirements.size()==1
			for tag:String in view.tags:ok=ok and not tag.contains("适配")
			if support.is_empty():support=view
		rows.append({"kind":item.kind,"rarity":view.rarity,"base_lines":view.base_lines.size(),"affix_lines":view.affix_lines.size()})
	var host:=Control.new();host.size=Vector2(1000,700);root.add_child(host)
	var card=load("res://scripts/ui/item_hover_card.gd").new();host.add_child(card)
	var lines:Array[String]=[]
	for i:int in range(60):lines.append("增加物理伤害 %d"%i)
	var long_view:Dictionary=support.duplicate(true);long_view.base_lines=lines
	card.present(long_view,[],Rect2(600,200,40,40),Rect2(0,0,1000,700))
	await process_frame;await process_frame
	var scroll:ScrollContainer=card.find_child("ItemDetailsScroll",true,false);var title:Control=card.find_child("ItemName",true,false)
	var routed:bool=card.scroll_at(host.get_global_transform_with_canvas()*Vector2(610,210),1,3)
	var scroll_ok:bool=routed and scroll.scroll_vertical>0 and not scroll.is_ancestor_of(title)
	ok=ok and fixed==9 and not support.is_empty() and scroll_ok and var_to_bytes(model.snapshot())==before
	for character:String in "基础额外词缀适用自然结束分裂碰撞消耗取消返回一次不刷新寿命".split(""):ok=ok and font.has_char(character.unicode_at(0))
	var report:Dictionary={"ok":ok,"game_version":version,"schema":model.snapshot().version,"save_directory":directory,"actual_user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"item_views":rows,"fixed_equipment":fixed,"packed_scroll_entry":routed,"body_scroll":scroll.scroll_vertical,"fixed_header":not scroll.is_ancestor_of(title),"model_unchanged":var_to_bytes(model.snapshot())==before,"scope":"Packed structured views and resource/scroll entry smoke only; source data and actual HUD input evidence reused"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE).store_string(Engine.get_license_text());FileAccess.open(output.path_join("GODOT_COPYRIGHT.txt"),FileAccess.WRITE).store_string(JSON.stringify(Engine.get_copyright_info(),"\t",true,true))
	var licenses:Dictionary=Engine.get_license_info();var names:=licenses.keys();names.sort();var text:="Godot 4.6.3 third-party license texts\n\n"
	for name:String in names:text+=name+"\n"+str(licenses[name])+"\n\n"
	FileAccess.open(output.path_join("GODOT_THIRD_PARTY_LICENSES.txt"),FileAccess.WRITE).store_string(text)
	host.queue_free();await process_frame
	print(JSON.stringify(report));quit(0 if ok else 1)
