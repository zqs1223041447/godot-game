extends SceneTree
## Bounded real-panel signal exercise; no arena, allocation or save migration.
const Game=preload("res://scripts/canonical_game_state.gd")
const PassivePanel=preload("res://scripts/ui/canonical_passive_panel.gd")
const Data=preload("res://scripts/passives/source_tree_data.gd")
const Locale=preload("res://scripts/passives/source_tree_localization.gd")
const SAVE_PATH="user://passive-description-search.json"
const TARGETS={"12926":["铁握持","Iron Grip"],"50288":["铁意志","Iron Will"],"15842":["与自然合一","One With Nature"]}
# Frozen source/display observations, independent of the panel's match collector.
const QUERIES={
	"投射物攻击":["12794","14804","28658","30455","12926","41119","42178","54922"],
	"全部法术伤害":["50288"],
	"攻击技能造成的元素伤害":["15842","18670","25511","30894","56646","64878"],
}
var game:RefCounted
var panel:Control
var checks:=0
var failures:=0
var changes:=0
var finished:=false
var messages:Array[String]=[]
var observations:Array[Dictionary]=[]

func _initialize()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-passive-search-") or not OS.get_user_data_dir().begins_with(isolated+"/"):
		push_error("Refusing non-isolated userdata")
		quit(78)
		return
	create_timer(30.0).timeout.connect(func():
		if not finished:
			check(false,"30-second guard")
			finish())
	call_deferred("run")

func run()->void:
	game=Game.new()
	if not check(game.save_build(SAVE_PATH)==OK,"Persist isolated lawful native fixture"):
		finish();return
	game.changed.connect(func():changes+=1)
	var source_bytes:=var_to_bytes(Data.nodes())
	var source_hash:=FileAccess.get_sha256(Data.PATH)
	var before:=checkpoint()
	root.size=Vector2i(1280,720)
	panel=PassivePanel.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.feedback.connect(func(message:String):messages.append(message))
	panel.setup(game,SAVE_PATH)
	await process_frame
	check(panel._tree._nodes.size()==2387,"Actual canonical standard graph loaded")
	check(panel._search.placeholder_text.contains("中文词缀"),"Search affordance names localized stat support")
	for id:String in TARGETS:
		for query:String in [TARGETS[id][0],"  "+str(TARGETS[id][1]).to_upper()+"  ",id]:
			submit(query,id,1,1)
		check(panel._allocate.disabled and panel._detail.text.contains("无法分配："),"Unconnected target retains authoritative allocation reason: "+id)
	for query:String in QUERIES:
		var expected:Array=QUERIES[query]
		# Visit every result, including wrapping exactly back to the first result.
		for index:int in range(expected.size()+1):
			var slot:=index%expected.size()
			submit(query,str(expected[slot]),slot+1,expected.size())
		check(panel._search_matches==expected,"Stable names-first source order without duplicate IDs: "+query)
	# Switching query resets to first; editing away and back before submission does too.
	submit("投射物攻击","12794",1,8)
	submit("投射物攻击","14804",2,8)
	submit("全部法术伤害","50288",1,1)
	submit("投射物攻击","12794",1,8)
	submit("投射物攻击","14804",2,8)
	panel._search.text="投射物攻"
	panel._search.text_changed.emit(panel._search.text)
	check(panel._search_matches.is_empty() and panel._search_index==-1,"Editing only resets; no eager graph scan")
	panel._search.text="投射物攻击"
	panel._search.text_changed.emit(panel._search.text)
	submit("投射物攻击","12794",1,8)
	# Exact IDs cannot join broader description matches and always locate one node.
	submit("  50288  ","50288",1,1)
	submit("  50288  ","50288",1,1)
	# Locked effects stay visible and locked after both name and ID searches.
	submit("风舞者","11239",1,1)
	check(panel._tree._nodes["11239"].status=="locked" and panel._allocate.disabled,"Search never opens an unsupported node")
	check(panel._detail.text.contains("暂未实装") and panel._detail.text.contains("不可分配"),"Unsupported effect explanation stays in details")
	for query:String in ["不存在的天赋搜索词","不存在的天赋搜索词","   ",""]:
		var prior_selection:String=panel.selected_node_id
		var prior_pan:Vector2=panel._tree.pan
		var prior_detail:String=panel._detail.text
		submit_missing(query)
		check(panel.selected_node_id==prior_selection and panel._tree.pan==prior_pan and panel._detail.text==prior_detail,"Empty/missing result preserves selection, location and details")
	submit("投射物攻击","12794",1,8)
	# Existing detached ID browsing must never pan to its absent coordinates.
	var prior_pan:Vector2=panel._tree.pan
	check(not Data.node("33").has_position and not panel._tree._nodes.has("33"),"Pinned detached definition has no canvas position")
	for repeat:int in range(2):
		panel._search.text="33"
		panel._search.text_submitted.emit("33")
		check(panel.selected_node_id=="33" and panel._tree.pan==prior_pan,"Detached exact ID keeps absent-position browsing")
		check(messages.back().contains("无此位置") and panel._detail.text.contains("无源坐标") and panel._allocate.disabled,"Detached record explains location and remains ineligible")
	# No stale cached IDs survive switching to an independent subgraph and back.
	submit("投射物攻击","12794",1,8)
	submit("投射物攻击","14804",2,8)
	panel._change_partition(1)
	check(panel._search_matches.is_empty(),"Graph replacement resets cached matches")
	panel._change_partition(0)
	submit("投射物攻击","12794",1,8)
	assert_readonly(before,"Entire signal-driven search session")
	check(var_to_bytes(Data.nodes())==source_bytes and FileAccess.get_sha256(Data.PATH)==source_hash,"Source identities, coordinates, stats and original data unchanged")
	finish()

func submit(query:String,id:String,index:int,total:int)->void:
	var before:=checkpoint()
	# Signal-driven input uses the real LineEdit and the real panel, without mocks.
	if panel._search.text!=query:
		panel._search.text=query
		panel._search.text_changed.emit(query)
	panel._search.text_submitted.emit(query)
	check(panel.selected_node_id==id and panel._tree._selected_id==id,"Selection: "+query+" -> "+id)
	check(panel._tree.pan==-Data.node(id).position*panel._tree.zoom,"Original-coordinate centering: "+id)
	check(panel._tree.node_screen_position(id).is_equal_approx(panel._tree.size*0.5),"Node actually at canvas center: "+id)
	check(panel._detail.text.begins_with(Locale.node_name(id)+"\n"+id+"\n"),"Details describe the selected result: "+id)
	check(panel._detail.text.contains(Locale.display_lines(Data.node(id).stats)),"Selected result retains its own localized effects: "+id)
	var message:String=messages.back() if not messages.is_empty() else ""
	check(message=="匹配 %d/%d · %s（%s）"%[index,total,Locale.node_name(id),id],"Feedback identity/index/count: "+query)
	assert_readonly(before,"Search "+query)
	observations.append({"query":query,"id":id,"index":index,"total":total,"feedback":message,"centered":panel._tree.node_screen_position(id).is_equal_approx(panel._tree.size*0.5)})

func submit_missing(query:String)->void:
	var before:=checkpoint()
	panel._search.text=query
	panel._search.text_changed.emit(query)
	panel._search.text_submitted.emit(query)
	check(messages.back().contains("请输入") if query.strip_edges().is_empty() else messages.back().contains("0 项"),"Explicit empty/no-result feedback")
	assert_readonly(before,"Missing/empty query")

func checkpoint()->Dictionary:
	game.get_stats();game.get_combat_snapshot()
	var files:=DirAccess.get_files_at(OS.get_user_data_dir());files.sort()
	return {"model":var_to_bytes(game.snapshot()),"stats":var_to_bytes(game.get_stats()),"combat":var_to_bytes(game.get_combat_snapshot()),"revision":game.revision(),"points":game.snapshot().talents.normal_points,"changed":changes,"epoch":game._content_epoch,"disk":FileAccess.get_file_as_bytes(SAVE_PATH),"files":files,"attempts":game.save_attempts,"saves":game.successful_saves}

func assert_readonly(before:Dictionary,label:String)->void:
	check(checkpoint()==before,label+": point balance/model/stats/snapshot/revision/signals/save bytes/files/counters unchanged")

func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func finish()->void:
	if finished:return
	finished=true
	var report:={"checks":checks,"failures":failures,"observations":observations,"schema":game.snapshot().version if game!=null else 0,"save_sha256":FileAccess.get_sha256(SAVE_PATH),"scope":"Real canonical panel text_changed/text_submitted signals; no native keyboard, arena, allocation, export or full suite"}
	var output:=OS.get_environment("PASSIVE_SEARCH_REPORT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t")+"\n")
	print("Passive description search checks=%d failures=%d submissions=%d"%[checks,failures,observations.size()])
	if is_instance_valid(panel):panel.queue_free()
	quit(1 if failures else 0)
