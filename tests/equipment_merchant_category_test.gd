extends "res://tests/flask_purchase_transactions_test.gd"
## Reuse the lawful physical-currency/capacity fixtures, not the parent's full run.
var arena:Node
var panel:Control
var cases:Array=[]
func settle()->void:await process_frame;await process_frame
func authority()->PackedByteArray:
	return var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(PATH),arena.state.save_attempts,arena.state.successful_saves,arena.rng.state,arena.critical_runtime.checkpoint(),arena.flask_runtime.snapshot()])
func click(button:Button)->void:
	var window:=button.get_window()
	var position:=button.get_global_rect().get_center()
	if window!=root and window.is_embedded():position+=Vector2(window.position)
	var window_id:int=root.get_window_id() if window.is_embedded() else window.get_window_id()
	var motion:=InputEventMouseMotion.new();motion.position=position;motion.window_id=window_id;Input.parse_input_event(motion)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=motion.position;event.window_id=window_id;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event)
	await settle()
func visible_rows()->Array:
	return panel._content.get_children().filter(func(row:Control)->bool:return row.visible)
func bottle_button(id:String)->Button:
	var rows:Array=arena.town_stock("equipment_merchant")
	for i:int in range(rows.size()):
		if rows[i].definition_id==id:return panel._content.get_child(i).get_child(2)
	return null
func fresh(balance:int,full:bool=false)->void:
	var model:=fixture(balance,full)
	arena=load("res://scenes/main.tscn").instantiate();arena.state=model;arena.build_save_path=PATH
	root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle();panel=arena.hud._town_view;panel.open_service("equipment_merchant");await settle()
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_environment("MERCHANT_CAPTURE_DIR")+"/"+name+".png")==OK,"Native merchant screenshot "+name)
func close_case()->void:arena.queue_free();await process_frame;arena=null
func unavailable_case(balance:int,full:bool)->void:
	await fresh(balance,full)
	check(panel._stock_categories.visible and visible_rows().size()==15,"Formal equipment tab initially shows the original fifteen bases")
	var before:=authority()
	await click(panel._stock_category_buttons.flask)
	check(panel._stock_category=="flask" and visible_rows().size()==2,"Real mouse category switch shows only original life and mana bottles")
	for id:String in ["flask:life","flask:mana"]:
		var button:=bottle_button(id)
		check(button.disabled and button.text=="8 碎片" and not button.tooltip_text.is_empty(),"Original price and unavailable reason retained: "+id)
		await click(button)
		check(panel._gem_pending.is_empty() and not panel._gem_dialog.visible,"Unavailable bottle cannot open a purchase")
		# A stale queued pressed signal still reaches the original guarded quote.
		button.pressed.emit();await settle()
		check(panel._gem_pending.is_empty() and authority()==before,"Authoritative quote rejects stale UI signal without debit/UID/save change")
	await click(panel._stock_category_buttons.flask);await click(panel._stock_category_buttons.flask)
	check(authority()==before and visible_rows().size()==2,"Repeated active-tab clicks neither purchase nor duplicate rows")
	await click(panel._stock_category_buttons.equipment)
	check(visible_rows().size()==15 and authority()==before,"Switch back restores original equipment with no economic side effect")
	cases.append({"case":"full_capacity" if full else "insufficient_funds","balance":arena.state.crafting_balance(),"rows":panel._content.get_child_count()})
	await close_case()
func purchase_case()->void:
	await fresh(16)
	await capture("equipment")
	var before:=authority();await click(panel._stock_category_buttons.flask)
	check(authority()==before,"Funded category change remains read-only")
	await capture("flasks")
	await click(bottle_button("flask:life"))
	check(panel._gem_dialog.visible and panel._gem_pending.get("kind","")=="flask","Real visible bottle row opens existing purchase confirmation")
	if panel._gem_pending.is_empty():await close_case();return
	var old_handle:String=panel._gem_pending.quote.handle
	# Defensive queued category change invalidates the same original quote service.
	panel._stock_category_buttons.equipment.pressed.emit();await settle()
	check(panel._gem_pending.is_empty() and not panel._gem_dialog.visible and not arena.execute_normal_flask_purchase(old_handle,"flask:life").ok and authority()==before,"Category change cancels old confirmation without a second purchase path")
	await click(panel._stock_category_buttons.flask)
	for id:String in ["flask:life","flask:mana"]:
		await click(bottle_button(id))
		check(panel._gem_pending.get("kind","")=="flask","Original bottle transaction selected: "+id)
		if panel._gem_pending.is_empty():await close_case();return
		var quote:Dictionary=panel._gem_pending.quote.duplicate(true)
		var prior:Dictionary=arena.state.snapshot();var balance:int=arena.state.crafting_balance();var saves:int=arena.state.successful_saves
		if id=="flask:life":await capture("confirmation")
		await click(panel._gem_dialog.get_ok_button())
		check(not arena.state.item(quote.uid).is_empty(),"Actual mouse confirmation purchases before duplicate callback probes")
		# Duplicate callbacks may already be queued when the original button disappears.
		panel._gem_dialog.confirmed.emit();panel._confirm_gem_purchase();await settle()
		check(arena.state.item(quote.uid)==Purchase.Flasks.create_instance(quote.uid,id) and arena.state.location(quote.uid).kind=="bag","Exact quoted existing flask UID enters canonical bag")
		check(arena.state.crafting_balance()==balance-8 and arena.state.successful_saves==saves+1 and arena.state.snapshot().next_item_serial==prior.next_item_serial+1,"Repeated confirmation still charges eight, allocates one UID and saves once")
		check(arena.state.snapshot().version==prior.version and arena.state.snapshot().journey==prior.journey,"Purchase preserves schema and journey/gift counters")
		check(panel._stock_category=="flask" and panel._stock_category_buttons.flask.button_pressed and visible_rows().size()==2,"Purchase refresh keeps the selected flask tab and exactly two rows")
		before=authority()
		check(not arena.execute_normal_flask_purchase(quote.handle,id).ok and authority()==before,"Consumed quote cannot replay")
	check(arena.state.crafting_balance()==0 and bottle_button("flask:life").disabled and bottle_button("flask:mana").disabled,"Last paid purchase refreshes affordability immediately")
	await click(panel._stock_category_buttons.equipment);check(visible_rows().size()==15,"Equipment remains reachable after purchase refresh")
	panel.open_service("skill_merchant");await settle();check(not panel._stock_categories.visible,"Other merchant has no irrelevant equipment/flask categories")
	panel.open_service("map_device");await settle();check(not panel._stock_categories.visible,"Map device keeps its existing layout")
	check(arena.enter_town_test(arena.world_context().revision).ok,"Existing isolated test profile still opens")
	panel.open_service("equipment_merchant");await settle();check(not panel._stock_categories.visible,"Free test supply remains unchanged")
	cases.append({"case":"two_paid_flasks","normal_purchase_count":2,"normal_cost":16})
	await close_case()
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-merchant-category-"):quit(78);return
	await unavailable_case(0,false);await unavailable_case(8,true);await purchase_case()
	var report:={"checks":checks,"failures":failures.size(),"failed_labels":failures,"cases":cases,"display":DisplayServer.get_name(),"fixture":"Existing lawful balance/full-bag fixtures; not natural currency acquisition"}
	FileAccess.open(OS.get_environment("MERCHANT_CATEGORY_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("MERCHANT_CATEGORY ",JSON.stringify(report));quit(1 if not failures.is_empty() else 0)
