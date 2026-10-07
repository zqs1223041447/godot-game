class_name StaticArenaLayer
extends Node2D
## Retained canvas commands for the immutable arena; no simulation/RNG access.
const EnvironmentArt = preload("res://scripts/visuals/fantasy_environment.gd")
const CampSigns = preload("res://scripts/visuals/map_camp_signs.gd")
const StudyGround = preload("res://scripts/visuals/study_ground_layer.gd")
class StudyMarks extends Node2D:
	var geometry: Dictionary = {}
	func update_geometry(value: Dictionary) -> void:
		if geometry == value: return
		geometry = value.duplicate(true); queue_redraw()
	func _draw() -> void:
		CampSigns.draw_ground(self, geometry.get("landmarks", {}))
		draw_rect(geometry.get("bounds", Rect2()), Color("596647"), false, 2.0)

var _camp_signs: Node2D
var ARENA: Rect2 = Rect2()
var draw_count: int = 0
var _font: Font
var _geometry: Dictionary = {}
var _study_ground: Node2D
var _study_marks: Node2D
var _study_ground_error := ""
func configure(bounds: Rect2, font_resource: Font) -> void:
	if ARENA == bounds and _font == font_resource:
		return
	ARENA = bounds
	_font = font_resource
	_update_signs()
	queue_redraw()
func _draw() -> void:
	draw_count += 1
	if is_instance_valid(_study_ground):
		# Child quad owns its shader. Marks, flags and module shadows keep their
		# normal materials; the old opaque tiled floor is not drawn underneath.
		draw_rect(ARENA.grow(600), Color("45543b"))
	else:
		EnvironmentArt.draw(self)

func set_geometry(value: Dictionary) -> void:
	if _geometry == value: return
	_geometry = value.duplicate(true)
	_update_study_ground()
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

func _update_study_ground() -> void:
	_study_ground_error = ""
	if _geometry.get("id", "") == "modular_study":
		if not is_instance_valid(_study_ground):
			_study_ground = StudyGround.new(); _study_ground.name = "StudyGround"
			add_child(_study_ground); move_child(_study_ground, 0)
		if _study_ground.configure(_geometry):
			if not is_instance_valid(_study_marks):
				_study_marks = StudyMarks.new(); _study_marks.name = "StudyGroundMarks"
				add_child(_study_marks); move_child(_study_marks, 1)
			_study_marks.update_geometry(_geometry)
			return
		_study_ground_error = str(_study_ground.diagnostics().error)
	# A different map or failed resource validation restores the whole original
	# retained environment, with no material left on this parent or on flags.
	for child: Node2D in [_study_ground, _study_marks]:
		if is_instance_valid(child): remove_child(child); child.queue_free()
	_study_ground = null; _study_marks = null
