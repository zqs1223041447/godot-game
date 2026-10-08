extends "res://tests/formal_boss_equipment_recovery_test.gd"
## Reuse the existing fault model, capacity fixture, death and reload helpers.
## This bounded run never executes the parent's historical suite/schema55 assertions.
const Base = preload("res://tests/formal_boss_equipment_recovery_test.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Jewels = preload("res://scripts/jewel_data.gd")

class JewelMain extends Base.ObservedMain:
	var jewel_awards: Array[Dictionary] = []
	func _award_kill_special_jewel(enemy: Dictionary = {}) -> void:
		var before: Dictionary = state.snapshot()
		var uid := "jewel_%06d" % int(before.next_item_serial)
		var rng_before: int = rng.state
		super._award_kill_special_jewel(enemy)
		jewel_awards.append({"uid":uid,"before":before,"expected":Build.Items.wrap_jewel(Jewels.generate_special(uid)),
			"item":state.item(uid),"location":state.location(uid),"rng_unchanged":rng.state==rng_before})

func fresh(label: String, test_profile: bool = false) -> bool:
	group = label
	await dispose()
	for path: String in [PATH, "user://town_test_build_save.json"]:
		if FileAccess.file_exists(path):
			if not check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path))==OK,"Remove only isolated suite save"):return false
	arena=load("res://scenes/main.tscn").instantiate();arena.set_script(JewelMain)
	model=FaultModel.new();arena.state=model
	root.add_child(arena);pause();await process_frame
	if not check(arena.world_context().normal_town and arena.save_build(),"Actual formal Main opens and saves"):return false
	arena.rng.seed=580155
	if test_profile:
		if not accepted(arena.enter_town_test(arena.world_context().revision),"Enter separate existing test town"):return false
		model=FaultModel.new()
		if not check(model.load_build(arena.TOWN_TEST_BUILD_PATH),"Load only test profile"):return false
		arena._replace_build(model,arena.TOWN_TEST_BUILD_PATH)
	else:
		if not accepted(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision),"Select free formal Old Garden I"):return false
	if not accepted(arena.start_map(arena.map_draft().revision),"Actual map admission"):return false
	pause();filler_uids.clear()
	return check(arena.enemies.size()==25 and arena._map_run.boss_id>0 and not boss().is_empty() and arena.reward_kills==0,"Current map admits 24 ordinary roots and one registered boss on entry")

func pair(jewel_kind:String,gear_kind:String)->Dictionary:
	if not check(arena.jewel_awards.size()==1 and arena.boss_awards.size()==1,"One existing gear decision and one special jewel decision"):return {}
	var jewel:Dictionary=arena.jewel_awards[0];var gear:Dictionary=arena.boss_awards[0]
	check(jewel.item==jewel.expected and not jewel.item.is_empty(),"Exact fixed branchfinder wrapper/payload and original UID")
	check(jewel.location.get("kind")==jewel_kind and gear.location.get("kind")==gear_kind,"Both reward destinations: jewel="+jewel_kind+", gear="+gear_kind)
	check(gear.item==gear.expected and gear.rng==gear.expected_rng and jewel.rng_unchanged,"Original equipment roll/RNG preserved; jewel consumes no random draw")
	check(int(jewel.before.next_item_serial)==int(gear.before.next_item_serial)+1 and int(model.snapshot().next_item_serial)==int(gear.before.next_item_serial)+2,"Coexisting gear and jewel consume exactly one sequential UID each")
	check(model.snapshot().version==58 and Model.Rules.reason(model.snapshot()).is_empty(),"Complete native schema58 accepts recovered jewel without rule changes")
	check(arena.reward_kills==1 and arena._map_run.boss_defeated,"Exactly one rewarded root death advances original boss ledger")
	for uid:String in gear.before.items:
		check(model.item(uid)==gear.before.items[uid] and model.location(uid)==gear.before.locations[uid],"Existing item and location preserved: "+uid)
	awards.append({"case":group,"jewel":jewel.item,"jewel_location":jewel.location,"gear":gear.item,"gear_location":gear.location})
	return jewel

func duplicate_check(enemy:Dictionary)->void:
	var count:int=arena.jewel_awards.size()
	repeated_death(enemy)
	check(arena.jewel_awards.size()==count,"Repeated corpse/reconstructed identity cannot mint another jewel")

func take_back(uid:String,expected:Dictionary)->void:
	arena.hud.open_panel("inventory");await process_frame;await process_frame
	var panel:Control=arena.hud._inventory_panel;panel.refresh()
	check(panel._pending.visible and panel._pending.get_child(1).get_child_count()==model.pending_items().size(),"Existing pending UI lists both rewards and old pending")
	var before:=observe()
	panel._pending.get_child(1).get_child(model.pending_items().find(uid)).pressed.emit()
	check(observe()==before,"Existing return button refuses full bag without mutation")
	check(model.item_definition(uid).size==Vector2i.ONE,"Actual jewel footprint is one cell")
	accepted(model.discard_item(filler_uids.back(),model.revision(),arena.build_save_path),"Free exactly one real fixture cell through canonical discard")
	check(not model.first_bag_position(uid).is_empty(),"Existing placement planner accepts that one cell")
	panel.refresh();before=observe();model.fail_writes=true
	panel._pending.get_child(1).get_child(model.pending_items().find(uid)).pressed.emit()
	check(observe()==before,"Failed pending-item move keeps exact item, location, disk and serial")
	model.fail_writes=false
	panel._pending.get_child(1).get_child(model.pending_items().find(uid)).pressed.emit()
	await process_frame;panel.refresh()
	check(model.location(uid).kind=="bag" and model.item(uid)==expected,"Same pending button retrieves exact same UID/fixed jewel")
	check(model.pending_items().has(str(arena.boss_awards[0].uid)) if not arena.boss_awards.is_empty() else not model.pending_items().is_empty(),"Retrieving jewel keeps coexisting pending equipment")
	reload_exact("Recovered jewel and pending gear survive exact schema58 reload")

func socket_checks(uid:String)->void:
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.hud.open_panel("talents");await process_frame;await process_frame
	var panel:Control=arena.hud._passive_panel
	if int(model.snapshot().talents.class_id)!=0:
		panel._class.item_selected.emit(0);await process_frame;await process_frame
	check(model.snapshot().talents.allocated==["58833"],"Existing UI selects lawful free Scion start")
	var initial_points:int=model.talent_points
	for id:String in ["2151","37690","48423","6230"]:
		panel._find_node(id);check(not panel._allocate.disabled,"Actual connected socket route button: "+id)
		panel._allocate.pressed.emit();await process_frame;await process_frame
	check(model.talent_points==initial_points-4,"Four real route points paid without grants")
	for i:int in range(panel._jewel.item_count):
		if str(panel._jewel.get_item_metadata(i))==uid:panel._jewel.select(i);panel._jewel.item_selected.emit(i);break
	check(not panel._socket.disabled,"Recovered boss jewel selectable in existing socket UI")
	panel._socket.pressed.emit();await process_frame;await process_frame
	check(model.location(uid)=={"kind":"passive_socket","node_id":"6230"},"Same rewarded UID installed through actual button")
	check(model.available_passives().has("26740") and model.passive_analysis().remote_sources.has("26740"),"Original 280 radius admits real disconnected standard-tree small node")
	var regeneration:float=model.get_stats().life_regen
	panel._find_node("26740");check(not panel._allocate.disabled,"Remote node has actual allocatable UI state")
	panel._allocate.pressed.emit();await process_frame;await process_frame
	check(model.talent_points==initial_points-5 and model.get_stats().life_regen>regeneration,"Remote allocation spends one point and produces original life regeneration")
	var before:=observe()
	panel._find_node("6230");panel._return.pressed.emit()
	check(observe()==before and model.location(uid).kind=="passive_socket","Removing supporting jewel is atomically refused")
	for id:String in ["50288","58833","6230"]:
		check(not model.passive_analysis().remote_sources.has(id),"Radius does not authorize keystone/start/socket: "+id)
	check(model.passive_analysis().remote_sources.keys().all(func(id:String):return Source.Data.node(id).type in ["small","notable"]),"All real covered candidates retain small/notable-only scope")
	reload_exact("Same boss jewel and actual remote allocation survive reload")

func normal_case()->void:
	if not await fresh("normal boss bag"):return
	var enemy:=boss();kill(enemy)
	var receipt:=pair("bag","bag")
	if receipt.is_empty():return
	check(model.pending_items().is_empty(),"Roomy bag introduces no recovery")
	duplicate_check(enemy);reload_exact("Normal rewards survive reload")

func recovery_case(existing:bool,fault:bool)->void:
	if not await fresh("full bag / existing=%s / write_fault=%s"%[existing,fault]):return
	var pending:=fill_bag(existing);var enemy:=boss()
	var old_disk:=disk();var old_state:Dictionary=model.snapshot();var saves:int=model.successful_saves
	model.fail_writes=fault;kill(enemy)
	var receipt:=pair("recovery","recovery")
	if receipt.is_empty():return
	var gear_uid:String=arena.boss_awards[0].uid
	check(model.pending_items()==([pending,gear_uid,receipt.uid] if existing else [gear_uid,receipt.uid]),"Append retains old pending plus both distinct boss rewards in order")
	if fault:
		check(disk()==old_disk and model.successful_saves==saves and arena._progress_save_dirty,"Failed death save preserves old bytes and dirty complete reward memory")
		var old:=Model.new();check(old.load_build(PATH) and old.snapshot()==old_state,"Disk reload after failure sees complete prior state")
		var expected:Dictionary=model.snapshot();duplicate_check(enemy)
		check(not arena.save_build() and model.snapshot()==expected and disk()==old_disk,"Failed explicit retry neither remints nor partially writes")
		model.fail_writes=false
		check(arena.save_build() and model.snapshot()==expected and not arena._progress_save_dirty,"Successful retry writes exact retained two rewards")
	else:check(model.successful_saves==saves+1,"Original reward batch saves both items once")
	duplicate_check(enemy);reload_exact("Both pending rewards survive canonical reload")
	if existing:
		var prior:Dictionary=model.snapshot()
		await dispose()
		arena=load("res://scenes/main.tscn").instantiate();arena.set_script(JewelMain)
		model=FaultModel.new();arena.state=model;root.add_child(arena);pause();await process_frame
		check(arena.world_context().normal_town and model.normal_journey().active_run.is_empty(),"Actual Main reload uses existing safe map abandonment")
		check(model.snapshot().items==prior.items and model.snapshot().locations==prior.locations and model.snapshot().next_item_serial==prior.next_item_serial,"Actual Main reload retains both rewards and old pending with no additional UIDs")
		check(model.normal_journey().pending_map_reward.is_empty() and model.normal_journey().best_tiers.old_garden==0,"Reload issues no completion receipt or tier unlock")
	await take_back(receipt.uid,receipt.item)
	if existing:check(model.pending_items().has(pending),"Original pending entry remains after jewel retrieval")
	else:await socket_checks(receipt.uid)

func pending_with_room_case()->void:
	if not await fresh("existing pending / room for both rewards"):return
	var pending:=fill_bag(true)
	# The old fixture's equipment-sized rectangle leaves room for the one-cell jewel too.
	for uid:String in filler_uids:
		var loc:Dictionary=model.location(uid)
		if loc.page==1 and loc.x>=4 and loc.y>=3:accepted(model.discard_item(uid,model.revision(),PATH),"Free actual bag rectangle while retaining old pending")
	var enemy:=boss();kill(enemy)
	if pair("bag","bag").is_empty():return
	check(model.pending_items()==[pending],"Existing recovery does not block normal bag placement or get overwritten")
	duplicate_check(enemy);reload_exact("Two new bag rewards and old pending reload unchanged")

func isolation_case()->void:
	if not await fresh("test boss remains original",true):return
	fill_bag();var formal_disk:=disk();var before:Dictionary=model.snapshot()
	kill(boss())
	check(model.pending_items().is_empty() and model.snapshot().items==before.items and model.snapshot().next_item_serial==before.next_item_serial,"Test boss full bag creates neither recovery nor new UID")
	check(disk()==formal_disk,"Test reward does not write formal profile")
	if not await fresh("ordinary / legacy / demo isolation"):return
	for enemy:Dictionary in arena.enemies:
		if int(enemy.id)!=arena._map_run.boss_id:kill(enemy);break
	check(arena.reward_kills==1 and arena.jewel_awards.is_empty() and not model.jewels.values().any(func(j:Dictionary):return j.base=="branchfinder"),"Actual ordinary root produces no special jewel")
	fill_bag();var authority:=observe()
	check(model.award_special_jewel().is_empty() and observe()==authority,"Original special award API retains full-bag refusal")
	check(model.award_jewel(arena.rng).is_empty() and observe()==authority,"Ordinary jewel drop retains original refusal and RNG")
	check(model.award_equipment(arena.rng,1).is_empty() and observe()==authority,"Ordinary equipment drop retains original refusal and RNG")
	arena.demo_mode=true;kill(boss())
	check(model.snapshot()==authority[0] and disk()==authority[1] and arena.jewel_awards.is_empty(),"Demo boss never enters special recovery path")

func guards_case()->void:
	if not await fresh("formal guard and original limits"):return
	var before:=observe()
	check(model.award_normal_boss_special_jewel(arena._normal_run_id+1).is_empty() and observe()==before,"Mismatched active run rejected")
	var original:Dictionary=model.snapshot()
	for field:String in ["revision","next_item_serial"]:
		var candidate:Dictionary=original.duplicate(true);candidate[field]=Model.Rules.MAX_SERIAL
		check(Model.Rules.reason(candidate).is_empty(),"Exhausted limit is still a lawful schema58 fixture: "+field)
		model._accept_memory(candidate);before=observe()
		check(model.award_normal_boss_special_jewel(arena._normal_run_id).is_empty() and observe()==before,"Original limit rejects admission without consuming identity: "+field)
	model._accept_memory(original)
	var capped:Dictionary=original.duplicate(true)
	while capped.items.size()<Model.Rules.V17_MAX_ITEMS:
		var uid:="item_%06d"%int(capped.next_item_serial);capped.next_item_serial+=1
		capped.items[uid]=Gems.create_instance(uid,"support:efficiency");capped.locations[uid]={"kind":"recovery","index":capped.items.size()-1}
	check(Model.Rules.reason(capped).is_empty(),"Original reward item-cap fixture passes unchanged schema58 rules")
	model._accept_memory(capped);before=observe()
	check(model.award_normal_boss_special_jewel(arena._normal_run_id).is_empty() and observe()==before,"Original item cap remains mandatory")
	model._accept_memory(original)
	accepted(model.normal_abandon_map(arena._normal_run_id,model.revision(),PATH),"Existing active-run abandonment")
	before=observe()
	check(model.award_normal_boss_special_jewel(arena._normal_run_id).is_empty() and observe()==before,"No active formal run cannot mint a recovered jewel")

func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-boss-jewel-"):quit(78);return
	await normal_case()
	await recovery_case(false,false)
	await recovery_case(true,true)
	await pending_with_room_case()
	await isolation_case()
	await guards_case()
	check(awards.size()==4,"All four actual positive boss scenarios completed")
	var description:=Jewels.get_description(Jewels.generate_special("jewel_000001"))
	check(description.contains("小型与显著天赋") and description.contains("不含基石、精通、起点或珠宝孔") and description.contains("280") and description.contains("1 点") and not description.contains("核心天赋"),"Actual item text accurately states unchanged type scope/radius/cost")
	await dispose()
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence,"awards":awards,"schema":Model.Rules.VERSION,"description":description,
		"scope":"Actual Main/HUD registered Old Garden boss in initial 25-root map; damage shortcut, capacity and write-fault fixtures; no natural-play or native-keyboard claim"}
	var path:=OS.get_environment("BOSS_JEWEL_REPORT")
	if not path.is_empty():
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n")
	print("FORMAL_BOSS_JEWEL_RECOVERY checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
