extends PanelContainer
## Town services use the same canonical inventory as the live build.
const SkillArt = preload("res://scripts/visuals/skill_emblem.gd")
const GearArt = preload("res://scripts/visuals/equipment_painterly_art.gd")
signal feedback(message: String)
signal crafter_requested
class ShardIcon extends TextureRect:
	func _draw() -> void:
		var points := PackedVector2Array([Vector2(21,4),Vector2(32,18),Vector2(22,37),Vector2(10,23)])
		draw_colored_polygon(points,Color("a78eb0"))
		points.append(points[0])
		draw_polyline(points,Color("624c70"),1.5,true)
		draw_line(Vector2(21,5),Vector2(22,35),Color("eadcf0"),1.5,true)

var arena: Node
var _body: VBoxContainer
var _title: Label
var _content: VBoxContainer
var _service := ""
var _reset: ConfirmationDialog
var _reset_revision := -1
var _map_select: OptionButton
var _tier_select: OptionButton
var _service_buttons: Dictionary = {}
var _leave: Button
var _test_enter: Button
var _claim: Button
var _normal := {}
var _special := {}

func setup(value: Node) -> void:
	arena = value
	name = "TownServices"
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	var header := HBoxContainer.new()
	_body.add_child(header)
	_title = Label.new()
	_title.text = "城镇 · 测试供应"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(hide)
	header.add_child(close)
	var services := GridContainer.new()
	services.columns = 3
	_body.add_child(services)
	for entry: Dictionary in arena.town_services():
		var button := Button.new()
		button.text = entry.name
		button.tooltip_text = entry.description
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select.bind(str(entry.id)))
		services.add_child(button)
		_service_buttons[str(entry.id)] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_claim = Button.new()
	_claim.text = "领取待领奖励"
	_claim.pressed.connect(func():
		_result(arena.claim_normal_rewards(int(arena.world_context().revision)))
		refresh_world()
		if not _service.is_empty(): _select(_service))
	_body.add_child(_claim)
	var routes := HBoxContainer.new()
	_body.add_child(routes)
	_leave = Button.new()
	_leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leave.pressed.connect(func():
		var context: Dictionary = arena.world_context()
		_result(arena.leave_town_test(int(context.revision)) if bool(context.get("test_mode", false)) else arena.leave_normal_town(int(context.revision))))
	routes.add_child(_leave)
	_test_enter = Button.new()
	_test_enter.text = "测试城镇"
	_test_enter.tooltip_text = "独立测试存档，免费物品不会带回正式游戏。"
	_test_enter.pressed.connect(func(): _result(arena.enter_town_test(int(arena.world_context().revision))))
	routes.add_child(_test_enter)
	_reset = ConfirmationDialog.new()
	_reset.title = "重置天赋"
	_reset.ok_button_text = "确认"
	_reset.cancel_button_text = "取消"
	_reset.dialog_text = "退还已分配天赋点，珠宝退回行囊或待安置区？"
	_reset.confirmed.connect(func(): _result(arena.town_reset_passives(_reset_revision)))
	add_child(_reset)
	refresh_world()
	_select("skill_merchant" if bool(arena.world_context().get("test_mode", false)) else "map_device")

func refresh_world() -> void:
	var context: Dictionary = arena.world_context()
	var testing := bool(context.get("test_mode", false))
	_title.text = "城镇 · 测试供应" if testing else "城镇 · 远征"
	_leave.text = "返回正式游戏" if testing else "竞技练习"
	_test_enter.visible = not testing
	for id: String in _service_buttons:
		_service_buttons[id].disabled = not testing and id not in ["map_device", "crafter", "passive_reset"]
		if _service_buttons[id].disabled: _service_buttons[id].tooltip_text = "免费供应仅在独立测试城镇开放。"
	_claim.visible = not testing and _has_pending_rewards(context)
	_claim.disabled = not bool(context.get("can_claim_normal_rewards", false))
	_claim.tooltip_text = str(context.get("claim_reason", ""))
	if not testing and _service not in ["", "map_device", "crafter", "passive_reset"]:
		_select("map_device")

static func _has_pending_rewards(context: Dictionary) -> bool:
	for key: String in ["pending_map_reward", "pending_gems", "pending_flasks"]:
		var value: Variant = context.get(key, 0)
		if value is Dictionary or value is Array:
			if not value.is_empty(): return true
		elif value is int or value is float:
			if value > 0: return true
	return false

func open_service(id: String = "") -> void:
	refresh_world()
	show()
	if not id.is_empty(): _select(id)
	elif not _service.is_empty(): _select(_service)

func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

func _select(id: String) -> void:
	if not bool(arena.world_context().get("test_mode", false)) and id not in ["map_device", "crafter", "passive_reset"]: id = "map_device"
	_service = id
	_clear()
	if id == "map_device":
		_build_map()
		return
	if id == "crafter":
		crafter_requested.emit()
		hide()
		return
	if id == "passive_reset":
		var button := Button.new()
		button.text = "重置已分配天赋"
		button.pressed.connect(func():
			_reset_revision = arena.state.revision()
			_reset.popup_centered(Vector2i(360,150)))
		_content.add_child(button)
		return
	for offer: Dictionary in arena.town_stock(id):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_content.add_child(row)
		var icon: TextureRect = ShardIcon.new() if str(offer.kind) == "currency" else TextureRect.new()
		icon.custom_minimum_size = Vector2(42,42)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(str(offer.icon_path)): icon.texture = load(str(offer.icon_path))
		elif str(offer.kind) in ["skill_gem","support_gem"]:
			icon.texture = SkillArt.ICONS.get(str(offer.definition_id).get_slice(":",1))
		else: icon.texture = GearArt.texture_for_entry(offer.preview)
		row.add_child(icon)
		var label := Label.new()
		label.text = str(offer.name)
		label.tooltip_text = str(offer.description)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		var buy := Button.new()
		buy.text = "领取"
		buy.tooltip_text = str(offer.price_label)
		buy.disabled = not bool(offer.available)
		buy.pressed.connect(func(): _result(arena.town_buy(str(offer.id),arena.state.revision())))
		row.add_child(buy)

func _build_map() -> void:
	var options: Dictionary = arena.map_options()
	var draft: Dictionary = arena.map_draft()
	_map_select = OptionButton.new()
	_content.add_child(_map_select)
	for entry: Dictionary in options.maps:
		_map_select.add_item(str(entry.name))
		_map_select.set_item_metadata(_map_select.item_count-1,str(entry.id))
		if str(entry.id) == str(draft.map_id): _map_select.select(_map_select.item_count-1)
	_tier_select = OptionButton.new()
	_content.add_child(_tier_select)
	_update_tiers(options, int(draft.get("tier", 1)))
	_normal.clear()
	_special.clear()
	for group: String in ["normal_modifiers","special_modifiers"]:
		var heading := Label.new()
		heading.text = "普通词缀" if group == "normal_modifiers" else "特殊词缀"
		_content.add_child(heading)
		for entry: Dictionary in options[group]:
			var check := CheckBox.new()
			check.text = str(entry.name)
			check.tooltip_text = str(entry.description)
			check.button_pressed = str(entry.id) in (draft.normal_ids if group == "normal_modifiers" else draft.special_ids)
			_content.add_child(check)
			if group == "normal_modifiers": _normal[str(entry.id)] = check
			else: _special[str(entry.id)] = check
	var summary := Label.new()
	summary.text = str(draft.summary)
	if not bool(arena.world_context().get("test_mode", false)):
		summary.text += "\n入场 %d 校准碎片 · 完成奖励 %d" % [int(draft.get("cost", 0)), int(draft.get("completion_reward", 0))]
		if not str(draft.get("reason", "")).is_empty(): summary.text += "\n" + str(draft.reason)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(summary)
	var craft := Button.new()
	craft.text = "制作地图 · 测试免费" if bool(arena.world_context().get("test_mode", false)) else "准备地图"
	craft.pressed.connect(_craft_map)
	_content.add_child(craft)
	var launch := Button.new()
	launch.text = "开启地图"
	launch.disabled = not bool(draft.get("can_start", draft.valid))
	var revision: int = int(draft.revision)
	launch.pressed.connect(func():
		var result: Dictionary = arena.start_map(revision)
		_result(result)
		if result.ok: hide())
	_content.add_child(launch)
	_map_select.item_selected.connect(func(_index: int):
		_update_tiers(options, 1)
		launch.disabled = true)
	_tier_select.item_selected.connect(func(_index: int): launch.disabled = true)
	for check: CheckBox in _normal.values()+_special.values():
		check.toggled.connect(func(_value: bool): launch.disabled = true)

func _update_tiers(options: Dictionary, selected: int) -> void:
	_tier_select.clear()
	_tier_select.visible = not bool(arena.world_context().get("test_mode", false))
	for entry: Dictionary in options.get("tiers", []):
		if str(entry.map_id) != str(_map_select.get_selected_metadata()): continue
		_tier_select.add_item(str(entry.label) + (" · 未解锁" if not bool(entry.unlocked) else ""))
		var index := _tier_select.item_count - 1
		_tier_select.set_item_metadata(index, int(entry.tier))
		_tier_select.set_item_disabled(index, not bool(entry.unlocked))
		_tier_select.get_popup().set_item_tooltip(index, str(entry.get("reason", "")))
		if int(entry.tier) == selected: _tier_select.select(index)

func _craft_map() -> void:
	var normals: Array = []
	var specials: Array = []
	for id: String in _normal:
		if _normal[id].button_pressed: normals.append(id)
	for id: String in _special:
		if _special[id].button_pressed: specials.append(id)
	var result: Dictionary
	if bool(arena.world_context().get("test_mode", false)):
		result = arena.craft_map(str(_map_select.get_selected_metadata()),normals,specials,int(arena.map_draft().revision))
	else:
		if _tier_select.item_count == 0: return
		result = arena.craft_normal_map(str(_map_select.get_selected_metadata()),int(_tier_select.get_selected_metadata()),normals,specials,int(arena.map_draft().revision))
	_result(result)
	if result.ok: _select("map_device")

func _result(result: Dictionary) -> void:
	feedback.emit(str(result.get("reason","操作完成")) if not result.get("ok",false) else "操作完成")

func cancel_pending() -> void:
	_reset_revision = -1
	_reset.hide()
	hide()
