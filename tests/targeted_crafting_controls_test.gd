extends SceneTree
const Controls = preload("res://scripts/ui/crafting_controls.gd")
var checks := 0
var failures := 0
var requests: Array[Dictionary] = []
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func entry(id: String,label: String,available: bool=true) -> Dictionary:
	return {"operation":"targeted_reforge_"+id,"targeted":true,"target_id":id,"target_label":label,"label":"定向重铸","available":available,"reason":"此底材没有合法目标" if not available else "","description":"保证所选方向","risk":"替换全部词缀","cost":{"calibration_shard":16}}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var controls := Controls.new()
	root.add_child(controls)
	await process_frame
	controls.craft_requested.connect(func(op: String,uid: String,source: Dictionary): requests.append({"operation":op,"uid":uid,"source":source}))
	var source := {"serial":1}
	var operations := [{"operation":"salvage","label":"回收","available":true,"materials":{"calibration_shard":1}},entry("critical","暴击"),entry("life_leech","生命偷取"),entry("mana_leech","魔力偷取"),entry("damage","伤害",false)]
	var original := var_to_bytes(operations)
	controls.set_operations_context("equipment-a",source,100,operations)
	expect(controls._target_row.visible and controls._target_select.item_count == 4,"Four families share one compact row")
	expect(controls._operation_buttons.size() == 2,"No four extra large operation buttons")
	expect(controls._target_button.text.contains("16") and not controls._target_button.disabled,"Actual quoted cost visible")
	expect(controls._target_select.is_item_disabled(3),"Incompatible family disabled")
	expect(controls._target_select.get_popup().get_item_tooltip(3).contains("没有合法目标"),"Incompatible reason accessible")
	expect(controls._target_button.tooltip_text.contains("替换全部词缀"),"Replacement risk in tooltip")
	expect(var_to_bytes(operations) == original,"UI does not mutate operation metadata")
	controls._capture_targeted()
	controls._request_targeted()
	expect(requests.size() == 1 and requests[0].operation == "targeted_reforge_critical","Selected family reaches existing request signal")
	expect(requests[0].uid == "equipment-a" and requests[0].source == source,"Exact UID and source carried")
	requests[0].source.serial = 99
	expect(controls._source_instance.serial == 1,"Emitted source is detached")
	requests.clear()
	controls._capture_targeted()
	controls._select_target(1)
	controls._request_targeted()
	expect(requests.is_empty(),"Changing target during press cancels that click")
	controls._request_targeted()
	expect(requests.size() == 1 and requests[0].operation == "targeted_reforge_life_leech","Keyboard/direct activation uses current target")
	requests.clear()
	controls._capture_targeted()
	controls._release_targeted()
	await process_frame
	expect(controls._target_pressed_operation.is_empty() and controls._pending_requests.is_empty(),"Interrupted click clears pending capture")
	controls._select_target(3)
	controls._request_targeted()
	expect(requests.is_empty() and controls._target_button.disabled,"Invalid family cannot request crafting")
	controls.set_operations_context("equipment-a",source,100,operations,"请先返回城镇")
	expect(controls._target_button.disabled and controls._target_button.tooltip_text.contains("返回城镇"),"Outer world restriction remains authoritative")
	controls.set_operations_context("gem-a",source,100,[operations[0]])
	expect(not controls._target_row.visible,"Gem recycling has no equipment-target controls")
	controls.set_context("equipment-a",source,100,{"ok":true,"materials":{"calibration_shard":1}},{"ok":true,"cost":{"calibration_shard":2}})
	expect(not controls._target_row.visible and not controls._salvage_button.disabled,"Legacy two-operation view unchanged")
	controls.queue_free()
	await process_frame
	print("Targeted crafting controls: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
