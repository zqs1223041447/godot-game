class_name VisualTheme
extends RefCounted
## Classic magic-world materials: walnut, leather, aged bronze, muted runes.
const Frame = preload("res://scripts/visuals/material_frame.gd")
const TEXT := Color("eee2c7")
const MUTED := Color("b2aa94")
const ACCENT := Color("b8c891")
const GOLD := Color("d8b577")
const PANEL := Color("29291f")
const BORDER := Color("827354")

static func panel(bg: Color = PANEL, line: Color = BORDER, radius: int = 6, border: int = 1, padding: float = 12.0) -> StyleBox:
	var style: StyleBox
	if border == 0:
		var flat := StyleBoxFlat.new()
		flat.bg_color=bg
		flat.set_corner_radius_all(mini(radius,2))
		style=flat
	else:
		var material := Frame.new()
		material.bg_color=bg
		material.border_color=line
		material.border_width=border
		material.corner_cut=mini(radius,4)
		style=material
	style.content_margin_left=padding
	style.content_margin_right=padding
	style.content_margin_top=padding*0.65
	style.content_margin_bottom=padding*0.65
	return style

static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/arena_sans.otf")
	theme.default_font_size = 16
	for type: String in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "PopupMenu", "TooltipLabel"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_disabled_color", type, Color("928c77"))
	for type: String in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, panel(Color("3b382a"), BORDER))
		theme.set_stylebox("hover", type, panel(Color("4f5238"), ACCENT))
		theme.set_stylebox("pressed", type, panel(Color("4e5537"), ACCENT, 6, 2))
		theme.set_stylebox("disabled", type, panel(Color("27291f"), Color("575341")))
		theme.set_stylebox("focus", type, panel(Color(0,0,0,0), GOLD, 6, 2, 0))
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_stylebox("panel", "AcceptDialog", panel())
	theme.set_color("title_color", "Window", TEXT)
	theme.set_stylebox("panel", "PopupMenu", panel(Color("302e22"), GOLD))
	theme.set_stylebox("panel", "TooltipPanel", panel(Color("24251d"), GOLD))
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_stylebox("normal", "LineEdit", panel(Color("24251d"), BORDER))
	theme.set_stylebox("focus", "LineEdit", panel(Color("3c402c"), ACCENT))
	theme.set_stylebox("background", "ProgressBar", panel(Color("1b1b15"), BORDER, 3, 1, 0))
	theme.set_constant("separation", "HBoxContainer", 9)
	theme.set_constant("separation", "VBoxContainer", 9)
	var track := panel(Color("211f18"), Color("3c392b"), 3, 0, 3)
	var grab := panel(Color("8c8061"), Color("b9a77b"), 3, 0, 3)
	for type: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, grab)
		theme.set_stylebox("grabber_highlight", type, panel(ACCENT, ACCENT, 3, 0, 3))
	return theme

static func apply_font_scale(node: Node, multiplier: float) -> void:
	if node is Control:
		var control := node as Control
		if control.has_theme_font_size_override("font_size"):
			if not control.has_meta("base_font_size"):
				control.set_meta("base_font_size", control.get_theme_font_size("font_size"))
			control.add_theme_font_size_override("font_size", roundi(float(control.get_meta("base_font_size")) * multiplier))
	for child: Node in node.get_children():
		apply_font_scale(child, multiplier)
