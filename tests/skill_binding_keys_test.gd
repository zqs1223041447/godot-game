extends "res://tests/flask_purchase_transactions_test.gd"
## Actual canonical K menu and physical-key input; no new gear or currency fixture.
var arena:Node
var panel:Control
var groups:Array[String]=[]
var observed:Array=[]
func settle()->void:await process_frame;await process_frame
func authority()->PackedByteArray:
	return var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(PATH),arena.state.successful_saves,arena.rng.state,arena.group_cooldowns.snapshot()])
func key(code:int,window_id:int=0)->void:
	for down:bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;event.window_id=window_id;Input.parse_input_event(event)
	await settle()
func picker(group:String)->OptionButton:return panel._rows._binding_controls[group]
func text_index(control:OptionButton,text:String)->int:
	for i:int in range(control.item_count):
		if control.get_item_text(i)==text:return i
	return -1
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_environment("BINDING_CAPTURE_DIR")+"/"+name+".png")==OK,"Native key menu screenshot "+name)
func choose(group:String,label:String)->void:
	var control:=picker(group);var index:=text_index(control,label)
	if index<0:check(false,"Visible key missing: "+label);return
	control.show_popup();await settle()
	var popup:=control.get_popup();popup.set_focused_item(index)
	await key(KEY_ENTER,root.get_window_id() if popup.is_embedded() else popup.get_window_id())
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-skill-binding-") or FileAccess.file_exists(PATH):quit(78);return
	var model:=FaultModel.new();check(model.save_build(PATH)==OK,"Fresh canonical save")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path=PATH
	root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle();await key(KEY_K);panel=arena.hud._skill_support_panel
	check(arena.hud._menu_routes.snapshot().left=="skills","Physical K opens canonical skill menu")
	for i:int in range(3):groups.append(arena.state.snapshot().skill_groups[i].id)
	var control:=picker(groups[0]);var ids:Array=[]
	for i:int in range(control.item_count):
		ids.append(control.get_item_id(i))
		var expected:String="未绑定" if control.get_item_id(i)==0 else OS.get_keycode_string(control.get_item_id(i))
		check(control.get_item_text(i)==expected,"Displayed key matches actual metadata: "+expected)
	var allowed:Array=Model.Rules.BINDABLE_KEYS.duplicate();allowed.push_front(0)
	check(ids==allowed and text_index(control,"C")==-1 and text_index(control,"M")>=0,"Exactly the canonical allowed keys; reserved C absent and M visible")
	for label:String in ["C","V","N","M"]:
		var index:=text_index(control,label)
		observed.append({"label":label,"actual_code":control.get_item_id(index) if index>=0 else -1})
	if OS.get_environment("BINDING_BASELINE_ONLY")=="1":finish();return
	if not failures.is_empty():finish();return
	var before:=authority();control.show_popup();await settle();control.get_popup().set_focused_item(control.get_item_index(KEY_M))
	await capture("picker");await key(KEY_ESCAPE)
	check(authority()==before,"Browsing and cancelling key menu never changes state")
	for i:int in range(3):
		var label:String=["V","N","M"][i];var code:int=[KEY_V,KEY_N,KEY_M][i]
		var saves:int=model.successful_saves;var serial:int=model.snapshot().next_item_serial
		await choose(groups[i],label)
		check(model.group_for_key(code)==groups[i] and picker(groups[i]).text==label,"Selecting visible "+label+" persists exactly that physical key")
		check(model.successful_saves==saves+1 and model.snapshot().next_item_serial==serial,"One binding save, no new UID: "+label)
		before=authority();await choose(groups[i],label)
		check(authority()==before,"Repeated current selection is a no-op: "+label)
	await capture("bound")
	var current:Dictionary=model.snapshot();var disk:=FileAccess.get_file_as_bytes(PATH);var loaded:=Model.new()
	check(loaded.load_build(PATH) and loaded.snapshot()==current and FileAccess.get_file_as_bytes(PATH)==disk,"V/N/M reload exactly without migration or rewrite")
	# Existing conflict semantics transfer the key; they never bind two groups at once.
	await choose(groups[1],"V")
	check(model.group_for_key(KEY_V)==groups[1] and model.group_for_key(KEY_N).is_empty() and picker(groups[0]).text=="未绑定","Rebinding an occupied key follows original transfer semantics")
	await choose(groups[1],"N");await choose(groups[0],"V")
	before=authority();model.fail_writes=true;await choose(groups[0],"Z");model.fail_writes=false
	check(authority()==before and picker(groups[0]).text=="V","Failed save preserves old binding and restores displayed key")
	before=authority();check(not model.bind_group(groups[0],KEY_C,model.revision(),PATH).ok and authority()==before,"Reserved C rejected by original authority")
	while arena.hud.is_blocking():arena.hud.close_panel()
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Existing free formal map starts for physical-key gameplay")
	while arena.hud.is_blocking():arena.hud.close_panel()
	for i:int in range(3):
		var code:int=[KEY_V,KEY_N,KEY_M][i];var cast:Dictionary=model.get_group_cast(groups[i]);var mana_before:float=arena.mana
		await key(code)
		check(arena.group_cooldown_remaining(groups[i])>0.0 and is_equal_approx(arena.mana,mana_before-float(cast.mana)),"Physical key admits its canonical skill and pays once: "+OS.get_keycode_string(code))
	var mana_before:float=arena.mana;var debt:Dictionary=arena.group_cooldowns.snapshot();await key(KEY_C)
	check(arena.hud._menu_routes.snapshot().left=="character" and arena.mana==mana_before and arena.group_cooldowns.snapshot()==debt,"Physical C still opens character panel without casting")
	await key(KEY_K);panel=arena.hud._skill_support_panel
	var remaining:float=arena.group_cooldown_remaining(groups[0]);await choose(groups[0],"Z")
	check(arena.group_cooldown_remaining(groups[0])==remaining,"Changing visible binding cannot reset existing cooldown")
	while arena.hud.is_blocking():arena.hud.close_panel()
	mana_before=arena.mana;await key(KEY_Z)
	check(arena.mana==mana_before and arena.group_cooldown_remaining(groups[0])==remaining,"New physical key cannot cast through old cooldown")
	check(model.snapshot().version==59,"No save schema change")
	finish()
func finish()->void:
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"observed_labels":observed,"display":DisplayServer.get_name()}
	FileAccess.open(OS.get_environment("BINDING_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("SKILL_BINDING_KEYS ",JSON.stringify(report));quit(1 if not failures.is_empty() else 0)
