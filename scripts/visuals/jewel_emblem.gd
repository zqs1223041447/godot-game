class_name JewelEmblem
extends Control
## Reuses the inventory silhouette for jewel pickers, socket previews and details.
const Art = preload("res://scripts/visuals/equipment_art.gd")
var jewel: Dictionary = {}:
	set(value):
		jewel = value.duplicate(true)
		queue_redraw()
var inset: float = 3.0:
	set(value):
		inset = maxf(0.0, value)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if jewel.is_empty():
		return
	var entry: Dictionary = jewel.duplicate(true)
	entry["kind"] = "jewel"
	var padding: float = minf(inset, minf(size.x, size.y) * 0.2)
	Art.draw_item(self, entry, Rect2(Vector2.ZERO, size).grow(-padding))
