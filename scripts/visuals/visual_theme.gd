class_name VisualTheme
extends RefCounted
## Approved grimoire style: warm parchment, brown ink, burgundy, painted spells.
const Frame = preload("res://scripts/visuals/material_frame.gd")
const TEXT := Color("3b281b")
const MUTED := Color("69523a")
const ACCENT := Color("52623b")
const GOLD := Color("79571f")
const PANEL := Color("f1deb3")
const BORDER := Color("8c6b42")

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
		theme.set_color("font_hover_color", type, Color("3b281b"))
		theme.set_color("font_pressed_color", type, TEXT)
		theme.set_color("font_disabled_color", type, Color("82725b"))
	for type: String in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, panel(Color("f8ecd0"), BORDER))
		theme.set_stylebox("hover", type, panel(Color("fff2d5"), ACCENT))
		theme.set_stylebox("pressed", type, panel(Color("ead3a2"), ACCENT, 6, 2))
		theme.set_stylebox("disabled", type, panel(Color("d9c8a5"), Color("9b8560")))
		theme.set_stylebox("focus", type, panel(Color(0,0,0,0), GOLD, 6, 2, 0))
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_stylebox("panel", "AcceptDialog", panel())
	theme.set_color("title_color", "Window", TEXT)
	theme.set_stylebox("panel", "PopupMenu", panel(Color("f1deb3"), GOLD))
	theme.set_stylebox("hover", "PopupMenu", panel(Color("f8ecd0"), GOLD))
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_selected_color", "LineEdit", Color("f8ecd0"))
	theme.set_color("selection_color", "LineEdit", Color("7a2f29"))
	theme.set_stylebox("panel", "TooltipPanel", panel(Color("f8ecd0"), GOLD))
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_color("font_placeholder_color", "LineEdit", Color("7e6847"))
	theme.set_stylebox("normal", "LineEdit", panel(Color("f8ecd0"), BORDER))
	theme.set_stylebox("focus", "LineEdit", panel(Color("f8ecd0"), ACCENT))
	theme.set_stylebox("background", "ProgressBar", panel(Color("38261d"), BORDER, 3, 1, 0))
	theme.set_constant("separation", "HBoxContainer", 9)
	theme.set_constant("separation", "VBoxContainer", 9)
	var track := panel(Color("d2bb92"), Color("9c8153"), 3, 0, 3)
	var grab := panel(Color("947044"), Color("c4a267"), 3, 0, 3)
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
			var target_size: int = roundi(float(control.get_meta("base_font_size")) * multiplier)
			if control.get_theme_font_size("font_size") != target_size:
				control.add_theme_font_size_override("font_size", target_size)
	for child: Node in node.get_children():
		apply_font_scale(child, multiplier)

static func ink(color: Color) -> Color:
	# Semantic accents authored for the old dark surface stay readable on paper.
	return color.darkened(0.52) if color.get_luminance()>0.34 else color

static func bookmark(selected: bool, padding: float = 12.0) -> StyleBox:
	return panel(Color("7a2f29") if selected else Color("f8ecd0"), Color("ba9148") if selected else BORDER, 6, 2 if selected else 1, padding)
