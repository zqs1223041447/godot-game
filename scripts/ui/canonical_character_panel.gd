class_name CanonicalCharacterPanel
extends ScrollContainer
## Read-only derived character sheet. CanonicalGameState remains authoritative.

const ThemeStyle = preload("res://scripts/visuals/visual_theme.gd")

var model: RefCounted
var font_scale: float = 1.0:
	set(value):
		font_scale = clampf(value, 0.8, 1.6)
		if is_instance_valid(_body): ThemeStyle.apply_font_scale(_body, font_scale)

var refresh_generation: int = 0
var _dirty: bool = true
var _body: VBoxContainer
var _progress: Label
var _values: Dictionary = {}

const STAT_ROWS: Array[Dictionary] = [
	{"id":"strength","label":"力量","format":"whole"},
	{"id":"dexterity","label":"敏捷","format":"whole"},
	{"id":"intelligence","label":"智慧","format":"whole"},
	{"id":"max_health","label":"生命上限","format":"whole"},
	{"id":"max_mana","label":"法力上限","format":"whole"},
	{"id":"max_shield","label":"护盾上限","format":"whole"},
	{"id":"shield_recharge_rate","label":"护盾充能 / 秒","format":"decimal"},
	{"id":"shield_recharge_delay","label":"充能等待 / 秒","format":"decimal"},
	{"id":"life_regen","label":"生命回复 / 秒","format":"decimal"},
	{"id":"mana_regen","label":"法力回复 / 秒","format":"decimal"},
	{"id":"attack_speed","label":"攻击频率 / 秒","format":"decimal"},
	{"id":"move_speed","label":"移动速度","format":"decimal"},
	{"id":"accuracy","label":"命中值","format":"whole"},
	{"id":"evasion","label":"闪避值","format":"decimal"},
	{"id":"armour","label":"护甲","format":"decimal"},
	{"id":"fire_resistance","label":"火焰抗性","format":"resistance"},
	{"id":"cold_resistance","label":"冰冷抗性","format":"resistance"},
	{"id":"lightning_resistance","label":"闪电抗性","format":"resistance"},
]


func setup(state: RefCounted) -> void:
	model = state
	if _body == null: _build()
	if not model.changed.is_connected(_on_model_changed): model.changed.connect(_on_model_changed)
	if not visibility_changed.is_connected(_on_visibility_changed): visibility_changed.connect(_on_visibility_changed)
	_dirty = true
	refresh()


func refresh() -> void:
	if model == null or _body == null or not _dirty: return
	_progress.text = "Lv.%d   ·   经验 %d   ·   未用天赋点 %d" % [int(model.level), int(model.xp), int(model.talent_points)]
	var stats: Dictionary = model.get_stats()
	for row: Dictionary in STAT_ROWS:
		var id: String = str(row.id)
		var value: float = float(stats.get(id, 0.0))
		var formatted := ""
		match str(row.format):
			"whole": formatted = "%d" % roundi(value)
			"decimal": formatted = "%.2f" % value
			"percent": formatted = "%.1f%%" % (value * 100.0)
			"multiplier": formatted = "%.2f×" % value
			"resistance": formatted = "%.0f%%" % (clampf(value, 0.0, 0.75) * 100.0)
		_values[id].text = formatted
	_dirty = false
	refresh_generation += 1


func _on_model_changed() -> void:
	_dirty = true
	if is_visible_in_tree(): refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _dirty: refresh()


func _build() -> void:
	name = "CanonicalCharacterPanel"
	custom_minimum_size.y = 320.0
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body = VBoxContainer.new()
	_body.name = "CharacterSheetBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 9)
	add_child(_body)
	_progress = Label.new()
	_progress.name = "CharacterProgress"
	_progress.add_theme_font_size_override("font_size",11)
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress.add_theme_color_override("font_color", ThemeStyle.GOLD)
	_body.add_child(_progress)
	var grid := GridContainer.new()
	grid.name = "CharacterStatsGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	_body.add_child(grid)
	for row: Dictionary in STAT_ROWS:
		var card := PanelContainer.new()
		card.name = "CharacterStat_" + str(row.id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0.0, 46.0)
		card.add_theme_stylebox_override("panel", ThemeStyle.panel(Color("f8ecd0"), Color("8c6b42"), 5, 1, 6))
		grid.add_child(card)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 1)
		card.add_child(stack)
		var label := Label.new()
		label.text = str(row.label)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", ThemeStyle.MUTED)
		stack.add_child(label)
		var value := Label.new()
		value.name = "Value_" + str(row.id)
		value.add_theme_font_size_override("font_size", 16)
		value.add_theme_color_override("font_color", ThemeStyle.TEXT)
		stack.add_child(value)
		_values[str(row.id)] = value
		if row.id in ["accuracy","evasion"]: card.tooltip_text = "攻击命中率取决于目标闪避；法术不进行闪避判定。"
		elif row.id == "shield_recharge_rate": card.tooltip_text = "等待结束后的实际每秒护盾充能；换装或退款会更新速率。即时回盾另行结算。"
		elif row.id == "shield_recharge_delay": card.tooltip_text = "下一次有效损伤后的充能等待。闪避或零伤害不重置；已经开始的等待不随换装或退款改变。"
		elif row.id == "armour": card.tooltip_text = "护甲减伤随每次物理命中大小变化。"
		elif str(row.id).ends_with("_resistance"): card.tooltip_text = "显示当前有效抗性；元素抗性上限为75%。"
