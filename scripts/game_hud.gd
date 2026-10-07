class_name GameHUD
extends CanvasLayer
## Responsive, keyboard-friendly combat HUD and live build editor.

const TownSquareView = preload("res://scripts/ui/town_square_view.gd")
const TownServiceView = preload("res://scripts/ui/town_service_panel.gd")
const FlaskSlotView = preload("res://scripts/ui/flask_slot.gd")
const CanonicalInventoryView = preload("res://scripts/ui/canonical_inventory_panel.gd")
const CanonicalSkillsView = preload("res://scripts/ui/canonical_skill_panel.gd")
const CanonicalPassivesView = preload("res://scripts/ui/canonical_passive_panel.gd")
const CanonicalCharacterView = preload("res://scripts/ui/canonical_character_panel.gd")
const ItemHoverView = preload("res://scripts/ui/item_hover_card.gd")
const ItemPresentation = preload("res://scripts/ui/unified_item_presentation.gd")
const DockedMenus = preload("res://scripts/ui/docked_menu_state.gd")
const DockStyle = preload("res://scripts/ui/dock_visual_style.gd")
const OVERLAY_PANELS: Array[String] = ["talents", "combat", "monsters", "pause", "settings", "death"]
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

var _town_square: Control
var _town_view: Control
var _world_context_cache: Dictionary = {}
var _world_button: Button
var _world_label: Label
var _cleanup_label: Label
var _cleanup_elapsed := 0.0
var _edition_label: Label
var _return_dialog: ConfirmationDialog
var _return_revision := -1
var _arena: Node
var _state
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
var _flask_hud_panel: PanelContainer
var _flask_buttons: Dictionary = {}
var _passive_panel: Control
var _skill_support_panel: Control
var _character_panel: Control
var _panel_margin: MarginContainer
var _panel_scroll: ScrollContainer
var _modal: Control
var _panel_title: Label
var _panel_subtitle: Label
var _panel_body: VBoxContainer
var _panel_footer: Label
var _menu_routes = DockedMenus.new()
var _windows: Dictionary = {}
var _dock_roots: Dictionary = {}
var _dock_bodies: Dictionary = {}
var _dock_titles: Dictionary = {}
var _dock_subtitles: Dictionary = {}
var _dock_footers: Dictionary = {}
var _dock_scrolls: Dictionary = {}
var _dock_built: Dictionary = {}
var _skills_dock_built: bool = false
var _character_dock_built: bool = false
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
var _item_hover: Control
var _hover_uid := ""
var _hover_anchor := Rect2()
var _hover_exit_at := 0
var _hover_compare := false
var _drag_active: bool = false


func setup(arena: Node) -> void:
	_arena = arena
	_state = arena.get("state")
	_preferences = arena.get("visual_settings") as VisualSettings
	layer = 10
	_root = Control.new()
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_root.name = "HUDRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.theme = _make_theme()
	_town_square = TownSquareView.new()
	_root.add_child(_town_square)
	_town_square.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_town_square.setup(_arena.town_services())
	_town_square.service_requested.connect(func(id: String): _town_view.open_service(id))
	_town_square.hide()
	_build_status()
	_build_navigation()
	_build_world_controls()
	_build_vitals()
	_build_flask_hotbar()
	_build_hotbar()
	_build_hint()
	_build_toast()
	_build_dock_windows()
	_build_modal()
	_item_hover = ItemHoverView.new()
	_item_hover.name = "SharedItemHover"
	_root.add_child(_item_hover)
	_build_encounter_confirmation()
	_style_dark_hud()
	get_viewport().size_changed.connect(_apply_presentation)
	_apply_presentation()
	refresh_build()
	_update_live()
	if not _arena.world_context_changed.is_connected(_refresh_world):
		_arena.world_context_changed.connect(_refresh_world)
		_arena.build_state_replaced.connect(_replace_build_profile)
	_refresh_world()


func _process(delta: float) -> void:
	if not is_instance_valid(_arena) or _root == null:
		return
	if _menu_routes.snapshot().death_latched and bool(_arena.get("alive")):
		_menu_routes = DockedMenus.new()
		_sync_menu_views()
	_set_drag_active(get_viewport().gui_is_dragging())
	if is_instance_valid(_item_hover) and _item_hover.visible:
		var compare: bool = Input.is_key_pressed(KEY_SHIFT)
		if compare != _hover_compare: _present_item_hover()
		if _hover_exit_at > 0 and Time.get_ticks_msec() >= _hover_exit_at and not _item_hover.get_global_rect().has_point(_root.get_global_mouse_position()):
			_dismiss_item_hover()
	_tick_cleanup_hint(delta)
	_refresh_clock += delta
	if _refresh_clock >= 0.05:
		_refresh_clock = 0.0
		_update_live()
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_set_drag_active(true)
	elif what == NOTIFICATION_DRAG_END:
		_set_drag_active(false)


func is_blocking() -> bool:
	return bool(_menu_routes.snapshot().paused) or (is_instance_valid(_return_dialog) and _return_dialog.visible)


func open_panel(panel_name: String) -> void:
	if _root == null:
		return
	var route: String = panel_name
	if route not in ["inventory", "skills", "character", "talents", "combat", "monsters", "pause", "settings", "death"]:
		route = "pause"
	_menu_routes.request(route)
	_sync_menu_views()


func handle_menu_key(key: int, pressed: bool = true, echo: bool = false) -> bool:
	if key not in [KEY_I, KEY_B, KEY_C, KEY_T, KEY_K, KEY_F6, KEY_F7, KEY_ESCAPE]:
		return false
	if not pressed:
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if key == KEY_C and (focus is LineEdit or focus is TextEdit):
		return true
	if _menu_routes.snapshot().death_latched and not bool(_arena.get("alive")):
		return true
	var key_name: String = ""
	match key:
		KEY_I: key_name = "i"
		KEY_B: key_name = "b"
		KEY_C: key_name = "c"
		KEY_T: key_name = "t"
		KEY_K: key_name = "k"
		KEY_F6: key_name = "f6"
		KEY_F7: key_name = "f7"
		KEY_ESCAPE: key_name = "escape"
	_menu_routes.handle_key(key_name, echo)
	_sync_menu_views()
	return true


func close_panel() -> void:
	var snapshot: Dictionary = _menu_routes.snapshot()
	if snapshot.death_latched:
		_menu_routes.close("death")
	elif not str(snapshot.overlay).is_empty():
		_menu_routes.close("overlay")
	elif not str(snapshot.left).is_empty() or bool(snapshot.right_inventory):
		_menu_routes.close()
	else:
		return
	_sync_menu_views()


func _hide_windows() -> void:
	_dismiss_item_hover()
	_cancel_encounter_request()
	_active_panel = ""
	for dock: Control in _dock_roots.values():
		dock.hide()
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


func _sync_menu_views() -> void:
	if _root == null:
		return
	_dismiss_item_hover()
	var snapshot: Dictionary = _menu_routes.snapshot()
	var nav: Control = _root.get_node_or_null("Navigation") as Control
	if is_instance_valid(nav): nav.visible = not bool(snapshot.paused)
	if not str(snapshot.overlay).is_empty():
		var overlay: String = str(snapshot.overlay)
		var overlay_panel: String = "talents" if overlay == "talents" else overlay
		if not _windows.has(overlay_panel):
			overlay_panel = "pause"
		if _active_panel != overlay_panel or not bool(_windows[overlay_panel].root.visible):
			_show_window(overlay_panel)
		else:
			for dock: Control in _dock_roots.values(): dock.hide()
		return
	_cancel_encounter_request()
	for view: Dictionary in _windows.values(): view.root.hide()
	var left: String = str(snapshot.left)
	var right: bool = bool(snapshot.right_inventory)
	for dock_name: String in ["left", "right"]:
		var dock: Control = _dock_roots[dock_name]
		dock.visible = (dock_name == "left" and not left.is_empty()) or (dock_name == "right" and right)
	if not left.is_empty():
		_active_panel = left
		if left == "skills": _build_skills_dock()
		elif left == "character": _build_character_dock()
	if right:
		if left.is_empty(): _active_panel = "inventory"
		_build_inventory_panel()
	if left.is_empty() and not right:
		_active_panel = ""
	_dismiss_item_hover()
	_apply_dock_layout()


func _close_dock(which: String) -> void:
	_menu_routes.close("left" if which == "left" else "right")
	_sync_menu_views()


func _set_drag_active(active: bool) -> void:
	if _drag_active == active:
		return
	_drag_active = active
	if active:
		_dismiss_item_hover()


func notify(message: String) -> void:
	if _toast_label == null:
		return
	if is_blocking():
		var menu_state: Dictionary = _menu_routes.snapshot()
		var target: Label = null
		if not str(menu_state.overlay).is_empty():
			target = _panel_footer
		elif bool(menu_state.right_inventory):
			target = _dock_footers.right
		elif not str(menu_state.left).is_empty():
			target = _dock_footers.left
		if is_instance_valid(target):
			target.show()
			if _state != null and not _state.save_block_reason().is_empty():
				target.text = "原存档已保护，本次进度未写入；请先备份并恢复有效存档"
				target.tooltip_text = _state.save_block_reason() + "\n" + message
				target.add_theme_color_override("font_color", GOLD)
				return
			target.text = message
			target.add_theme_color_override("font_color", CYAN)
			return
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
	if not _hover_uid.is_empty(): _present_item_hover()
	_update_live()
	var menus: Dictionary = _menu_routes.snapshot()
	if not str(menus.overlay).is_empty():
		if menus.overlay == "talents" and is_instance_valid(_passive_panel): _passive_panel.refresh()
		elif not str(menus.overlay) in ["combat", "monsters"]: _rebuild_panel()
		return
	if bool(menus.right_inventory) and is_instance_valid(_inventory_panel):
		_inventory_panel.refresh()
	if menus.left == "skills" and is_instance_valid(_skill_support_panel):
		if not _state.has_method("get_group_cast"):
			var selected_position: int = _state.skill_slots.find(_selected_support_skill_id)
			if selected_position >= 0:
				_selected_skill_slot = selected_position
				_skill_support_panel.select_skill(_selected_support_skill_id)
		_skill_support_panel.refresh()
	if menus.left == "character" and is_instance_valid(_character_panel):
		_character_panel.refresh()


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
	_edition_label = _label("灰烬庭院", 12, MUTED)
	_edition_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_edition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.add_child(_edition_label)
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
	nav.add_child(_button("I  行囊", "InventoryButton", open_panel.bind("inventory"), 112))
	nav.add_child(_button("C  属性", "CharacterButton", open_panel.bind("character"), 86))
	nav.add_child(_button("T  天赋", "TalentsButton", open_panel.bind("talents"), 82))
	nav.add_child(_button("K  技能", "SkillsButton", open_panel.bind("skills"), 82))
	nav.add_child(_button("Esc  暂停", "PauseButton", open_panel.bind("pause"), 96))


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


func _build_flask_hotbar() -> void:
	_flask_hud_panel = PanelContainer.new()
	_flask_hud_panel.name = "FlaskHotbar"
	_flask_hud_panel.add_theme_stylebox_override("panel",DockStyle.surface(Color("544133"),3.0))
	_place(_flask_hud_panel,Rect2(20,-211,280,49),Control.PRESET_BOTTOM_LEFT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_flask_hud_panel.add_child(row)
	for index: int in range(5):
		var slot := FlaskSlotView.new()
		slot.name = "CombatFlask_%d" % index
		slot.slot_id = "flask_%d" % (index+1)
		slot.editing = false
		slot.use_requested.connect(func(id: String):
			if not _arena.has_method("use_flask"): return
			var result: Dictionary = _arena.use_flask(id)
			if not result.get("ok",false) and not str(result.get("reason","")).is_empty(): notify(str(result.reason))
			_update_flasks())
		row.add_child(slot)
		_flask_buttons[slot.slot_id] = slot

func _update_flasks() -> void:
	if not is_instance_valid(_flask_hud_panel): return
	_flask_hud_panel.visible = _arena.has_method("flask_statuses")
	if not _flask_hud_panel.visible: return
	for status: Dictionary in _arena.flask_statuses():
		if _flask_buttons.has(status.slot_id): _flask_buttons[status.slot_id].set_status(status)


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
	for panel_name: String in OVERLAY_PANELS:
		_build_window(panel_name)


func _build_dock_windows() -> void:
	for side: String in ["left", "right"]:
		var dock_root := Control.new()
		dock_root.name = "LeftDockRoot" if side == "left" else "RightDockRoot"
		dock_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dock_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(dock_root)
		var panel := PanelContainer.new()
		panel.name = "SkillsCharacterDock" if side == "left" else "InventoryDock"
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.anchor_left = 0.0 if side == "left" else 2.0 / 3.0
		panel.anchor_right = 1.0 / 3.0 if side == "left" else 1.0
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.add_theme_stylebox_override("panel", PresentationTheme.panel(PANEL, BORDER.lightened(0.12), 8, 1, 6))
		dock_root.add_child(panel)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge: String in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 6 if side == "right" else 9)
		panel.add_child(margin)
		var stack := VBoxContainer.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_theme_constant_override("separation", 6)
		margin.add_child(stack)
		var title_band := PanelContainer.new()
		title_band.name = "DockTitleBand"
		title_band.add_theme_stylebox_override("panel",DockStyle.surface(DockStyle.LEATHER,8.0))
		stack.add_child(title_band)
		var header := HBoxContainer.new()
		title_band.add_child(header)
		var title := _label("技能", 15, DockStyle.IVORY) if side == "left" else _label("行囊", 15, DockStyle.IVORY)
		title.add_theme_color_override("font_color",DockStyle.IVORY)
		title.add_theme_font_override("font",DockStyle.bold_font(load("res://assets/fonts/arena_sans.otf")))
		title.name = "LeftDockTitle" if side == "left" else "RightDockTitle"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var close := _button("关闭", "CloseLeftDock" if side == "left" else "CloseRightDock", _close_dock.bind(side), 58)
		close.custom_minimum_size = Vector2(38,24)
		DockStyle.style_action(close,10)
		header.add_child(close)
		var subtitle := _wrap_label("技能宝石组合", 12, MUTED) if side == "left" else _wrap_label("九个装备位 · 分页共用行囊", 12, MUTED)
		subtitle.name = "LeftDockSubtitle" if side == "left" else "RightDockSubtitle"
		stack.add_child(subtitle)
		var scroll := ScrollContainer.new()
		scroll.name = "LeftDockScroll" if side == "left" else "RightDockScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		stack.add_child(scroll)
		var content := VBoxContainer.new()
		content.name = "LeftDockContent" if side == "left" else "RightDockContent"
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 7)
		scroll.add_child(content)
		var footer := _wrap_label("", 12, MUTED)
		footer.name = "LeftDockFeedback" if side == "left" else "RightDockFeedback"
		stack.add_child(footer)
		_dock_roots[side] = dock_root
		_dock_bodies[side] = content
		_dock_titles[side] = title
		_dock_subtitles[side] = subtitle
		_dock_footers[side] = footer
		_dock_scrolls[side] = scroll
		_dock_built[side] = false
		dock_root.hide()


func _apply_dock_layout() -> void:
	# Anchor widths stay at one third in logical canvas units at every viewport size.
	for side: String in ["left", "right"]:
		if not _dock_roots.has(side): continue
		_dock_subtitles[side].visible = not _dock_subtitles[side].text.is_empty()
		_dock_footers[side].visible = not _dock_footers[side].text.is_empty()
		var panel: Control = _dock_roots[side].get_child(0) as Control
		panel.offset_left = 0.0
		panel.offset_right = 0.0
		panel.offset_top = 0.0
		panel.offset_bottom = 0.0
		if _dock_roots[side].visible:
			PresentationTheme.apply_font_scale(panel, _preferences.font_scale)


func _build_window(panel_name: String) -> void:
	_modal = Control.new()
	_modal.name = panel_name.to_pascal_case() + "Window"
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


func _skill_view(id: String, group_id: String = "") -> Dictionary:
	var cache_key: String = id if group_id.is_empty() else "group:"+group_id
	if _skill_views.has(cache_key):
		return _skill_views[cache_key]
	var skill: Dictionary = GameData.SKILLS.get(id, {})
	var cast: Dictionary = _state.get_skill_cast(id) if group_id.is_empty() else _state.get_group_cast(group_id)
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
	_skill_views[cache_key] = result
	return result


func _update_live() -> void:
	_update_flasks()
	if _state == null:
		return
	var stats: Dictionary = _arena.call("get_stats") as Dictionary
	var seconds: int = int(float(_arena.get("elapsed")))
	_wave_label.text = "第 %d 波 · 击败 %d · 场上 %d" % [int(_arena.get("wave")), int(_arena.get("kills")), _arena.enemies.size()]
	_run_label.text = "%02d:%02d   /   %s" % [seconds / 60, seconds % 60, "试验场 · 无奖励" if bool(_arena.get("demo_mode")) else ("战斗已暂停" if is_blocking() else "战斗进行中")]
	if not bool(_arena.get("demo_mode")) and not _arena.encounter_selection().is_empty():
		_run_label.text = "%02d:%02d   /   %s" % [seconds / 60, seconds % 60,"挑战已暂停" if is_blocking() else "挑战进行中"]
	_run_label.tooltip_text = "本轮：%s\n无额外奖励；不随构筑存档保存" % _arena.encounter_summary()
	if str(_world_context_cache.get("mode", "")) == "town":
		_wave_label.text = "测试城镇" if bool(_world_context_cache.get("test_mode", false)) else "正式城镇"
		_run_label.text = "战斗未开启"
		_run_label.tooltip_text = "独立测试进度" if bool(_world_context_cache.get("test_mode", false)) else "选择地图与挑战档位"
	elif str(_world_context_cache.get("mode", "")) in ["map", "map_complete"]:
		_run_label.tooltip_text = "独立测试进度" if bool(_world_context_cache.get("test_mode", false)) else "完成地图后返回城镇领取结算"
		if str(_world_context_cache.get("encounter_mode", "")) == "exploration":
			_wave_label.text = "探索 · 击败 %d · 剩余 %d" % [int(_arena.get("kills")), _arena.enemies.size()]
			_run_label.text = "%02d:%02d   /   %s" % [seconds / 60, seconds % 60, "探索已暂停" if is_blocking() else "探索中"]
			_run_label.tooltip_text = str(_world_context_cache.get("exploration_description", "寻找并击败地图中的敌人，清理完成后返回城镇"))
		if str(_world_context_cache.mode) == "map_complete": _run_label.text = "挑战完成 · 返回城镇"
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
	var slots: Array = _state.skill_slots
	for index: int in range(_skill_buttons.size()):
		var button: Button = _skill_buttons[index]
		if index >= slots.size() or str(slots[index]).is_empty():
			button.text = "%d\n空技能槽" % (index + 1)
			button.disabled = true
			continue
		var id: String = slots[index]
		var skill: Dictionary = GameData.SKILLS.get(id, {}) as Dictionary
		var group_id: String = _state.group_for_key(KEY_1+index) if _state.has_method("group_for_key") else ""
		var view: Dictionary = _skill_view(id,group_id)
		var valid_cast: bool = bool(view.ok)
		var mana_cost: float = float(view.mana)
		var cooldown: float = float(cooldowns.get(id, 0.0)) if group_id.is_empty() else _arena.group_cooldown_remaining(group_id)
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
	caption.text = "%d / %d" % [int(ceilf(value)), int(ceilf(maximum))]


func _rebuild_panel() -> void:
	var menu_state: Dictionary = _menu_routes.snapshot()
	var rebuild_skills_dock: bool = str(menu_state.overlay).is_empty() and str(menu_state.left) == "skills"
	var saved_panel_fields: Dictionary = {}
	if rebuild_skills_dock:
		saved_panel_fields = {
			"body": _panel_body,
			"scroll": _panel_scroll,
			"title": _panel_title,
			"subtitle": _panel_subtitle,
			"footer": _panel_footer,
			"active": _active_panel,
		}
		_panel_body = _dock_bodies.left as VBoxContainer
		_panel_scroll = _dock_scrolls.left as ScrollContainer
		_panel_title = _dock_titles.left as Label
		_panel_subtitle = _dock_subtitles.left as Label
		_panel_footer = _dock_footers.left as Label
		_active_panel = "skills"
	_cancel_encounter_request()
	for child: Node in _panel_body.get_children():
		if child == _passive_panel or child == _inventory_panel or child == _skill_support_panel:
			(child as Control).hide()
			continue
		_panel_body.remove_child(child)
		child.queue_free()
	if not rebuild_skills_dock:
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
	PresentationTheme.apply_font_scale(_dock_roots.left if rebuild_skills_dock else _modal, _preferences.font_scale)
	if rebuild_skills_dock:
		_panel_body = saved_panel_fields.body as VBoxContainer
		_panel_scroll = saved_panel_fields.scroll as ScrollContainer
		_panel_title = saved_panel_fields.title as Label
		_panel_subtitle = saved_panel_fields.subtitle as Label
		_panel_footer = saved_panel_fields.footer as Label
		_active_panel = str(saved_panel_fields.active)


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
	var body: VBoxContainer = _dock_bodies.right as VBoxContainer
	_dock_titles.right.text = "行囊"
	if _state.has_method("equipped_items"):
		if not is_instance_valid(_inventory_panel):
			_inventory_panel = CanonicalInventoryView.new()
			_inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_inventory_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(_inventory_panel)
			_inventory_panel.setup(_state, str(_arena.build_save_path), _arena)
			_inventory_panel.feedback.connect(notify)
			_inventory_panel.item_hovered.connect(_show_item_hover)
			_inventory_panel.hover_left.connect(_leave_item_hover)
			_inventory_panel.character_requested.connect(open_panel.bind("character"))
		_inventory_panel.show()
		_inventory_panel.refresh()
		_dock_subtitles.right.text = ""
		_dock_titles.right.tooltip_text = "九个装备目标 · 装备、珠宝与宝石共用分页行囊"
		_dock_footers.right.text = ""
	else:
		if not is_instance_valid(_inventory_panel):
			_inventory_panel = InventoryPanelView.new()
			_inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_inventory_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(_inventory_panel)
			_inventory_panel.setup(_state)
			_inventory_panel.feedback.connect(notify)
			_inventory_panel.open_passives_requested.connect(_open_passives_from_inventory)
		_dock_subtitles.right.text = "整理格子，搭配装备 · 珠宝与装备共用行囊"
		_dock_footers.right.text = "拖动摆放物品 · 装备拖入对应槽位 · 珠宝在天赋星图镶嵌"
		_inventory_panel.show()
		_inventory_panel.refresh()
	_dock_built.right = true


func _build_skills_dock() -> void:
	_dock_titles.left.text = "技能"
	if not _skills_dock_built:
		var previous_body: VBoxContainer = _panel_body
		var previous_title: Label = _panel_title
		var previous_subtitle: Label = _panel_subtitle
		var previous_footer: Label = _panel_footer
		var previous_active: String = _active_panel
		_panel_body = _dock_bodies.left
		_panel_title = _dock_titles.left
		_panel_subtitle = _dock_subtitles.left
		_panel_footer = _dock_footers.left
		_active_panel = "skills"
		_build_skills_panel()
		_panel_body = previous_body
		_panel_title = previous_title
		_panel_subtitle = previous_subtitle
		_panel_footer = previous_footer
		_active_panel = previous_active
		_skills_dock_built = true
	if is_instance_valid(_character_panel): _character_panel.hide()
	if is_instance_valid(_skill_support_panel):
		_skill_support_panel.show()
		_skill_support_panel.refresh()
	_dock_subtitles.left.text = ""
	_dock_titles.left.tooltip_text = "每行 1 主 + 5 辅；绑定按键可施放。"
	_dock_footers.left.text = ""


func _build_character_dock() -> void:
	_dock_titles.left.text = "角色属性"
	_dock_subtitles.left.text = ""
	_dock_footers.left.text = ""
	if not is_instance_valid(_character_panel):
		_character_panel = CanonicalCharacterView.new()
		_character_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_character_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_dock_bodies.left.add_child(_character_panel)
		_character_panel.setup(_state)
	if is_instance_valid(_skill_support_panel): _skill_support_panel.hide()
	_character_panel.show()
	_character_panel.refresh()


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
	_panel_title.text = "源天赋树 · 珠宝" if _state.has_method("passive_analysis") else "天赋星图 · 珠宝"
	_panel_subtitle.text = "拖动平移 · 滚轮缩放 · 双击分配 / 右键退款" if _state.has_method("passive_analysis") else "分配天赋 · 镶嵌珠宝 · 查看覆盖"
	if not is_instance_valid(_passive_panel):
		_passive_panel = CanonicalPassivesView.new() if _state.has_method("passive_analysis") else PassivePanel.new()
		_passive_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_passive_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel_body.add_child(_passive_panel)
		_passive_panel.setup(_state, str(_arena.build_save_path))
		_passive_panel.feedback.connect(notify)
		if _passive_panel is CanonicalPassivesView:
			_passive_panel.item_hovered.connect(_show_item_hover)
			_passive_panel.hover_left.connect(_leave_item_hover)
	_passive_panel.show()
	_passive_panel.refresh()
	_panel_footer.text = "每点消耗 1 天赋点 · 普通珠宝每20有效击杀 · 寻枝晶玉来自首领 · F8 离线图鉴"


func _build_skills_panel() -> void:
	if _state.has_method("get_group_cast"):
		_panel_title.text = "技能宝石 · 组合"
		_panel_subtitle.text = "独立实例与五个辅助孔 · 所有激活行均可绑定施放"
		if not is_instance_valid(_skill_support_panel):
			_skill_support_panel = CanonicalSkillsView.new()
			_skill_support_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_skill_support_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_panel_body.add_child(_skill_support_panel)
			_skill_support_panel.setup(_state, str(_arena.build_save_path))
			_skill_support_panel.feedback.connect(notify)
			_skill_support_panel.item_hovered.connect(_show_item_hover)
			_skill_support_panel.hover_left.connect(_leave_item_hover)
		_skill_support_panel.font_scale = _preferences.font_scale
		_skill_support_panel.show()
		_skill_support_panel.refresh()
		_panel_footer.text = "背包宝石可拖入任意合适孔位 · 右键取回 · 减少容量保留配置"
		return
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
	var has_preview_penetration := false
	for preview_role: String in ["parent", "child", "explosion"]:
		for detail: Dictionary in preview.get(preview_role, {}).get("details", []):
			if float(detail.get("penetration", 0.0)) > 0.0: has_preview_penetration = true
	_section("02  当前构筑的逐分量伤害", "零抗性、零护甲目标估算（含穿透） · 非每秒伤害" if has_preview_penetration else "未计敌人抗性 · 非每秒伤害")
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
			details.append_array(TypedPreview.component_detail_lines(part))
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
				parts.append("%s %s" % [type, observed_damage_text(float(record.components[type]))])
			var damage_label: Label = _wrap_label("施放 #%d / 敌人 #%d · %s · 减伤后 %s（%s）" % [int(record.cast_id), int(record.target_id), "爆炸" if record.tags.has("explosion") else "返回命中" if record.phase == "returning" else "去程或直接命中", observed_damage_text(float(record.total)), " + ".join(parts)], 14, GOLD if record.tags.has("explosion") else CYAN)
			damage_label.tooltip_text = "敌方防御前：%s\n敌方防御后：%s\n护盾消耗 %s · 生命损失 %s；逐次命中，非每秒伤害。" % [TypedPreview.points(record.get("before_defense_components", {})), TypedPreview.points(record.components), observed_damage_text(float(record.get("shield_spent", 0.0))), observed_damage_text(float(record.get("health_lost", 0.0)))]
			damage_label.mouse_filter = Control.MOUSE_FILTER_PASS
			_panel_body.add_child(damage_label)
	var trace: Array = _arena.get("combat_trace")
	var lines: PackedStringArray = []
	var names: Dictionary = {"split": "分裂", "spawned": "子箭生成", "range_reached": "抵达射程", "return_started": "开始返回", "lifetime_expired": "寿命耗尽", "flight_ended": "自然飞行结束", "explosion": "爆炸", "terminated": "已终止", "hit": "碰撞命中", "spawn_rejected": "容量取消", "evaded": "攻击准入未通过（查看判定结果）", "terrain_hit": "投射物撞墙"}
	for index: int in range(maxi(0, trace.size() - 12), trace.size()):
		var event: Dictionary = trace[index]
		lines.append("施放 #%d · 箭 #%d ← 母箭 #%d · %.3f 秒 · %s" % [int(event.cast_id), int(event.projectile_id), int(event.parent_id), float(event.age), names.get(event.type, event.type)])
	if not lines.is_empty():
		_panel_body.add_child(_wrap_label("\n".join(lines), 13))
	if _arena.has_method("combat_outcomes"):
		var outcomes: Array = _arena.combat_outcomes()
		if not outcomes.is_empty():
			_section("命中判定结果", "只记录已知结果；出生保护不含预选阶段被排除的目标")
			for outcome: Dictionary in outcomes.slice(maxi(0,outcomes.size()-32)):
				_panel_body.add_child(_wrap_label(combat_outcome_text(outcome),13))
	_panel_footer.text = "F6 随时查看 · 命中按每枚箭每阶段每敌人一次 · 不同子箭与不同爆炸可分别命中 · 记录保留最近事件"


func _toggle_combat_item(id: String) -> void:
	var slot: String = str(GameData.ITEMS[id].slot)
	if _state.has_method("equipped_items"):slot=preload("res://scripts/items/equipment_slots.gd").legacy_slot(slot)
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
	actions.add_child(_button("保存并退出", "ExitButton", _exit_game, 180))
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
	if str(_world_context_cache.get("encounter_mode", "")) == "exploration":
		summary = "探索 %02d:%02d     ·     击败 %d" % [seconds / 60, seconds % 60, int(_arena.get("kills"))]
	_card(_panel_body, summary, "角色等级 %d  ·  可用天赋点 %d" % [_state.level, _state.talent_points], GOLD)
	_card(_panel_body, "再试一次，让组合更进一步", "重新开始会恢复生命与法力，重置敌人和战斗计时。\n装备、已分配天赋和技能栏保留；进入战斗后可随时打开面板调整。")
	var actions: HBoxContainer = HBoxContainer.new()
	_panel_body.add_child(actions)
	var retry: Button = _button("重新挑战", "RetryButton", _restart, 210)
	var world: Dictionary = _arena.world_context()
	if str(world.mode) in ["map", "map_complete"] and not bool(world.get("test_mode", false)):
		retry.text = "重新挑战 · %d 碎片" % int(world.get("retry_cost", world.get("fee_paid", 0)))
		retry.tooltip_text = "重新挑战将再次支付入场费；不足时可以返回城镇。"
	_accent_button(retry)
	actions.add_child(retry)
	if str(_arena.world_context().mode) in ["map","map_complete"]:
		var revision: int = int(_arena.world_context().revision)
		actions.add_child(_button("返回城镇", "DeathReturnTown", func():
			var result: Dictionary = _arena.return_to_town(revision)
			if bool(result.get("ok",false)):
				_menu_routes = DockedMenus.new()
				_sync_menu_views()
			_world_result(result),180))
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
	var context: Dictionary = _arena.world_context()
	if str(context.mode) in ["map", "map_complete"] and not bool(context.get("test_mode", false)):
		var result: Dictionary = _arena.retry_normal_map(int(context.revision))
		if not bool(result.get("ok", false)):
			notify(str(result.get("reason", "重新挑战失败")))
			return
	else:
		_arena.call("restart_run")
	_menu_routes = DockedMenus.new()
	_sync_menu_views()
	notify("新一轮试炼开始，构筑已保留")


func _exit_game() -> void:
	var result: Dictionary = _arena.call("request_safe_exit")
	if not bool(result.get("ok", false)):
		notify(str(result.get("reason", "保存失败，请重试")))


func _apply_presentation() -> void:
	if _root == null or _preferences == null:
		return
	# Canvas-items stretch handles physical pixels; UI zoom has its own transform.
	# Combat remains exactly 1280×720 regardless of either presentation preference.
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.scale = Vector2.ONE * _preferences.ui_scale
	_root.size = get_viewport().get_visible_rect().size / _preferences.ui_scale
	_root.theme.default_font_size = roundi(16 * _preferences.font_scale)
	if is_instance_valid(_skill_support_panel) and _skill_support_panel.is_visible_in_tree():
		_skill_support_panel.font_scale = _preferences.font_scale
	if is_instance_valid(_character_panel) and _character_panel.is_visible_in_tree():
		_character_panel.font_scale = _preferences.font_scale
	if is_instance_valid(_passive_panel) and _passive_panel.is_visible_in_tree():
		_passive_panel.font_scale = _preferences.font_scale
	for view: Dictionary in _windows.values():
		if view.root.visible: PresentationTheme.apply_font_scale(view.root, _preferences.font_scale)
	for dock: Control in _dock_roots.values():
		if dock.visible: PresentationTheme.apply_font_scale(dock, _preferences.font_scale)
	_apply_dock_layout()
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


func _show_item_hover(uid: String,anchor: Rect2) -> void:
	if _drag_active or get_viewport().gui_is_dragging():
		_set_drag_active(true)
		return
	if not _state.has_method("item") or _state.item(uid).is_empty(): return
	if is_instance_valid(_item_hover) and _item_hover.contains_viewport_point(get_viewport().get_mouse_position()) and not _hover_uid.is_empty(): return
	_hover_uid = uid
	_hover_anchor = anchor
	_hover_exit_at = 0
	_present_item_hover()


func _present_item_hover() -> void:
	if _drag_active or get_viewport().gui_is_dragging():
		_set_drag_active(true)
		return
	if _hover_uid.is_empty() or not is_instance_valid(_item_hover): return
	var view: Dictionary = ItemPresentation.view(_state,_hover_uid)
	if view.is_empty():
		_dismiss_item_hover()
		return
	_hover_compare = Input.is_key_pressed(KEY_SHIFT)
	_item_hover.font_scale = _preferences.font_scale
	var anchor: Rect2 = _root.get_global_transform_with_canvas().affine_inverse() * _hover_anchor
	_item_hover.present(view,ItemPresentation.comparisons(_state,_hover_uid),anchor,Rect2(Vector2.ZERO,_root.size),_hover_compare)


func _leave_item_hover() -> void:
	_hover_exit_at = Time.get_ticks_msec()+180


func _dismiss_item_hover() -> void:
	_hover_uid = ""
	_hover_exit_at = 0
	if is_instance_valid(_item_hover): _item_hover.dismiss()


func _build_world_controls() -> void:
	var box := VBoxContainer.new()
	box.name = "WorldControls"
	_place(box, Rect2(20,130,250,84))
	_world_label = _label("", 12)
	_world_label.add_theme_color_override("font_color", Color("f8ecd0"))
	box.add_child(_world_label)
	_cleanup_label = _label("", 12)
	_cleanup_label.name = "CleanupHint"
	_cleanup_label.add_theme_color_override("font_color", Color("f8ecd0"))
	_cleanup_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_cleanup_label.hide()
	box.add_child(_cleanup_label)
	_world_button = _button("城镇测试", "TownEntry", _world_action, 130)
	_world_button.custom_minimum_size.y = 28
	box.add_child(_world_button)
	_town_view = TownServiceView.new()
	_town_view.hide()
	_place(_town_view, Rect2(20,208,430,350))
	_town_view.z_index = 20
	_town_view.setup(_arena)
	_town_view.feedback.connect(notify)
	_town_view.crafter_requested.connect(func():
		if not _menu_routes.snapshot().right_inventory: open_panel("inventory"))
	_return_dialog = ConfirmationDialog.new()
	_return_dialog.title = "离开地图"
	_return_dialog.ok_button_text = "确认"
	_return_dialog.cancel_button_text = "取消"
	_return_dialog.dialog_text = "保留已经获得的物品并返回城镇？未完成的地图将放弃。"
	_return_dialog.confirmed.connect(func(): _world_result(_arena.return_to_town(_return_revision)))
	_root.add_child(_return_dialog)


func _refresh_world() -> void:
	var previous_mode := str(_world_context_cache.get("mode", ""))
	var context: Dictionary = _arena.world_context()
	_world_context_cache = context
	if is_instance_valid(_edition_label): _edition_label.text = world_caption(context)
	_town_square.visible = str(context.mode) in ["town", "normal_town"]
	_town_square.set_test_mode(bool(context.get("test_mode", false)))
	_town_view.refresh_world()
	match str(context.mode):
		"normal":
			_world_label.text = "竞技练习"
			_world_button.text = "返回正式城镇"
			_town_view.hide()
		"town", "normal_town":
			_world_label.text = "城镇 · 独立测试存档" if bool(context.get("test_mode", false)) else "城镇 · 正式存档"
			_world_button.text = "城镇服务"
		_:
			_world_label.text = exploration_progress_text(context) if str(context.get("encounter_mode", "")) == "exploration" else "%s · %d / %d" % [str(context.map_name),int(context.ordinary_kills),int(context.ordinary_target)]
			var camps: Array = context.get("camp_states", [])
			if not camps.is_empty() and str(context.get("encounter_mode", "")) != "exploration":
				var cleared := 0
				for camp: Dictionary in camps:
					if str(camp.state) == "cleared": cleared += 1
				_world_label.text += "\n据点 %d/%d · %s" % [cleared, camps.size(), {"sealed":"首领封印中", "ready":"首领入口已开启", "active":"首领已出现", "defeated":"首领已击败"}.get(str(context.get("boss_phase", "sealed")), "")]
			_world_button.text = "返回城镇"
			_town_view.hide()


	if previous_mode != str(context.mode):
		_cleanup_elapsed = 0.0
		_refresh_cleanup_hint()


func _tick_cleanup_hint(delta: float) -> void:
	if not is_instance_valid(_cleanup_label):
		return
	if str(_world_context_cache.get("encounter_mode", "")) != "exploration" or str(_world_context_cache.get("mode", "")) not in ["map", "map_complete"]:
		_cleanup_elapsed = 0.0
		_cleanup_label.hide()
		_cleanup_label.text = ""
		_cleanup_label.tooltip_text = ""
		return
	_cleanup_elapsed += maxf(delta, 0.0)
	if _cleanup_elapsed >= 0.2:
		_cleanup_elapsed = 0.0
		_refresh_cleanup_hint()


func _refresh_cleanup_hint() -> void:
	if not is_instance_valid(_cleanup_label):
		return
	var view: Dictionary = cleanup_hint_view(_arena.exploration_cleanup_hint())
	_cleanup_label.text = str(view.text)
	_cleanup_label.tooltip_text = str(view.tooltip)
	_cleanup_label.visible = not str(view.text).is_empty()


static func cleanup_hint_view(hint: Dictionary) -> Dictionary:
	var kind := str(hint.get("kind", "inactive"))
	var text := ""
	var details: Array[String] = []
	match kind:
		"target":
			var target: Dictionary = hint.get("target", {})
			var direction := str({"east":"东", "southeast":"东南", "south":"南", "southwest":"西南", "west":"西", "northwest":"西北", "north":"北", "northeast":"东北", "here":"附近"}.get(str(target.get("direction", "")), "附近"))
			text = "余敌 %d · %s" % [int(hint.get("living_count", 0)), direction]
			details.append("最近目标：%s" % ("首领" if bool(target.get("is_boss", false)) else str(target.get("outpost_name", "地图敌人"))))
			details.append("方向按目标当前位置显示，需绕开障碍")
		"overview":
			text = "未清驻点 %d" % hint.get("outposts", []).size()
		"waiting":
			text = "等待后续怪物"
		"settlement":
			text = "结算待保存"
		"complete":
			text = "清理完成"
	for outpost: Dictionary in hint.get("outposts", []):
		details.append("%s：余敌 %d" % [str(outpost.get("name", "")), int(outpost.get("living_count", 0))])
	var pending := int(hint.get("pending_count", 0))
	if pending > 0: details.append("后续怪物 %d" % pending)
	return {"text":text, "tooltip":"\n".join(details)}


func _world_action() -> void:
	var context: Dictionary = _arena.world_context()
	if str(context.mode) == "normal":
		_world_result(_arena.enter_normal_town(int(context.revision)))
		if str(_arena.world_context().mode) in ["town", "normal_town"]: _town_view.open_service("map_device")
	elif str(context.mode) in ["town", "normal_town"]:
		_town_view.open_service()
	elif str(context.mode) == "map_complete":
		_world_result(_arena.return_to_town(int(context.revision)))
	else:
		_return_revision = int(context.revision)
		_return_dialog.dialog_text = "保留已经获得的物品并返回城镇？未完成的地图将放弃。" if bool(context.get("test_mode", false)) else "保留已获得的物品并返回城镇？未完成地图不结算，入场费用不退还。"
		_return_dialog.popup_centered(Vector2i(380,160))


func _world_result(result: Dictionary) -> void:
	if not bool(result.get("ok",false)): notify(str(result.get("reason","操作失败")))
	_refresh_world()


func _replace_build_profile() -> void:
	# Release every old-model control and its deferred confirmations before rebinding.
	get_viewport().gui_cancel_drag()
	_dismiss_item_hover()
	for panel in [_inventory_panel,_skill_support_panel,_character_panel,_passive_panel]:
		if is_instance_valid(panel):
			panel.get_parent().remove_child(panel)
			panel.queue_free()
	_inventory_panel = null
	_skill_support_panel = null
	_character_panel = null
	_passive_panel = null
	_skills_dock_built = false
	_character_dock_built = false
	_dock_built.right = false
	_state = _arena.state
	_menu_routes = DockedMenus.new()
	_encounter_request_pending = false
	_encounter_dialog.hide()
	_return_dialog.hide()
	_town_view.cancel_pending()
	_skill_view_token = PackedByteArray()
	_sync_menu_views()
	refresh_build()


static func world_caption(context: Dictionary) -> String:
	if str(context.get("mode", "")) in ["map", "map_complete"]:
		return str(context.get("map_name", "地图"))
	if str(context.get("mode", "")) in ["town", "normal_town"]:
		return "测试城镇" if bool(context.get("test_mode", false)) else "正式城镇"
	return "灰烬庭院"


static func observed_damage_text(value: float) -> String:
	if value > 0.0 and value < 0.01: return "<0.01"
	return "%.2f" % value

static func combat_outcome_text(row: Dictionary) -> String:
	var labels := {"evaded":"攻击被闪避", "zero_damage":"已命中，实际损失为零", "terrain_blocked":"投射物撞墙", "spawn_protected":"出生保护：进入结算后被拒绝"}
	var outcome: String = str(row.get("outcome", ""))
	var text: String = str(labels.get(outcome, "未分类结果"))
	var target_id: int = int(row.get("target_id", 0))
	var cast_id: int = int(row.get("cast_id", 0))
	text += " · 敌人 #%d" % target_id if target_id > 0 else " · 目标未知"
	text += " · 施放 #%d" % cast_id if cast_id > 0 else " · 施放编号未知"
	if int(row.get("projectile_id", 0)) > 0: text += " · 箭 #%d" % int(row.projectile_id)
	if outcome == "evaded" and row.has("chance"): text += " · 本次命中率 %.1f%%" % (float(row.chance)*100.0)
	if row.has("at"): text += " · 记录时刻 %.3f 秒" % float(row.at)
	return text


static func exploration_progress_text(context: Dictionary) -> String:
	var headline := "%s · %d / %d" % [str(context.get("map_name", "地图")), int(context.get("ordinary_kills", 0)), int(context.get("ordinary_target", 0))]
	var outpost_text := ""
	var outposts: Array = context.get("outpost_states", [])
	if not outposts.is_empty():
		var cleared := 0
		for outpost: Dictionary in outposts:
			if str(outpost.get("state", "")) == "cleared": cleared += 1
		outpost_text = "驻点 %d/%d · " % [cleared, outposts.size()]
	var phase := str(context.get("boss_phase", "active"))
	var complete := str(context.get("mode", "")) == "map_complete"
	return headline + "\n" + outpost_text + ("地图已清理" if complete else "首领已击败 · 继续清理" if phase == "defeated" else "首领驻守" if not outposts.is_empty() else "寻找敌人 · 首领驻守")
