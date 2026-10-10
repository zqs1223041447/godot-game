extends "res://tests/flask_purchase_transactions_test.gd"
## Paid canonical gems and real empty-slot clicks; original movement remains authority.
var arena:Node
var panel:Control
var owned:Array[String]=[]
var feedback_messages:Array[String]=[]
func settle()->void:await process_frame;await process_frame
func authority()->PackedByteArray:
	return var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(PATH),arena.state.successful_saves,arena.rng.state,arena.group_cooldowns.snapshot()])
func key(code:int,window_id:int=0)->void:
	for down:bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;event.window_id=window_id;Input.parse_input_event(event)
	await settle()
func click(control:Control,button:int=MOUSE_BUTTON_LEFT)->void:
	var motion:=InputEventMouseMotion.new();motion.position=control.get_global_rect().get_center();Input.parse_input_event(motion)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=motion.position;event.button_index=button;event.pressed=down;Input.parse_input_event(event)
	await settle()
func slot(row:int,index:int=-1)->Control:
	return panel._rows.find_child("MainGem_%02d"%row if index<0 else "SupportGem_%02d_%d"%[row,index],true,false)
func open_slot(row:int,index:int=-1)->void:
	var target:=slot(row,index);panel._rows.ensure_control_visible(target);await settle();await click(target)
	check(panel._gem_picker.visible,"Click actual empty slot opens owned-gem choices")
func choose(uid:String)->int:
	var id:=-1
	for candidate:int in panel._gem_choices:
		if panel._gem_choices[candidate]==uid:id=candidate;break
	if id<0:check(false,"Owned compatible UID absent from choices "+uid);return id
	panel._gem_picker.set_focused_item(id)
	await key(KEY_ENTER,root.get_window_id() if panel._gem_picker.is_embedded() else panel._gem_picker.get_window_id())
	return id
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_environment("GEM_PICKER_CAPTURE_DIR")+"/"+name+".png")==OK,"Native picker screenshot "+name)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-owned-gem-picker-"):quit(78);return
	var model:=fixture(40)
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path=PATH
	root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle()
	for definition:String in ["skill:bolt","support:efficiency","support:efficiency","support:heavy_projectiles","support:frost_lock"]:
		var previous:Array=model.snapshot().items.keys()
		var quote:Dictionary=arena.normal_gem_trade_quote("buy",definition,model.revision())
		check(quote.ok and arena.execute_normal_gem_trade(quote.handle,definition).ok,"Existing paid gem transaction: "+definition)
		for uid:String in model.snapshot().items:
			if uid not in previous:owned.append(uid)
	check(owned.size()==5,"Five actual purchased gem instances in the canonical bag")
	await key(KEY_K);panel=arena.hud._skill_support_panel
	panel.feedback.connect(func(message:String):feedback_messages.append(message))
	var group:String=model.snapshot().skill_groups[0].id
	var empty_group:String=model.snapshot().skill_groups[8].id
	var before:=authority();await open_slot(8,0)
	check(panel._gem_choices.is_empty() and panel._gem_picker.get_item_text(1)=="请先装入主动宝石","Support convenience picker explains missing active gem")
	await key(KEY_ESCAPE);check(authority()==before,"Empty and cancelled picker does not mutate authority")
	await open_slot(8)
	check(panel._gem_choices.values()==[owned[0]],"Main slot lists only the owned bag active gem")
	await capture("active-choice")
	var saves:int=model.successful_saves;var snapshot:Dictionary=model.snapshot()
	var accepted_id:int=await choose(owned[0])
	check(model.location(owned[0])=={"kind":"skill_main","group_id":empty_group} and model.successful_saves==saves+1,"Real popup confirmation moves the exact main UID and saves once")
	check(model.snapshot().items==snapshot.items and model.snapshot().next_item_serial==snapshot.next_item_serial,"Convenience move creates no item, quantity or UID")
	before=authority();panel._gem_picker.id_pressed.emit(accepted_id);await settle()
	check(authority()==before,"Repeated consumed selection cannot move again")
	var original_mana:float=model.get_group_cast(group).mana
	await open_slot(0,0)
	check(panel._gem_choices.values().has(owned[1]) and panel._gem_choices.values().has(owned[2]) and panel._gem_choices.values().has(owned[3]) and not panel._gem_choices.values().has(owned[4]),"Bolt support choices include owned compatible gems and exclude frost-only support")
	await capture("support-choice")
	saves=model.successful_saves;await choose(owned[1])
	check(model.location(owned[1])=={"kind":"skill_support","group_id":group,"index":0} and model.successful_saves==saves+1,"Chosen support uses original exact-location save transaction")
	check(model.get_group_cast(group).mana<original_mana and panel._rows._rows_by_id[group].preview.begins_with("%.2f 魔力"%model.get_group_cast(group).mana),"Existing compiled preview immediately reflects installed efficiency")
	await open_slot(0,1)
	check(not panel._gem_choices.values().has(owned[2]) and panel._gem_choices.values()==[owned[3]],"Duplicate support instance and incompatible support are filtered by original rules")
	var stale_id:int=panel._gem_choices.keys()[0]
	check(model.bind_group(group,KEY_V,model.revision(),PATH).ok,"Independent authoritative change invalidates open picker")
	before=authority();panel._gem_picker.id_pressed.emit(stale_id);await settle()
	check(not panel._gem_picker.visible and panel._gem_choices.is_empty() and authority()==before and model.location(owned[3]).kind=="bag","Stale queued selection cannot apply after revision change")
	await open_slot(0,1);before=authority();model.fail_writes=true;await choose(owned[3]);model.fail_writes=false
	check(authority()==before and model.location(owned[3]).kind=="bag" and not feedback_messages.is_empty(),"Save failure preserves inventory/disk and reports original failure")
	await open_slot(0,1);await choose(owned[3]);await open_slot(0,2)
	check(panel._gem_choices.is_empty() and panel._gem_picker.is_item_disabled(1),"No compatible bag gems shows a disabled empty-state explanation")
	await capture("no-compatible-gems");await key(KEY_ESCAPE)
	# Original right-click and drag/drop remain usable beside the new convenience.
	await click(slot(0,1),MOUSE_BUTTON_RIGHT)
	check(model.location(owned[3]).kind=="bag","Right-click still returns the exact installed support")
	var target:Control=slot(0,1)
	var payload:={"type":"unified_item","uid":owned[3],"revision":model.revision(),"grab_offset":Vector2i.ZERO}
	check(target._can_drop_data(Vector2.ZERO,payload),"Original drag validator still accepts compatible owned support")
	target._drop_data(Vector2.ZERO,payload);await settle()
	check(model.location(owned[3])=={"kind":"skill_support","group_id":group,"index":1},"Original drop remains the same authoritative move")
	before=authority();await click(slot(0,0))
	check(not panel._gem_picker.visible and authority()==before,"Clicking an occupied slot never replaces its gem")
	await click(slot(0,1),MOUSE_BUTTON_RIGHT);await open_slot(0,1)
	var closing_id:int=panel._gem_choices.keys()[0]
	arena.hud.close_panel();await settle();before=authority();panel._gem_picker.id_pressed.emit(closing_id)
	check(not panel._gem_picker.visible and authority()==before,"Closing the K panel cancels pending convenience choices")
	var restored:=Model.new();var disk:=FileAccess.get_file_as_bytes(PATH)
	check(restored.load_build(PATH) and restored.snapshot()==model.snapshot() and FileAccess.get_file_as_bytes(PATH)==disk,"Arrangement reloads with original UIDs and no rewrite")
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Original free formal map accepts the assembled build")
	while arena.hud.is_blocking():arena.hud.close_panel()
	var mana_before:float=arena.mana;var compiled:Dictionary=model.get_group_cast(group)
	await key(KEY_V)
	check(arena.group_cooldown_remaining(group)>0.0 and is_equal_approx(arena.mana,mana_before-float(compiled.mana)) and float(compiled.mana)<original_mana,"Physical V casts the chosen efficiency-supported group at its actual reduced cost")
	check(model.snapshot().version==59,"No schema change")
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"owned_uids":owned,"display":DisplayServer.get_name(),"fixture":"Canonical physical currency40; five gems bought via original paid transactions. No natural earning claim."}
	FileAccess.open(OS.get_environment("GEM_PICKER_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("OWNED_GEM_PICKER ",JSON.stringify(report));quit(1 if not failures.is_empty() else 0)
