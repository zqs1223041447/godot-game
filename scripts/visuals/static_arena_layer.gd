class_name StaticArenaLayer
extends Node2D
## Retained canvas commands for the immutable arena; no simulation/RNG access.
const EnvironmentArt = preload("res://scripts/visuals/fantasy_environment.gd")
const CampSigns = preload("res://scripts/visuals/map_camp_signs.gd")
var _camp_signs: Node2D
var ARENA: Rect2 = Rect2()
var draw_count: int = 0
var _font: Font
var _geometry: Dictionary = {}
func configure(bounds: Rect2, font_resource: Font) -> void:
	if ARENA == bounds and _font == font_resource:
		return
	ARENA = bounds
	_font = font_resource
	_update_signs()
	queue_redraw()
func _draw() -> void:
	draw_count += 1
	EnvironmentArt.draw(self)

func set_geometry(value: Dictionary) -> void:
	if _geometry == value: return
	_geometry = value.duplicate(true)
	_update_signs()
	queue_redraw()

func _update_signs() -> void:
	if _camp_signs == null:
		_camp_signs = CampSigns.new()
		add_child(_camp_signs)
	_camp_signs.configure(_geometry.get("landmarks", {}), _font)

func set_encounter_state(camps: Array, boss_phase: String) -> void:
	_update_signs()
	_camp_signs.set_encounter_state(camps, boss_phase)

func world_geometry() -> Dictionary:
	return _geometry.duplicate(true)
