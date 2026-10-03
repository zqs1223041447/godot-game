extends PanelContainer
## Town services use the same canonical inventory as the live build.
signal feedback(message: String)
signal crafter_requested
var arena: Node
var _body: VBoxContainer
var _title: Label
var _content: VBoxContainer
var _service := ""
var _reset: ConfirmationDialog
var _reset_revision := -1
var _map_select: OptionButton
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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	var leave := Button.new()
	leave.text = "返回正常游戏"
	leave.pressed.connect(func(): _result(arena.leave_town_test(int(arena.world_context().revision))))
	_body.add_child(leave)
	_reset = ConfirmationDialog.new()
	_reset.title = "重置天赋"
	_reset.dialog_text = "退还已分配天赋点，珠宝退回行囊或待安置区？"
	_reset.confirmed.connect(func(): _result(arena.town_reset_passives(_reset_revision)))
	add_child(_reset)
	_select("skill_merchant")

func open_service(id: String = "") -> void:
	show()
	if not id.is_empty(): _select(id)
	elif not _service.is_empty(): _select(_service)

func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

func _select(id: String) -> void:
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
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(42,42)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(str(offer.icon_path)): icon.texture = load(str(offer.icon_path))
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
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(summary)
	var craft := Button.new()
	craft.text = "制作地图 · 测试免费"
	craft.pressed.connect(_craft_map)
	_content.add_child(craft)
	var launch := Button.new()
	launch.text = "开启地图"
	launch.disabled = not bool(draft.valid)
	var revision: int = int(draft.revision)
	launch.pressed.connect(func():
		var result: Dictionary = arena.start_map(revision)
		_result(result)
		if result.ok: hide())
	_content.add_child(launch)
	_map_select.item_selected.connect(func(_index: int): launch.disabled = true)
	for check: CheckBox in _normal.values()+_special.values():
		check.toggled.connect(func(_value: bool): launch.disabled = true)

func _craft_map() -> void:
	var normals: Array = []
	var specials: Array = []
	for id: String in _normal:
		if _normal[id].button_pressed: normals.append(id)
	for id: String in _special:
		if _special[id].button_pressed: specials.append(id)
	var result: Dictionary = arena.craft_map(str(_map_select.get_selected_metadata()),normals,specials,int(arena.map_draft().revision))
	_result(result)
	if result.ok: _select("map_device")

func _result(result: Dictionary) -> void:
	feedback.emit(str(result.get("reason","操作完成")) if not result.get("ok",false) else "操作完成")

func cancel_pending() -> void:
	_reset_revision = -1
	_reset.hide()
	hide()
