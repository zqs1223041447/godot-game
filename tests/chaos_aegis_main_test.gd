extends "res://tests/flask_purchase_transactions_test.gd"
## Canonical formal admission with a disclosed finite currency/progression fixture.
const Maps=preload("res://scripts/world/map_compiler.gd")
const Damage=preload("res://scripts/combat/damage_resolver.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
var arena:Node
var panel:Control
var cases:Array=[]
func settle()->void:await process_frame;await process_frame
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_environment("CHAOS_AEGIS_CAPTURE_DIR")+"/"+name+".png")==OK,"Native screenshot "+name)
func select_option(option:OptionButton,value:Variant)->void:
	for i:int in range(option.item_count):
		if option.get_item_metadata(i)==value:option.select(i);option.item_selected.emit(i);return
	check(false,"Missing UI option "+str(value))
func click(button:Button)->void:
	var motion:=InputEventMouseMotion.new();motion.position=button.get_global_rect().get_center();Input.parse_input_event(motion)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=motion.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event)
	await settle()
func actors_once(label:String)->void:
	check(arena.enemies.size()==25,label+" admits the existing24 roots and1 boss")
	var boss_count:=0
	for enemy:Dictionary in arena.enemies:
		var base:Dictionary=Monsters.make_enemy(enemy.id,enemy.template_id,arena.wave,enemy.pos,"map_boss" if enemy.rarity=="boss" else "ordinary")
		if base.is_empty():check(false,label+" cannot construct baseline template "+enemy.template_id);continue
		check(enemy.map_defense_source.modifier_id=="chaos_aegis" and is_equal_approx(enemy.resistances.chaos,float(base.resistances.get("chaos",0.0))+0.2),label+" enemy gets its own base plus20 once")
		if enemy.rarity=="boss":boss_count+=1
	check(boss_count==1,label+" includes the existing boss")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-chaos-aegis-main-"):quit(78);return
	var model:=fixture(40)
	var old_snapshot:Dictionary=model.snapshot();var old_bytes:=FileAccess.get_file_as_bytes(PATH)
	var restored:=Model.new()
	check(restored.load_build(PATH) and restored.snapshot()==old_snapshot and FileAccess.get_file_as_bytes(PATH)==old_bytes,"Existing unselected schema59 save loads byte-preserved without migration")
	# Trusted progression fixture: use existing start/complete/claim, not natural kills.
	var first:Dictionary=Maps.compile_normal("old_garden",1,[],[]).profile
	var unlocked:Dictionary=model.normal_start_map(first,model.revision(),PATH)
	check(unlocked.ok and model.normal_complete_map(unlocked.run_id,model.revision(),PATH).ok and model.normal_claim_rewards(model.revision(),PATH).ok,"Existing canonical fixture unlocks tierII")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path=PATH
	root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle();panel=arena.hud._town_view;panel.open_service("map_device");await settle()
	select_option(panel._map_select,"old_garden");select_option(panel._tier_select,1);await settle()
	check(panel._special.has("chaos_aegis") and panel._special.chaos_aegis.disabled,"Original map UI exposes the new special and enforces wave gate")
	select_option(panel._tier_select,2);await settle()
	var baseline:=var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(PATH),arena.rng.state,arena._stats])
	var scroll:=panel._content.get_parent() as ScrollContainer
	scroll.ensure_control_visible(panel._special.chaos_aegis);await settle()
	await click(panel._special.chaos_aegis)
	check(panel._special.chaos_aegis.button_pressed and panel._map_preview.text.contains("入场 4 校准碎片 · 全清结算 10"),"Actual checkbox selects chaos aegis with existing fee4/reward10")
	check(var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(PATH),arena.rng.state,arena._stats])==baseline,"Selecting the special cannot mutate build/save/RNG/player defense")
	await capture("selection")
	var player_stats:Dictionary=arena._stats.duplicate(true)
	# Invoke the real original prepare and launch buttons after bringing them into view.
	scroll.ensure_control_visible(panel._map_prepare);await settle();await click(panel._map_prepare)
	check(arena.map_draft().special_ids==["chaos_aegis"] and not panel._map_launch.disabled,"Original prepare button compiles the single selected special")
	var balance:int=arena.state.crafting_balance();var saves:int=arena.state.successful_saves
	scroll.ensure_control_visible(panel._map_launch);await settle();await click(panel._map_launch)
	check(arena.world_context().mode=="map" and arena.state.crafting_balance()==balance-4 and arena.state.successful_saves==saves+1,"Original launch admits formal map with exactly one existing fee/save")
	if arena.world_context().mode!="map":finish();return
	actors_once("Initial entry")
	check(arena._stats==player_stats and arena.state.snapshot().version==59,"Enemy modifier leaves player stats and current schema unchanged")
	var active_bytes:=FileAccess.get_file_as_bytes(PATH);restored=Model.new()
	check(restored.load_build(PATH) and restored.normal_journey().active_run.special_ids==["chaos_aegis"] and FileAccess.get_file_as_bytes(PATH)==active_bytes,"New active selection reloads using existing save fields without an implicit write")
	# Existing Main damage settlement on an actual admitted root, before any kills.
	var target:Dictionary=arena.enemies.filter(func(e:Dictionary)->bool:return e.template_id=="crawler")[0]
	target.spawn=0.0;target.health=10000.0;target.max_health=10000.0;target.shield=50.0;target.max_shield=50.0
	var packet:Dictionary=Damage.packet({"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},["hit"],"chaos_aegis_main")
	var snapshot:Dictionary=arena.state.get_combat_snapshot()
	var unchanged:=var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(PATH)])
	arena._apply_damage_packet(target,packet,snapshot,Color.WHITE,0.0)
	var hit:Dictionary=arena.damage_trace.back()
	check(is_equal_approx(hit.components.chaos,80.0) and hit.components.fire==100.0 and hit.components.cold==100.0 and hit.components.lightning==100.0 and hit.components.physical==100.0,"Main mixed hit reduces chaos100 to80; other four components unchanged")
	check(hit.shield_spent==50.0 and target.shield==0.0 and is_equal_approx(target.health,9570.0),"Mitigation precedes shield50 then life430; chaos never bypasses shield")
	check(var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(PATH)])==unchanged,"Nonlethal defense settlement writes no inventory or save")
	cases.append({"case":"formal_mixed_hit","components":hit.components,"shield_spent":hit.shield_spent,"health_after":target.health})
	balance=arena.state.crafting_balance();saves=arena.state.successful_saves
	check(arena.retry_normal_map(arena.world_context().revision).ok and arena.state.crafting_balance()==balance-4 and arena.state.successful_saves==saves+1,"Existing retry pays once and starts a fresh formal run")
	actors_once("Retry")
	check(arena.return_to_town(arena.world_context().revision).ok,"Return through existing town transition")
	check(arena.craft_normal_map("old_garden",2,[],["chaos_aegis"],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Reenter the selected map normally")
	actors_once("Reentry")
	check(arena.return_to_town(arena.world_context().revision).ok,"Return before plain-map comparison")
	check(arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Subsequent ordinary map launches without the special")
	check(arena.enemies.all(func(e:Dictionary)->bool:return not e.has("map_defense_source") and not e.defense_stats.has("chaos_resistance")),"Subsequent plain-map roots and boss have no leaked chaos grant")
	check(arena._stats==player_stats and arena.state.snapshot().version==59,"All transitions preserve player stats and schema")
	check(arena.return_to_town(arena.world_context().revision).ok,"Final return clears active run")
	check(arena.state.normal_journey().active_run.is_empty(),"No lingering active map or modifier in completed session")
	finish()
func finish()->void:
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"cases":cases,"display":DisplayServer.get_name(),"fixture":"Canonical physical currency40 and trusted tierI completion; not natural earning or full-clear combat"}
	FileAccess.open(OS.get_environment("CHAOS_AEGIS_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("CHAOS_AEGIS_MAIN ",JSON.stringify(report));quit(1 if not failures.is_empty() else 0)
