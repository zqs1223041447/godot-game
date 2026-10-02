class_name GameHUD
extends CanvasLayer
## Responsive, keyboard-friendly combat HUD and live build editor.

const INK: Color = Color("0b1320")
const PANEL: Color = Color("111e2e")
const PANEL_LIGHT: Color = Color("192a3b")
const BORDER: Color = Color("304659")
const TEXT: Color = Color("e8f1f5")
const MUTED: Color = Color("9aafbd")
const CYAN: Color = Color("70e0dc")
const GOLD: Color = Color("f4ca78")
const RED: Color = Color("f27786")
const BLUE: Color = Color("729eea")
const STAT_NAMES: Dictionary = {
	"max_health": "生命上限", "max_mana": "法力上限", "max_shield": "护盾上限",
	"shield": "护盾上限", "damage": "伤害", "damage_mult": "伤害倍率",
	"damage_multiplier": "伤害倍率", "move_speed": "移动速度", "speed": "移动速度",
	"mana_regen": "法力回复", "health_regen": "生命回复", "shield_regen": "护盾回复",
	"armor": "护甲", "crit_chance": "暴击几率", "crit_multiplier": "暴击伤害",
	"attack_speed": "攻击速度", "cooldown_reduction": "冷却缩减",
	"projectile_count": "额外投射物", "pickup_radius": "拾取范围",
	"area_mult": "范围倍率", "area_multiplier": "范围倍率"
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
var _auto_button: Button
var _toast: PanelContainer
var _toast_label: Label
var _toast_left: float = 0.0
var _modal: Control
var _panel_title: Label
var _panel_subtitle: Label
var _panel_body: VBoxContainer
var _panel_footer: Label
var _panel_tabs: HBoxContainer
var _close_button: Button
var _active_panel: String = ""
var _selected_skill_slot: int = 0
var _refresh_clock: float = 0.0


func setup(arena: Node) -> void:
	_arena = arena
	_state = arena.get("state") as BuildState
	layer = 10
	_root = Control.new()
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
	return not _active_panel.is_empty()


func open_panel(panel_name: String) -> void:
	if _root == null:
		return
	if _active_panel == "death" and panel_name != "death":
		return
	if panel_name not in ["inventory", "talents", "skills", "pause", "death"]:
		panel_name = "pause"
	_active_panel = panel_name
	_modal.show()
	_rebuild_panel()


func close_panel() -> void:
	if _active_panel == "death" and not bool(_arena.get("alive")):
		return
	_active_panel = ""
	if _modal != null:
		_modal.hide()


func notify(message: String) -> void:
	if _toast_label == null:
		return
	if is_blocking():
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
	if not _active_panel.is_empty():
		_rebuild_panel()


func _make_theme() -> Theme:
	var result: Theme = Theme.new()
	result.default_font_size = 17
	if ResourceLoader.exists("res://assets/fonts/arena_sans.otf"):
		result.default_font = load("res://assets/fonts/arena_sans.otf") as Font
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", CYAN)
	result.set_color("font_disabled_color", "Button", Color("677d8e"))
	result.set_stylebox("normal", "Button", _style(PANEL_LIGHT, BORDER, 8, 1))
	result.set_stylebox("hover", "Button", _style(Color("263c50"), CYAN, 8, 1))
	result.set_stylebox("pressed", "Button", _style(Color("173f48"), CYAN, 8, 2))
	result.set_stylebox("disabled", "Button", _style(Color("111c29"), Color("233443"), 8, 1))
	result.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	result.set_constant("h_separation", "HBoxContainer", 10)
	result.set_constant("v_separation", "VBoxContainer", 10)
	result.set_stylebox("panel", "PanelContainer", _style(PANEL, BORDER, 12, 1))
	result.set_stylebox("background", "ProgressBar", _style(Color("101b29"), Color("273849"), 5, 1))
	return result


func _style(bg: Color, line: Color, radius: int = 8, border: int = 1) -> StyleBoxFlat:
	var result: StyleBoxFlat = StyleBoxFlat.new()
	result.bg_color = bg
	result.border_color = line
	result.set_border_width_all(border)
	result.set_corner_radius_all(radius)
	result.content_margin_left = 14.0
	result.content_margin_right = 14.0
	result.content_margin_top = 10.0
	result.content_margin_bottom = 10.0
	return result


func _label(text: String, font_size: int = 17, color: Color = TEXT) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
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
	result.focus_mode = Control.FOCUS_NONE
	if callback.is_valid():
		result.pressed.connect(callback)
	return result


func _accent_button(button: Button, accent: Color = CYAN) -> void:
	button.add_theme_color_override("font_color", accent)
	button.add_theme_stylebox_override("normal", _style(Color("18313d"), accent.darkened(0.4), 8, 1))


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
	panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.065, 0.105, 0.92), BORDER, 10, 1))
	_place(panel, Rect2(20, 18, 310, 97))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var brand: HBoxContainer = HBoxContainer.new()
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(brand)
	brand.add_child(_label("◈  裂隙试炼", 23, CYAN))
	var edition: Label = _label("构筑实验场", 12, MUTED)
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
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(panel, Rect2(20, -163, 310, 143), Control.PRESET_BOTTOM_LEFT)
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
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = _style(color.darkened(0.17), color, 4, 0)
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
	_place(panel, Rect2(-287, -133, 598, 113), Control.PRESET_CENTER_BOTTOM)
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
		var button: Button = _button("", "SkillButton%d" % (index + 1), _cast_skill.bind(index), 105)
		button.custom_minimum_size.y = 65
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		row.add_child(button)
		_skill_buttons.append(button)


func _build_hint() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "CombatHelp"
	box.add_theme_constant_override("separation", 7)
	_place(box, Rect2(-271, -116, 251, 96), Control.PRESET_BOTTOM_RIGHT)
	_auto_button = _button("自动攻击  开启", "AutoFireButton", _toggle_auto)
	_auto_button.add_theme_font_size_override("font_size", 14)
	box.add_child(_auto_button)
	var move_hint: Label = _label("WASD / 方向键  移动    空格  闪避", 13, MUTED)
	move_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(move_hint)
	var aim_hint: Label = _label("按住左键瞄准  ·  Q 切换自动攻击", 13, MUTED)
	aim_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(aim_hint)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "NotificationToast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", _style(Color("17313d"), CYAN.darkened(0.5), 8, 1))
	_place(_toast, Rect2(-310, 132, 620, 49), Control.PRESET_CENTER_TOP)
	_toast_label = _label("", 17, CYAN)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_child(_toast_label)
	_toast.hide()


func _build_modal() -> void:
	_modal = Control.new()
	_modal.name = "ModalOverlay"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal)
	var shade: ColorRect = ColorRect.new()
	shade.name = "ModalShade"
	shade.color = Color(0.018, 0.029, 0.045, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "PanelMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 68)
	margin.add_theme_constant_override("margin_bottom", 68)
	_modal.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "BuildPanel"
	var style: StyleBoxFlat = _style(PANEL, BORDER.lightened(0.12), 16, 1)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 22
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 13)
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
	_panel_subtitle = _label("战斗已暂停", 14, MUTED)
	titles.add_child(_panel_subtitle)
	_close_button = _button("关闭  Esc", "ClosePanelButton", close_panel, 114)
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_close_button)
	_panel_tabs = HBoxContainer.new()
	_panel_tabs.name = "BuildTabs"
	layout.add_child(_panel_tabs)
	_panel_tabs.add_child(_button("装备背包", "InventoryTab", open_panel.bind("inventory"), 140))
	_panel_tabs.add_child(_button("天赋成长", "TalentsTab", open_panel.bind("talents"), 140))
	_panel_tabs.add_child(_button("技能组合", "SkillsTab", open_panel.bind("skills"), 140))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "PanelScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.name = "PanelBody"
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_panel_body)
	_panel_footer = _label("构筑变更会自动保存  ·  关闭面板继续战斗", 13, MUTED)
	layout.add_child(_panel_footer)
	_modal.hide()


func _update_live() -> void:
	if _state == null:
		return
	var stats: Dictionary = _arena.call("get_stats") as Dictionary
	var seconds: int = int(float(_arena.get("elapsed")))
	_wave_label.text = "第 %d 波   ·   击败 %d" % [int(_arena.get("wave")), int(_arena.get("kills"))]
	_run_label.text = "%02d:%02d   /   %s" % [seconds / 60, seconds % 60, "战斗已暂停" if is_blocking() else "战斗进行中"]
	_level_label.text = "Lv.%d  ·  经验 %d  ·  天赋点 %d" % [_state.level, _state.xp, _state.talent_points]
	_set_vital("health", float(_arena.get("health")), float(stats.get("max_health", 100.0)))
	_set_vital("mana", float(_arena.get("mana")), float(stats.get("max_mana", 100.0)))
	_set_vital("shield", float(_arena.get("shield")), float(stats.get("max_shield", stats.get("shield", 0.0))))
	var cooldowns: Dictionary = _arena.get("cooldowns") as Dictionary
	for index: int in range(_skill_buttons.size()):
		var button: Button = _skill_buttons[index]
		if index >= _state.skill_slots.size():
			button.text = "%d\n空技能槽" % (index + 1)
			button.disabled = true
			continue
		var id: String = _state.skill_slots[index]
		var skill: Dictionary = GameData.SKILLS.get(id, {}) as Dictionary
		var mana_cost: float = float(skill.get("mana", 0.0))
		var cooldown: float = float(cooldowns.get(id, 0.0))
		var ready: String = "就绪" if cooldown <= 0.0 else "%.1fs" % cooldown
		if cooldown <= 0.0 and float(_arena.get("mana")) < mana_cost:
			ready = "法力不足"
		button.text = "%d  %s\n%d 法力 · %s" % [index + 1, str(skill.get("short_name", skill.get("name", id))), int(mana_cost), ready]
		button.tooltip_text = "%s\n%s\n消耗 %d 法力 · 冷却 %.1f 秒" % [str(skill.get("name", id)), str(skill.get("description", "")), int(mana_cost), float(skill.get("cooldown", 0.0))]
		var tint: Color = skill.get("color", CYAN) as Color
		button.add_theme_color_override("font_color", tint if cooldown <= 0.0 else MUTED)
		button.disabled = not bool(_arena.get("alive")) or is_blocking()
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
	for child: Node in _panel_body.get_children():
		_panel_body.remove_child(child)
		child.queue_free()
	_close_button.visible = _active_panel != "death"
	_panel_tabs.visible = _active_panel in ["inventory", "talents", "skills"]
	_panel_subtitle.text = "战斗已暂停  /  调整构筑后随时继续"
	_panel_footer.text = "构筑变更会自动保存  ·  关闭面板继续战斗"
	_panel_footer.add_theme_color_override("font_color", MUTED)
	var panel_order: Array[String] = ["inventory", "talents", "skills"]
	for index: int in range(_panel_tabs.get_child_count()):
		var tab: Button = _panel_tabs.get_child(index) as Button
		tab.add_theme_color_override("font_color", CYAN if panel_order[index] == _active_panel else MUTED)
	match _active_panel:
		"inventory":
			_build_inventory_panel()
		"talents":
			_build_talents_panel()
		"skills":
			_build_skills_panel()
		"pause":
			_build_pause_panel()
		"death":
			_build_death_panel()


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
	_panel_title.text = "装备背包"
	_section("已装备", "替换装备会立即更新角色属性")
	var equipped_row: HBoxContainer = HBoxContainer.new()
	_panel_body.add_child(equipped_row)
	for slot: String in ["weapon", "armor", "charm"]:
		var item_id: String = str(_state.equipped.get(slot, ""))
		var item: Dictionary = GameData.ITEMS.get(item_id, {}) as Dictionary
		var panel: PanelContainer = PanelContainer.new()
		panel.name = "Equipped_" + slot
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equipped_row.add_child(panel)
		var copy: VBoxContainer = VBoxContainer.new()
		copy.add_theme_constant_override("separation", 4)
		panel.add_child(copy)
		copy.add_child(_label(_slot_name(slot), 13, MUTED))
		copy.add_child(_label(str(item.get("name", "未装备")), 17, CYAN))
		copy.add_child(_wrap_label(_stats_text(item.get("stats", {}) as Dictionary), 13, MUTED))
		var remove: Button = _button("卸下", "Unequip_" + slot, _unequip_item.bind(slot))
		remove.disabled = item_id.is_empty()
		remove.add_theme_font_size_override("font_size", 14)
		copy.add_child(remove)
	_section("背包", "点击装备，替换相同部位的物品")
	for id: String in _state.inventory:
		var item: Dictionary = GameData.ITEMS.get(id, {}) as Dictionary
		var slot: String = str(item.get("slot", ""))
		var is_equipped: bool = str(_state.equipped.get(slot, "")) == id
		var copy: String = "%s  ·  %s" % [_slot_name(slot), str(item.get("description", ""))]
		var row: HBoxContainer = _card(_panel_body, str(item.get("name", id)), copy, GOLD if is_equipped else TEXT)
		var equip: Button = _button("已装备" if is_equipped else "装备", "Equip_" + id, _equip_item.bind(id), 110)
		equip.disabled = is_equipped
		equip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(equip)
	_section("当前角色属性")
	var stats: Dictionary = _arena.call("get_stats") as Dictionary
	var stat_panel: PanelContainer = PanelContainer.new()
	_panel_body.add_child(stat_panel)
	_panel_footer.text = "当前属性  ·  生命 %d  /  法力 %d  /  护盾 %d  /  伤害 %.0f  /  攻速 %.2f  /  移速 %.0f" % [int(stats.get("max_health", 0)), int(stats.get("max_mana", 0)), int(stats.get("max_shield", 0)), float(stats.get("damage", 0)), float(stats.get("attack_speed", 0)), float(stats.get("move_speed", 0))]
	var summary: Label = _wrap_label(_stats_text(stats, "     ·     "), 15, TEXT)
	summary.name = "DerivedStatsLabel"
	stat_panel.add_child(summary)


func _build_talents_panel() -> void:
	_panel_title.text = "天赋成长"
	_section("可分配天赋点  %d" % _state.talent_points, "升级获得天赋点  ·  可随时免费重置")
	for key: Variant in GameData.TALENTS.keys():
		var id: String = str(key)
		var talent: Dictionary = GameData.TALENTS[id] as Dictionary
		var rank: int = int(_state.talents.get(id, 0))
		var max_rank: int = int(talent.get("max_rank", 1))
		var title: String = "%s   %d / %d" % [str(talent.get("name", id)), rank, max_rank]
		var description: String = str(talent.get("description", ""))
		var row: HBoxContainer = _card(_panel_body, title, description, GOLD if rank > 0 else TEXT)
		var allocate: Button = _button("已满级" if rank >= max_rank else "+  分配一点", "Allocate_" + id, _allocate_talent.bind(id), 145)
		allocate.disabled = rank >= max_rank or _state.talent_points <= 0
		allocate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(allocate)
	var refund: Button = _button("重置全部天赋 · 返还所有点数", "RefundTalentsButton", _refund_talents)
	refund.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var allocated: int = 0
	for value: Variant in _state.talents.values():
		allocated += int(value)
	refund.disabled = allocated == 0
	_panel_body.add_child(refund)


func _build_skills_panel() -> void:
	_panel_title.text = "技能组合"
	_section("先选择要替换的技能槽", "已装配的技能会互换位置，不会重复占槽")
	var slots: HBoxContainer = HBoxContainer.new()
	slots.name = "SkillSlotSelector"
	_panel_body.add_child(slots)
	for index: int in range(5):
		var id: String = _state.skill_slots[index] if index < _state.skill_slots.size() else ""
		var skill: Dictionary = GameData.SKILLS.get(id, {}) as Dictionary
		var button: Button = _button("%d  %s" % [index + 1, str(skill.get("short_name", skill.get("name", "空槽")))], "SlotButton%d" % (index + 1), _select_skill_slot.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if index == _selected_skill_slot:
			_accent_button(button)
		slots.add_child(button)
	_section("可用技能", "当前目标：技能槽 %d" % (_selected_skill_slot + 1))
	for key: Variant in GameData.SKILLS.keys():
		var id: String = str(key)
		var skill: Dictionary = GameData.SKILLS[id] as Dictionary
		var assigned: int = _state.skill_slots.find(id)
		var status: String = "  ·  已在槽 %d" % (assigned + 1) if assigned >= 0 else ""
		var description: String = "%d 法力  ·  %.1f 秒冷却%s\n%s" % [int(skill.get("mana", 0)), float(skill.get("cooldown", 0.0)), status, str(skill.get("description", ""))]
		var row: HBoxContainer = _card(_panel_body, str(skill.get("name", id)), description, skill.get("color", CYAN) as Color)
		var select: Button = _button("当前技能" if assigned == _selected_skill_slot else "装入槽 %d" % (_selected_skill_slot + 1), "SelectSkill_" + id, _slot_skill.bind(id), 130)
		select.disabled = assigned == _selected_skill_slot
		select.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(select)


func _build_pause_panel() -> void:
	_panel_title.text = "暂停一下"
	_panel_subtitle.text = "调整节奏，准备下一轮试炼"
	_section("操作指南")
	var row: HBoxContainer = _card(_panel_body, "移动 · 瞄准 · 释放", "WASD / 方向键：移动   ·   按住鼠标左键：瞄准射击   ·   空格：闪避（需装配冲刺）\n1 – 5：释放技能   ·   Q：切换自动攻击\nI / B：装备背包   ·   T：天赋   ·   K：技能   ·   Esc：关闭面板 / 暂停")
	row.name = "ControlsGuide"
	_card(_panel_body, "你的构筑，由你决定", "装备、天赋与五个主动技能可以随时自由组合。\n击败敌人积累经验，升级后打开天赋面板分配点数；重试会保留当前构筑。", GOLD)
	var actions: HBoxContainer = HBoxContainer.new()
	_panel_body.add_child(actions)
	var resume: Button = _button("继续战斗", "ResumeButton", close_panel, 180)
	_accent_button(resume)
	actions.add_child(resume)
	actions.add_child(_button("重新开始", "RestartButton", _restart, 180))
	actions.add_child(_button("保存并退出", "ExitButton", _exit_game, 180))
	_panel_footer.text = "游戏仅保存构筑进度；重新开始会重置本轮战斗"


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
		if id.contains("mult") or id == "crit_chance" or id == "cooldown_reduction":
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


func _allocate_talent(id: String) -> void:
	if _state.allocate_talent(id):
		notify("天赋提升：%s" % str((GameData.TALENTS[id] as Dictionary).get("name", id)))


func _refund_talents() -> void:
	_state.refund_talents()
	notify("天赋点已全部返还")


func _select_skill_slot(index: int) -> void:
	_selected_skill_slot = index
	_rebuild_panel()


func _slot_skill(id: String) -> void:
	if _state.slot_skill(_selected_skill_slot, id):
		notify("技能槽 %d 已更新" % (_selected_skill_slot + 1))


func _restart() -> void:
	_active_panel = ""
	_modal.hide()
	_arena.call("restart_run")
	notify("新一轮试炼开始，构筑已保留")


func _exit_game() -> void:
	if bool(_arena.call("save_build")):
		get_tree().quit()
	else:
		notify("构筑保存失败，请检查存储权限后重试")
