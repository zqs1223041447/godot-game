class_name CombatFeedbackRenderer
extends RefCounted
## Read-only presentation of accepted resource loss. Never calculate damage here.
const View = preload("res://scripts/visuals/world_view.gd")
const MAX_ROWS := 48

static func amount_text(amount: float) -> String:
	if amount <= 0.0: return ""
	if amount < 0.01: return "<0.01"
	if amount < 1.0: return "%.2f" % amount
	if amount < 10.0: return "%.1f" % amount
	return str(roundi(amount))

static func presentation(row: Dictionary) -> Dictionary:
	var amount := float(row.get("amount", 0.0))
	var lifetime := float(row.get("lifetime", 0.75))
	var age := float(row.get("age", 0.0))
	if not is_finite(amount) or amount <= 0.0 or lifetime <= 0.0 or age >= lifetime: return {}
	var kind := str(row.get("kind", "hit"))
	var color := Color("ebdcb9")
	var font_size := 16
	var baseline := -18.0
	var text := amount_text(amount)
	if kind == "critical":
		color = Color("e2b05f")
		font_size = 19
		baseline = -37.0
		text += "!"
	elif kind == "burn":
		color = Color("d59b67")
		font_size = 15
		baseline = -54.0
		text = "燃 " + text
	if str(row.get("target_kind", "monster")) == "player":
		color = Color("e79b88")
		text = "-" + text
	var progress := clampf(age / lifetime, 0.0, 1.0)
	color.a = clampf((1.0 - progress) / 0.35, 0.0, 1.0)
	return {"text":text, "color":color, "font_size":font_size, "offset":Vector2(0, baseline - 12.0 * progress)}

static func draw(arena: Node2D, rows: Array, preferences: RefCounted) -> void:
	if not preferences.damage_numbers or arena._font == null: return
	var zoom := maxf(0.01, View.zoom_for(arena))
	for index in range(mini(MAX_ROWS, rows.size())):
		var row: Dictionary = rows[index]
		var style := presentation(row)
		if style.is_empty(): continue
		var pos: Vector2 = row.get("position", Vector2.ZERO)
		var text: String = style.text
		var color: Color = style.color
		var font_size := roundi(int(style.font_size) * float(preferences.font_scale))
		var offset: Vector2 = style.offset
		offset.x -= arena._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
		arena.draw_set_transform(pos, 0, Vector2.ONE / zoom)
		arena.draw_string_outline(arena._font, offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.09,0.07,0.04,color.a))
		arena.draw_string(arena._font, offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		arena.draw_set_transform(Vector2.ZERO)
