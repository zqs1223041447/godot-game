extends SceneTree
const Items=preload("res://scripts/items/unified_item_catalog.gd")
var checks:=0
var failures:=0
var arena: Node
var panel: Control
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func frames(count:int=3)->void:
	for unused:int in range(count):await process_frame
func request(operation:String)->void:
	var button:Button=panel._craft_controls._operation_buttons[operation]
	button.button_down.emit();button.pressed.emit();await frames()
func confirm()->void:
	panel._craft_dialog.get_ok_button().pressed.emit();await frames()
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-root-craft-ui-"):quit(78);return
	root.size=Vector2i(1280,720)
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
	arena.set_process(false);arena.set_physics_process(false);await frames(5)
	var state=arena.state
	var first:="gear_%06d" % int(state.snapshot().next_item_serial)
	var second:="gear_%06d" % (int(state.snapshot().next_item_serial)+1)
	check(state._admit_reward_item(Items.wrap_equipment({"id":first,"base_id":"cinder_reed","rarity":"normal","item_level":30,"affixes":[]})),"Legal normal fixture admitted")
	check(state._admit_reward_item(Items.wrap_equipment({"id":second,"base_id":"cinder_reed","rarity":"magic","item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]})),"Legal one-affix fixture admitted")
	if failures>0:
		arena.queue_free();await frames(1);quit(1);return
	var candidate:Dictionary=state.snapshot();check(state._set_bag_currency_balance(candidate,200).ok,"Real shard fixture funded")
	state._accept_memory(candidate);check(state.save_build("user://build_save.json")==OK,"Fixture persisted before UI actions")
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.hud.open_panel("inventory");await frames()
	panel=arena.hud._inventory_panel
	check(panel._craft_controls._operation_buttons.size()==6,"Six metadata operations remain visible without selection")
	for button:Button in panel._craft_controls._operation_buttons.values():check(button.visible and button.disabled,"Unselected action is present and disabled")
	var sequence:int=state._craft_sequence
	panel._select_item(first);await frames()
	check(state._craft_quotes.is_empty() and state._craft_sequence==sequence,"Selecting item creates zero quotes")
	check(not panel._craft_controls._operation_buttons.enchant.disabled,"Normal gear enables enchant")
	check(panel._craft_controls._operation_buttons.elevate.disabled,"Normal gear cannot elevate")
	check(not panel._craft_controls._balance_label.visible,"No duplicate material wallet label")
	await request("enchant")
	check(panel._craft_dialog.visible and state._craft_quotes.size()==1,"Click requests exactly one authoritative quote")
	if not panel._pending_craft.has("quote"):
		arena.queue_free();await frames(1);quit(1);return
	check(panel._pending_craft.quote.cost.calibration_shard==8 and "8" in panel._craft_dialog.dialog_text,"Confirmation displays authoritative fee")
	panel._craft_dialog.get_cancel_button().pressed.emit();await frames()
	check(state._craft_quotes.is_empty() and state.crafting_balance()==200,"Cancel releases handle without payment")
	var runtime:Dictionary=arena.flask_runtime.snapshot()
	await request("enchant");await confirm()
	check(state.item(first).payload.rarity=="magic" and state.crafting_balance()==192,"Confirmed UI enchant commits exact cost")
	await request("elevate");await confirm()
	check(state.item(first).payload.rarity=="rare" and state.crafting_balance()==168,"UI elevate retains identity and spends24")
	await request("reforge")
	check(not str(panel._craft_metadata.reforge.risk).is_empty() and str(panel._craft_metadata.reforge.risk) in panel._craft_dialog.dialog_text,"Reforge risk appears in confirmation")
	await confirm();check(state.crafting_balance()==140,"UI reforge charges correct rare fee")
	panel._select_item(second);await request("augment");await confirm()
	check(state.item(second).payload.affixes.size()==2 and state.crafting_balance()==134,"UI augment appends one for six shards")
	var saved:int=state.successful_saves;var revision:int=state.revision()
	panel._craft_dialog.confirmed.emit();await frames()
	check(state.successful_saves==saved and state.revision()==revision,"Duplicate confirmation has no second transaction")
	var button:Button=panel._craft_controls._operation_buttons.reforge
	button.button_down.emit();panel._select_item(first);sequence=state._craft_sequence;button.pressed.emit();await frames()
	check(state._craft_sequence==sequence and state._craft_quotes.is_empty(),"Selection change during press cannot request stale item")
	check(arena.flask_runtime.snapshot()==runtime,"Crafting leaves flask runtime unchanged")
	for resolution:Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=resolution
		if resolution.x==2560:arena.visual_settings.ui_scale=1.1;arena.visual_settings.font_scale=1.2
		arena.hud._apply_presentation();await frames()
		var row:Control=panel._craft_controls._button_row
		for action:Button in panel._craft_controls._operation_buttons.values():check(row.get_global_rect().encloses(action.get_global_rect()),"Action fits compact row at %d"%resolution.x)
	print("Craft metadata UI: %d checks, %d failures"%[checks,failures])
	arena.queue_free();await frames(1);quit(1 if failures else 0)
