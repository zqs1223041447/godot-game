extends SceneTree
const Items=preload("res://scripts/items/unified_item_catalog.gd")
class CaptureObserver extends Node:
	var arena: Node
	var folder: String
	var last := ""
	var index := 0
	func _process(_delta: float) -> void:
		var panel: Control=arena.hud._inventory_panel
		if not is_instance_valid(panel):return
		var stamp: String="%d:%s:%s" % [arena.state.revision(),panel._selected_uid,panel._craft_dialog.visible]
		if stamp!=last:
			last=stamp
			capture.call_deferred(stamp)
	func capture(stamp: String) -> void:
		await RenderingServer.frame_post_draw
		index+=1
		get_viewport().get_texture().get_image().save_png(folder.path_join("craft-%02d.png"%index))
		var file:=FileAccess.open(folder.path_join("craft-%02d.json"%index),FileAccess.WRITE)
		file.store_string(JSON.stringify({"stamp":stamp,"balance":arena.state.crafting_balance(),"snapshot":arena.state.snapshot()},"\t",true))
func _initialize()->void:call_deferred("run")
func run()->void:
	var folder:=OS.get_environment("CRAFT_CAPTURE_DIR")
	if DisplayServer.get_name()=="headless" or folder.is_empty() or not OS.get_environment("XDG_DATA_HOME").contains("root-craft-native"):
		quit(78);return
	DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1280,720)
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
	arena.set_process(false);arena.set_physics_process(false);arena.auto_fire=false;arena.enemies.clear()
	for unused:int in range(6):await process_frame
	var state=arena.state
	var first:="gear_%06d" % int(state.snapshot().next_item_serial)
	if not state._admit_reward_item(Items.wrap_equipment({"id":first,"base_id":"cinder_reed","rarity":"normal","item_level":30,"affixes":[]})):quit(1);return
	var second:="gear_%06d" % int(state.snapshot().next_item_serial)
	if not state._admit_reward_item(Items.wrap_equipment({"id":second,"base_id":"cinder_reed","rarity":"magic","item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]})):quit(1);return
	var candidate:Dictionary=state.snapshot()
	if not state._set_bag_currency_balance(candidate,200).ok:quit(1);return
	state._accept_memory(candidate)
	if state.save_build("user://build_save.json")!=OK:quit(1);return
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.hud.open_panel("inventory")
	arena.hud._inventory_panel._select_item(first)
	arena.hud._toast_left=0;arena.hud._toast.hide()
	var observer:=CaptureObserver.new();observer.arena=arena;observer.folder=folder;root.add_child(observer)
	print("CRAFT_NATIVE_REVIEW_READY ",first," ",second)
