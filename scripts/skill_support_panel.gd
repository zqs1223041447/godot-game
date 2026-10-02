class_name SkillSupportPanel
extends VBoxContainer
## Skill-owned supports are edited only through BuildState's validated transactions.

signal feedback(message: String)

const Emblem = preload("res://scripts/visuals/skill_emblem.gd")
const TypedPreview = preload("res://scripts/combat/damage_preview.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const TEXT: Color = Color("3b281b")
const MUTED: Color = Color("69523a")
const CYAN: Color = Color("52623b")
const GOLD: Color = Color("79571f")
const RED: Color = Color("a13b2d")

var selected_skill_id: String = ""
var font_scale: float = 1.0
var _state: BuildState
var _selected_label: Label
var _preview_label: Label
var _selected_art: Control
var _slot_caption: Label
var _slot_row: HBoxContainer
var _add_buttons: Dictionary = {}
var _reasons: Dictionary = {}


func setup(state: BuildState) -> void:
	_state = state
	name = "SkillSupportPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 9)
	var selected_header := HBoxContainer.new()
	selected_header.add_theme_constant_override("separation",18)
	add_child(selected_header)
	_selected_art = Emblem.new()
	_selected_art.custom_minimum_size = Vector2(112,112)
	_selected_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	selected_header.add_child(_selected_art)
	var selected_copy := VBoxContainer.new()
	selected_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_header.add_child(selected_copy)
	_selected_label = _label("", "SelectedSupportSkill", 20, GOLD)
	selected_copy.add_child(_selected_label)
	_preview_label = _label("", "SupportCastPreview", 16, CYAN)
	selected_copy.add_child(_preview_label)
	_slot_caption = _label("", "SupportSlotCaption", 14, MUTED)
	selected_copy.add_child(_slot_caption)
	_slot_row = HBoxContainer.new()
	_slot_row.name = "SupportSlots"
	add_child(_slot_row)
	for key: Variant in Supports.SUPPORTS:
		var support_id: String = str(key)
		var definition: Dictionary = Supports.get_definition(support_id)
		var card: PanelContainer = _card()
		card.name = "SupportOption_" + support_id
		add_child(card)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var gem := Emblem.new()
		gem.skill_id = support_id
		gem.custom_minimum_size = Vector2(58,58)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(gem)
		var copy: VBoxContainer = VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		copy.add_child(_label(str(definition.get("name", support_id)), "SupportName_" + support_id, 17, TEXT))
		copy.add_child(_label(str(definition.get("description", "")), "SupportDescription_" + support_id, 14, MUTED))
		var reason: Label = _label("", "SupportReason_" + support_id, 14, MUTED)
		copy.add_child(reason)
		_reasons[support_id] = reason
		var add: Button = _button("添加辅助", "AddSupport_" + support_id)
		add.custom_minimum_size.x = 128
		add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add.pressed.connect(_add_support.bind(support_id))
		row.add_child(add)
		_add_buttons[support_id] = add
	add_child(_label("辅助全部可用，同一技能不重复装配；只影响投射物击中。辅助随技能保存，交换快捷栏位置不改变配置或已有冷却。", "SupportRules", 13, MUTED))


func select_skill(skill_id: String) -> void:
	selected_skill_id = skill_id
	refresh()


func refresh() -> void:
	if _state == null:
		return
	var skill: Dictionary = GameData.SKILLS.get(selected_skill_id, {})
	var position: int = _state.skill_slots.find(selected_skill_id)
	_selected_label.text = "辅助目标：%s  ·  %s" % [str(skill.get("name", "未选择技能")), "快捷栏 %d" % (position + 1) if position >= 0 else "未装配"]
	_selected_art.skill_id = selected_skill_id
	_selected_art.queue_redraw()
	var selected: Array[String] = _state.get_skill_supports(selected_skill_id)
	_slot_caption.text = "独立辅助槽  %d / %d" % [selected.size(), Supports.MAX_SUPPORTS]
	_rebuild_slots(selected)
	var cast: Dictionary = _state.get_skill_cast(selected_skill_id)
	var valid: bool = bool(cast.get("ok", false))
	if valid:
		var count: int = int(cast.get("initial_count", 0))
		_preview_label.text = "当前施放：%.2f 法力  ·  %.2f 秒冷却  ·  初始投射物 %d 枚" % [float(cast.get("mana", 0.0)), float(cast.get("cooldown", 0.0)), count]
		_preview_label.text += "\n" + TypedPreview.summary(cast)
		_preview_label.tooltip_text = TypedPreview.details(cast)
		_preview_label.add_theme_color_override("font_color", CYAN)
	else:
		_preview_label.text = "无法施放：%s" % str(cast.get("error", "技能编译失败"))
		_preview_label.tooltip_text = str(cast.get("error", "技能编译失败"))
		_preview_label.add_theme_color_override("font_color", RED)
	for support_id: String in _add_buttons:
		var reason: String = _state.support_reason(selected_skill_id, support_id)
		if not valid and reason.is_empty():
			reason = str(cast.get("error", "技能编译失败"))
		var added: bool = selected.has(support_id)
		var button: Button = _add_buttons[support_id]
		button.disabled = not reason.is_empty()
		button.text = "已装配" if added else "添加辅助"
		button.tooltip_text = reason if not reason.is_empty() else "为%s添加%s" % [str(skill.get("name", selected_skill_id)), str(Supports.get_definition(support_id).get("name", support_id))]
		var label: Label = _reasons[support_id]
		label.text = reason if not reason.is_empty() else "可添加 · 作用于当前选中的技能"
		label.add_theme_color_override("font_color", MUTED if added else GOLD if not reason.is_empty() else CYAN)

	PresentationTheme.apply_font_scale(self, font_scale)


func _rebuild_slots(selected: Array[String]) -> void:
	for child: Node in _slot_row.get_children():
		_slot_row.remove_child(child)
		child.queue_free()
	for index: int in range(Supports.MAX_SUPPORTS):
		var support_id: String = selected[index] if index < selected.size() else ""
		var definition: Dictionary = Supports.get_definition(support_id)
		var card: PanelContainer = _card()
		card.name = "SupportSlot%d" % (index + 1)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slot_row.add_child(card)
		var box: VBoxContainer = VBoxContainer.new()
		card.add_child(box)
		box.add_child(_label("辅助槽 %d：%s" % [index + 1, str(definition.get("name", "空槽"))], "SupportSlotName%d" % (index + 1), 16, MUTED if support_id.is_empty() else TEXT))
		var remove: Button = _button("取下" if not support_id.is_empty() else "尚未装配", "RemoveSupport%d" % (index + 1))
		remove.disabled = support_id.is_empty()
		remove.tooltip_text = "取下%s" % str(definition.get("name", "辅助")) if not support_id.is_empty() else "在下方选择辅助"
		# Bind the displayed identities. A repeated stale click cannot remove the
		# other support that just shifted into this array position.
		remove.pressed.connect(_remove_support.bind(selected_skill_id, support_id))
		remove.icon = Emblem.ICONS.get(support_id)
		remove.expand_icon = true
		remove.add_theme_constant_override("icon_max_width", 26)
		box.add_child(remove)


func _add_support(support_id: String) -> void:
	var cast: Dictionary = _state.get_skill_cast(selected_skill_id)
	if not bool(cast.get("ok", false)):
		feedback.emit("无法添加辅助：%s" % str(cast.get("error", "技能编译失败")))
		return
	var reason: String = _state.support_reason(selected_skill_id, support_id)
	if not reason.is_empty():
		feedback.emit(reason)
		return
	if _state.add_skill_support(selected_skill_id, support_id):
		refresh()
		feedback.emit("%s已添加%s" % [str(GameData.SKILLS[selected_skill_id].name), str(Supports.get_definition(support_id).get("name", support_id))])
	else:
		refresh()
		feedback.emit("辅助未能添加；请检查当前技能配置")


func _remove_support(skill_id: String, support_id: String) -> void:
	if skill_id != selected_skill_id:
		feedback.emit("技能选择已变化，请确认当前辅助目标")
		return
	if support_id.is_empty() or not _state.remove_skill_support(skill_id, support_id):
		feedback.emit("该辅助已取下，配置未改变")
		return
	refresh()
	feedback.emit("已取下%s" % str(Supports.get_definition(support_id).get("name", support_id)))


func _label(text: String, stable_name: String, font_size: int, color: Color) -> Label:
	var result: Label = Label.new()
	result.name = stable_name
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PresentationTheme.ink(color))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _button(text: String, stable_name: String) -> Button:
	var result: Button = Button.new()
	result.name = stable_name
	result.text = text
	result.custom_minimum_size.y = 40
	result.focus_mode = Control.FOCUS_ALL
	return result


func _card() -> PanelContainer:
	var result: PanelContainer = PanelContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_stylebox_override("panel", PresentationTheme.panel(Color("f8ecd0"), Color("8c6b42")))
	return result
