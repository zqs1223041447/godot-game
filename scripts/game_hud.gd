class_name GameHUD
extends CanvasLayer
## Responsive, keyboard-friendly combat HUD and live build editor.

const MenuRoutes = preload("res://scripts/ui/menu_route_state.gd")
const PANEL_ROUTES: Dictionary = {"inventory":"inventory", "talents":"passive_tree", "skills":"skill_gems", "combat":"debug_build", "monsters":"debug_monsters", "pause":"pause", "settings":"settings"}
const TypedPreview = preload("res://scripts/combat/damage_preview.gd")
const PassivePanel = preload("res://scripts/passive_panel.gd")
const InventoryPanelView = preload("res://scripts/inventory_panel.gd")
const SkillSupportPanelView = preload("res://scripts/skill_support_panel.gd")
const EncounterChoices = preload("res://scripts/ui/encounter_controls.gd")
const Passives = preload("res://scripts/passive_data.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const Emblem = preload("res://scripts/visuals/skill_emblem.gd")
const Palette = preload("res://scripts/visuals/fantasy_palette.gd")

const INK: Color = Color("161a14")
const PANEL: Color = Color("f1deb3")
const PANEL_LIGHT: Color = Color("f8ecd0")
const BORDER: Color = Color("8c6b42")
const TEXT: Color = Color("3b281b")
const MUTED: Color = Color("69523a")
const CYAN: Color = Color("52623b")
const GOLD: Color = Color("79571f")
const RED: Color = Color("c67865")
const BLUE: Color = Color("839cb4")
const STAT_NAMES: Dictionary = {
	"max_health": "生命上限", "max_mana": "法力上限", "max_shield": "护盾上限",
	"shield": "护盾上限", "damage": "伤害", "damage_mult": "伤害倍率",
	"damage_multiplier": "伤害倍率", "move_speed": "移动速度", "speed": "移动速度",
	"mana_regen": "法力回复", "health_regen": "生命回复", "shield_regen": "护盾回复",
	"armor": "护甲", "crit_chance": "暴击几率", "crit_multiplier": "暴击伤害",
	"attack_speed": "攻击速度", "cooldown_reduction": "冷却缩减",
	"projectile_count": "额外母箭", "pickup_radius": "拾取范围",
	"global_increased": "全局伤害提高", "projectile_increased": "投射物伤害提高",
	"elemental_increased": "元素伤害提高", "area_increased": "范围伤害提高",
	"area_mult": "范围倍率", "area_multiplier": "范围倍率", "fire_resistance": "火焰抗性"
}

var _arena: Node
var _state: BuildState
var _root: Control
var _wave_label: Label
var _run_label: Label
var _level_label: Label
var _bars: Dictionary = {}
var _bar_values: Dictionary = {}
var _skill_buttons: Array[Button] = []
var _skill_view_token: PackedByteArray = PackedByteArray()
var _skill_views: Dictionary = {}
var _auto_button: Button
var _toast: PanelContainer
var _toast_label: Label
var _toast_left: float = 0.0
var _inventory_panel: Control
var _passive_panel: Control
var _skill_support_panel: Control
var _panel_margin: MarginContainer
var _panel_scroll: ScrollContainer
var _modal: Control
var _panel_title: Label
var _panel_subtitle: Label
var _panel_body: VBoxContainer
var _panel_footer: Label
var _menu_routes = MenuRoutes.new()
var _windows: Dictionary = {}
var _close_button: Button
var _active_panel: String = ""
var _selected_skill_slot: int = 0
# Selection follows a skill identity, never the array position that used to hold it.
var _selected_support_skill_id: String = ""
var _refresh_clock: float = 0.0
var _skill_emblems: Array[Control] = []
var _preferences: VisualSettings
var _encounter_dialog: ConfirmationDialog
var _encounter_request_pending: bool = false
var _encounter_request_ids: Array[String] = []
var _encounter_request_revision: int = -1


func setup(arena: Node) -> void:
	_arena = arena
	_state = arena.get("state") as BuildState
	_preferences = arena.get("visual_settings") as VisualSettings
	layer = 10
	_root = Control.new()
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_root.name = "HUDRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.theme = _make_theme()
	_build_status()
	_build_navigation()
	_build_vitals()
	_build_hotbar()
	_build_hint()
	_build_toast()
	_build_modal()
	_build_encounter_confirmation()
	_style_dark_hud()
	get_viewport().size_changed.connect(_apply_presentation)
	_apply_presentation()
	refresh_build()
	_update_live()


func _process(delta: float) -> void:
	if not is_instance_valid(_arena) or _root == null:
		return
	_refresh_clock += delta
	if _refresh_clock >= 0.05:
		_refresh_clock = 0.0
		_update_live()
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0


func is_blocking() -> bool:
	return _active_panel == "death" or bool(_menu_routes.current_state().paused)


func open_panel(panel_name: String) -> void:
	if _root == null or (_active_panel == "death" and panel_name != "death"):
		return
	if panel_name == "death":
		_show_window("death")
		return
	if not PANEL_ROUTES.has(panel_name):
		panel_name = "pause"
	_menu_routes.request_window(PANEL_ROUTES[panel_name])
	_show_window(panel_name)


func handle_menu_key(key: int, pressed: bool = true, echo: bool = false) -> bool:
	if key not in [KEY_I, KEY_B, KEY_T, KEY_K, KEY_F6, KEY_F7, KEY_ESCAPE]:
		return false
	if _active_panel == "death" or not bool(_arena.get("alive")):
		return true
	var transition: Dictionary = _menu_routes.handle_key(key, pressed, echo)
	if not transition.changed:
		return true
	if transition.window.is_empty():
		_hide_windows()
	else:
		for name: String in PANEL_ROUTES:
			if PANEL_ROUTES[name] == transition.window:
				_show_window(name)
				break
	return true


func close_panel() -> void:
	if _active_panel == "death" and not bool(_arena.get("alive")):
		return
	if not _menu_routes.current_state().window.is_empty():
		_menu_routes.handle_key(KEY_ESCAPE)
	_hide_windows()


func _hide_windows() -> void:
	_cancel_encounter_request()
	_active_panel = ""
	for view: Dictionary in _windows.values():
		view.root.hide()


func _show_window(panel_name: String) -> void:
	if not _windows.has(panel_name):
		return
	_hide_windows()
	_active_panel = panel_name
	var view: Dictionary = _windows[panel_name]
	_modal = view.root
	_panel_margin = view.margin
	_panel_scroll = view.scroll
	_panel_title = view.title
	_panel_subtitle = view.subtitle
	_panel_body = view.body
	_panel_footer = view.footer
	_close_button = view.close_button
	_modal.show()
	_rebuild_panel()


func notify(message: String) -> void:
	if _toast_label == null:
		return
	if is_blocking():
		if _state != null and not _state.save_block_reason().is_empty():
			_panel_footer.text = "原存档已保护，本次进度未写入；请先备份并恢复有效存档"
			_panel_footer.tooltip_text = _state.save_block_reason() + "\n" + message
			_panel_footer.add_theme_color_override("font_color", GOLD)
			return
		_panel_footer.text = message
		_panel_footer.add_theme_color_override("font_color", CYAN)
		return
	_toast_label.text = message
	_toast_left = 3.5
	_toast.show()


func show_death() -> void:
	open_panel("death")


func refresh_build() -> void:
	if _root == null or _state == null:
		return
	_update_live()
	if _active_panel == "talents" and is_instance_valid(_passive_panel):
		_passive_panel.refresh()
	elif _active_panel == "inventory" and is_instance_valid(_inventory_panel):
		_inventory_panel.refresh()
	elif _active_panel == "skills":
		var scroll_position: int = _panel_scroll.scroll_vertical
		_rebuild_panel()
		_panel_scroll.set_deferred("scroll_vertical", scroll_position)
	elif not _active_panel.is_empty():
		_rebuild_panel()


func _make_theme() -> Theme:
	return PresentationTheme.create_theme()


func _style(bg: Color, line: Color, radius: int = 8, border: int = 1) -> StyleBox:
	return PresentationTheme.panel(bg, line, mini(radius, 7), border, 12)


func _label(text: String, font_size: int = 17, color: Color = TEXT) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PresentationTheme.ink(color))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _wrap_label(text: String, font_size: int = 16, color: Color = MUTED) -> Label:
	var result: Label = _label(text, font_size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


func _button(text: String, stable_name: String, callback: Callable, width: float = 0.0) -> Button:
	var result: Button = Button.new()
	result.name = stable_name
	result.text = text
	result.custom_minimum_size = Vector2(width, 40.0)
	result.focus_mode = Control.FOCUS_ALL
	if callback.is_valid():
		result.pressed.connect(callback)
	return result


func _accent_button(button: Button, accent: Color = CYAN) -> void:
	button.add_theme_color_override("font_color", Color("f8ecd0"))
	button.add_theme_color_override("font_hover_color", Color("f8ecd0"))
	button.add_theme_stylebox_override("normal", PresentationTheme.bookmark(true))
	button.add_theme_stylebox_override("hover", PresentationTheme.bookmark(true))


func _place(control: Control, rect: Rect2, preset: int = Control.PRESET_TOP_LEFT) -> void:
	_root.add_child(control)
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _build_status() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "RunStatus"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color("38261d"), BORDER, 10, 1))
	_place(panel, Rect2(20, 18, 294, 88))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var brand: HBoxContainer = HBoxContainer.new()
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(brand)
	brand.add_child(_label("◈  裂隙试炼", 23, CYAN))
	var edition: Label = _label("灰烬庭院", 12, MUTED)
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edition.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.add_child(edition)
	_wave_label = _label("第 1 波  ·  击败 0", 16, TEXT)
	_wave_label.name = "WaveLabel"
	box.add_child(_wave_label)
	_run_label = _label("00:00   /   战斗进行中", 13, MUTED)
	_run_label.name = "RunTimeLabel"
	box.add_child(_run_label)


func _build_navigation() -> void:
	var nav: HBoxContainer = HBoxContainer.new()
	nav.name = "Navigation"
	nav.add_theme_constant_override("separation", 7)
	_place(nav, Rect2(-506, 20, 486, 42), Control.PRESET_TOP_RIGHT)
	nav.add_child(_button("I  装备背包", "InventoryButton", open_panel.bind("inventory"), 133))
	nav.add_child(_button("T  天赋", "TalentsButton", open_panel.bind("talents"), 104))
	nav.add_child(_button("K  技能", "SkillsButton", open_panel.bind("skills"), 104))
	nav.add_child(_button("Esc  暂停", "PauseButton", open_panel.bind("pause"), 112))


func _build_vitals() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "PlayerVitals"
	panel.add_theme_stylebox_override("panel", _style(Color("38261d"), BORDER, 8, 1))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(panel, Rect2(20, -154, 280, 134), Control.PRESET_BOTTOM_LEFT)
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	_level_label = _label("Lv.1  /  成长进度", 14, GOLD)
	_level_label.name = "LevelLabel"
	box.add_child(_level_label)
	_add_vital(box, "health", "生命", RED)
	_add_vital(box, "mana", "法力", BLUE)
	_add_vital(box, "shield", "护盾", CYAN)


func _add_vital(parent: VBoxContainer, key: String, caption: String, color: Color) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	row.add_child(_label(caption, 14, color))
	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(180, 23)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	var bar: ProgressBar = ProgressBar.new()
	bar.name = key.capitalize() + "Bar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_PASS if key == "health" else Control.MOUSE_FILTER_IGNORE
	var fill: StyleBox = _style(color.darkened(0.17), color, 4, 0)
	bar.add_theme_stylebox_override("fill", fill)
	holder.add_child(bar)
	var value: Label = _label("0 / 0", 13, Color.WHITE)
	value.name = key.capitalize() + "Value"
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_shadow_color", Color("07101b"))
	value.add_theme_constant_override("shadow_offset_x", 1)
	value.add_theme_constant_override("shadow_offset_y", 1)
	holder.add_child(value)
	_bars[key] = bar
	_bar_values[key] = value


func _build_hotbar() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Hotbar"
	panel.add_theme_stylebox_override("panel", _style(Color("38261d"), BORDER, 8, 1))
	_place(panel, Rect2(-270, -145, 540, 125), Control.PRESET_CENTER_BOTTOM)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)
	var caption: Label = _label("主动技能", 12, MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(caption)
	header.add_child(_label("1 – 5  释放  ·  K  调整组合", 12, MUTED))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	box.add_child(row)
	for index: int in range(5):
		var button: Button = _button("", "SkillButton%d" % (index + 1), _cast_skill.bind(index), 94)
		button.custom_minimum_size.y = 84
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		for style_name: String in ["normal", "hover", "pressed", "disabled"]:
			var frame: StyleBox = _root.theme.get_stylebox(style_name,"Button").duplicate()
			frame.content_margin_top = 43
			frame.content_margin_bottom = 5
			frame.content_margin_left = 5
			frame.content_margin_right = 5
			button.add_theme_stylebox_override(style_name,frame)
		row.add_child(button)
		var emblem := Emblem.new()
		emblem.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		emblem.position = Vector2(-21,3)
		emblem.size = Vector2(42,42)
		button.add_child(emblem)
		_skill_emblems.append(emblem)
		var key_label := _label(str(index+1),11,GOLD)
		key_label.position = Vector2(8,6)
		button.add_child(key_label)
		_skill_buttons.append(button)


func _build_hint() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "CombatHelp"
	box.add_theme_constant_override("separation", 7)
	_place(box, Rect2(-250, -114, 230, 94), Control.PRESET_BOTTOM_RIGHT)
	_auto_button = _button("自动攻击  开启", "AutoFireButton", _toggle_auto)
	_auto_button.add_theme_font_size_override("font_size", 14)
	box.add_child(_auto_button)
	var move_hint: Label = _label("WASD 移动  ·  空格 闪避", 12, MUTED)
	move_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(move_hint)
	var aim_hint: Label = _label("Q 自动  /  F6 战斗  /  F7 怪物", 12, MUTED)
	aim_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(aim_hint)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "NotificationToast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", _style(Color("f1deb3"), CYAN.darkened(0.5), 8, 1))
	_place(_toast, Rect2(-310, 132, 620, 49), Control.PRESET_CENTER_TOP)
	_toast_label = _label("", 17, CYAN)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_child(_toast_label)
	_toast.hide()


func _build_modal() -> void:
	for panel_name: String in ["inventory", "talents", "skills", "combat", "monsters", "pause", "settings", "death"]:
		_build_window(panel_name)


func _build_window(panel_name: String) -> void:
	_modal = Control.new()
	_modal.name = str(PANEL_ROUTES.get(panel_name, "death")).to_pascal_case() + "Window"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal)
	var shade: ColorRect = ColorRect.new()
	shade.name = "ModalShade"
	shade.color = Color(0.15, 0.10, 0.065, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	_panel_margin = margin
	margin.name = "PanelMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 68)
	margin.add_theme_constant_override("margin_bottom", 68)
	_modal.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "BuildPanel"
	var style: StyleBox = _style(PANEL, BORDER.lightened(0.12), 16, 1)
	style.book_cover = true
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	var header: HBoxContainer = HBoxContainer.new()
	layout.add_child(header)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	_panel_title = _label("构筑", 28, TEXT)
	_panel_title.name = "PanelTitle"
	titles.add_child(_panel_title)
	_panel_subtitle = _wrap_label("战斗已暂停", 14, MUTED)
	titles.add_child(_panel_subtitle)
	_close_button = _button("关闭  Esc", "ClosePanelButton", close_panel, 114)
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_close_button)
	var scroll: ScrollContainer = ScrollContainer.new()
	_panel_scroll = scroll
	scroll.name = "PanelScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.name = "PanelBody"
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_panel_body)
	_panel_footer = _wrap_label("构筑变更会自动保存  ·  关闭面板继续战斗", 13, MUTED)
	layout.add_child(_panel_footer)
	_windows[panel_name] = {"root":_modal, "margin":_panel_margin, "scroll":_panel_scroll,
		"title":_panel_title, "subtitle":_panel_subtitle, "body":_panel_body,
		"footer":_panel_footer, "close_button":_close_button}
	_modal.hide()


func _skill_view(id: String) -> Dictionary:
	if _skill_views.has(id):
		return _skill_views[id]
	var skill: Dictionary = GameData.SKILLS.get(id, {})
	var cast: Dictionary = _state.get_skill_cast(id)
	var valid: bool = bool(cast.get("ok", false))
	var cost: float = float(cast.get("mana", 0.0))
	var tooltip: String = "%s\n基础技能：%s\n当前消耗 %.2f 法力 · 冷却 %.2f 秒" % [str(skill.get("name", id)), str(skill.get("description", "")), cost, float(cast.get("cooldown", 0.0))]
	if int(cast.get("initial_count", 0)) > 0:
		tooltip += "\n当前初始投射物：%d 枚" % int(cast.initial_count)
	if valid:
		tooltip += "\n" + TypedPreview.summary(cast) + "\n" + TypedPreview.details(cast)
	else:
		tooltip = "%s\n无法施放：%s" % [str(skill.get("name", id)), str(cast.get("error", "技能编译失败"))]
	var result: Dictionary = {"ok": valid, "mana": cost, "tooltip": tooltip}
	_skill_views[id] = result
	return result


func _update_live() -> void:
	if _state == null:
		return
	var stats: Dictionary = _arena.call("get_stats") as Dictionary
	var seconds: int = int(float(_arena.get("elapsed")))
	_wave_label.text = "第 %d 波 · 击败 %d · 场上 %d" % [int(_arena.get("wave")), int(_arena.get("kills")), _arena.enemies.size()]
	_run_label.text = "%02d:%02d   /   %s" % [seconds / 60, seconds % 60, "试验场 · 无奖励" if bool(_arena.get("demo_mode")) else ("战斗已暂停" if is_blocking() else "战斗进行中")]
	if not bool(_arena.get("demo_mode")) and not _arena.encounter_selection().is_empty():
		_run_label.text = "%02d:%02d   /   %s" % [seconds / 60, seconds % 60,"挑战已暂停" if is_blocking() else "挑战进行中"]
	_run_label.tooltip_text = "本轮：%s\n无额外奖励；不随构筑存档保存" % _arena.encounter_summary()
	_run_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_level_label.text = "Lv.%d  ·  经验 %d  ·  天赋点 %d" % [_state.level, _state.xp, _state.talent_points]
	_set_vital("health", float(_arena.get("health")), float(stats.get("max_health", 100.0)))
	_set_vital("mana", float(_arena.get("mana")), float(stats.get("max_mana", 100.0)))
	_set_vital("shield", float(_arena.get("shield")), float(stats.get("max_shield", stats.get("shield", 0.0))))
	var defense: Dictionary = _arena.call("player_defense_profile")
	_bars.health.tooltip_text = "火抗 %.0f%%（合计 %.0f%%）\n火焰分量减伤后，先消耗护盾，再消耗生命。详细规则见离线图鉴。" % [float(defense.effective_resistances.fire) * 100.0, float(defense.raw_resistances.fire) * 100.0]
	var token: PackedByteArray = _state.get_build_view_token()
	if token != _skill_view_token:
		_skill_view_token = token
		_skill_views.clear()
	var cooldowns: Dictionary = _arena.get("cooldowns") as Dictionary
	for index: int in range(_skill_buttons.size()):
		var button: Button = _skill_buttons[index]
		if index >= _state.skill_slots.size():
			button.text = "%d\n空技能槽" % (index + 1)
			button.disabled = true
			continue
		var id: String = _state.skill_slots[index]
		var skill: Dictionary = GameData.SKILLS.get(id, {}) as Dictionary
		var view: Dictionary = _skill_view(id)
		var valid_cast: bool = bool(view.ok)
		var mana_cost: float = float(view.mana)
		var cooldown: float = float(cooldowns.get(id, 0.0))
		var ready: String = "就绪" if cooldown <= 0.0 else "%.1fs" % cooldown
		if cooldown <= 0.0 and float(_arena.get("mana")) < mana_cost:
			ready = "法力不足"
		button.text = "%s\n%s" % [str(skill.get("short_name", skill.get("name", id))), ready]
		button.tooltip_text = str(view.tooltip)
		if not valid_cast:
			button.text = "%s\n配置无效" % str(skill.get("name", id))

		var tint: Color = Palette.skill(id,skill.get("color", CYAN) as Color)
		var emblem: Control = _skill_emblems[index]
		emblem.skill_id = id
		emblem.accent = tint
		emblem.subdued = cooldown > 0.0
		emblem.queue_redraw()
		button.add_theme_color_override("font_color", PresentationTheme.ink(tint) if cooldown <= 0.0 else MUTED)
		button.disabled = not valid_cast or not bool(_arena.get("alive")) or is_blocking()
	_auto_button.text = "自动攻击  %s" % ("开启  ●" if bool(_arena.get("auto_fire")) else "关闭  ○")
	_auto_button.add_theme_color_override("font_color", CYAN if bool(_arena.get("auto_fire")) else MUTED)
	_auto_button.disabled = is_blocking()


func _set_vital(key: String, value: float, maximum: float) -> void:
	var bar: ProgressBar = _bars[key] as ProgressBar
	bar.max_value = maxf(1.0, maximum)
	bar.value = value
	var caption: Label = _bar_values[key] as Label
	caption.text = "%d / %d" % [int(ceilf(value)), int(maximum)]


func _rebuild_panel() -> void:
	_cancel_encounter_request()
	for child: Node in _panel_body.get_children():
		if child == _passive_panel or child == _inventory_panel or child == _skill_support_panel:
			(child as Control).hide()
			continue
		_panel_body.remove_child(child)
		child.queue_free()
	var is_tree: bool = _active_panel in ["talents", "inventory"]
	_panel_margin.add_theme_constant_override("margin_left", 16 if is_tree else 64)
	_panel_margin.add_theme_constant_override("margin_right", 16 if is_tree else 64)
	_panel_margin.add_theme_constant_override("margin_top", 14 if is_tree else 36)
	_panel_margin.add_theme_constant_override("margin_bottom", 14 if is_tree else 36)
	_panel_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel_scroll.scroll_vertical = 0
	_close_button.visible = _active_panel != "death"
	_panel_subtitle.text = "战斗已暂停  /  调整构筑后随时继续"
	_panel_footer.text = "构筑变更会自动保存  ·  关闭面板继续战斗"
	_panel_footer.add_theme_color_override("font_color", MUTED)
	match _active_panel:
		"inventory":
			_build_inventory_panel()
		"talents":
			_build_talents_panel()
		"skills":
			_build_skills_panel()
		"combat":
			_build_combat_panel()
		"monsters":
			_build_monsters_panel()
		"settings":
			_build_settings_panel()
		"pause":
			_build_pause_panel()
		"death":
			_build_death_panel()
	if not _state.save_block_reason().is_empty():
		_panel_footer.text = "原存档已保护，本次进度未写入；请先备份并恢复有效存档"
		_panel_footer.tooltip_text = _state.save_block_reason()
		_panel_footer.add_theme_color_override("font_color", GOLD)
	else:
		_panel_footer.tooltip_text = ""
	PresentationTheme.apply_font_scale(_root, _preferences.font_scale)


func _section(title: String, caption: String = "") -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_panel_body.add_child(row)
	row.add_child(_label(title, 18, GOLD))
	if not caption.is_empty():
		var hint: Label = _label(caption, 13, MUTED)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(hint)


func _card(parent: Node, title: String, description: String, accent: Color = CYAN) -> HBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL_LIGHT, BORDER, 9, 1))
	parent.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 3)
	row.add_child(copy)
	copy.add_child(_wrap_label(title, 18, accent))
	if not description.is_empty():
		copy.add_child(_wrap_label(description, 14, MUTED))
	return row


func _slot_name(slot: String) -> String:
	match slot:
		"weapon": return "武器"
		"armor": return "护甲"
		"accessory", "relic", "charm": return "饰品"
		_: return slot


func _build_inventory_panel() -> void:
	_panel_title.text = "行囊 · 装备"
	_panel_subtitle.text = "整理格子，搭配装备  /  珠宝与装备共用背包"
	if not is_instance_valid(_inventory_panel):
		_inventory_panel = InventoryPanelView.new()
		_inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_inventory_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel_body.add_child(_inventory_panel)
		_inventory_panel.setup(_state)
		_inventory_panel.feedback.connect(notify)
		_inventory_panel.open_passives_requested.connect(_open_passives_from_inventory)
	_inventory_panel.show()
	_inventory_panel.refresh()
	_panel_footer.text = "拖动摆放物品 · 装备拖入对应槽位 · 珠宝在天赋星图镶嵌 · 一键整理不改变已装备物品"


func _open_passives_from_inventory() -> void:
	var key: String = str(_inventory_panel.get("selected_item_key"))
	open_panel("talents")
	if key.begins_with("jewel:") and is_instance_valid(_passive_panel):
		var selected: String = str(_passive_panel.get("selected_node_id"))
		if str(Passives.get_nodes().get(selected, {}).get("type", "")) != "socket":
			for node_id: String in _state.allocated_nodes:
				if Passives.get_nodes()[node_id]["type"] == "socket":
					_passive_panel.select_node(node_id)
					break
		_passive_panel.select_jewel(key.trim_prefix("jewel:"))


func _build_talents_panel() -> void:
	_panel_title.text = "天赋星图 · 珠宝"
	_panel_subtitle.text = "分配天赋 · 镶嵌珠宝 · 查看覆盖"
	if not is_instance_valid(_passive_panel):
		_passive_panel = PassivePanel.new()
		_passive_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_passive_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel_body.add_child(_passive_panel)
		_passive_panel.setup(_state)
		_passive_panel.feedback.connect(notify)
	_passive_panel.show()
	_passive_panel.refresh()
	_panel_footer.text = "每点消耗 1 天赋点 · 普通珠宝每20有效击杀 · 寻枝晶玉来自首领 · F8 离线图鉴"


func _build_skills_panel() -> void:
	_panel_title.text = "技能组合 · 辅助"
	_panel_subtitle.text = "每个技能独立保存两个辅助槽 / 可用技能依辅助而定"
	if _selected_support_skill_id.is_empty() and _selected_skill_slot < _state.skill_slots.size():
		_selected_support_skill_id = _state.skill_slots[_selected_skill_slot]
	var selected_position: int = _state.skill_slots.find(_selected_support_skill_id)
	if selected_position >= 0:
		_selected_skill_slot = selected_position
	_panel_body.add_child(_button("F6 战斗机制：查看龙卷组合、分类增伤和事件记录", "OpenCombatInspector", open_panel.bind("combat")))
	_section("先选择要替换的技能槽", "已装配的技能会互换位置，不会重复占槽")
	var slots: HBoxContainer = HBoxContainer.new()
	slots.name = "SkillSlotSelector"
	_panel_body.add_child(slots)
	for index: int in range(5):
		var id: String = _state.skill_slots[index] if index < _state.skill_slots.size() else ""
		var skill: Dictionary = GameData.SKILLS.get(id, {}) as Dictionary
		var button: Button = _button("%d  %s" % [index + 1, str(skill.get("short_name", skill.get("name", "空槽")))], "SlotButton%d" % (index + 1), _select_skill_slot.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = Emblem.ICONS.get(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 34)
		if index == _selected_skill_slot:
			_accent_button(button)
		slots.add_child(button)
	if not is_instance_valid(_skill_support_panel):
		_skill_support_panel = SkillSupportPanelView.new()
		_panel_body.add_child(_skill_support_panel)
		_skill_support_panel.setup(_state)
		_skill_support_panel.feedback.connect(notify)
	_panel_body.move_child(_skill_support_panel, _panel_body.get_child_count() - 1)
	_skill_support_panel.font_scale = _preferences.font_scale
	_skill_support_panel.select_skill(_selected_support_skill_id)
	_skill_support_panel.show()
	_section("可用技能", "当前目标：技能槽 %d" % (_selected_skill_slot + 1))
	for key: Variant in GameData.SKILLS.keys():
		var id: String = str(key)
		var skill: Dictionary = GameData.SKILLS[id] as Dictionary
		var assigned: int = _state.skill_slots.find(id)
		var status: String = "  ·  已在槽 %d" % (assigned + 1) if assigned >= 0 else ""
		var cast: Dictionary = _state.get_skill_cast(id)
		var description: String = "%.2f 法力  ·  %.2f 秒冷却%s\n基础技能：%s" % [float(cast.get("mana", 0.0)), float(cast.get("cooldown", 0.0)), status, str(skill.get("description", ""))]
		if not bool(cast.get("ok", false)):
			description = "配置无效：%s%s" % [str(cast.get("error", "技能编译失败")), status]
		var row: HBoxContainer = _card(_panel_body, str(skill.get("name", id)), description, skill.get("color", CYAN) as Color)
		var art := Emblem.new()
		art.skill_id = id
		art.custom_minimum_size = Vector2(64,64)
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(art)
		row.move_child(art,0)
		var select: Button = _button("当前技能" if assigned == _selected_skill_slot else "装入槽 %d" % (_selected_skill_slot + 1), "SelectSkill_" + id, _slot_skill.bind(id), 130)
		select.disabled = assigned == _selected_skill_slot
		select.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(select)


func _build_combat_panel() -> void:
	_panel_title.text = "战斗机制 · 龙卷实验"
	_panel_subtitle.text = "技能生成载体，装备改变生命周期，每次命中独立结算伤害"
	var preview: Dictionary = _arena.call("combat_preview")
	var snapshot: Dictionary = preview.snapshot
	var returning: bool = snapshot.effects.has("return_on_range")
	var exploding: bool = snapshot.effects.has("explode_on_flight_end")
	_section("01  组合与生命周期", "原型规则 · 施放时锁定构筑")
	var row: HBoxContainer = _card(_panel_body, "%d 母箭 → 每枚 3 子箭 → %s → %s" % [int(preview.count), "返回" if returning else "射程结束", "火焰爆炸" if exploding else "消失"],
		"母箭飞行 150 距离后分裂；子箭飞行 150 距离后判断返回。
返回时取人物此刻中心方向，穿过中心继续直飞；子箭总寿命 1.7 秒，返回不刷新。
寿命与射程同时到达：寿命优先。分裂、碰撞消耗、死亡或重置不爆炸。", Color("426035"))
	row.add_child(_button("试装完整组合", "EquipTornadoExample", _arena.equip_tornado_example, 160))
	var toggles := HBoxContainer.new()
	_panel_body.add_child(toggles)
	toggles.add_child(_button("返回：%s" % ("已装备" if returning else "未装备"), "ToggleReturnEffect", _toggle_combat_item.bind("return_mantle"), 200))
	toggles.add_child(_button("爆炸：%s" % ("已装备" if exploding else "未装备"), "ToggleExplosionEffect", _toggle_combat_item.bind("detonation_charm"), 200))
	toggles.add_child(_button("母箭数量：%d" % int(preview.count), "ToggleProjectileCount", _toggle_combat_item.bind("prism_bow"), 200))
	_panel_body.add_child(_wrap_label("按钮实际穿戴或卸下对应装备，并自动保存。仅爆炸：射程处爆炸；仅返回：返回后寿命结束消失；两者都有：返回后寿命结束爆炸。", 14))
	_section("02  当前构筑的逐分量伤害", "未计敌人抗性 · 非每秒伤害")
	_panel_body.add_child(_wrap_label("通用基础伤害 %.1f；全局提高 %.0f%%，投射物提高 %.0f%%，元素提高 %.0f%%。同一分量适用的“提高”先相加。" % [float(snapshot.base_damage), float(_state.get_stats().global_increased) * 100.0, float(_state.get_stats().projectile_increased) * 100.0, float(_state.get_stats().elemental_increased) * 100.0], 15, TEXT))
	for role: String in ["parent", "child", "explosion"]:
		var result: Dictionary = preview[role]
		var title: String = {"parent": "母箭：攻击 / 投射物击中", "child": "子箭：攻击 / 投射物击中", "explosion": "爆炸：次级 / 范围击中（不属于投射物伤害）"}[role]
		var details: PackedStringArray = []
		var packet_role: String = "secondary" if role == "explosion" else role
		var packet: Dictionary = preview.get("packets", {}).get(packet_role, {})
		if not packet.is_empty():
			details.append(TypedPreview.assembly_line(packet))
		for part: Dictionary in result.details:
			var type_name: String = {"physical": "物理", "fire": "火焰", "cold": "冰冷", "lightning": "闪电", "chaos": "混沌"}.get(part.type, part.type)
			details.append("%s %.2f × (1 + %.0f%%) × %.2f = %.2f" % [type_name, float(part.base), float(part.increased) * 100.0, float(part.more), float(part.final)])
		_card(_panel_body, "%s · 合计 %.2f%s" % [title, float(result.total), "（未装备爆炸，仅显示配方）" if role == "explosion" and not exploding else ""], "\n".join(details), GOLD if role == "explosion" else CYAN)
	_section("03  本轮真实事件", "母箭绿 · 子箭青 · 返回紫 · 爆炸橙")
	var counts: Dictionary = _arena.get("event_counts")
	_panel_body.add_child(_wrap_label("分裂 %d 次 · 返回 %d 次 · 爆炸 %d 次 · 投射物碰撞 %d 次" % [int(counts.get("split", 0)), int(counts.get("return_started", 0)), int(counts.get("explosion", 0)), int(counts.get("hit", 0))], 15, TEXT))
	var records: Array = _arena.get("damage_trace")
	if records.is_empty():
		_panel_body.add_child(_wrap_label("尚无伤害记录。试装完整组合，关闭面板后按 1 释放，再按 F6 查看实际命中。", 15))
	else:
		for index: int in range(maxi(0, records.size() - 5), records.size()):
			var record: Dictionary = records[index]
			var parts: PackedStringArray = []
			for type: String in record.components:
				parts.append("%s %.2f" % [type, float(record.components[type])])
			var damage_label: Label = _wrap_label("施放 #%d / 敌人 #%d · %s · 减伤后 %.2f（%s）" % [int(record.cast_id), int(record.target_id), "爆炸" if record.tags.has("explosion") else "返回命中" if record.phase == "returning" else "去程或直接命中", float(record.total), " + ".join(parts)], 14, GOLD if record.tags.has("explosion") else CYAN)
			damage_label.tooltip_text = "敌方防御前：%s\n敌方防御后：%s\n护盾消耗 %.2f · 生命损失 %.2f；逐次命中，非每秒伤害。" % [TypedPreview.points(record.get("before_defense_components", {})), TypedPreview.points(record.components), float(record.get("shield_spent", 0.0)), float(record.get("health_lost", 0.0))]
			damage_label.mouse_filter = Control.MOUSE_FILTER_PASS
			_panel_body.add_child(damage_label)
	var trace: Array = _arena.get("combat_trace")
	var lines: PackedStringArray = []
	var names: Dictionary = {"split": "分裂", "spawned": "子箭生成", "range_reached": "抵达射程", "return_started": "开始返回", "lifetime_expired": "寿命耗尽", "flight_ended": "自然飞行结束", "explosion": "爆炸", "terminated": "已终止", "hit": "碰撞命中", "spawn_rejected": "容量取消"}
	for index: int in range(maxi(0, trace.size() - 12), trace.size()):
		var event: Dictionary = trace[index]
		lines.append("施放 #%d · 箭 #%d ← 母箭 #%d · %.3f 秒 · %s" % [int(event.cast_id), int(event.projectile_id), int(event.parent_id), float(event.age), names.get(event.type, event.type)])
	if not lines.is_empty():
		_panel_body.add_child(_wrap_label("\n".join(lines), 13))
	_panel_footer.text = "F6 随时查看 · 命中按每枚箭每阶段每敌人一次 · 不同子箭与不同爆炸可分别命中 · 记录保留最近事件"


func _toggle_combat_item(id: String) -> void:
	var slot: String = str(GameData.ITEMS[id].slot)
	if _state.equipped.get(slot, "") == id:
		_state.unequip(slot)
	else:
		_state.equip(id)


func _build_monsters_panel() -> void:
	_panel_title.text = "怪物 · 共享天赋与死亡分裂"
	_panel_subtitle.text = "同一机制注册表驱动人物与怪物  /  F7 打开  /  战斗已暂停"
	var catalog = preload("res://scripts/monsters/monster_catalog.gd")
	var runtime = _arena.get("monster_runtime")
	var controls := HBoxContainer.new()
	_panel_body.add_child(controls)
	controls.add_child(_button("进入 / 重置试验场", "StartMonsterDemo", _arena.start_monster_demo, 230))
	controls.add_child(_button("演示 A → 2A + B", "TriggerMonsterSplit", _arena.trigger_demo_split, 230))
	controls.add_child(_button("恢复常规挑战", "RestoreStandardRun", _arena.restore_standard_run, 200))
	_panel_body.add_child(_button("100 怪视距试验", "StartDensityDemo", _arena.start_density_demo, 230))
	_panel_body.add_child(_wrap_label("试验场没有经验、补给或珠宝奖励；会重开当前战斗，保留人物构筑。关闭面板后按原有方式战斗。", 14, GOLD))
	_panel_body.add_child(_wrap_label("百怪试验生成 100 只真实怪物；常规挑战也使用 100 只上限与每批 2～5 只的渐进密度。视野面积扩大至原来的 2.37 倍，人物、怪物的真实碰撞与伤害不变。", 14))
	_section("五类怪物", "黑色仅预留，不能生成")
	var rarities := HBoxContainer.new()
	_panel_body.add_child(rarities)
	for id: String in catalog.RARITIES:
		var tier: Dictionary = catalog.RARITIES[id]
		var label: Label = _label(tier.name, 17, Color(tier.color).lightened(0.35) if id == "reserved" else tier.color)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rarities.add_child(label)
	var encounter: Dictionary = catalog.fire_encounter_policy()
	var encounter_note: Label = _wrap_label("第 %d 波起，每 %d 个自然入场名额包含一只灰烬守卫；击败原始守卫可获稀有灰烬皮甲。" % [int(encounter.minimum_wave), int(encounter.ordinary_admission_interval)], 14)
	encounter_note.tooltip_text = "本游戏可调平衡。满场、等待中的死亡生成不占自然入场计数；第1波初始怪计入，重开重置。试验怪与子怪无奖励。接触伤害组成与当前火抗见下方快照，完整机制见离线图鉴。其他普通怪仍使用白/蓝/金随机池；每五波出现橙色首领。"
	encounter_note.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_body.add_child(encounter_note)
	_section("生成规则", "队列 %d / 64 · 谱系 %d" % [runtime.queue.size(), runtime.roots.size()])
	_panel_body.add_child(_wrap_label("裂殖巡游体 → 2 普通巡游体 + 1 掠行体；孵化重壳体 → 2 裂殖巡游体 → 6 普通小怪。子怪不继承母体机制，按显式目标模板生成；只有原始怪发奖励。", 14))
	_panel_body.add_child(_wrap_label("模板图拒绝环；一次死亡只触发一次；每根最多 3 代 / 12 后代 / 每次 6 只。场上满 %d 只时排队，队列或谱系预算不足则整组取消。" % _arena.MAX_ENEMIES, 14))
	_section("当前怪物机制快照", "形状表示物种，外环与名称表示稀有度")
	var shown: int = 0
	for enemy: Dictionary in _arena.get("enemies"):
		if float(enemy.health) <= 0.0 or shown >= 8:
			continue
		shown += 1
		var tier: Dictionary = catalog.RARITIES[enemy.get("rarity", "normal")]
		var detail: String = "%s · %s · 第 %d 代 · %s\n生命 %.0f / %.0f · 护盾 %.0f / %.0f · 伤害 %.1f · 攻速 %.2f / 秒 · 移速 %.1f" % [enemy.name, tier.name, int(enemy.generation), catalog.mechanism_text(enemy), float(enemy.health), float(enemy.max_health), float(enemy.shield), float(enemy.max_shield), float(enemy.damage), float(enemy.attack_speed), float(enemy.speed)]
		_panel_body.add_child(_wrap_label(detail, 14, tier.color))
	_section("最近死亡生成记录", "重新打开面板刷新")
	if runtime.trace.is_empty():
		_panel_body.add_child(_wrap_label("尚无记录。进入试验场后点击演示按钮，或在战斗中击败带三点外标记的分裂怪。", 14))
	else:
		for event: Dictionary in runtime.trace.slice(maxi(0, runtime.trace.size() - 8)):
			var line: String = ""
			match str(event.type):
				"queued": line = "死亡 #%d：第 %d 代 %d 只子怪已入队" % [event.parent_id, event.generation, event.count]
				"spawned": line = "生成 %s · 第 %d 代 · 无额外奖励" % [event.template, event.generation]
				"rejected": line = "整组取消：%s" % event.reason
				"cancelled": line = "队列取消：%s" % event.reason
			_panel_body.add_child(_wrap_label(line, 14, CYAN))


func _build_pause_panel() -> void:
	_panel_title.text = "暂停一下"
	_panel_subtitle.text = "调整节奏，准备下一轮试炼"
	_section("操作指南")
	var row: HBoxContainer = _card(_panel_body, "移动 · 瞄准 · 释放", "WASD / 方向键：移动   ·   按住鼠标左键：瞄准射击   ·   空格：闪避（需装配冲刺）\n1 – 5：释放技能   ·   Q：切换自动攻击\nI / B：装备背包   ·   T：天赋   ·   K：技能   ·   Esc：关闭面板 / 暂停")
	row.name = "ControlsGuide"
	_card(_panel_body, "你的构筑，由你决定", "装备、天赋、珠宝与五个主动技能可以随时自由组合。\n升级获得天赋点；每 20 次有效原始怪击杀获得随机珠宝。原始首领另授予寻枝晶玉；T 分配与镶嵌，F8 查看完整图鉴。重试保留构筑。", GOLD)
	var actions: HBoxContainer = HBoxContainer.new()
	_panel_body.add_child(actions)
	var resume: Button = _button("继续战斗", "ResumeButton", close_panel, 180)
	_accent_button(resume)
	actions.add_child(resume)
	actions.add_child(_button("显示设置", "VisualSettingsButton", open_panel.bind("settings"), 150))
	actions.add_child(_button("重新开始", "RestartButton", _restart, 150))
	actions.add_child(_button("退出（未保存）" if not _state.save_block_reason().is_empty() else "保存并退出", "ExitButton", _exit_game, 180))
	var reference_button: Button = _button("离线图鉴 F8", "ReferenceCatalogButton", _arena.open_reference_catalog, 180)
	reference_button.tooltip_text = "在浏览器查看装备、技能、珠宝与机制；保持战斗暂停"
	_panel_body.add_child(reference_button)
	var choices = EncounterChoices.new()
	choices.font_scale = _preferences.font_scale
	choices.show_run_contract()
	choices.set_context(_arena.encounter_selection())
	choices.encounter_requested.connect(_request_encounter)
	_panel_body.add_child(choices)
	_panel_footer.text = "游戏仅保存构筑进度；重新开始会重置本轮战斗"


func _build_encounter_confirmation() -> void:
	_encounter_dialog = ConfirmationDialog.new()
	_encounter_dialog.name = "EncounterConfirmation"
	_encounter_dialog.title = "确认重开本轮"
	_encounter_dialog.dialog_autowrap = true
	_encounter_dialog.cancel_button_text = "取消"
	_encounter_dialog.ok_button_text = "确认重开"
	var dialog_theme := Theme.new()
	dialog_theme.set_color("title_color","Window",Color("f8ecd0"))
	for style_name: String in ["embedded_border","embedded_unfocused_border"]:
		var frame: StyleBoxFlat = ThemeDB.get_default_theme().get_stylebox(style_name,"Window").duplicate() as StyleBoxFlat
		if frame != null:
			frame.bg_color = Color("60432f")
			frame.border_color = BORDER
			dialog_theme.set_stylebox(style_name,"Window",frame)
	_encounter_dialog.theme = dialog_theme
	_root.add_child(_encounter_dialog)
	_encounter_dialog.get_ok_button().add_theme_color_override("font_focus_color",TEXT)
	_encounter_dialog.get_cancel_button().add_theme_color_override("font_focus_color",TEXT)
	_encounter_dialog.confirmed.connect(_confirm_encounter)
	_encounter_dialog.canceled.connect(_cancel_encounter_request)


func _request_encounter(ids: Array[String]) -> void:
	if _active_panel != "pause" or _encounter_request_pending:
		return
	var compiled: Dictionary = _arena.EncounterCompiler.compile(ids)
	if not compiled.ok:
		notify(str(compiled.error))
		return
	_encounter_request_ids.assign(compiled.profile.modifier_ids)
	_encounter_request_revision = int(_arena.run_revision)
	_encounter_request_pending = true
	var names: PackedStringArray = []
	for entry: Dictionary in compiled.profile.definitions:
		names.append(str(entry.name))
	var summary: String = "、".join(names) if not names.is_empty() else "常规（无挑战）"
	_encounter_dialog.dialog_text = "本轮选择：%s\n\n确认后结束当前战斗，重置怪物、时间和本轮击败数。\n构筑、经验、装备与材料保留。\n挑战不增加奖励，不持久保存；普通重试保留本轮选择。" % summary
	_encounter_dialog.popup_centered(Vector2i(560,260))


func _cancel_encounter_request() -> void:
	_encounter_request_pending = false
	_encounter_request_ids.clear()
	_encounter_request_revision = -1
	if is_instance_valid(_encounter_dialog):
		_encounter_dialog.hide()


func _confirm_encounter() -> void:
	if not _encounter_request_pending:
		return
	var ids: Array[String] = _encounter_request_ids.duplicate()
	var revision: int = _encounter_request_revision
	_cancel_encounter_request()
	if not _arena.start_encounter(ids,revision):
		notify("本轮已变化，未重开；请重新确认选择")
		return
	notify("新一轮：%s · 无额外奖励" % _arena.encounter_summary())


func _build_death_panel() -> void:
	_panel_title.text = "试炼结束"
	_panel_subtitle.text = "这次倒下，是下一次构筑的起点"
	_panel_footer.text = "装备、天赋与技能组合已保留  ·  重新挑战，寻找更强的连招"
	var seconds: int = int(float(_arena.get("elapsed")))
	var summary: String = "坚持 %02d:%02d     ·     击败 %d     ·     到达第 %d 波" % [seconds / 60, seconds % 60, int(_arena.get("kills")), int(_arena.get("wave"))]
	_card(_panel_body, summary, "角色等级 %d  ·  可用天赋点 %d" % [_state.level, _state.talent_points], GOLD)
	_card(_panel_body, "再试一次，让组合更进一步", "重新开始会恢复生命与法力，重置敌人和战斗计时。\n装备、已分配天赋和技能栏保留；进入战斗后可随时打开面板调整。")
	var actions: HBoxContainer = HBoxContainer.new()
	_panel_body.add_child(actions)
	var retry: Button = _button("重新挑战", "RetryButton", _restart, 210)
	_accent_button(retry)
	actions.add_child(retry)
	actions.add_child(_button("保存并退出", "ExitButton", _exit_game, 180))


func _stats_text(stats: Dictionary, separator: String = "  ·  ") -> String:
	if stats.is_empty():
		return "无额外属性"
	var pieces: PackedStringArray = PackedStringArray()
	for key: Variant in stats.keys():
		var id: String = str(key)
		var value: float = float(stats[key])
		var shown: String
		if id.contains("mult") or id.ends_with("_increased") or id == "crit_chance" or id == "cooldown_reduction" or id == "fire_resistance":
			shown = String.num(value * 100.0, 2) + "%"
		elif is_equal_approx(value, roundf(value)):
			shown = "%d" % int(value)
		else:
			shown = String.num(value, 2)
		pieces.append("%s %s" % [str(STAT_NAMES.get(id, id)), shown])
	return separator.join(pieces)


func _cast_skill(index: int) -> void:
	if is_blocking():
		return
	_arena.call("cast_skill", index)


func _toggle_auto() -> void:
	_arena.call("toggle_auto_fire")
	_update_live()


func _equip_item(id: String) -> void:
	if _state.equip(id):
		notify("已装备：%s" % str((GameData.ITEMS[id] as Dictionary).get("name", id)))


func _unequip_item(slot: String) -> void:
	if _state.unequip(slot):
		notify("已卸下%s" % _slot_name(slot))


func _select_skill_slot(index: int) -> void:
	if index < 0 or index >= _state.skill_slots.size():
		return
	_selected_skill_slot = index
	_selected_support_skill_id = _state.skill_slots[index]
	_rebuild_panel()


func _slot_skill(id: String) -> void:
	var previous_selection: String = _selected_support_skill_id
	# The transaction emits changed synchronously; set the intended identity first.
	_selected_support_skill_id = id
	if _state.slot_skill(_selected_skill_slot, id):
		notify("技能槽 %d 已更新；辅助跟随技能保存" % (_selected_skill_slot + 1))
	else:
		_selected_support_skill_id = previous_selection


func _restart() -> void:
	if not _menu_routes.current_state().window.is_empty():
		_menu_routes.handle_key(KEY_ESCAPE)
	_hide_windows()
	_arena.call("restart_run")
	notify("新一轮试炼开始，构筑已保留")


func _exit_game() -> void:
	if bool(_arena.call("save_build")):
		get_tree().quit()
	else:
		notify("构筑保存失败，请检查存储权限后重试")


func _apply_presentation() -> void:
	if _root == null or _preferences == null:
		return
	# Canvas-items stretch handles physical pixels; UI zoom has its own transform.
	# Combat remains exactly 1280×720 regardless of either presentation preference.
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.scale = Vector2.ONE * _preferences.ui_scale
	_root.size = get_viewport().get_visible_rect().size / _preferences.ui_scale
	_root.theme.default_font_size = roundi(16 * _preferences.font_scale)
	if is_instance_valid(_skill_support_panel):
		_skill_support_panel.font_scale = _preferences.font_scale
	PresentationTheme.apply_font_scale(_root, _preferences.font_scale)
	var width: float = _root.size.x
	var vitals: Control = _root.get_node("PlayerVitals")
	vitals.offset_left = 16
	vitals.offset_right = 292 if width > 1200 else 264
	var hotbar: Control = _root.get_node("Hotbar")
	hotbar.offset_left = -260
	hotbar.offset_right = 260
	var help: Control = _root.get_node("CombatHelp")
	help.visible = width >= 1200
	# At large zoom the hints move to pause; primary controls keep full hit targets.

	if is_instance_valid(_arena):
		_arena.queue_redraw()


func _build_settings_panel() -> void:
	_panel_title.text = "显示与可读性"
	_panel_subtitle.text = "2K 清晰缩放  /  设置独立保存，不影响战斗与构筑"
	_section("界面尺寸")
	_setting_choice("界面缩放", "UI 缩放独立于世界坐标，改变后按钮和面板同步调整", "UIScaleOption", ["90% · 紧凑", "100% · 标准", "110% · 放大"], VisualSettings.UI_SCALES.find(_preferences.ui_scale), _set_ui_scale)
	_setting_choice("字体大小", "所有面板文字与伤害数字保持中文清晰显示", "FontScaleOption", ["100% · 标准", "110% · 大字", "120% · 特大"], VisualSettings.FONT_SCALES.find(_preferences.font_scale), _set_font_scale)
	_section("战斗可读性")
	_setting_choice("特效强度", "减少装饰粒子与辉光；攻击、范围边界与稀有度标记始终保留", "EffectsOption", ["低 · 清晰优先", "中 · 平衡", "高 · 完整"], _preferences.effects_level, _set_effects)
	var numbers := CheckButton.new()
	numbers.name = "DamageNumbersToggle"
	numbers.text = "显示伤害与回复数字"
	numbers.button_pressed = _preferences.damage_numbers
	numbers.toggled.connect(func(value: bool) -> void: _preferences.damage_numbers = value; _save_presentation())
	_panel_body.add_child(numbers)
	var motion := CheckButton.new()
	motion.name = "MotionToggle"
	motion.text = "角色装饰动画"
	motion.button_pressed = _preferences.motion
	motion.toggled.connect(func(value: bool) -> void: _preferences.motion = value; _save_presentation())
	_panel_body.add_child(motion)
	var actions := HBoxContainer.new()
	_panel_body.add_child(actions)
	actions.add_child(_button("恢复默认显示", "ResetVisualSettings", _reset_presentation, 180))
	actions.add_child(_button("返回暂停菜单", "BackToPause", open_panel.bind("pause"), 180))
	_panel_footer.text = "建议 2560 × 1440 使用标准界面与大字；低分辨率可选择紧凑界面"


func _setting_choice(title: String, description: String, stable_name: String, options: Array, selected: int, callback: Callable) -> void:
	var row := _card(_panel_body,title,description,GOLD)
	var select := OptionButton.new()
	select.name = stable_name
	select.custom_minimum_size = Vector2(170,42)
	select.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for option: String in options:
		select.add_item(option)
	select.selected = maxi(0,selected)
	select.item_selected.connect(callback)
	row.add_child(select)

func _set_ui_scale(index: int) -> void:
	_preferences.ui_scale = VisualSettings.UI_SCALES[index]
	_save_presentation()
func _set_font_scale(index: int) -> void:
	_preferences.font_scale = VisualSettings.FONT_SCALES[index]
	_save_presentation()
func _set_effects(index: int) -> void:
	_preferences.effects_level = index
	_save_presentation()
func _reset_presentation() -> void:
	_preferences.ui_scale = 1.0
	_preferences.font_scale = 1.0
	_preferences.effects_level = 2
	_preferences.damage_numbers = true
	_preferences.motion = true
	_save_presentation()
	_rebuild_panel()
func _save_presentation() -> void:
	_apply_presentation()
	var result: Error = _preferences.save_settings()
	_panel_footer.text = "显示设置已保存" if result == OK else "设置未能保存；本次运行仍会使用新设置"

func _style_dark_hud() -> void:
	for stable_name: String in ["RunStatus","PlayerVitals","Hotbar","CombatHelp"]:
		var surface: Node=_root.find_child(stable_name,true,false)
		if surface==null: continue
		for child: Node in surface.find_children("*","Label",true,false):
			var label := child as Label
			if label.get_parent() is Button: continue
			label.add_theme_color_override("font_color",Color("f8ecd0"))
			if stable_name=="CombatHelp":
				label.add_theme_color_override("font_shadow_color",Color("211b14"))
				label.add_theme_constant_override("shadow_offset_x",1)
				label.add_theme_constant_override("shadow_offset_y",1)
