class_name VisualSettings
extends RefCounted
## Presentation preferences never alter combat coordinates, rolls, or build saves.
const PATH := "user://visual_settings.cfg"
const UI_SCALES: Array[float] = [0.9, 1.0, 1.1]
const FONT_SCALES: Array[float] = [1.0, 1.1, 1.2]
var ui_scale: float = 1.0
var font_scale: float = 1.0
var effects_level: int = 2
var damage_numbers: bool = true
var motion: bool = true

func load_settings(path: String = PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	ui_scale = _allowed(config.get_value("display", "ui_scale", 1.0), UI_SCALES, 1.0)
	font_scale = _allowed(config.get_value("display", "font_scale", 1.0), FONT_SCALES, 1.0)
	var raw: Variant = config.get_value("display", "effects_level", 2)
	effects_level = clampi(int(raw), 0, 2) if raw is int else 2
	damage_numbers = config.get_value("display", "damage_numbers", true) == true
	motion = config.get_value("display", "motion", true) == true

func save_settings(path: String = PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "ui_scale", ui_scale)
	config.set_value("display", "font_scale", font_scale)
	config.set_value("display", "effects_level", effects_level)
	config.set_value("display", "damage_numbers", damage_numbers)
	config.set_value("display", "motion", motion)
	return config.save(path)

static func _allowed(value: Variant, values: Array[float], fallback: float) -> float:
	if value is float or value is int:
		for candidate: float in values:
			if is_equal_approx(float(value), candidate):
				return candidate
	return fallback
