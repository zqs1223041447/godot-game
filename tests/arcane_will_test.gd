extends "res://tests/attack_elemental_passive_migration_test.gd"
const Source=preload("res://scripts/passives/source_tree_runtime.gd")
const Locale=preload("res://scripts/passives/source_tree_localization.gd")
const QA="res://docs/qa/arcane-will/"
const TARGET="27163"
const ENTRY="Regenerate 5 Mana per second"
const ROUTE=["54447","57226","21678","32210","8948","27929","7503","65203",TARGET]
const SAVE="user://build_save.json"
var evidence:Array=[]
var observations:Dictionary={}
var arena:Node
var panel:Control
func check(ok:bool,label:String)->void:evidence.append({"label":label,"ok":ok});super.check(ok,label)
func close(actual:float,wanted:float,label:String)->void:check(is_equal_approx(actual,wanted),label)
func clean(value:Variant)->Variant:return JSON.parse_string(JSON.stringify(value,"",true,true))
func prefix()->Dictionary:
	var value:=Rules.decode_v60(JSON.parse_string(FileAccess.get_file_as_string(QA+"schema60-town.json")))
	value.version=Rules.VERSION;return value
func selected()->Dictionary:
	var value:=prefix();value.talents.allocated.append(TARGET);value.talents.normal_points-=1
	check(Rules.reason(value).is_empty(),"Full canonical legal eight-point Witch build");return value
func source_checks()->void:
	var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(QA+"schema60-oracle.json"))
	var effects:Dictionary={};var changed:Array=[]
	for id:String in Source.Data.nodes():
		var node:=Source.Data.node(id)
		if node.type=="mastery":
			for effect:Dictionary in node.mastery_effects:
				var old:=Source.node_effect(id,int(effect.effect),60);effects[id+":"+str(effect.effect)]=old
				if old!=Source.node_effect(id,int(effect.effect),61):changed.append(id)
		else:
			var old:=Source.node_effect(id,0,60);effects[id+":0"]=old
			if old!=Source.node_effect(id,0,61):changed.append(id)
	check(effects.size()==oracle.effects_count and JSON.stringify(clean(effects),"",true,true).sha256_text()==oracle.effects_policy60_sha256,"Entire pre-edit60 effect policy fingerprint preserved")
	check(changed==[TARGET],"Only27163 changes; all other source nodes/masteries stay frozen")
	check(Source.node_effect(TARGET).status=="full" and Source.node_effect(TARGET).grants==[{"stat":"max_mana","value":0.3,"mode":"increased"},{"stat":"mana_regen","value":5.0,"mode":"flat"},{"stat":"intelligence","value":10.0,"mode":"flat"}],"All original clauses become executable together")
	for version:int in [19,55,59,60]:check(Source.node_effect(TARGET,0,version).status=="partial","Old policy continues to reject complete node: %d"%version)
	for line:String in [ENTRY+"."," "+ENTRY,ENTRY+"\n","Regenerate 6 Mana per second","Regenerate 5% of Mana per second",ENTRY+" while on Low Life"]:check(not Source.line_effect(line,Rules.VERSION,TARGET).supported,"No other flat amount, percent, condition or wording variant admitted")
	check(not Source.Patterns.parse_line(ENTRY,false).supported,"Disabled historical parser gate cannot open new entry")
	check(Locale.node_name(TARGET)=="奥术意志" and Locale.line_status(ENTRY,TARGET).implemented and not Locale.display_line(ENTRY,TARGET).contains(Locale.NOT_IMPLEMENTED),"Chinese line status is backed by existing live resource consumer")
	check(not Source.line_effect(ENTRY).supported and not Locale.line_status(ENTRY).implemented,"Shared text alone cannot grant or advertise the node-specific effect")
	for id:String in Source.Data.nodes():
		var node:=Source.Data.node(id)
		for option:Dictionary in node.mastery_effects:
			if option.stats.has(ENTRY):
				check(Source.node_effect(id,int(option.effect)).status=="unsupported" and Locale.display_line(ENTRY,id).contains(Locale.NOT_IMPLEMENTED),"Shared mana mastery remains blocked and honestly marked: "+id)
	for i:int in range(1,ROUTE.size()):check(Source.Data.adjacency(ROUTE[i-1]).has(ROUTE[i]),"Actual connected source edge: "+ROUTE[i])
	check(clean(Game._stats_for(prefix()))==oracle.stats,"Unselected61 build equals pre-edit60 stats exactly")
func arithmetic_checks()->void:
	var base:=prefix();var before:=Game._stats_for(base);var stats:=Game._stats_for(selected())
	close(stats.mana_regen-before.mana_regen,5.0*(1.0+before.mana_regen_increased),"Fixed5 is added before all existing regeneration increases")
	close(stats.intelligence-before.intelligence,10.0,"Original ten Intelligence counted once")
	var increase:=0.0
	for id:String in base.talents.allocated:
		for grant:Dictionary in Source.node_effect(id).grants:
			if grant.stat=="max_mana" and grant.mode=="increased":increase+=float(grant.value)
	close(stats.max_mana,(before.max_mana/(1.0+increase)+5.0)*(1.0+increase+0.3),"Thirty percent mana is additive; Intelligence adds five flat mana before capacity scaling")
	check(stats.max_shield>before.max_shield and stats.max_health==before.max_health,"Original Intelligence also increases shield; no phantom life benefit")
	observations={"before":before,"after":stats,"mana_regen_gain":stats.mana_regen-before.mana_regen}
func settle()->void:await process_frame;await process_frame
func click(button:Button)->void:
	var scroll:ScrollContainer=button.get_parent().get_parent();scroll.ensure_control_visible(button);await settle()
	var motion:=InputEventMouseMotion.new();motion.position=button.get_global_rect().get_center();Input.parse_input_event(motion)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=motion.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event)
	await settle()
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	var scroll:ScrollContainer=panel._detail.get_parent().get_parent();scroll.ensure_control_visible(panel._allocate);await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_environment("ARCANE_OUTPUT").path_join(name+".png"))==OK,"Native original T screenshot: "+name)
func live_checks()->void:
	var game:=Game.new();var start:=prefix();start.talents.allocated=[ROUTE[0]];start.talents.normal_points=8
	check(Rules.reason(start).is_empty(),"Legal level4 eight-point fixture, no natural-earning claim")
	game._accept_memory(start);check(game.save_build(SAVE)==OK,"Save isolated formal profile")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=game;arena.build_save_path=SAVE;root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;await settle()
	check(not game.allocate_passive(TARGET,0,game.revision(),SAVE).ok,"Disconnected target rejected")
	for id:String in ROUTE.slice(1,-1):check(game.allocate_passive(id,0,game.revision(),SAVE).ok,"Actual paid path allocation: "+id)
	check(game.talent_points==1,"Seven real allocations leave exactly one point")
	arena.hud.open_panel("talents");await settle();panel=arena.hud._passive_panel
	panel._tree.node_clicked.emit(TARGET,MOUSE_BUTTON_LEFT,false);panel._tree.pan=-Source.Data.node(TARGET).position*panel._tree.zoom;panel._tree.queue_redraw();await settle()
	check(not panel._allocate.disabled and panel._detail.text.contains("奥术意志") and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED),"Actual T presents full Chinese node and enables allocation")
	await capture("available")
	panel._tree.node_clicked.emit("10495",MOUSE_BUTTON_LEFT,false);await settle()
	var found_blocked:=false
	for i:int in range(panel._mastery.item_count):
		if int(panel._mastery.get_item_metadata(i))==2902:
			found_blocked=panel._mastery.is_item_disabled(i) and panel._mastery.get_item_text(i).contains(Locale.NOT_IMPLEMENTED)
	check(found_blocked,"Real mastery selector leaves identical mana recovery option disabled and marked")
	panel._tree.node_clicked.emit(TARGET,MOUSE_BUTTON_LEFT,false);await settle()
	var before:=game.snapshot();var stats_before:=game.get_stats();var disk:=FileAccess.get_file_as_bytes(SAVE)
	arena.mana=10.0;arena.shield=5.0
	check(DirAccess.make_dir_absolute(SAVE+".tmp")==OK,"Inject atomic allocation failure")
	check(not game.allocate_passive(TARGET,0,game.revision(),SAVE).ok and game.snapshot()==before and FileAccess.get_file_as_bytes(SAVE)==disk and arena.mana==10.0 and arena.shield==5.0,"Failed allocation preserves build, points, disk and resources")
	check(DirAccess.remove_absolute(SAVE+".tmp")==OK,"Remove isolated allocation fault")
	var saves:int=game.successful_saves
	if DisplayServer.get_name()=="headless":panel._allocate.pressed.emit()
	else:await click(panel._allocate)
	check(game.snapshot().talents.allocated==ROUTE and game.talent_points==0 and game.successful_saves==saves+1,"Actual T allocation pays final point and saves once")
	check(arena.mana==10.0 and arena.shield==5.0 and arena._stats==game.get_stats(),"Allocation refreshes capacities/rate without free mana or shield")
	await settle();await capture("allocated")
	var reopened:=Game.new();check(reopened.load_build(SAVE) and reopened.snapshot()==game.snapshot() and reopened.get_stats()==game.get_stats() and reopened.save_attempts==0,"Allocated current profile reloads exact build without migration/write")
	check(not game.refund_passive("65203",game.revision(),SAVE).ok,"Cannot refund required bridge")
	# Existing authored helmet supplies flat0.1 mana/s and a legal2% regeneration suffix.
	var helmet:={"id":"gear_%06d"%game.snapshot().next_item_serial,"base_id":"nine_slot_slate_helmet","rarity":"magic","item_level":1,"affixes":[{"id":"nine_slot_suffix_mana_flow","tier":1,"value":2}]}
	check(game._admit_reward_item(Store.Items.wrap_equipment(helmet)) and game.equip(helmet.id),"Existing legal flat/percentage regeneration helmet admitted and equipped")
	var slot:String=game.snapshot().locations[helmet.id].slot_id
	var plain:=game.snapshot();plain.talents.allocated.erase(TARGET);plain.talents.normal_points+=1
	check(Rules.reason(plain).is_empty(),"Equipment comparison without node remains a legal build")
	var gear_off:=Game._stats_for(plain);var geared:=game.get_stats()
	close(geared.mana_regen-gear_off.mana_regen,5.0*(1.0+geared.mana_regen_increased),"Actual equipped flat and percentage sources stack with node in correct order")
	observations.equipped_mana_regen=geared.mana_regen
	while arena.hud.is_blocking():arena.hud.close_panel()
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Enter real existing free formal map for cast/recovery")
	arena.auto_fire=false;arena.invulnerable=10000.0
	var group:String=game.group_for_key(KEY_1);var cast:Dictionary=game.get_group_cast(group)
	arena.mana=arena._stats.max_mana;var full:float=arena.mana
	check(arena.cast_group(group),"Actual original skill cast accepted in formal map")
	close(arena.mana,full-float(cast.mana),"Actual cast deducts existing compiled cost, no immediate refund")
	var spent:float=arena.mana;arena.tick(1.0/60.0)
	close(arena.mana,minf(full,spent+geared.mana_regen/60.0),"Real Main resource phase recovers compiled rate after actual casting")
	arena.mana=full-0.01;arena.tick(1.0/60.0);close(arena.mana,full,"Real per-frame recovery clamps to full mana")
	check(arena.return_to_town(arena.world_context().revision).ok,"Return through original formal journey transaction")
	arena.hud.open_panel("talents");await settle();panel._tree.node_clicked.emit(TARGET,MOUSE_BUTTON_LEFT,false);await settle()
	var refund_before:=game.snapshot();disk=FileAccess.get_file_as_bytes(SAVE)
	arena.mana=geared.max_mana;arena.shield=geared.max_shield
	var pools:=[arena.mana,arena.shield]
	check(pools[0]>gear_off.max_mana and pools[1]>gear_off.max_shield,"Refund fixture is above new mana and shield caps")
	check(DirAccess.make_dir_absolute(SAVE+".tmp")==OK,"Inject atomic refund failure")
	check(not game.refund_passive(TARGET,game.revision(),SAVE).ok and game.snapshot()==refund_before and FileAccess.get_file_as_bytes(SAVE)==disk and [arena.mana,arena.shield]==pools,"Failed refund preserves selection, rate, current resources and disk")
	check(DirAccess.remove_absolute(SAVE+".tmp")==OK,"Remove isolated refund fault")
	await settle();saves=game.successful_saves
	if DisplayServer.get_name()=="headless":panel._refund.pressed.emit()
	else:await click(panel._refund)
	check(game.talent_points==1 and not game.snapshot().talents.allocated.has(TARGET) and game.successful_saves==saves+1,"Actual T refund returns one point and saves once")
	check(arena.mana==gear_off.max_mana and arena.shield==gear_off.max_shield and arena._stats.mana_regen==gear_off.mana_regen,"Refund clamps mana/shield down and removes exact regeneration source without healing")
	for field:String in Rules.FIELDS:
		if field not in ["revision","talents"]:check(game.snapshot()[field]==refund_before[field],"Refund preserves unrelated domain: "+field)
	check(game.unequip(slot) and game.get_stats()==stats_before,"Removing test helmet restores exact unselected stats")
	check(reopened.load_build(SAVE) and reopened.snapshot()==game.snapshot(),"Refunded current save reloads all domains")
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-arcane-"):quit(78);return
	source_checks();arithmetic_checks();await live_checks()
	FileAccess.open(OS.get_environment("ARCANE_OUTPUT").path_join("mechanism.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence,"observations":observations,"display":DisplayServer.get_name(),"fixture":"Legal level4 Witch8-point route; existing starter gear and controlled legal mana-regeneration helmet; original formal-map entry, cast and resource phase. No natural progression or performance claim."},"\t")+"\n")
	print("ARCANE_WILL checks=%d failures=%d"%[checks,failures.size()]);quit(1 if not failures.is_empty() else 0)
