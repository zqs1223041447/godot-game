class_name GemIcon
extends Control
## Aspect-fit gem art inside the project's parchment-and-antique-bronze frame.
## Drawing is mouse-transparent so a parent slot keeps its normal click/drag behavior.

const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const FIXED_ICON_INSET: float = 6.0
const MIN_SIDE: float = 48.0
const FRAME_INK: Color = Color("8c6b42")
const PARCHMENT: Color = Color("f1deb3")
const PLACEHOLDER_INK: Color = Color("8b7558")
const MARK_GOLD: Color = Color("ba9148")

@export var texture: Texture2D:
	set(value):
		if texture == value:
			return
		texture = value
		queue_redraw()

@export var accessible_label: String = "宝石":
	set(value):
		accessible_label = value
		accessibility_name = value + "图标"

@export_enum("active", "support") var gem_role: String = "active":
	set(value):
		gem_role = "support" if value == "support" else "active"
		queue_redraw()

var _frame_style: StyleBox


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(MIN_SIDE, MIN_SIDE)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	accessibility_name = accessible_label + "图标"
	if _frame_style == null:
		_frame_style = PresentationTheme.panel(PARCHMENT, FRAME_INK, 4, 1, 0)
	queue_redraw()


## Configure the source art, accessible name, and active/support rune in one call.
func set_gem_icon(source: Texture2D, label: String = "宝石", role: String = "active") -> void:
	texture = source
	accessible_label = label
	gem_role = role


## Return the largest rectangle with the source aspect ratio that fits inside bounds.
static func aspect_fit_rect(source_size: Vector2, bounds: Rect2) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Rect2()
	var scale_factor: float = minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
	var fitted_size: Vector2 = source_size * scale_factor
	return Rect2(bounds.position + (bounds.size - fitted_size) * 0.5, fitted_size)


static func square_tile_rect(control_size: Vector2) -> Rect2:
	var side: float = minf(control_size.x, control_size.y)
	return Rect2((control_size - Vector2.ONE * side) * 0.5, Vector2.ONE * side) if side > 0.0 else Rect2()


static func image_fit_rect(control_size: Vector2, source_size: Vector2) -> Rect2:
	var tile: Rect2 = square_tile_rect(control_size)
	if tile.size.x <= 0.0 or tile.size.y <= 0.0:
		return Rect2()
	var inset: float = minf(FIXED_ICON_INSET, tile.size.x * 0.22)
	return aspect_fit_rect(source_size, tile.grow(-inset))


## Geometry shared by the neutral no-art mark and its layout checks.
static func empty_gem_points(bounds: Rect2) -> PackedVector2Array:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return PackedVector2Array()
	var center: Vector2 = bounds.get_center()
	var radius: float = minf(bounds.size.x, bounds.size.y) * 0.28
	return PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius * 0.78, -radius * 0.15),
		center + Vector2(0.0, radius),
		center - Vector2(radius * 0.78, radius * 0.15),
	])


static func marker_center(tile: Rect2) -> Vector2:
	return tile.position + Vector2(tile.size.x * 0.78, tile.size.y * 0.22)


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 0.0:
		return
	var tile: Rect2 = square_tile_rect(size)
	if _frame_style != null:
		draw_style_box(_frame_style, tile)
	else:
		draw_rect(tile, PARCHMENT, true)
		draw_rect(tile, FRAME_INK, false, 1.0, true)

	var inner_outline: Rect2 = tile.grow(-3.0)
	if inner_outline.size.x > 0.0 and inner_outline.size.y > 0.0:
		draw_rect(inner_outline, Color("a68759"), false, 0.75, true)

	if texture != null and texture.get_width() > 0 and texture.get_height() > 0:
		var fitted: Rect2 = image_fit_rect(size, texture.get_size())
		if fitted.size.x > 0.0 and fitted.size.y > 0.0:
			draw_texture_rect(texture, fitted, false)
	else:
		var inset: float = minf(FIXED_ICON_INSET, side * 0.22)
		_draw_empty_gem(tile.grow(-inset))

	_draw_corner_ticks(tile)
	_draw_marker(tile)


func _draw_empty_gem(bounds: Rect2) -> void:
	var points: PackedVector2Array = empty_gem_points(bounds)
	if points.size() != 4:
		return
	var center: Vector2 = bounds.get_center()
	var radius: float = minf(bounds.size.x, bounds.size.y) * 0.28
	for index: int in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], PLACEHOLDER_INK, 1.7, true)
	draw_line(points[0], center + Vector2(0.0, radius * 0.22), Color("b39a70"), 1.0, true)
	draw_circle(center, maxf(1.5, radius * 0.12), Color("b39a70"))


func _draw_corner_ticks(tile: Rect2) -> void:
	var tick: float = minf(5.0, tile.size.x * 0.08)
	var edge: float = 4.0
	var color: Color = Color("9b7b4b")
	for corner: Vector2 in [
		tile.position + Vector2(edge, edge),
		tile.position + Vector2(tile.size.x - edge, edge),
		tile.position + Vector2(edge, tile.size.y - edge),
		tile.end - Vector2(edge, edge),
	]:
		var horizontal_direction: float = 1.0 if corner.x < tile.get_center().x else -1.0
		var vertical_direction: float = 1.0 if corner.y < tile.get_center().y else -1.0
		draw_line(corner, corner + Vector2(tick * horizontal_direction, 0.0), color, 0.8, true)
		draw_line(corner, corner + Vector2(0.0, tick * vertical_direction), color, 0.8, true)


func _draw_marker(tile: Rect2) -> void:
	var radius: float = minf(4.0, tile.size.x * 0.07)
	var center: Vector2 = marker_center(tile)
	draw_circle(center, radius + 1.0, FRAME_INK)
	draw_circle(center, radius, Color("ead4a5"))
	if gem_role == "support":
		var offset: float = radius * 0.34
		var dot_radius: float = maxf(0.8, radius * 0.25)
		draw_line(center - Vector2(offset * 0.5, 0.0), center + Vector2(offset * 0.5, 0.0), MARK_GOLD, 1.0, true)
		draw_circle(center - Vector2(offset, 0.0), dot_radius, MARK_GOLD)
		draw_circle(center + Vector2(offset, 0.0), dot_radius, MARK_GOLD)
	else:
		var point: float = radius * 0.56
		draw_line(center + Vector2(-point, 0.0), center + Vector2(point, 0.0), MARK_GOLD, 1.0, true)
		draw_line(center + Vector2(0.0, -point), center + Vector2(0.0, point), MARK_GOLD, 1.0, true)
