extends "res://tests/passive_action_preview_test.gd"
## Legal high-level graph fixture; original preview planner and real save commands.
var resource_cases:Array=[]
var ui_case:Dictionary={}
var arena:Node
var panel:Control
func choose(stat:String,mode:String,excluded:Array=[]) -> String:
	for id:String in source_graph().reached:
		if id in excluded:continue
		for grant:Dictionary in Runtime.node_effect(id).grants:
			if grant.stat==stat and grant.mode==mode and float(grant.value)>0:return id
	return ""
func prefix_for(id:String) -> Array:
	var prefix:=path_to(id);prefix.pop_back();return prefix
func resource_case(label:String,id:String,source:Dictionary,effect:int=0) -> Dictionary:
	var f:=fixture(source)
	var preview:=read_preview(f,id,effect)
	if not check(preview.allocate.allowed,label+": original plan admits selected node"):return {}
	var changes:Dictionary=preview.allocate.resource_changes
	var before:Dictionary=f.model.get_stats()
	check(f.model.allocate_passive(id,effect,f.model.revision(),f.path).ok,label+": actual allocation saves")
	var after:Dictionary=f.model.get_stats()
	for stat:String in ["max_health","max_mana","max_shield"]:
		check(changes.has(stat)==not is_equal_approx(before[stat],after[stat]),label+": only actual changed capacity appears: "+stat)
		if changes.has(stat):check(changes[stat].before==before[stat] and changes[stat].after==after[stat],label+": preview equals actual compiled result: "+stat)
	var reverse:=read_preview(f,id,effect)
	check(reverse.refund.allowed,label+": original leaf can be refunded")
	for stat:String in changes:
		check(reverse.refund.resource_changes[stat]=={"before":after[stat],"after":before[stat]},label+": refund predicts exact inverse: "+stat)
	check(f.model.refund_passive(id,f.model.revision(),f.path).ok and f.model.get_stats()==before,label+": actual refund restores compiled build")
	var loaded:=Model.new();check(loaded.load_build(f.path) and loaded.get_stats()==before,label+": actual reload retains restored build")
	resource_cases.append({"case":label,"node":id,"effect":effect,"changes":changes})
	return {"source":source,"id":id,"preview":preview,"changes":changes}
func settle() -> void:await process_frame;await process_frame
func click(button:Button) -> void:
	var scroll:ScrollContainer=button.get_parent().get_parent();scroll.ensure_control_visible(button);await settle()
	var motion:=InputEventMouseMotion.new();motion.position=button.get_global_rect().get_center();Input.parse_input_event(motion)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=motion.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event)
	await settle()
func capture(name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	var scroll:ScrollContainer=panel._detail.get_parent().get_parent();scroll.ensure_control_visible(panel._allocate);await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_environment("RESOURCE_PREVIEW_OUTPUT").path_join(name+".png"))==OK,"Native T screenshot "+name)
func ui_checks() -> void:
	var f:=fixture(ui_case.source);f.path="user://build_save.json";check(f.model.save_build(f.path)==OK,"Persist UI fixture at original formal path")
	arena=load("res://scenes/main.tscn").instantiate();arena.state=f.model;arena.build_save_path=f.path;root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false);await settle();arena.hud.open_panel("talents");await settle()
	panel=arena.hud._passive_panel
	panel._tree.node_clicked.emit(ui_case.id,MOUSE_BUTTON_LEFT,false)
	panel._tree.pan=-Runtime.Data.node(ui_case.id).position*panel._tree.zoom;panel._tree.queue_redraw();await settle()
	check(panel._detail.text.contains("分配后资源上限") and panel._detail.text.contains("生命"),"Actual T selection displays compiled capacity preview")
	await capture("allocate-preview")
	var before:=mark(f);f.model.fail_save=true;await click(panel._allocate);f.model.fail_save=false
	failed_commit_unchanged(f,before,1,"Failed real UI allocation preserves build, capacities, revision, UID/currency data and disk")
	check(panel._detail.text.contains("分配后资源上限") and not panel._allocate.disabled,"Save failure leaves actionable allocation preview")
	await click(panel._allocate)
	check(panel._detail.text.contains("退还后资源上限") and panel._refund.disabled==false,"Successful UI allocation changes selection preview to refund")
	for stat:String in ui_case.changes:check(f.model.get_stats()[stat]==ui_case.changes[stat].after,"UI real saved capacity equals preview "+stat)
	await capture("refund-preview")
	await click(panel._refund)
	check(f.model.get_stats()==bytes_to_var(before.stats) and panel._detail.text.contains("分配后资源上限"),"Actual refund returns caps and refreshes allocation preview")
	check(economy(f.model.snapshot())==before.economy and f.model.snapshot().version==Rules.VERSION,"UI round-trip preserves items/UIDs/economy and current schema")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-passive-resource-"):quit(78);return
	var initial:=Model.new();base_source=initial.snapshot()
	for spec:Array in [["life-percent","max_health","increased"],["mana-percent","max_mana","increased"],["shield-percent","max_shield","increased"],["strength","strength","flat"],["intelligence","intelligence","flat"]]:
		var id:=choose(spec[1],spec[2])
		if not check(not id.is_empty(),"Supported source exists for "+spec[0]):continue
		var result:=resource_case(spec[0],id,selection(prefix_for(id)))
		if spec[0]=="life-percent":ui_case=result
	var ci:=resource_case("chaos-inoculation","11455",selection(prefix_for("11455")))
	check(not ci.is_empty() and ci.changes.max_health.after==1.0,"CI preview applies final maximum-life-one override")
	var ci_path:=path_to("11455");var life:=choose("max_health","increased",ci_path)
	if check(not life.is_empty(),"Life capacity source outside CI path"):
		var ids:=ci_path.duplicate()
		for id:String in prefix_for(life):if id not in ids:ids.append(id)
		var ci_life:=resource_case("life-while-CI",life,selection(ids))
		check(not ci_life.is_empty() and not ci_life.changes.has("max_health"),"Life modifier under CI never promises fictitious extra maximum life")
	var denied:=read_preview(fixture(),"26740")
	check(not denied.allocate.allowed and denied.allocate.resource_changes.is_empty(),"Disconnected node has reason and no impossible resource prediction")
	# Connected mastery candidate with an implemented resource modifier.
	var found:=false
	for id:String in source_graph().context.nodes:
		if found:break
		var node:Dictionary=graph.context.nodes[id]
		if node.type!="mastery":continue
		for notable:String in graph.reached:
			if found:break
			if graph.context.nodes[notable].type!="notable" or graph.context.nodes[notable].group_id!=node.group_id:continue
			for effect:int in node.mastery_effects:
				var execution:=Runtime.node_effect(id,effect)
				if execution.status!="full":continue
				if execution.grants.any(func(grant:Dictionary)->bool:return grant.stat in ["max_health","max_mana","max_shield"]):
					resource_case("selected-mastery",id,selection(path_to(notable)),effect);found=true;break
	check(found,"Selected implemented mastery resource effect covered")
	if not ui_case.is_empty():await ui_checks()
	var output:={"checks":checks,"failures":failures,"failed_labels":report.failures,"resource_cases":resource_cases,"display":DisplayServer.get_name(),"fixture":"Current canonical starter equipment plus valid level119 source paths; no natural earning claim. Actual original allocation/refund/save and native T buttons."}
	FileAccess.open(OS.get_environment("RESOURCE_PREVIEW_OUTPUT").path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(output,"\t")+"\n")
	print("PASSIVE_RESOURCE_PREVIEW ",JSON.stringify({"checks":checks,"failures":failures,"failed_labels":report.failures}));quit(0 if failures==0 else 1)
