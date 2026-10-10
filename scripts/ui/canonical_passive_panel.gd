class_name CanonicalPassivePanel
extends VBoxContainer
signal feedback(message: String)
signal item_hovered(uid: String,anchor: Rect2)
signal hover_left
const TreeView = preload("res://scripts/ui/source_passive_tree_view.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const CraftControls = preload("res://scripts/ui/crafting_controls.gd")
var model: RefCounted
var save_path := "user://build_save.json"
var selected_node_id := "58833"
var font_scale := 1.0
var _tree: Control
var _class: OptionButton
var _partition: OptionButton
var _summary: Label
var _detail: Label
var _mastery: OptionButton
var _jewel: OptionButton
var _allocate: Button
var _refund: Button
var _socket: Button
var _return: Button
var _search: LineEdit
var _search_query := ""
var _search_matches: Array[String] = []
var _search_index := -1
var _subtree := "standard"
var _loaded_graph := ""
var _refreshing := false
var _socket_uid := ""
var _refresh_dirty: bool = true
var _model_refresh_queued := false
var refresh_generation: int = 0

class WrappedLabel extends Label:
	func _make_custom_tooltip(text:String)->Object:return CraftControls.wrapped_tooltip(self,text)

class WrappedOption extends OptionButton:
	func _make_custom_tooltip(text:String)->Object:return CraftControls.wrapped_tooltip(self,text)

class SocketTarget extends Button:
	var owner_panel: CanonicalPassivePanel
	func _can_drop_data(_at: Vector2,payload: Variant)->bool:
		return owner_panel._can_drop(payload)
	func _drop_data(_at: Vector2,payload: Variant)->void:
		if owner_panel._can_drop(payload): owner_panel._move(payload.uid,{"kind":"passive_socket","node_id":owner_panel.selected_node_id},payload.revision)


func setup(state: RefCounted,path: String="user://build_save.json")->void:
	model=state
	save_path=path
	selected_node_id=Data.start_for_class(int(model.snapshot().talents.class_id))
	if _tree==null: _build()
	if not model.changed.is_connected(_on_model_changed): model.changed.connect(_on_model_changed)
	if not visibility_changed.is_connected(_on_visibility_changed): visibility_changed.connect(_on_visibility_changed)
	_refresh_dirty=true
	refresh()


func _build()->void:
	name="CanonicalPassivePanel"
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	custom_minimum_size.y=410
	var toolbar:=HFlowContainer.new()
	add_child(toolbar)
	_class=WrappedOption.new()
	_class.name="SourceClassPicker"
	for entry: Dictionary in Data.class_starts():
		_class.add_item(Localization.class_label(str(entry.class_name)),int(entry.class_index))
	_class.tooltip_text="仅切换原始树起点。必须先退还所有已点节点；装备、宝石与未用点数保留。"
	_class.item_selected.connect(_change_class)
	toolbar.add_child(_class)
	_partition=OptionButton.new()
	_partition.fit_to_longest_item=false
	_partition.name="SourcePartitionPicker"
	_partition.add_item("标准主树")
	_partition.set_item_metadata(0,"standard")
	for name_value: String in Data.special_subtrees().ascendancies:
		_partition.add_item("升华 · "+Localization.partition_label(name_value))
		_partition.set_item_metadata(_partition.item_count-1,name_value)
	_partition.add_item("扩展珠宝分区 · 仅浏览")
	_partition.set_item_metadata(_partition.item_count-1,"expansion")
	_partition.custom_minimum_size.x=190
	_partition.item_selected.connect(_change_partition)
	toolbar.add_child(_partition)
	var fit:=Button.new()
	fit.text="全图"
	fit.pressed.connect(func():_tree.fit_tree())
	toolbar.add_child(fit)
	var home:=Button.new()
	home.text="起点"
	home.pressed.connect(_focus_start)
	toolbar.add_child(home)
	_search=LineEdit.new()
	_search.placeholder_text="名称 / 中文词缀 / 编号"
	_search.custom_minimum_size.x=170
	_search.tooltip_text="搜索当前子树的中文名、原英文名或中文词缀；回车定位，再按回车查看下一项。精确节点编号优先。"
	_search.text_changed.connect(func(_text:String):_reset_search())
	_search.text_submitted.connect(_find_node)
	toolbar.add_child(_search)
	_summary=WrappedLabel.new()
	_summary.mouse_filter=Control.MOUSE_FILTER_PASS
	_summary.name="SourceTreeSummary"
	_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size",13)
	add_child(_summary)
	var row:=HBoxContainer.new()
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_child(row)
	_tree=TreeView.new()
	_tree.name="SourceTreeCanvas"
	_tree.custom_minimum_size=Vector2(350,310)
	_tree.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_tree.size_flags_stretch_ratio=2.5
	row.add_child(_tree)
	_tree.node_clicked.connect(_node_clicked)
	_tree.node_hovered.connect(_node_hovered)
	_tree.hover_left.connect(func():_tree.tooltip_text="")
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.x=250
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio=1.0
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var right:=VBoxContainer.new()
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(right)
	_detail=WrappedLabel.new()
	_detail.mouse_filter=Control.MOUSE_FILTER_PASS
	_detail.name="SourceNodeDetails"
	_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size",14)
	right.add_child(_detail)
	_mastery=WrappedOption.new()
	_mastery.fit_to_longest_item=false
	_mastery.name="SourceMasteryPicker"
	_mastery.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_mastery.item_selected.connect(func(_index:int):_refresh_details())
	right.add_child(_mastery)
	_allocate=Button.new()
	_allocate.text="分配 · 1 点"
	_allocate.name="AllocateSourceNode"
	_allocate.pressed.connect(_allocate_selected)
	right.add_child(_allocate)
	_refund=Button.new()
	_refund.text="退还 · 1 点"
	_refund.name="RefundSourceNode"
	_refund.pressed.connect(_refund_selected)
	right.add_child(_refund)
	_jewel=OptionButton.new()
	_jewel.fit_to_longest_item=false
	_jewel.name="SourceJewelPicker"
	_jewel.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_jewel.item_selected.connect(func(_index:int):_refresh_details();_refresh_overlay())
	right.add_child(_jewel)
	_socket=SocketTarget.new()
	_socket.owner_panel=self
	_socket.name="SourceSocketTarget"
	_socket.text="镶嵌所选珠宝"
	_socket.pressed.connect(_socket_selected)
	_socket.mouse_entered.connect(func():
		if not _socket_uid.is_empty():item_hovered.emit(_socket_uid,_socket.get_global_rect()))
	_socket.mouse_exited.connect(func():hover_left.emit())
	right.add_child(_socket)
	_return=Button.new()
	_return.text="取回珠宝到背包"
	_return.pressed.connect(_return_jewel)
	right.add_child(_return)


func refresh()->void:
	if model==null or _tree==null or _refreshing:return
	if not _refresh_dirty:return
	_refreshing=true
	var snapshot:Dictionary=model.snapshot()
	_class.select(int(snapshot.talents.class_id))
	_class.disabled=snapshot.talents.allocated.size()>1
	_load_graph()
	_summary.text="原树 3.29.1 · 可用 %d / 123 点 · 灰色斜线节点含未实现效果，不能分配" % int(snapshot.talents.normal_points)
	_summary.tooltip_text="3390条源记录，标准图2387个位置、2697条内部边；这不是全部效果完成。保留源数值和坐标，锁定节点会阻断其后路径。绿色为当前可点，金色为已点。升华与扩展点数尚未接入。\n迁移退还 %d 点，超出当前123点预算的 %d 点已保留记账。" % [int(snapshot.migration_ledger.legacy_points_refunded),int(snapshot.migration_ledger.excess_points_recorded)]
	var prior_uid:String=str(_jewel.get_item_metadata(_jewel.selected)) if _jewel.selected>=0 else ""
	_jewel.clear()
	for uid:String in snapshot.locations:
		if snapshot.locations[uid].kind=="bag" and snapshot.items[uid].kind=="jewel":
			_jewel.add_item(str(model.item_definition(uid).name))
			_jewel.set_item_metadata(_jewel.item_count-1,uid)
			if uid==prior_uid:_jewel.select(_jewel.item_count-1)
	_refresh_details()
	_refresh_overlay()
	_refreshing=false
	_refresh_dirty=false
	refresh_generation+=1


func _on_model_changed()->void:
	_refresh_dirty=true
	# changed is emitted inside the model transaction; query capabilities after it ends.
	if is_visible_in_tree() and not _model_refresh_queued:
		_model_refresh_queued = true
		_refresh_after_model_commit.call_deferred()


func _refresh_after_model_commit()->void:
	_model_refresh_queued = false
	if is_visible_in_tree() and _refresh_dirty: refresh()


func _on_visibility_changed()->void:
	if is_visible_in_tree() and _refresh_dirty:refresh()


func _load_graph()->void:
	var snapshot:Dictionary=model.snapshot()
	var key:="%s:%d"%[_subtree,int(snapshot.talents.class_id)]
	if key==_loaded_graph:return
	var ids:Array=Data.standard_ids()
	var edges:Array=[]
	var focus:String=Data.start_for_class(int(snapshot.talents.class_id))
	if _subtree!="standard":
		var branch:Dictionary=Data.special_subtrees().expansion_jewels if _subtree=="expansion" else Data.special_subtrees().ascendancies.get(_subtree,{})
		ids=branch.get("positioned_node_ids",[])
		edges=Data.edges_for(branch.get("internal_edge_ids",[]))
		focus=str(branch.get("start_node_ids",[""])[0])
	else:
		for id:String in ids:
			for adjacent:String in Data.adjacency(id):
				if id<adjacent:edges.append({"a":id,"b":adjacent})
	var nodes:Dictionary={}
	for id:String in ids:
		var node:=Data.node(id)
		var effect:=Runtime.node_effect(id)
		var locked:bool=_subtree!="standard" or node.source.get("isProxy",false) or node.source.get("isBlighted",false) or effect.status in ["partial","unsupported"]
		nodes[id]={"id":id,"position":node.position,"type":node.type,"name":Localization.node_name(id),
			"description":Localization.display_lines(node.stats,"\n",id),"status":"locked" if locked else "choice" if effect.status=="choice" else "implemented"}
	if _tree.set_tree(nodes,edges,focus):
		_reset_search()
		_loaded_graph=key
		if not nodes.has(selected_node_id):selected_node_id=focus


func _refresh_overlay()->void:
	var snapshot:Dictionary=model.snapshot()
	var analysis:Dictionary=model.passive_analysis()
	var ranges:Array=[]
	for uid:String in snapshot.locations:
		var loc:Dictionary=snapshot.locations[uid]
		if loc.kind!="passive_socket":continue
		var rule:=Jewels.allocation_rule(snapshot.items[uid].payload)
		if not rule.is_empty():ranges.append({"center":Data.node(loc.node_id).position,"radius":float(rule.radius),"active":true})
	if _subtree=="standard" and Data.node(selected_node_id).get("type")=="socket" and _socket_uid.is_empty() and _jewel.selected>=0:
		var uid:String=str(_jewel.get_item_metadata(_jewel.selected))
		var rule:=Jewels.allocation_rule(model.item(uid).payload)
		if not rule.is_empty():ranges.append({"center":Data.node(selected_node_id).position,"radius":float(rule.radius),"active":false})
	_tree.set_allocation_state({"allocated":snapshot.talents.allocated if _subtree=="standard" else [],"available":model.available_passives() if _subtree=="standard" else [],"remote":analysis.remote_sources.keys(),"socket_ranges":ranges,"selected_id":selected_node_id})


func _refresh_details()->void:
	var node:=Data.node(selected_node_id)
	if node.is_empty():return
	var snapshot:Dictionary=model.snapshot()
	var allocated:bool=snapshot.talents.allocated.has(selected_node_id)
	var is_mastery:bool=node.type=="mastery"
	var previous_effect:int=int(_mastery.get_item_metadata(_mastery.selected)) if _mastery.selected>=0 else 0
	_mastery.clear()
	_mastery.visible=is_mastery
	if is_mastery:
		for effect:Dictionary in node.mastery_effects:
			var execution:=Runtime.node_effect(selected_node_id,int(effect.effect))
			_mastery.add_item(Localization.display_lines(effect.stats," · ",selected_node_id) if not effect.stats.is_empty() else "空效果")
			var index:int=_mastery.item_count-1
			_mastery.set_item_metadata(index,int(effect.effect))
			_mastery.set_item_disabled(index,execution.status!="full")
			if int(effect.effect)==int(snapshot.talents.masteries.get(selected_node_id,previous_effect)):_mastery.select(index)
		if _mastery.selected>=0 and _mastery.is_item_disabled(_mastery.selected):
			for i:int in range(_mastery.item_count):
				if not _mastery.is_item_disabled(i):_mastery.select(i);break
	var effect_id:int=int(_mastery.get_item_metadata(_mastery.selected)) if is_mastery and _mastery.selected>=0 else 0
	var execution:=Runtime.node_effect(selected_node_id,effect_id)
	var lines:Array=Runtime.lines_for(selected_node_id,effect_id)
	var display_lines:=Localization.display_lines(lines,"\n",selected_node_id)
	var status:String="当前节点或所选专精的全部效果均已接入游戏" if execution.status=="full" else "当前节点或所选专精仍有未接入效果 · 不可分配"
	if _subtree!="standard":status="独立源子树 · 仅浏览，点数与效果未接入"
	elif not node.has_position:status="无源坐标的定义记录 · 仅浏览"
	elif node.source.get("isProxy",false):status="源位置代理 · 不可分配"
	elif node.source.get("isBlighted",false):status="涂油专属节点 · 不可直接分配"
	_detail.text="%s\n%s\n%s\n\n%s\n\n%s"%[Localization.node_name(selected_node_id),selected_node_id,status,display_lines,Localization.TERM_NOTE]
	_detail.tooltip_text=Localization.TERM_NOTE+"\n\n词缀后的状态按完整源词条逐行判断。只有当前节点或所选专精的全部词缀均已接入游戏，才允许分配。"
	_mastery.tooltip_text=display_lines
	if _subtree == "standard":
		var preview: Dictionary = model.passive_action_preview(selected_node_id, effect_id)
		_apply_action_preview(preview, allocated)
	else:
		_allocate.disabled = true
		_refund.disabled = true
		_allocate.tooltip_text = "此子树仅供浏览"
		_refund.tooltip_text = "此子树仅供浏览"
	_socket_uid=""
	for uid:String in snapshot.locations:
		if snapshot.locations[uid].kind=="passive_socket" and snapshot.locations[uid].node_id==selected_node_id:_socket_uid=uid
	var is_socket:bool=node.type=="socket" and _subtree=="standard"
	_jewel.visible=is_socket
	_socket.visible=is_socket
	_return.visible=is_socket
	_socket.disabled=not allocated or _jewel.selected<0
	_return.disabled=_socket_uid.is_empty()
	if not _socket_uid.is_empty():_detail.text+="\n\n"+str(model.item_definition(_socket_uid).name)
	elif is_socket and _jewel.selected>=0:_detail.text+="\n\n候选范围仅为预览，镶嵌后生效"


func _apply_action_preview(preview: Dictionary, allocated: bool) -> void:
	var allocation: Dictionary = preview.get("allocate", {})
	var refund: Dictionary = preview.get("refund", {})
	_allocate.disabled = not bool(allocation.get("allowed", false))
	_refund.disabled = not bool(refund.get("allowed", false))
	_allocate.tooltip_text = str(allocation.get("reason", "无法分配")) if _allocate.disabled else "分配此节点，消耗 1 点"
	_refund.tooltip_text = str(refund.get("reason", "无法退还")) if _refund.disabled else "退还此节点，获得 1 点"
	# Only the action relevant to the selected node adds a reason to its details.
	var selected_action: Dictionary = refund if allocated else allocation
	if not bool(selected_action.get("allowed", false)):
		var reason := str(selected_action.get("reason", ""))
		if not reason.is_empty():
			_detail.text += "\n\n" + ("无法退还：" if allocated else "无法分配：") + reason
	else:
		var resources := resource_preview_text(selected_action.get("resource_changes", {}), allocated)
		if not resources.is_empty(): _detail.text += "\n\n" + resources


static func resource_preview_text(changes: Dictionary, allocated: bool) -> String:
	var lines: Array[String] = []
	var names := {"max_health":"生命", "max_mana":"魔力", "max_shield":"护盾"}
	for stat: String in names:
		if not changes.has(stat): continue
		var before := float(changes[stat].before)
		var after := float(changes[stat].after)
		var delta := after-before
		lines.append("%s %s → %s（%s%s）" % [names[stat],String.num(before,2),String.num(after,2),"+" if delta>0 else "",String.num(delta,2)])
	return "" if lines.is_empty() else ("退还后资源上限" if allocated else "分配后资源上限") + "\n" + "\n".join(lines)


func _node_clicked(id:String,button:int,double_click:bool)->void:
	selected_node_id=id
	_refresh_details()
	_refresh_overlay()
	if button==MOUSE_BUTTON_RIGHT:_refund_selected()
	elif double_click:_allocate_selected()
func _node_hovered(id:String,_anchor:Rect2)->void:
	var node:=Data.node(id)
	_tree.tooltip_text=Localization.node_name(id)+"\n"+Localization.display_lines(node.stats,"\n",id)+"\n点击查看逐条接入状态"
func _allocate_selected()->void:
	if _allocate.disabled:return
	var effect:int=int(_mastery.get_item_metadata(_mastery.selected)) if _mastery.visible and _mastery.selected>=0 else 0
	_report(model.allocate_passive(selected_node_id,effect,model.revision(),save_path))
func _refund_selected()->void:
	if not _refund.disabled:_report(model.refund_passive(selected_node_id,model.revision(),save_path))
func _change_class(index:int)->void:
	if _refreshing:return
	_report(model.select_class(_class.get_item_id(index),model.revision(),save_path))
	_focus_start()
func _change_partition(index:int)->void:
	if index<0 or index>=_partition.item_count:return
	_partition.select(index)
	_subtree=str(_partition.get_item_metadata(index))
	_loaded_graph=""
	_refresh_dirty=true
	refresh()
func _focus_start()->void:
	_subtree="standard"
	_partition.select(0)
	_loaded_graph=""
	selected_node_id=Data.start_for_class(int(model.snapshot().talents.class_id))
	_refresh_dirty=true
	refresh()
	_tree.pan=-Data.node(selected_node_id).position*_tree.zoom
	_tree.queue_redraw()
func _reset_search()->void:
	_search_query=""
	_search_matches.clear()
	_search_index=-1

func _find_node(query:String)->void:
	var needle:=query.strip_edges().to_lower()
	if needle.is_empty():
		_reset_search()
		feedback.emit("请输入名称、中文词缀或节点编号")
		return
	if needle!=_search_query:
		_reset_search()
		_search_query=needle
		# Exact IDs win over every text match. Detached definitions retain their
		# identity without inventing a position or changing allocation eligibility.
		if _tree._nodes.has(needle):
			_search_matches.append(needle)
		else:
			var record:=Data.node(query.strip_edges())
			if not record.is_empty():
				selected_node_id=str(record.id)
				_refresh_details();_refresh_overlay()
				feedback.emit("匹配 1/1 · %s（%s） · 当前子树无此位置，仅显示详情"%[Localization.node_name(selected_node_id),selected_node_id])
				# Repeated submissions of a detached ID must retain this behavior.
				_search_query=""
				return
			var description_matches: Array[String]=[]
			# Keep the original pinned graph order and put name matches first, so
			# existing name queries still select their prior first result.
			for id:String in _tree._node_order:
				var node:Dictionary=_tree._nodes[id]
				var source_name:=str(Data.node(id).name).to_lower()
				if str(node.name).to_lower().contains(needle) or source_name.contains(needle):
					_search_matches.append(id)
				elif str(node.description).to_lower().contains(needle):
					description_matches.append(id)
			_search_matches.append_array(description_matches)
	if _search_matches.is_empty():
		feedback.emit("当前子树未找到此名称、中文词缀或编号（0 项）")
		return
	_search_index=(_search_index+1)%_search_matches.size()
	selected_node_id=_search_matches[_search_index]
	_tree.pan=-_tree._nodes[selected_node_id].position*_tree.zoom
	_refresh_details();_refresh_overlay()
	_tree.queue_redraw()
	feedback.emit("匹配 %d/%d · %s（%s）"%[_search_index+1,_search_matches.size(),Localization.node_name(selected_node_id),selected_node_id])
func _socket_selected()->void:
	if not _socket.disabled:_move(str(_jewel.get_item_metadata(_jewel.selected)),{"kind":"passive_socket","node_id":selected_node_id},model.revision())
func _return_jewel()->void:
	if _socket_uid.is_empty():return
	var destination:Dictionary=model.first_bag_position(_socket_uid)
	if destination.is_empty():feedback.emit("背包空间不足，珠宝保留原孔")
	else:_move(_socket_uid,destination,model.revision())
func _can_drop(payload:Variant)->bool:
	return payload is Dictionary and payload.get("type")=="unified_item" and payload.get("uid") is String and payload.get("revision") is int and _subtree=="standard" and model.can_move_item(payload.uid,{"kind":"passive_socket","node_id":selected_node_id},payload.revision)
func _move(uid:String,destination:Dictionary,revision_value:int)->void:_report(model.move_item(uid,destination,revision_value,save_path))
func _report(result:Dictionary)->void:
	if not result.get("ok",false) and not str(result.get("reason","")).is_empty():feedback.emit(result.reason)
	refresh()
