extends Node2D

var study: Node2D
var font_resource: Font

func _ready() -> void:
	font_resource = load("res://assets/arena_sans.otf")

func _process(_delta: float) -> void:
	if study.debug_visible:
		queue_redraw()

func _draw() -> void:
	if font_resource == null:
		return
	draw_style_box(_panel(), Rect2(16, 672, 614, 32))
	draw_string(font_resource, Vector2(28, 694), "环境行走/遮挡测试 · 人物为静态图", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e8e2cf"))
	draw_string(font_resource, Vector2(838, 693), "WASD / 方向键   R 复位   F1 诊断", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e8e2cf"))
	if not study.debug_visible:
		return
	for collider in study.manifest.colliders:
		for polygon in collider.polygons:
			var outline: PackedVector2Array = study.points(polygon.screen_pixel)
			outline.append(outline[0])
			draw_polyline(outline, Color(1.0, 0.35, 0.14, 0.85), 1.25, true)
	for prop in study.prop_nodes.values():
		draw_circle(prop.position, 2.5, Color(0.3, 1.0, 0.75))
		draw_line(prop.position - Vector2(8, 0), prop.position + Vector2(8, 0), Color(0.3, 1.0, 0.75))
	draw_arc(study.player.position, study.player.RADIUS_PIXEL, 0, TAU, 48, Color(0.3, 0.8, 1), 1.5, true)
	draw_circle(study.player.position, 2.0, Color.WHITE)
	draw_style_box(_panel(), Rect2(16, 16, 662, 30))
	var line := "screen_pixel · 脚点 (%.1f, %.1f) · %s · 半径 %.2fpx · 固定场景" % [study.player.position.x, study.player.position.y, study.player.DIRECTION_NAMES[study.player.direction_index], study.player.RADIUS_PIXEL]
	draw_string(font_resource, Vector2(27, 37), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e8e2cf"))

func _panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.09, 0.83)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
