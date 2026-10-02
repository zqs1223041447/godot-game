class_name VisualTheme
extends RefCounted
## Original rift-forge design language: charcoal stone, oxidized teal, brass.
const TEXT := Color("eee9dd")
const MUTED := Color("a9b5b3")
const ACCENT := Color("78d9ce")
const GOLD := Color("d9b779")
const PANEL := Color("152122")
const BORDER := Color("455754")

static func panel(bg: Color = PANEL, line: Color = BORDER, radius: int = 6, border: int = 1, padding: float = 12.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = line
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.65
	style.content_margin_bottom = padding * 0.65
	style.shadow_color = Color(0.01, 0.018, 0.018, 0.24)
	style.shadow_size = 5
	return style

static func create_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/arena_sans.otf")
	theme.default_font_size = 16
	for type: String in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "PopupMenu", "TooltipLabel"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_disabled_color", type, Color("7d8b88"))
	for type: String in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, panel(Color("243130"), BORDER))
		theme.set_stylebox("hover", type, panel(Color("304441"), ACCENT))
		theme.set_stylebox("pressed", type, panel(Color("234944"), ACCENT, 6, 2))
		theme.set_stylebox("disabled", type, panel(Color("192423"), Color("34413f")))
		theme.set_stylebox("focus", type, panel(Color(0,0,0,0), GOLD, 6, 2, 0))
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_stylebox("panel", "PopupMenu", panel(Color("162623"), GOLD))
	theme.set_stylebox("panel", "TooltipPanel", panel(Color("101b1b"), GOLD))
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_stylebox("normal", "LineEdit", panel(Color("101b1b"), BORDER))
	theme.set_stylebox("focus", "LineEdit", panel(Color("172b28"), ACCENT))
	theme.set_stylebox("background", "ProgressBar", panel(Color("0a1213"), BORDER, 3, 1, 0))
	theme.set_constant("separation", "HBoxContainer", 9)
	theme.set_constant("separation", "VBoxContainer", 9)
	var track := panel(Color("0e1818"), Color("20312d"), 3, 0, 3)
	var grab := panel(Color("657c71"), Color("94b8a6"), 3, 0, 3)
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
