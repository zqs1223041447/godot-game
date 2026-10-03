class_name DockVisualStyle
extends RefCounted
## Local, original book-and-brass styling for the two buildcraft docks.
## No game state, layout rules or input ownership lives in this palette.
const INK := Color("3d3327")
const MUTED := Color("776951")
const PAPER := Color("ede3cc")
const PAPER_ALT := Color("e6dac0")
const BRASS := Color("ab8b55")
const RULE := Color("c2ac80")
const LEATHER := Color("534137")
const IVORY := Color("f3e9d2")

static func surface(fill: Color = PAPER, inset: float = 7.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = RULE
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

static func action(hovered: bool = false) -> StyleBoxFlat:
	var style := surface(Color("f5ecd8") if hovered else PAPER_ALT, 6.0)
	style.border_color = BRASS if hovered else RULE
	return style

static func inset_slot(hovered: bool = false) -> StyleBoxFlat:
	var style := surface(Color("eee5d2") if hovered else Color("ded1b6"), 2.0)
	style.border_color = BRASS if hovered else Color("b09a73")
	style.border_width_bottom = 2
	return style

static func style_action(control: Button, point_size: int = 11) -> void:
	control.add_theme_font_size_override("font_size", point_size)
	control.add_theme_color_override("font_color", INK)
	control.add_theme_color_override("font_hover_color", INK)
	control.add_theme_stylebox_override("normal", action())
	control.add_theme_stylebox_override("hover", action(true))
	control.add_theme_stylebox_override("pressed", surface(Color("d3c19e"),6.0))
	control.add_theme_stylebox_override("disabled", surface(Color("e4dac5"),6.0))
	control.add_theme_color_override("font_disabled_color",Color("9a8e77"))

static func bold_font(base: Font) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	font.variation_embolden = 0.5
	return font
