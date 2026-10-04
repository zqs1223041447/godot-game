class_name EncounterControls
extends PanelContainer
## Embeddable draft selection only. The owner decides where and when to admit it.

signal encounter_requested(ids_copy: Array[String])

const Catalog = preload("res://scripts/encounters/encounter_catalog.gd")
const Compiler = preload("res://scripts/encounters/encounter_compiler.gd")
const Design = preload("res://scripts/visuals/visual_theme.gd")

var font_scale: float = 1.0:
	set(value):
		font_scale = value
		Design.apply_font_scale(self, font_scale)

var _selected_ids: Array[String] = []
var _disabled_reason: String = ""
var _selection_error: String = ""
var _options: Dictionary = {}
var _preview: Label
var _status: Label
var _confirm: Button
var _integration: Label

class ChoiceButton extends Button:
	func _make_custom_tooltip(text: String) -> Object:
		return EncounterControls.wrapped_tooltip(self,text)

class ChoiceCheckBox extends CheckBox:
	func _make_custom_tooltip(text: String) -> Object:
		return EncounterControls.wrapped_tooltip(self,text)

static func wrapped_tooltip(source: Control, text: String) -> Label:
	var label := Label.new()
	label.name = "TooltipLabel"
	label.theme_type_variation = "TooltipLabel"
	var font: Font = source.get_theme_font("font","TooltipLabel")
	var size: int = source.get_theme_font_size("font_size","TooltipLabel")
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Design.TEXT)
	label.text = text
	var width: float = source.get_viewport_rect().size.x if source.is_inside_tree() else 1280.0
	label.custom_minimum_size.x = minf(maxf(1.0,width-48.0),minf(420.0,maxf(120.0,font.get_multiline_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x)))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _init() -> void:
	name = "EncounterControls"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme = Design.create_theme()
	theme.set_color("font_focus_color","Button",Design.TEXT)
	theme.set_color("font_focus_color","CheckBox",Design.TEXT)
	# Checkboxes use the existing paper/button materials, ink and focus outline.
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckBox", theme.get_stylebox(state, "Button"))
	for color: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		theme.set_color(color, "CheckBox", theme.get_color(color, "Button"))
	add_theme_stylebox_override("panel", Design.panel(Design.PANEL, Design.BORDER, 4, 1, 8.0))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	body.add_child(_label("遭遇挑战", "EncounterTitle", 16, Design.TEXT))
	_integration = _label("未集成 · 仅提交选择请求", "EncounterIntegration", 12, Design.MUTED)
	body.add_child(_integration)
	var metadata: Dictionary = Catalog.metadata()
	for definition: Dictionary in metadata.definitions:
		_add_option(body, definition)
	body.add_child(_label("参数风险 · 难度尚未评估", "EncounterRisk", 12, Design.MUTED))
	_preview = _label("", "EncounterPreview", 14, Design.TEXT)
	body.add_child(_preview)
	_status = _label("", "EncounterStatus", 13, Design.GOLD)
	body.add_child(_status)
	_confirm = ChoiceButton.new()
	_confirm.name = "EncounterConfirm"
	_confirm.text = "确认选择"
	_confirm.custom_minimum_size.y = 36
	_confirm.add_theme_font_size_override("font_size", 15)
	_confirm.pressed.connect(_request)
	body.add_child(_confirm)
	Design.apply_font_scale(self, font_scale)
	set_context([])


func show_run_contract() -> void:
	(find_child("EncounterTitle",true,false) as Label).text = "本轮挑战"
	_integration.text = "本轮选择 · 确认后重开 · 不持久保存 · 无额外奖励"
	_confirm.text = "确认并重开本轮"


## May be called before adding to the tree. Invalid input fails closed until replaced.
func set_context(selected_ids: Variant, disabled_reason: String = "") -> bool:
	var detached: Variant = selected_ids.duplicate(true) if selected_ids is Array else selected_ids
	var compiled: Dictionary = Compiler.compile(detached)
	_disabled_reason = disabled_reason
	_selection_error = str(compiled.error)
	_selected_ids.clear()
	if compiled.ok:
		_selected_ids.assign(compiled.profile.modifier_ids.duplicate(true))
	_refresh()
	return bool(compiled.ok)


func get_selected_ids() -> Array[String]:
	return _selected_ids.duplicate(true)


func _add_option(body: VBoxContainer, metadata: Dictionary) -> void:
	var id: String = str(metadata.id)
	var compiled: Dictionary = Compiler.compile([id])
	var definition: Dictionary = compiled.profile.definitions[0]
	
	var option := ChoiceCheckBox.new()
	option.name = "EncounterOption_" + id
	option.text = str(metadata.name)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size.y = 32
	option.add_theme_font_size_override("font_size", 15)
	option.toggled.connect(_toggle.bind(id))
	body.add_child(option)
	_options[id] = option
	# Definitions already carry units. Flat armour and base-health shield must not be formatted as multipliers.
	body.add_child(_label(str(definition.description), "EncounterDescription_" + id, 12, Design.MUTED))


func _toggle(pressed: bool, id: String) -> void:
	if not _disabled_reason.is_empty() or not _selection_error.is_empty():
		_refresh()
		return
	var candidate: Array[String] = get_selected_ids()
	if pressed:
		candidate.append(id)
	else:
		candidate.erase(id)
	set_context(candidate, _disabled_reason)


func _refresh() -> void:
	var blocked: bool = not _disabled_reason.is_empty() or not _selection_error.is_empty()
	for id: String in _options:
		var option: CheckBox = _options[id]
		option.set_pressed_no_signal(_selected_ids.has(id))
		option.disabled = blocked
		option.tooltip_text = _disabled_reason if not _disabled_reason.is_empty() else _selection_error
	_confirm.disabled = blocked
	var reasons: PackedStringArray = []
	if not _selection_error.is_empty():
		reasons.append(_selection_error)
	if not _disabled_reason.is_empty():
		reasons.append(_disabled_reason)
	_status.text = "\n".join(reasons)
	_status.visible = not reasons.is_empty()
	_confirm.tooltip_text = _status.text
	if not _selection_error.is_empty():
		_preview.text = "选择无效，请由上层重新设置。"
		return
	var profile: Dictionary = Compiler.compile(_selected_ids).profile
	var heading: String = "普通遭遇（无挑战）" if _selected_ids.is_empty() else \
		"已选择 %d / %d 条" % [_selected_ids.size(), Catalog.metadata().max_modifiers]
	_preview.text = selection_summary(heading, profile.definitions)


static func selection_summary(heading: String, definitions: Array) -> String:
	var lines := PackedStringArray([heading])
	for definition: Dictionary in definitions:
		lines.append(str(definition.get("description", "")))
	return "\n".join(lines)


func _request() -> void:
	# Guard again: manually emitted pressed signals must also respect owner locks.
	if not _disabled_reason.is_empty() or not _selection_error.is_empty():
		return
	var compiled: Dictionary = Compiler.compile(get_selected_ids())
	if not compiled.ok:
		_selection_error = str(compiled.error)
		_refresh()
		return
	var ids_copy: Array[String] = []
	ids_copy.assign(compiled.profile.modifier_ids.duplicate(true))
	encounter_requested.emit(ids_copy)


func _label(copy: String, stable_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = stable_name
	label.text = copy
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
