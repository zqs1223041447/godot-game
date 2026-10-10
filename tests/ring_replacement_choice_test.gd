extends "res://tests/recovery_item_comparison_test.gd"
## Reuse real Main/death/save-fault and viewport input helpers, not prior suites.
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Base = preload("res://tests/formal_boss_equipment_recovery_test.gd")
var messages: Array[String] = []
var rings: Array[String] = []
var chosen_seed := -1

class RingMain extends Base.ObservedMain:
	var ring_seed := -1
	func _award_kill_equipment(enemy: Dictionary) -> void:
		if enemy.get("rarity", "") == "boss" and ring_seed >= 0: rng.seed = ring_seed
		super._award_kill_equipment(enemy)

func fresh(label: String, _test_profile: bool = false) -> bool:
	group = label
	await dispose()
	if FileAccess.file_exists(PATH):
		if not check(DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))==OK,"Remove only isolated suite save"): return false
	arena=load("res://scenes/main.tscn").instantiate(); arena.set_script(RingMain)
	model=FaultModel.new(); arena.state=model
	root.add_child(arena); pause(); await process_frame
	if not check(arena.world_context().normal_town and arena.save_build(),"Actual Main opens formal town"): return false
	if not accepted(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision),"Select existing free tier-I map"): return false
	if not accepted(arena.start_map(arena.map_draft().revision),"Actual map admission"): return false
	pause(); filler_uids.clear()
	return check(arena.enemies.size()==25 and not boss().is_empty(),"Actual map registers full roots and boss")

func owned_ring() -> String:
	var uid := "gear_%06d" % int(model.snapshot().next_item_serial)
	var affixes: Array = []
	for id: String in ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "nine_slot_suffix_endurance"]:
		var tier: Dictionary = Gear.affix_definition(id).tiers[2]
		affixes.append({"id":id,"tier":3,"value":tier.max})
	var item := {"id":uid,"base_id":"nine_slot_etched_ring","rarity":"rare","item_level":16,"affixes":affixes}
	check(Gear.validate_instance(item) and model._admit_reward_item(Model.Items.wrap_equipment(item)), "Lawful pre-owned ring fixture admitted without replacing existing items")
	return uid
func activate(uid: String) -> void:
	var panel: Control = arena.hud._inventory_panel
	var target_page: int = model.location(uid).page
	panel._turn_page(target_page - panel._bag_page)
	var scroll: ScrollContainer = arena.hud._dock_scrolls.right
	scroll.scroll_vertical = 0; await frames()
	var point: Vector2 = panel._grid.get_global_transform_with_canvas() * panel._grid.item_rect(uid).get_center()
	await motion(point)
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_RIGHT; event.pressed = down
		Input.parse_input_event(event); Input.flush_buffered_events(); await frames(1)
func menu_key(code: int) -> void:
	var menu: PopupMenu = arena.hud._inventory_panel._equip_menu
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = down
		event.window_id = root.get_window_id() if menu.is_embedded() else menu.get_window_id()
		Input.parse_input_event(event)
	await frames()
func choose(index: int) -> void:
	arena.hud._inventory_panel._equip_menu.set_focused_item(index)
	await menu_key(KEY_ENTER)
func finish() -> void:
	var path := OS.get_environment("RING_CHOICE_REPORT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"baseline":baseline,"seed":chosen_seed,"checks":checks,"failures":failures,"evidence":evidence,"messages":messages,"rings":rings,"reward":receipt},"\t")+"\n")
	print("Ring replacement: %d checks, %d failures" % [checks,failures.size()])
	await dispose(); quit(0 if failures.is_empty() else 1)
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-ring-choice-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78); return
	baseline = OS.get_environment("RING_CHOICE_BASELINE") == "1"
	root.size = Vector2i(1280,720)
	if not await fresh("right-click ring target choice"): await finish(); return
	# Search only an isolated oracle, then control a single boss reward RNG seed.
	var random := RandomNumberGenerator.new()
	for value: int in range(128):
		random.seed = value
		var rolled: Dictionary = Gear.generate_loot_profile(random,"gear_999999",1,"rare",Model.LOOT_PROFILE_ID)
		if Gear.base_definition(rolled.base_id).slot == "ring": chosen_seed = value; break
	if not check(chosen_seed >= 0,"Bounded oracle finds naturally eligible current-pool ring roll"): await finish(); return
	arena.ring_seed = chosen_seed
	for slot: String in ["ring_1","ring_2"]:
		var uid := owned_ring(); rings.append(uid)
		accepted(model.move_item(uid,{"kind":"equipment","slot_id":slot},model.revision(),PATH),"Equip pre-owned " + slot)
	var enemy := boss(); kill(enemy)
	if not check(arena.boss_awards.size()==1,"Actual registered boss awards one original equipment roll"): await finish(); return
	receipt = arena.boss_awards[0]
	var uid: String = receipt.uid
	check(model.item(uid)==receipt.expected and receipt.rng==receipt.expected_rng and model.item_definition(uid).category=="ring", "Actual boss ring keeps exact original UID, roll and RNG")
	check(model.location(uid).kind=="bag", "Actual reward enters bag")
	repeated_death(enemy)
	arena.hud.open_panel("inventory"); await frames()
	var panel: Control = arena.hud._inventory_panel
	panel.feedback.connect(func(message: String): messages.append(message))
	check(Presentation.comparisons(model,uid).size()==2,"Existing comparison exposes both occupied ring targets")
	var before := observe()
	await activate(uid)
	if baseline:
		check(model.equipped_items().ring_1==uid and model.equipped_items().ring_2==rings[1],"BASELINE REPRO: actual right-click immediately replaces ring one, offers no target choice")
		check(model.location(rings[0]).kind=="bag", "Baseline original ring is safely returned, not lost")
		await finish(); return
	check(panel._equip_menu.visible and observe()==before,"Actual right-click opens target menu without any mutation")
	check(panel._equip_menu.item_count==2 and panel._equip_menu.get_item_text(0).contains("戒指一") and panel._equip_menu.get_item_text(1).contains("戒指二"),"Both menu options identify actual destination slots")
	for index: int in range(2):
		check(panel._equip_menu.get_item_text(index).contains(model.item_definition(rings[index]).name),"Choice names exact currently equipped ring")
	await menu_key(KEY_ESCAPE)
	check(observe()==before and panel._pending_equip.is_empty(),"Actual Escape cancels menu without writes or equip")
	await activate(uid)
	model.fail_writes = true; await choose(1)
	check(observe()==before and messages.any(func(message:String):return message.contains("保存失败")),"Selected ring-two save failure reports reason and preserves complete memory/disk/UIDs")
	model.fail_writes = false
	accepted(model.move_item(rings[1],model.first_bag_position(rings[1]),model.revision(),PATH),"Temporarily unequip original ring through canonical transfer")
	await activate(uid)
	check(not panel._equip_menu.visible and model.equipped_items().ring_2==uid and model.equipped_items().ring_1==rings[0],"Actual right-click uses empty second slot directly, preserving first ring")
	accepted(model.move_item(rings[1],{"kind":"equipment","slot_id":"ring_2"},model.revision(),PATH),"Restore prior equipped ring through original swap")
	# Fill remaining cells; swapping one ring can reuse its original cell.
	fill_bag(); before = observe()
	arena.health = float(arena.get_stats().max_health); arena.mana = float(arena.get_stats().max_mana); arena.shield = float(arena.get_stats().max_shield)
	var old_caps: Dictionary = arena.get_stats().duplicate(true)
	await activate(uid); await choose(1)
	check(model.equipped_items().ring_2==uid and model.equipped_items().ring_1==rings[0],"Actual target selection replaces ring two while preserving ring one")
	check(model.location(rings[1])==before[0].locations[uid],"Full bag swaps displaced original ring into vacated candidate cell")
	check(model.snapshot().items==before[0].items and model.snapshot().next_item_serial==before[0].next_item_serial,"Swap preserves every UID/payload and serial; no reward, sale or deletion")
	check(arena.get_stats().max_health < old_caps.max_health and arena.get_stats().max_mana < old_caps.max_mana and arena.get_stats().max_shield < old_caps.max_shield,"Replacing controlled high-stat ring produces real lower resource caps")
	check(arena.health==arena.get_stats().max_health and arena.mana==arena.get_stats().max_mana and arena.shield==arena.get_stats().max_shield,"Main clamps current health, mana and shield to actual post-equip maxima")
	check(model.snapshot().skill_groups==before[0].skill_groups and model.snapshot().bindings==before[0].bindings and Model.Rules.reason(model.snapshot()).is_empty(),"Original skill groups, bindings and complete build legality preserved")
	reload_exact("Chosen ring target and all displaced/full-bag items survive exact reload")
	await activate(rings[1]); await choose(0)
	check(model.equipped_items().ring_1==rings[1] and model.equipped_items().ring_2==uid and model.location(rings[0]).kind=="bag","Explicit first target also swaps safely without disturbing second target")
	var bag_ring: String = rings[0]
	# Open a second choice, then change revision via a legal arrangement.
	await activate(bag_ring)
	accepted(model.arrange_items(model.revision(),PATH),"Existing arrangement changes revision during open choice")
	await frames(); before = observe()
	check(not panel._equip_menu.visible and panel._pending_equip.is_empty(),"Model change cancels stale target choice")
	panel._choose_equipment_target(0)
	check(observe()==before,"Late menu callback cannot execute canceled request")
	await activate(bag_ring); before = observe(); arena.hud.close_panel(); await frames()
	check(not panel._equip_menu.visible and panel._pending_equip.is_empty() and observe()==before,"Closing inventory cancels open choice without changing items")
	repeated_death(enemy)
	await finish()
