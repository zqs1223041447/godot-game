class_name StaticArenaLayer
extends Node2D
## Retained canvas commands for the immutable arena; no simulation/RNG access.
const EnvironmentArt = preload("res://scripts/visuals/fantasy_environment.gd")
var ARENA: Rect2 = Rect2()
var draw_count: int = 0
var _font: Font
func configure(bounds: Rect2, font_resource: Font) -> void:
	if ARENA == bounds and _font == font_resource:
		return
	ARENA = bounds
	_font = font_resource
	queue_redraw()
func _draw() -> void:
	draw_count += 1
	EnvironmentArt.draw(self)
