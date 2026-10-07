extends PanelContainer
## Town services use the same canonical inventory as the live build.
const SkillArt = preload("res://scripts/visuals/skill_emblem.gd")
const GearArt = preload("res://scripts/visuals/equipment_painterly_art.gd")
const ThemeStyle = preload("res://scripts/visuals/visual_theme.gd")
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
var _reward_status: Label
var _gem_dialog: ConfirmationDialog
var _gem_pending: Dictionary = {}
var _stock_model: RefCounted
var _stock_revision := -1
var _stock_refresh_queued := false
var _normal := {}
var _special := {}
var _map_summary: Label
var _map_launch: Button
var _map_selection_dirty := false
var _map_status_queued := false
var _map_prepared_revision := -1
var _map_launch_pending := false

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
	_claim.pressed.connect(_claim_rewards)
	_body.add_child(_claim)
	_reward_status = Label.new()
	_reward_status.name = "RewardClaimStatus"
	_reward_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_status.add_theme_font_size_override("font_size", 13)
	_body.add_child(_reward_status)
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
	_gem_dialog = ConfirmationDialog.new()
	_gem_dialog.title = "购买宝石"
	_gem_dialog.ok_button_text = "确认购买"
	_gem_dialog.cancel_button_text = "取消"
	_gem_dialog.dialog_autowrap = true
	var confirmation_theme := Theme.new()
	confirmation_theme.set_color("title_color", "Window", Color("f8ecd0"))
	for style_name: String in ["embedded_border", "embedded_unfocused_border"]:
		var frame := ThemeDB.get_default_theme().get_stylebox(style_name, "Window").duplicate() as StyleBoxFlat
		if frame != null:
			frame.bg_color = Color("60432f")
			frame.border_color = ThemeStyle.BORDER
			confirmation_theme.set_stylebox(style_name, "Window", frame)
	_gem_dialog.theme = confirmation_theme
	_gem_dialog.confirmed.connect(_confirm_gem_purchase)
	_gem_dialog.canceled.connect(_cancel_gem_purchase)
	add_child(_gem_dialog)
	_gem_dialog.get_ok_button().add_theme_color_override("font_focus_color", ThemeStyle.TEXT)
	_gem_dialog.get_cancel_button().add_theme_color_override("font_focus_color", ThemeStyle.TEXT)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_cancel_gem_purchase()
			arena.cancel_map_preparation())
	refresh_world()
	_select("skill_merchant" if bool(arena.world_context().get("test_mode", false)) else "map_device")

func refresh_world() -> void:
	_observe_stock_model()
	var context: Dictionary = arena.world_context()
	var testing := bool(context.get("test_mode", false))
	if not _gem_pending.is_empty() and (arena.state != _gem_pending.model or int(context.revision) != int(_gem_pending.world_revision)):
		_cancel_gem_purchase()
	_title.text = "城镇 · 测试供应" if testing else "城镇 · 远征"
	_leave.text = "返回正式游戏" if testing else "竞技练习"
	_test_enter.visible = not testing
	for id: String in _service_buttons:
		_service_buttons[id].disabled = not testing and id not in ["map_device", "crafter", "passive_reset", "skill_merchant"]
		if _service_buttons[id].disabled: _service_buttons[id].tooltip_text = "免费供应仅在独立测试城镇开放。"
	_claim.visible = not testing and _has_pending_rewards(context)
	_claim.disabled = not bool(context.get("can_claim_normal_rewards", false))
	var pending_text := pending_reward_text(context)
	_claim.tooltip_text = pending_text
	if not str(context.get("claim_reason", "")).is_empty():
		_claim.tooltip_text += ("\n" if not pending_text.is_empty() else "") + str(context.claim_reason)
	_reward_status.text = pending_text
	_reward_status.visible = not testing and not pending_text.is_empty()
	if not testing and _service not in ["", "map_device", "crafter", "passive_reset", "skill_merchant"]:
		_select("map_device")
	_queue_stock_refresh()
	_queue_map_status_refresh()

func _observe_stock_model() -> void:
	if _stock_model == arena.state: return
	if _stock_model != null and _stock_model.changed.is_connected(_on_stock_changed):
		_stock_model.changed.disconnect(_on_stock_changed)
	_stock_model = arena.state
	_stock_revision = -1
	_stock_model.changed.connect(_on_stock_changed)

func _on_stock_changed() -> void:
	_cancel_gem_purchase()
	_queue_stock_refresh()
	_queue_map_status_refresh()

func _queue_stock_refresh() -> void:
	if _stock_refresh_queued or not is_visible_in_tree() or _service != "skill_merchant": return
	_stock_refresh_queued = true
	_refresh_stock_if_needed.call_deferred()

func _refresh_stock_if_needed() -> void:
	_stock_refresh_queued = false
	if is_visible_in_tree() and _service == "skill_merchant" and _stock_revision != arena.state.revision():
		_select("skill_merchant")

func _queue_map_status_refresh() -> void:
	if _map_status_queued or not is_visible_in_tree() or _service != "map_device": return
	_map_status_queued = true
	_refresh_map_status.call_deferred()

func _refresh_map_status() -> void:
	_map_status_queued = false
	if not is_visible_in_tree() or _service != "map_device" or not is_instance_valid(_map_summary) or not is_instance_valid(_map_launch): return
	var draft: Dictionary = arena.map_draft()
	if _map_selection_dirty:
		_map_summary.text = "配置已更改 · 请准备地图"
	else:
		_map_summary.text = str(draft.summary)
		if not bool(arena.world_context().get("test_mode", false)):
			_map_summary.text += "\n入场 %d 校准碎片 · 完成奖励 %d" % [int(draft.get("cost", 0)), int(draft.get("completion_reward", 0))]
			if not str(draft.get("reason", "")).is_empty(): _map_summary.text += "\n" + str(draft.reason)
	# Currency updates never prepare changed controls or adopt an external draft.
	_map_launch.disabled = _map_launch_pending or _map_selection_dirty or int(draft.revision) != _map_prepared_revision or not bool(draft.get("can_start", draft.valid))

func _mark_map_selection_dirty() -> void:
	arena.cancel_map_preparation()
	_map_selection_dirty = true
	if is_instance_valid(_map_launch): _map_launch.disabled = true
	_queue_map_status_refresh()

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
	# Canvas z-order alone does not move this panel ahead of later HUD controls
	# for pointer picking; its footer can overlap the flask strip.
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	show()
	if not id.is_empty(): _select(id)
	elif not _service.is_empty(): _select(_service)

func _clear() -> void:
	_map_summary = null
	_map_launch = null
	_map_selection_dirty = false
	_map_prepared_revision = -1
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

func _select(id: String) -> void:
	arena.cancel_map_preparation()
	_cancel_gem_purchase()
	if not bool(arena.world_context().get("test_mode", false)) and id not in ["map_device", "crafter", "passive_reset", "skill_merchant"]: id = "map_device"
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
		buy.text = "%d 碎片" % int(offer.get("cost", 0)) if bool(offer.get("paid", false)) else "领取"
		buy.tooltip_text = str(offer.price_label)
		if not str(offer.get("reason", "")).is_empty(): buy.tooltip_text += "\n" + str(offer.reason)
		buy.disabled = not bool(offer.available)
		if bool(offer.get("paid", false)):
			buy.pressed.connect(_request_gem_purchase.bind(str(offer.definition_id)))
		else:
			buy.pressed.connect(func(): _result(arena.town_buy(str(offer.id),arena.state.revision())))
		row.add_child(buy)
	_stock_revision = arena.state.revision()

func _request_gem_purchase(definition_id: String) -> void:
	_cancel_gem_purchase()
	var quote: Dictionary = arena.normal_gem_trade_quote("buy", definition_id, arena.state.revision())
	if not bool(quote.get("ok", false)):
		_result(quote)
		return
	_gem_pending = {"quote":quote.duplicate(true),"target":definition_id,"model":arena.state,"world_revision":int(arena.world_context().revision)}
	_gem_dialog.dialog_text = "购买「%s」？\n消耗校准碎片 %d 枚，放入行囊。" % [str(quote.name), int(quote.cost.calibration_shard)]
	_gem_dialog.popup_centered(Vector2i(420,180))

func _confirm_gem_purchase() -> void:
	if _gem_pending.is_empty(): return
	var issued: Dictionary = _gem_pending
	_gem_pending = {}
	_result(arena.execute_normal_gem_trade(issued.quote.handle, issued.target))
	if is_visible_in_tree(): _select("skill_merchant")

func _cancel_gem_purchase() -> void:
	if not _gem_pending.is_empty():
		if arena.state == _gem_pending.model: arena.cancel_normal_gem_trade_quote(_gem_pending.quote.handle)
		else: _gem_pending.model.cancel_gem_trade_quote(_gem_pending.quote.handle)
		_gem_pending = {}
	if is_instance_valid(_gem_dialog): _gem_dialog.hide()

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
	_map_summary = summary
	_map_selection_dirty = false
	_map_prepared_revision = int(draft.revision)
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
	_map_launch = launch
	launch.text = "开启地图"
	launch.disabled = not bool(draft.get("can_start", draft.valid))
	var revision: int = int(draft.revision)
	launch.pressed.connect(_launch_map.bind(revision))
	_content.add_child(launch)
	_map_select.item_selected.connect(func(_index: int):
		_update_tiers(options, 1)
		_mark_map_selection_dirty())
	_tier_select.item_selected.connect(func(_index: int): _mark_map_selection_dirty())
	for check: CheckBox in _normal.values()+_special.values():
		check.toggled.connect(func(_value: bool): _mark_map_selection_dirty())

func _launch_map(revision: int) -> void:
	if _map_launch_pending: return
	_map_launch_pending = true
	_map_launch.disabled = true
	_map_launch.text = "准备地形…"
	var result: Dictionary = await arena.open_map(revision)
	_map_launch_pending = false
	if is_instance_valid(_map_launch): _map_launch.text = "开启地图"
	if result.ok:
		_result(result)
		hide()
	elif is_visible_in_tree():
		_result(result)
		_refresh_map_status()


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


func _claim_rewards() -> void:
	var result: Dictionary = arena.claim_normal_rewards(int(arena.world_context().revision))
	# Results report committed quantities; current world context owns the remainder.
	refresh_world()
	if not _service.is_empty(): _select(_service)
	var message := claim_reward_text(result, arena.world_context())
	_reward_status.text = message
	_reward_status.show()
	feedback.emit(message)

static func _reward_quantities(shards: int, gems: int, flasks: int) -> String:
	var parts: Array[String] = []
	if shards > 0: parts.append("校准碎片 ×%d" % shards)
	if gems > 0: parts.append("宝石 ×%d" % gems)
	if flasks > 0: parts.append("药剂 ×%d" % flasks)
	return " · ".join(parts)

static func pending_reward_text(context: Dictionary) -> String:
	var map_reward: Dictionary = context.get("pending_map_reward", {})
	var quantities := _reward_quantities(int(map_reward.get("shards", 0)), int(context.get("pending_gems", 0)), int(context.get("pending_flasks", 0)))
	return "待领：" + quantities if not quantities.is_empty() else ""

static func claim_reward_text(result: Dictionary, context: Dictionary) -> String:
	var message: String
	if bool(result.get("ok", false)):
		var quantities := _reward_quantities(int(result.get("claimed_shards", 0)), int(result.get("claimed_gems", 0)), int(result.get("claimed_flasks", 0)))
		message = "已领取：" + quantities if not quantities.is_empty() else "本次没有领取奖励"
	else:
		message = str(result.get("reason", "领取失败，请重试"))
	var pending := pending_reward_text(context)
	if not pending.is_empty(): message += "\n" + pending
	return message

func _result(result: Dictionary) -> void:
	feedback.emit(str(result.get("reason","操作完成")) if not result.get("ok",false) else "操作完成")

func cancel_pending() -> void:
	_cancel_gem_purchase()
	_reset_revision = -1
	_reset.hide()
	hide()
