extends SceneTree
const Model=preload("res://scripts/build_state.gd")
const Passives=preload("res://scripts/passive_data.gd")
const TreePanel=preload("res://scripts/passive_panel.gd")
const ThemeKit=preload("res://scripts/visuals/visual_theme.gd")
var checks:int=0
var failures:int=0
var panel:PassivePanel
var state:BuildState
func _initialize()->void: call_deferred("run")
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func path_to(target:String)->Array[String]:
	var queue:Array[String]=["origin"]
	var previous:Dictionary={"origin":""}
	while not queue.is_empty():
		var id:String=queue.pop_front()
		if id==target:
			var path:Array[String]=[]
			while id!="":
				path.push_front(id)
				id=previous[id]
			return path
		for next:String in Passives.get_neighbors(id):
			if not previous.has(next):
				previous[next]=id
				queue.append(next)
	return []
func run()->void:
	state=Model.new()
	state.talent_points=60
	var special:String=state.award_special_jewel()
	expect(not special.is_empty(),"special award fixture")
	panel=TreePanel.new()
	panel.theme=ThemeKit.create_theme()
	root.add_child(panel)
	panel.size=Vector2(1150,610)
	panel.setup(state)
	panel.select_node("ember_3_0")
	panel.select_jewel(special)
	var tree:PassiveTreeView=panel.tree_view
	expect(not tree._radius_preview.is_empty() and not tree._radius_preview.active,"unallocated socket has inactive radius preview")
	expect(tree._radius_preview.covered_nodes==state.jewel_radius_preview("ember_3_0",special).covered_nodes,"preview coverage comes from model")
	expect(tree._reachable==state.allocation_analysis().eligible_nodes,"one model analysis drives eligibility")
	expect(panel._insert_button.disabled,"inactive socket rejects insert")
	for id:String in path_to("ember_3_0"):
		if id!="origin": expect(state.allocate_passive(id),"ordinary path remains allocatable "+id)
	panel.select_node("ember_3_0")
	panel.select_jewel(special)
	expect(tree._radius_preview.active,"connected socket enables preview")
	expect(panel.insert_selected_jewel(),"UI inserts special jewel")
	expect(tree._analysis.active_sources.has("ember_3_0"),"source visible after insertion")
	var remote:String=""
	for id:String in tree._analysis.granted_by:
		if state.allocated_nodes.has(id): continue
		var touches:bool=false
		for neighbor:String in Passives.get_neighbors(id):
			if tree._analysis.connected.has(neighbor): touches=true
		if not touches:
			remote=id
			break
	expect(not remote.is_empty(),"fixture has remotely supported candidate")
	if remote.is_empty(): quit(1); return
	var points:int=state.talent_points
	panel.select_node(remote)
	expect(not panel._allocate_button.disabled,"remote candidate action enabled")
	expect(panel.allocate_selected(),"UI spends a point on remote node")
	expect(state.talent_points==points-1,"remote allocation still costs one point")
	expect(tree._analysis.remote_nodes.has(remote),"remote badge follows model status")
	expect(panel._node_type.text.contains("寻枝点亮"),"inspector distinguishes remote allocation")
	expect(tree._get_tooltip(tree.node_screen_position(remote)).contains("寻枝"),"hover tooltip explains remote source")
	panel.select_node("ember_3_0")
	var before:Dictionary=state._snapshot()
	expect(panel._remove_button.disabled and not panel._remove_button.tooltip_text.is_empty(),"dependent removal disabled with reason")
	expect(not panel.remove_selected_jewel() and state._snapshot()==before,"forced removal stays atomic")
	panel.select_jewel("jewel_000001")
	expect(panel._insert_button.disabled,"ordinary replacement cannot strand node")
	expect(not panel.insert_selected_jewel() and state._snapshot()==before,"forced replacement stays atomic")
	panel.select_jewel(special)
	expect(panel._jewel_affixes.text.length()<35 and panel._jewel_affixes.tooltip_text.length()>70,"special rules compact with full tooltip")
	expect(panel._jewel_affixes.mouse_filter==Control.MOUSE_FILTER_PASS,"rules tooltip receives pointer input")
	var saved_pan:Vector2=tree.pan
	tree.set_zoom(0.7)
	saved_pan=tree.pan
	panel.refresh()
	expect(is_equal_approx(tree.zoom,0.7) and tree.pan==saved_pan,"refresh preserves tree camera")
	panel._jewel_filter.select(4)
	panel._on_jewel_filter_changed(4)
	expect(panel._jewel_list.get_child_count()==1 and panel._jewel_list.get_child(0).name=="Jewel_"+special,"special filter shows only special")
	expect(panel._jewel_list.get_child(0).find_child("JewelEmblem",true,false)!=null,"jewel list includes actual reusable art")
	panel.select_node(remote)
	expect(panel.refund_selected(),"remote refund works")
	panel.select_node("ember_3_0")
	expect(not panel._remove_button.disabled and panel.remove_selected_jewel(),"removal succeeds after dependencies refunded")
	expect(tree._analysis.remote_nodes.is_empty() and tree._analysis.active_sources.is_empty(),"markers clear after removal")
	for id:String in Passives.get_nodes():
		expect(tree._reachable.has(id)==state.can_allocate(id),"ordinary reachability matches model "+id)
	for font_scale:float in [1.0,1.2]:
		ThemeKit.apply_font_scale(panel,font_scale)
		for i:int in range(5): await process_frame
		expect(panel._insert_button.size.x>=100 and panel._remove_button.size.x>=50,"actions retain usable targets")
		expect(panel._node_reason.get_line_count()<=2,"node badge stays compact")
	print("special_jewel_ui_test: %d checks, %d failures"%[checks,failures])
	panel.queue_free()
	await process_frame
	quit(1 if failures else 0)
