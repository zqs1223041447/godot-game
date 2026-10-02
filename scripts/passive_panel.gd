class_name PassivePanel
extends VBoxContainer
## Live build editor; all mutations go through BuildState's checked transaction API.

signal feedback(message: String)

const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const TreeCanvas = preload("res://scripts/passive_tree_view.gd")
const JewelIcon = preload("res://scripts/visuals/jewel_emblem.gd")
const TEXT: Color = Color("3b281b")
const MUTED: Color = Color("69523a")
const CYAN: Color = Color("52623b")
const GOLD: Color = Color("79571f")
const RED: Color = Color("a13b2d")
const BORDER: Color = Color("8c6b42")

var tree_view: PassiveTreeView
var selected_node_id: String = "origin"
var selected_jewel_id: String = ""
var _state: BuildState
var _built: bool = false
var _points_label: Label
var _count_label: Label
var _zoom_label: Label
var _node_title: Label
var _node_type: Label
var _node_description: Label
var _node_reason: Label
var _allocate_button: Button
var _refund_button: Button
var _reset_button: Button
var _jewel_count: Label
var _jewel_filter: OptionButton
var _jewel_scroll: ScrollContainer
var _jewel_list: VBoxContainer
var _jewel_name: Label
var _jewel_detail_icon: Control
var _jewel_affixes: Label
var _jewel_location: Label
var _jewel_reason: Label
var _insert_button: Button
var _remove_button: Button
var _discard_button: Button
var _stat_label: Label
var _discard_pending: String = ""
var _jewel_signature: String = ""
var _search: LineEdit


func setup(state: BuildState) -> void:
	if _state != null and _state.changed.is_connected(refresh):
		_state.changed.disconnect(refresh)
	_state = state
	name = "PassiveTreePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 400)
	add_theme_constant_override("separation", 8)
	if not _built:
		_build_ui()
		_built = true
	tree_view.setup(state)
	if not _state.changed.is_connected(refresh):
		_state.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not _built or _state == null:
		return
	if not Passives.get_nodes().has(selected_node_id):
		selected_node_id = "origin"
	if not _state.jewels.has(selected_jewel_id):
		selected_jewel_id = "" if _state.jewels.is_empty() else str(_state.jewels.keys()[0])
	_points_label.text = "可用天赋点  %d" % _state.talent_points
	_count_label.text = "已点亮 %d / %d   ·   已镶嵌 %d / 12" % [_state.allocated_nodes.size() - 1, Passives.get_nodes().size() - 1, _state.socketed_jewels.size()]
	_reset_button.disabled = _state.allocated_nodes.size() <= 1
	tree_view.selected_node_id = selected_node_id
	tree_view.refresh()
	_refresh_node()
	_refresh_jewel_inventory()
	_refresh_jewel_detail()
	var stats: Dictionary = _state.get_stats()
	_stat_label.text = "伤害 %.1f   攻速 %.2f\n生命 %.0f   魔力 %.0f   护盾 %.0f" % [float(stats.get("damage", 0)), float(stats.get("attack_speed", 0)), float(stats.get("max_health", 0)), float(stats.get("max_mana", 0)), float(stats.get("max_shield", 0))]
	_stat_label.tooltip_text = "装备、天赋与已镶嵌珠宝的合计属性\n" + Passives.describe_stats(stats)
	_refresh_zoom()


func select_node(node_id: String) -> void:
	if not Passives.get_nodes().has(node_id):
		return
	selected_node_id = node_id
	_discard_pending = ""
	if _state != null and _state.socketed_jewels.has(node_id):
		selected_jewel_id = str(_state.socketed_jewels[node_id])
	if tree_view != null:
		tree_view.selected_node_id = node_id
		tree_view.queue_redraw()
	refresh()


func select_jewel(jewel_id: String) -> void:
	if _state == null or not _state.jewels.has(jewel_id):
		return
	selected_jewel_id = jewel_id
	_discard_pending = ""
	_refresh_jewel_inventory(true)
	_refresh_jewel_detail()


func allocate_selected() -> bool:
	if _state == null:
		return false
	var reason: String = _state.allocation_reason(selected_node_id)
	if not reason.is_empty():
		feedback.emit(reason)
		return false
	var success: bool = _state.allocate_passive(selected_node_id)
	if success:
		feedback.emit("已点亮「%s」· 属性已更新" % _node_name(selected_node_id))
	return success


func refund_selected() -> bool:
	if _state == null:
		return false
	var reason: String = _state.refund_reason(selected_node_id)
	if not reason.is_empty():
		feedback.emit(reason)
		return false
	var had_jewel: bool = _state.socketed_jewels.has(selected_node_id)
	var success: bool = _state.refund_passive(selected_node_id)
	if success:
		feedback.emit("已退还 1 点天赋" + (" · 珠宝已放回背包" if had_jewel else ""))
	return success


func insert_selected_jewel() -> bool:
	if _state == null or selected_jewel_id.is_empty():
		return false
	var reason: String = _state.socket_reason(selected_node_id, selected_jewel_id)
	if not reason.is_empty():
		feedback.emit(reason)
		return false
	var success: bool = _state.socket_jewel(selected_node_id, selected_jewel_id)
	if success:
		feedback.emit("珠宝已镶嵌至「%s」· 词缀立即生效" % _node_name(selected_node_id))
	return success


func remove_selected_jewel() -> bool:
	if _state == null:
		return false
	var reason: String = _state.remove_jewel_reason(selected_node_id)
	if not reason.is_empty():
		feedback.emit(reason)
		return false
	var success: bool = _state.remove_jewel(selected_node_id)
	if success:
		feedback.emit("珠宝已取回背包 · 可再次镶嵌")
	return success


func _build_ui() -> void:
	var toolbar: HFlowContainer = HFlowContainer.new()
	toolbar.name = "TreeToolbar"
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)
	_points_label = _label("", 17, GOLD)
	_points_label.name = "PassivePointsLabel"
	toolbar.add_child(_points_label)
	_count_label = _label("", 12, MUTED)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_count_label)
	_search = LineEdit.new()
	_search.name = "SearchNodes"
	_search.placeholder_text = "搜索天赋 / 属性"
	_search.custom_minimum_size = Vector2(164, 32)
	_search.add_theme_font_size_override("font_size", 13)
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	_search.text_submitted.connect(_on_search_submitted)
	toolbar.add_child(_search)
	toolbar.add_child(_button("−", "ZoomOutButton", _zoom_out, 30))
	_zoom_label = _label("34%", 12, MUTED)
	_zoom_label.custom_minimum_size.x = 32
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(_zoom_label)
	toolbar.add_child(_button("+", "ZoomInButton", _zoom_in, 30))
	toolbar.add_child(_button("起点", "CenterOriginButton", _center_origin, 48))
	toolbar.add_child(_button("全图", "FitTreeButton", _fit_tree, 48))
	_reset_button = _button("重置天赋", "ResetPassivesButton", _reset_passives, 82)
	_reset_button.tooltip_text = "免费退还全部天赋点；所有已镶嵌珠宝安全返回背包"
	toolbar.add_child(_reset_button)
	var content: HBoxContainer = HBoxContainer.new()
	content.name = "TreeAndInspector"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	var canvas_panel: PanelContainer = PanelContainer.new()
	canvas_panel.name = "ConstellationFrame"
	canvas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_panel.add_theme_stylebox_override("panel", _style(Color("efdbad"), BORDER, 9, 1, 2))
	content.add_child(canvas_panel)
	tree_view = TreeCanvas.new() as PassiveTreeView
	canvas_panel.add_child(tree_view)
	tree_view.selection_changed.connect(select_node)
	tree_view.node_activated.connect(_on_node_activated)
	tree_view.viewport_changed.connect(_refresh_zoom)
	var inspector: PanelContainer = PanelContainer.new()
	inspector.name = "NodeInspector"
	inspector.custom_minimum_size.x = 340
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_theme_stylebox_override("panel", _style(Color("f8ecd0"), BORDER, 9, 1, 11))
	content.add_child(inspector)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "InspectorScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_child(scroll)
	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 5)
	scroll.add_child(details)
	_node_type = _label("", 11, MUTED)
	_node_type.name = "NodeStateLabel"
	details.add_child(_node_type)
	_node_title = _wrap_label("", 20, GOLD)
	_node_title.name = "NodeTitleLabel"
	details.add_child(_node_title)
	_node_description = _wrap_label("", 13, TEXT)
	_node_description.name = "NodeDescriptionLabel"
	_node_description.mouse_filter = Control.MOUSE_FILTER_PASS
	details.add_child(_node_description)
	var node_buttons: HBoxContainer = HBoxContainer.new()
	node_buttons.add_theme_constant_override("separation", 7)
	details.add_child(node_buttons)
	_allocate_button = _button("分配  1 点", "AllocateButton", allocate_selected, 139)
	_allocate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_allocate_button.add_theme_color_override("font_color", CYAN)
	node_buttons.add_child(_allocate_button)
	_refund_button = _button("退还天赋", "RefundButton", refund_selected, 133)
	_refund_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_buttons.add_child(_refund_button)
	_node_reason = _wrap_label("", 11, MUTED)
	_node_reason.name = "NodeRestrictionLabel"
	_node_reason.mouse_filter = Control.MOUSE_FILTER_PASS
	details.add_child(_node_reason)
	details.add_child(HSeparator.new())
	var jewels_header: HBoxContainer = HBoxContainer.new()
	details.add_child(jewels_header)
	_jewel_count = _label("珠宝", 15, TEXT)
	_jewel_count.name = "JewelCountLabel"
	_jewel_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jewels_header.add_child(_jewel_count)
	_jewel_filter = OptionButton.new()
	_jewel_filter.name = "JewelFilter"
	_jewel_filter.add_item("全部", 0)
	_jewel_filter.add_item("背包", 1)
	_jewel_filter.add_item("已镶嵌", 2)
	_jewel_filter.add_item("稀有", 3)
	_jewel_filter.add_item("特殊", 4)
	_jewel_filter.add_theme_font_size_override("font_size", 12)
	_jewel_filter.custom_minimum_size.x = 88
	_jewel_filter.item_selected.connect(_on_jewel_filter_changed)
	jewels_header.add_child(_jewel_filter)
	_jewel_scroll = ScrollContainer.new()
	_jewel_scroll.name = "JewelInventory"
	_jewel_scroll.custom_minimum_size.y = 82
	_jewel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(_jewel_scroll)
	_jewel_list = VBoxContainer.new()
	_jewel_list.name = "JewelList"
	_jewel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jewel_list.add_theme_constant_override("separation", 4)
	_jewel_scroll.add_child(_jewel_list)
	_jewel_name = _wrap_label("", 15, CYAN)
	_jewel_name.name = "SelectedJewelLabel"
	_jewel_name.mouse_filter = Control.MOUSE_FILTER_PASS
	details.add_child(_jewel_name)
	_jewel_detail_icon = JewelIcon.new()
	_jewel_detail_icon.name = "SelectedJewelEmblem"
	_jewel_detail_icon.position = Vector2(0, 1)
	_jewel_detail_icon.size = Vector2(20, 20)
	_jewel_name.add_child(_jewel_detail_icon)
	_jewel_affixes = _wrap_label("", 12, TEXT)
	_jewel_affixes.name = "JewelAffixesLabel"
	_jewel_affixes.mouse_filter = Control.MOUSE_FILTER_PASS
	details.add_child(_jewel_affixes)
	_jewel_location = _wrap_label("", 11, MUTED)
	_jewel_location.name = "JewelLocationLabel"
	details.add_child(_jewel_location)
	var jewel_buttons: HBoxContainer = HBoxContainer.new()
	jewel_buttons.add_theme_constant_override("separation", 5)
	details.add_child(jewel_buttons)
	_insert_button = _button("镶嵌所选", "InsertJewelButton", insert_selected_jewel, 116)
	_insert_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insert_button.add_theme_color_override("font_color", CYAN)
	jewel_buttons.add_child(_insert_button)
	_remove_button = _button("取回", "RemoveJewelButton", remove_selected_jewel, 57)
	jewel_buttons.add_child(_remove_button)
	_discard_button = _button("丢弃", "DiscardJewelButton", _discard_jewel, 57)
	_discard_button.add_theme_color_override("font_color", RED)
	jewel_buttons.add_child(_discard_button)
	# Keep primary jewel actions visible before long four-affix descriptions.
	details.move_child(jewel_buttons, _jewel_name.get_index() + 1)
	_jewel_reason = _wrap_label("", 11, MUTED)
	_jewel_reason.name = "JewelRestrictionLabel"
	_jewel_reason.mouse_filter = Control.MOUSE_FILTER_PASS
	details.add_child(_jewel_reason)
	details.add_child(HSeparator.new())
	var stats_heading: Label = _label("当前构筑合计", 11, MUTED)
	details.add_child(stats_heading)
	_stat_label = _wrap_label("", 12, CYAN)
	_stat_label.name = "TreeDerivedStatsLabel"
	details.add_child(_stat_label)
	var legend: HFlowContainer = HFlowContainer.new()
	legend.name = "TreeLegend"
	legend.add_theme_constant_override("separation", 18)
	add_child(legend)
	legend.add_child(_label("● 已点亮", 11, GOLD))
	legend.add_child(_label("○ 可分配", 11, CYAN))
	legend.add_child(_label("● 未连接", 11, MUTED))
	legend.add_child(_label("◈ 珠宝孔", 11, Color("715285")))
	var tip: Label = _label("⌁ 寻枝覆盖 / 点亮", 11, GOLD)
	tip.mouse_filter = Control.MOUSE_FILTER_PASS
	tip.tooltip_text = "淡金范围与枝形标记：特殊珠宝覆盖\n完整枝形：借助寻枝晶玉远程点亮；每个节点仍消耗1点\n未激活的预览范围为灰色；先沿连线点亮珠宝孔"
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	legend.add_child(tip)


func _refresh_node() -> void:
	var node: Dictionary = Passives.get_nodes()[selected_node_id] as Dictionary
	var kind: String = str(node.get("type", "small"))
	var allocated: bool = _state.allocated_nodes.has(selected_node_id)
	var kind_names: Dictionary = {"start": "起点", "small": "基础天赋", "notable": "核心天赋", "socket": "珠宝插槽"}
	var status: String = "已点亮" if allocated else ("可分配" if _state.can_allocate(selected_node_id) else "未连接")
	var remote: bool = tree_view._analysis.get("remote_nodes", []).has(selected_node_id)
	if remote: status = "寻枝点亮"
	_node_type.text = "%s  /  %s" % [kind_names.get(kind, "天赋"), status]
	_node_type.add_theme_color_override("font_color", GOLD if allocated else (CYAN if _state.can_allocate(selected_node_id) else MUTED))
	_node_title.text = str(node.get("name", selected_node_id))
	_node_title.add_theme_color_override("font_color", GOLD if allocated else TEXT)
	_node_description.text = str(node.get("description", ""))
	_node_description.tooltip_text = _node_description.text
	if kind == "socket" and _state.socketed_jewels.has(selected_node_id):
		_node_description.text = "已镶嵌：" + _jewel_title(_state.get_jewel_at(selected_node_id))
		_node_description.tooltip_text = Jewels.get_description(_state.get_jewel_at(selected_node_id))
	elif kind == "socket":
		_node_description.text = "空珠宝孔 · 选择珠宝镶嵌"
		_node_description.tooltip_text = "沿已点连线连通起点后，可镶嵌一颗珠宝"
	_allocate_button.disabled = not _state.can_allocate(selected_node_id)
	_allocate_button.text = "已点亮" if allocated else "分配  1 点"
	_refund_button.disabled = not _state.can_refund(selected_node_id)
	_allocate_button.tooltip_text = _state.allocation_reason(selected_node_id)
	_refund_button.tooltip_text = _state.refund_reason(selected_node_id)
	if kind == "start":
		_node_reason.text = "从相邻高亮节点开始；升级获得天赋点"
	elif allocated:
		_node_reason.text = _state.refund_reason(selected_node_id) if _refund_button.disabled else "可免费退还 1 点" + ("，珠宝自动回到背包" if kind == "socket" else "；不会切断其他天赋")
	else:
		_node_reason.text = _state.allocation_reason(selected_node_id) if _allocate_button.disabled else "沿相连的天赋分配 · 双击节点也可点亮"
	if remote:
		_node_reason.text = "寻枝支持 · 已消耗 1 点"
	elif not allocated and tree_view._analysis.get("granted_by", {}).has(selected_node_id):
		_node_reason.text = "寻枝覆盖 · 分配仍需 1 点" if not _allocate_button.disabled else _state.allocation_reason(selected_node_id)
	_node_reason.tooltip_text = _node_reason.text + "\n" + _state.refund_reason(selected_node_id) if allocated else _node_reason.text
	if _node_reason.text.length() > 30:
		_node_reason.text = "操作受限 · 悬停查看原因"


func _refresh_jewel_inventory(force: bool = false) -> void:
	_jewel_count.text = "珠宝 %d / 64" % _state.jewels.size()
	var signature: String = str(_state.jewels.keys()) + str(_state.socketed_jewels) + str(_jewel_filter.selected) + selected_jewel_id
	if not force and signature == _jewel_signature:
		return
	_jewel_signature = signature
	var scroll_position: int = _jewel_scroll.scroll_vertical
	for child: Node in _jewel_list.get_children():
		_jewel_list.remove_child(child)
		child.queue_free()
	var visible_count: int = 0
	for id: String in _state.jewels:
		var jewel: Dictionary = _state.jewels[id] as Dictionary
		var location: String = _state.jewel_location(id)
		if (_jewel_filter.selected == 1 and location != "inventory") or (_jewel_filter.selected == 2 and location == "inventory") or (_jewel_filter.selected == 3 and str(jewel.get("rarity", "")) != "rare") or (_jewel_filter.selected == 4 and str(jewel.get("rarity", "")) != "special"):
			continue
		visible_count += 1
		var button: Button = _button("", "Jewel_" + id, select_jewel.bind(id))
		button.custom_minimum_size.y = 40
		button.text = "　　%s\n　　%s" % [_jewel_title(jewel), "背包" if location == "inventory" else "已镶嵌 · " + _node_name(location)]
		var icon := JewelIcon.new()
		icon.name = "JewelEmblem"
		icon.jewel = jewel
		icon.position = Vector2(5, 6)
		icon.size = Vector2(26, 28)
		button.add_child(icon)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", PresentationTheme.ink(Jewels.get_color(jewel)))
		button.add_theme_stylebox_override("normal", _style(Color("ead3a2") if id == selected_jewel_id else Color("f8ecd0"), CYAN.darkened(0.4) if id == selected_jewel_id else BORDER.darkened(0.2), 5, 1, 7))
		button.tooltip_text = _jewel_title(jewel) + "\n" + Jewels.get_description(jewel)
		_jewel_list.add_child(button)
	if visible_count == 0:
		var empty: Label = _wrap_label("暂无符合筛选的珠宝\n每击败 20 名敌人获得一颗", 12, MUTED)
		empty.name = "EmptyJewelInventory"
		_jewel_list.add_child(empty)
	_jewel_scroll.set_deferred("scroll_vertical", scroll_position)


func _refresh_jewel_detail() -> void:
	var jewel: Dictionary = _state.jewels.get(selected_jewel_id, {}) as Dictionary
	var node: Dictionary = Passives.get_nodes().get(selected_node_id, {}) as Dictionary
	var is_socket: bool = str(node.get("type", "")) == "socket"
	var current: String = str(_state.socketed_jewels.get(selected_node_id, ""))
	_jewel_name.text = "选择一颗珠宝查看词缀" if jewel.is_empty() else "　　" + _jewel_title(jewel)
	_jewel_detail_icon.set("jewel", jewel)
	_jewel_detail_icon.visible = not jewel.is_empty()
	_jewel_name.add_theme_color_override("font_color", MUTED if jewel.is_empty() else PresentationTheme.ink(Jewels.get_color(jewel)))
	var rule: Dictionary = Jewels.allocation_rule(jewel)
	if jewel.is_empty():
		_jewel_affixes.text = "选择珠宝 · 悬停查看完整效果"
	elif not rule.is_empty():
		_jewel_affixes.text = "寻枝范围 %d · 每个天赋仍需 1 点" % int(rule.radius)
	else:
		_jewel_affixes.text = "%d 条属性词缀 · 悬停查看" % jewel.get("affixes", []).size()
	_jewel_affixes.tooltip_text = Jewels.get_description(jewel)
	_jewel_name.tooltip_text = _jewel_title(jewel) + "\n" + Jewels.get_description(jewel) if not jewel.is_empty() else ""
	tree_view.preview_jewel(selected_node_id if is_socket else "", selected_jewel_id)
	var location: String = "" if jewel.is_empty() else _state.jewel_location(selected_jewel_id)
	if not rule.is_empty() and is_socket and current != selected_jewel_id:
		_jewel_affixes.text = "范围预览 %d · 镶嵌后生效" % int(rule.radius)
	_jewel_location.text = "每击败 20 名敌人获得珠宝" if jewel.is_empty() else ("所在位置：背包" if location == "inventory" else "所在位置：" + _node_name(location))
	_insert_button.disabled = jewel.is_empty() or not _state.socket_reason(selected_node_id, selected_jewel_id).is_empty()
	_insert_button.text = "已镶嵌" if not current.is_empty() and current == selected_jewel_id else ("替换 / 交换" if not current.is_empty() else "镶嵌所选")
	var remove_reason: String = _state.remove_jewel_reason(selected_node_id)
	_remove_button.disabled = not remove_reason.is_empty()
	_remove_button.tooltip_text = remove_reason if not remove_reason.is_empty() else "将所选插槽内的珠宝取回背包"
	_discard_button.disabled = jewel.is_empty() or location != "inventory"
	_discard_button.text = "确认？" if _discard_pending == selected_jewel_id and not selected_jewel_id.is_empty() else "丢弃"
	_discard_button.tooltip_text = "仅能丢弃背包珠宝；再次点击确认后无法恢复"
	if _discard_pending == selected_jewel_id and not selected_jewel_id.is_empty():
		_jewel_reason.text = "再次点击「确认？」永久丢弃所选珠宝"
		_jewel_reason.add_theme_color_override("font_color", RED)
	else:
		_jewel_reason.add_theme_color_override("font_color", MUTED)
		if not is_socket:
			_jewel_reason.text = "先在星图选择菱形珠宝孔；点亮后才能镶嵌"
		elif not _state.allocated_nodes.has(selected_node_id):
			_jewel_reason.text = "此插槽尚未点亮；先沿连线分配天赋"
		elif jewel.is_empty():
			_jewel_reason.text = "选择背包中的珠宝镶嵌"
		elif _insert_button.disabled:
			_jewel_reason.text = _state.socket_reason(selected_node_id, selected_jewel_id)
		elif current.is_empty():
			_jewel_reason.text = "范围天赋仍需 1 点 · 不可向外延伸" if not rule.is_empty() else "珠宝词缀镶嵌后生效 · 操作免费"
		else:
			_jewel_reason.text = "替换后原珠宝回到背包；两个插槽之间可交换"
	if not current.is_empty() and not remove_reason.is_empty():
		_jewel_reason.text = "取回受限 · 先退还依赖天赋"
		_jewel_reason.tooltip_text = remove_reason
	else:
		_jewel_reason.tooltip_text = _jewel_reason.text
		if _jewel_reason.text.length() > 30:
			_jewel_reason.text = "暂不可镶嵌 · 悬停查看原因" if _insert_button.disabled else "镶嵌提示 · 悬停查看"


func _node_name(node_id: String) -> String:
	var node: Dictionary = Passives.get_nodes().get(node_id, {}) as Dictionary
	var result: String = str(node.get("name", node_id))
	if str(node.get("type", "")) == "socket":
		for sector: Dictionary in Passives.SECTORS:
			if str(sector["id"]) == str(node.get("sector", "")):
				return str(sector["name"]).split(" · ")[0] + " · " + result
	return result


func _jewel_title(jewel: Dictionary) -> String:
	var serial: int = str(jewel.get("id", "")).get_slice("_", 1).to_int()
	return "%s  #%03d" % [Jewels.display_name(jewel), serial]


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _built and not is_visible_in_tree():
		_discard_pending = ""
		if _state != null:
			_refresh_jewel_detail()


func _on_node_activated(node_id: String) -> void:
	select_node(node_id)
	if _state.can_allocate(node_id):
		allocate_selected()


func _reset_passives() -> void:
	var refunded: int = _state.allocated_nodes.size() - 1
	_state.refund_talents()
	feedback.emit("已退还 %d 点天赋 · 全部珠宝已安全返回背包" % refunded)


func _discard_jewel() -> void:
	if selected_jewel_id.is_empty() or _state.jewel_location(selected_jewel_id) != "inventory":
		return
	if _discard_pending != selected_jewel_id:
		_discard_pending = selected_jewel_id
		_refresh_jewel_detail()
		return
	var id: String = selected_jewel_id
	_discard_pending = ""
	if _state.discard_jewel(id):
		feedback.emit("珠宝已丢弃 · 背包空位已释放")


func _on_jewel_filter_changed(_index: int) -> void:
	_refresh_jewel_inventory(true)


func _on_search_changed(query: String) -> void:
	tree_view.set_search_query(query)
	_search.tooltip_text = "匹配 %d 个节点 · 按回车定位首个结果" % tree_view.get_search_match_count()


func _on_search_submitted(_query: String) -> void:
	tree_view.focus_first_match()
	_search.release_focus()
	if tree_view.get_search_match_count() == 0:
		feedback.emit("没有匹配的天赋；试试「伤害」「护盾」或「珠宝」")


func _zoom_in() -> void:
	tree_view.set_zoom(tree_view.zoom * 1.2)


func _zoom_out() -> void:
	tree_view.set_zoom(tree_view.zoom / 1.2)


func _center_origin() -> void:
	tree_view.center_origin()


func _fit_tree() -> void:
	tree_view.fit_tree()


func _refresh_zoom() -> void:
	if tree_view != null and _zoom_label != null:
		_zoom_label.text = "%d%%" % roundi(tree_view.zoom * 100.0)


func _label(text: String, font_size: int, color: Color) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PresentationTheme.ink(color))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _wrap_label(text: String, font_size: int, color: Color) -> Label:
	var result: Label = _label(text, font_size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


func _button(text: String, stable_name: String, callback: Callable, width: float = 0.0) -> Button:
	var result: Button = Button.new()
	result.name = stable_name
	result.text = text
	result.custom_minimum_size = Vector2(width, 30)
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_filter = Control.MOUSE_FILTER_STOP
	result.add_theme_font_size_override("font_size", 12)
	result.add_theme_stylebox_override("normal", _style(Color("f8ecd0"), BORDER, 5, 1, 7))
	result.add_theme_stylebox_override("hover", _style(Color("fff2d5"), CYAN.darkened(0.2), 5, 1, 7))
	result.add_theme_stylebox_override("pressed", _style(Color("ead3a2"), CYAN, 5, 1, 7))
	result.add_theme_stylebox_override("disabled", _style(Color("d9c8a5"), Color("9b8560"), 5, 1, 7))
	result.add_theme_color_override("font_disabled_color", Color("82725b"))
	if callback.is_valid():
		result.pressed.connect(callback)
	return result


func _style(bg: Color, border: Color, radius: int = 6, border_width: int = 1, margin: int = 8) -> StyleBox:
	var frame: StyleBox=preload("res://scripts/visuals/visual_theme.gd").panel(bg,border,radius,border_width,margin)
	frame.content_margin_top=margin
	frame.content_margin_bottom=margin
	return frame
