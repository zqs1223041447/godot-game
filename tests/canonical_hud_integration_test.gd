extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const HudView = preload("res://scripts/game_hud.gd")
var arena: Node
var checks := 0
var failures := 0
var output := OS.get_environment("CANONICAL_HUD_CAPTURE_DIR")
func _initialize()->void: call_deferred("run")
func run()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		quit(78)
		return
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	var old_hud: Node=arena.hud
	arena.remove_child(old_hud)
	old_hud.free()
	var model:=Model.new()
	check(model.save_build()==OK,"fixture canonical save")
	arena.state=model
	arena._stats=model.get_stats()
	arena.hud=HudView.new()
	arena.add_child(arena.hud)
	arena.hud.setup(arena)
	model.changed.connect(arena._on_build_changed)
	arena.visual_settings.ui_scale=1.1
	arena.visual_settings.font_scale=1.2
	root.size=Vector2i(2560,1440)
	arena.hud._apply_presentation()
	await frames()
	var hud: Node=arena.hud
	hud.open_panel("inventory")
	await frames()
	check(hud._inventory_panel is CanonicalInventoryPanel,"I uses canonical inventory body")
	check(hud._inventory_panel._slots.size()==9,"actual HUD has nine equipment targets")
	check(hud._root.find_child("BuildTabs",true,false)==null,"independent root retains no shared tabs")
	var inventory: Node=hud._inventory_panel
	inventory._activate_item("swift_blade")
	await frames()
	check(model.location("swift_blade").kind=="equipment","UI action commits authoritative model")
	var uid: String="migration_gem_000009"
	var bag_ids: Array=[]
	for id: String in model.snapshot().locations:
		if model.location(id).kind=="bag": bag_ids.append(id)
	uid=str(bag_ids[0])
	hud._show_item_hover(uid,inventory._grid.get_global_transform()*inventory._grid.item_rect(uid))
	await frames()
	check(hud._item_hover.visible,"shared hover card opens from UID")
	var discard_uid:=""
	for id:String in model.snapshot().items:
		if model.item(id).definition_id=="support:physical_focus":discard_uid=id
	inventory._select_item(discard_uid)
	inventory._request_discard()
	check(inventory._craft_dialog.visible and not inventory._pending_discard.is_empty(),"discard first action only opens confirmation")
	inventory._cancel_craft()
	check(not inventory._craft_dialog.visible and not model.item(discard_uid).is_empty(),"discard cancel preserves exact instance")
	inventory._request_discard()
	model.bind_group("group_000009",KEY_9,model.revision(),"user://build_save.json")
	inventory._confirm_craft()
	check(not model.item(discard_uid).is_empty(),"stale visible discard request cannot consume item")
	inventory._craft_dialog.hide()
	inventory._request_discard()
	inventory._confirm_craft()
	check(model.item(discard_uid).is_empty(),"fresh confirmed discard persists exactly selected bag gem")
	inventory._confirm_craft()
	check(model.item(discard_uid).is_empty(),"repeat confirmation cannot consume any other item")
	inventory._craft_dialog.hide()
	await capture("inventory")
	hud.open_panel("skills")
	await frames()
	check(not hud._item_hover.visible,"switching independent root clears old hover")
	check(hud._skill_support_panel is CanonicalSkillPanel,"K uses instantiated gem rows")
	var skills: Node=hud._skill_support_panel
	check(skills._rows._rows.size()==10,"ten real rows")
	var source:=model.snapshot()
	for definition_id: String in ["swift_projectiles","heavy_projectiles","lingering_chill","efficiency","quickcast"]:
		var support_uid: String=""
		for id: String in source.items:
			if source.items[id].definition_id=="support:"+definition_id: support_uid=id
		var index:int=model.skill_group("group_000002").support_ids.size()
		skills._move(support_uid,{"kind":"skill_support","group_id":"group_000002","index":index},model.revision())
	await frames()
	check(model.skill_group("group_000002").support_ids.size()==5,"K controller applies all five owned instances")
	check(skills._rows._rows[1].supports[4].uid!="","fifth slot visibly reflects actual UID")
	skills._bind("group_000002",KEY_F1,model.revision())
	check(model.group_for_key(KEY_F1)=="group_000002","K binding controller commits same group")
	await capture("skills-five-links")
	hud.close_panel()
	arena.mana=arena._stats.max_mana
	var event:=InputEventKey.new()
	event.physical_keycode=KEY_F1
	event.keycode=KEY_F1
	event.pressed=true
	root.push_input(event,true)
	await frames()
	check(arena.projectiles.size()==5 and arena.group_cooldown_remaining("group_000002")>0,"configured F1 input actually casts same five-link group")
	hud.open_panel("skills")
	await frames()
	check(model.skill_group("group_000002").support_ids.size()==5,"menu reopen preserves five owned gems")
	hud.open_panel("talents")
	await frames()
	check(hud._passive_panel is CanonicalPassivePanel,"T uses full pinned source canvas")
	var passives:Node=hud._passive_panel
	check(passives._tree._nodes.size()==2387 and passives._tree._edges.size()==2697,"real standard source topology in HUD")
	passives._node_clicked("2151",MOUSE_BUTTON_LEFT,false)
	check(not passives._allocate.disabled,"default Scion intelligence first step enabled")
	var before_points:int=model.talent_points
	passives._allocate_selected()
	await frames()
	check(model.talent_points==before_points-1 and model.snapshot().talents.allocated.has("2151"),"T action uses source transaction and points")
	check(model.get_stats().intelligence==25,"allocated original stat has actual derived consumer")
	await capture("source-tree")
	passives._refund_selected()
	await frames()
	check(model.talent_points==before_points,"T refund reverses source allocation")
	passives._node_clicked("22497",MOUSE_BUTTON_LEFT,false)
	check(passives._allocate.disabled and passives._detail.text.contains("不可分配"),"unsupported cast-speed node clearly locked")
	passives._change_partition(1)
	await frames()
	check(not passives._tree._nodes.is_empty() and passives._allocate.disabled,"separate source ascendancy browsable without free allocations")
	await capture("source-ascendancy")
	passives._focus_start()
	await frames()
	check(passives._tree._nodes.size()==2387,"return from subtree restores full standard graph")
	passives._tree.fit_tree()
	await frames()
	var overview_bounds:=Rect2(Vector2.ZERO,passives._tree.size)
	for id:String in passives._tree._nodes:
		check(overview_bounds.has_point(passives._tree.node_screen_position(id)),"full-tree action includes original node "+id)
	await capture("source-tree-overview")
	passives._focus_start()
	root.size=Vector2i(1280,720)
	hud._apply_presentation()
	await frames()
	check(passives.get_global_rect().end.x<=root.get_visible_rect().size.x+1.0,"720p source panel no horizontal overflow in viewport coordinates")
	await capture("source-tree-720p")
	print("Canonical HUD integration: %d checks, %d failures" % [checks,failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
func frames()->void:
	for i:int in range(6): await process_frame
func capture(stem:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(output)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(stem+"-ui110-font120.png"))
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
