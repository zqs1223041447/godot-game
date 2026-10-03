extends SceneTree
const Model=preload("res://scripts/build_state.gd")
const Emblem=preload("res://scripts/visuals/skill_emblem.gd")
var arena: Node
var checks: int=0
var failures: int=0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func button(id: String) -> Button: return arena.hud.find_child(id,true,false) as Button
func label(id: String) -> Label: return arena.hud.find_child(id,true,false) as Label
func select_skill(skill: String) -> void:
	var position: int=arena.state.skill_slots.find(skill)
	button("SlotButton%d" % (position+1) if position>=0 else "SelectSkill_"+skill).pressed.emit()
func settle() -> void:
	for i: int in range(4): await process_frame
func run() -> void:
	var isolated: String=OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name()!="Linux" or not isolated.begins_with("/tmp/godot-") or not OS.get_user_data_dir().simplify_path().begins_with(isolated+"/"):
		quit(78)
		return
	var state:=Model.new()
	expect(state.save_build()==OK,"Isolated initial save")
	arena=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	var key:=InputEventKey.new()
	key.physical_keycode=KEY_K
	key.pressed=true
	arena._unhandled_key_input(key)
	await settle()
	expect(arena.hud.is_blocking(),"Actual K handler opens support UI")
	var panel: Control=arena.hud.find_child("SkillSupportPanel",true,false)
	expect(Emblem.ICONS.has("breadth") and Emblem.ICONS.breadth.get_width()==512,"Approved original icon imported at expected size")
	for skill: String in ["nova","meteor"]:
		select_skill(skill)
		await settle()
		var radius: String="186" if skill=="nova" else "132"
		expect(not button("AddSupport_breadth").disabled,"New area support eligible in real panel")
		for other: String in ["focus","volley","pierce"]:
			expect(button("AddSupport_"+other).disabled,"Other programs stay ineligible")
		arena.cooldowns[skill]=1.23
		button("AddSupport_breadth").pressed.emit()
		expect(arena.state.get_skill_supports(skill)==["breadth"],"Connected add commits correct skill identity")
		expect(label("SupportCastPreview").text.contains("半径 "+radius) and label("SupportCastPreview").text.contains("面积 ×1.44"),"Compact preview explains both values")
		expect(label("SupportCastPreview").tooltip_text.contains("平方根") and not label("SupportCastPreview").text.contains("初始投射物"),"Detail explains conversion without irrelevant projectile count")
		var snapshot: Dictionary=arena.state._snapshot()
		var saved: PackedByteArray=FileAccess.get_file_as_bytes("user://build_save.json")
		button("AddSupport_breadth").pressed.emit()
		expect(arena.state._snapshot()==snapshot and FileAccess.get_file_as_bytes("user://build_save.json")==saved,"Repeated disabled add has no changes or extra save")
		var stale: Button=button("RemoveSupport1")
		stale.pressed.emit()
		expect(arena.state.get_skill_supports(skill).is_empty(),"Actual remove restores original geometry")
		stale.pressed.emit()
		expect(arena.state.get_skill_supports(skill).is_empty(),"Stale remove stays harmless")
		button("AddSupport_breadth").pressed.emit()
		expect(arena.cooldowns[skill]==1.23,"Editing does not reset cooldown")
	for skill: String in ["bolt","frost","tornado","chain","dash","ward"]:
		select_skill(skill)
		var before: Dictionary=arena.state._snapshot()
		expect(button("AddSupport_breadth").disabled,"Unsupported selection visibly disables area helper")
		button("AddSupport_breadth").pressed.emit()
		expect(arena.state._snapshot()==before,"Forced disabled callback rejects atomically")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		for scale: float in [1.0,1.2]:
			root.size=dimensions
			arena.visual_settings.ui_scale=1.1 if scale>1 else 1.0
			arena.visual_settings.font_scale=scale
			arena.hud._apply_presentation()
			for skill: String in ["nova","meteor"]:
				select_skill(skill)
				await settle()
				arena.hud._panel_scroll.ensure_control_visible(button("AddSupport_breadth"))
				await settle()
				var rect: Rect2=panel.get_global_rect()
				for control: Control in [button("AddSupport_breadth"),label("SupportCastPreview"),label("SupportDescription_breadth")]:
					expect(control.get_global_rect().position.x>=rect.position.x-0.1 and control.get_global_rect().end.x<=rect.end.x+0.1,"Area panel fits unchanged scroll width at both font scales")
	var reloaded:=Model.new()
	expect(reloaded.load_build() and reloaded.get_skill_supports("nova")==["breadth"] and reloaded.get_skill_supports("meteor")==["breadth"],"UI autosave reloads independent new links")
	arena.hud.close_panel()
	arena._unhandled_key_input(key)
	await settle()
	panel=arena.hud.find_child("SkillSupportPanel",true,false)
	select_skill("nova")
	expect(button("AddSupport_breadth").disabled and label("SupportSlotCaption").text.contains("1 / 2"),"Reopen retains one used slot without claiming multiple compatible choices")
	arena.queue_free()
	await process_frame
	print("Area support UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
