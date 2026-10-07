class_name MapCampSigns
extends Node2D
## Retained wayfinding only. Simulation owns activation, spawning and completion.
var _landmarks: Dictionary = {}
var _states: Dictionary = {}
var _boss := "sealed"
var _font: Font
var draw_count := 0

func configure(landmarks: Dictionary, font_resource: Font) -> void:
	if _landmarks == landmarks and _font == font_resource: return
	_landmarks = landmarks.duplicate(true)
	_font = font_resource
	queue_redraw()

func set_encounter_state(camps: Array, boss_phase: String) -> void:
	var next: Dictionary = {}
	for camp: Dictionary in camps: next[str(camp.id)] = str(camp.state)
	if next == _states and _boss == boss_phase: return
	_states = next
	_boss = boss_phase
	queue_redraw()

func _draw() -> void:
	draw_count += 1
	var index := 0
	for camp: Dictionary in _landmarks.get("outposts", _landmarks.get("camps", [])):
		var state := str(_states.get(str(camp.id), "dormant"))
		_sign(Vector2(camp.get("sign_position", camp.get("trigger_center", camp.get("center", Vector2.ZERO)))), ["I", "II", "III", "IV", "V", "VI"][index % 6], state, false)
		index += 1
	var boss: Dictionary = _landmarks.get("boss", {})
	if not boss.is_empty():
		_sign(Vector2(boss.get("sign_position", boss.get("trigger_center", boss.get("center", Vector2.ZERO)))), "首领", "cleared" if _boss == "defeated" else "active" if _boss in ["ready", "active"] else "dormant", true)

func _sign(center: Vector2, caption: String, state: String, boss: bool) -> void:
	var cloth := Color("998768") if state in ["dormant", "resident"] else Color("af784a") if state == "active" else Color("748765")
	var width := 44.0 if boss else 32.0
	draw_line(center + Vector2(-width / 2, 8), center + Vector2(-width / 2, -37), Color("554936"), 4.0, true)
	var flag := PackedVector2Array([center + Vector2(-width / 2, -37), center + Vector2(width / 2 + 8, -37), center + Vector2(width / 2, -24), center + Vector2(width / 2 + 8, -11), center + Vector2(-width / 2, -11)])
	draw_colored_polygon(flag, cloth)
	flag.append(flag[0])
	draw_polyline(flag, Color("625039"), 1.5, true)
	if _font:
		draw_string(_font, center + Vector2(-width / 2 + 5, -17), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f1e4c3"))
	# A slate arrow guides approach without resembling a circular damage telegraph.
	var arrow := PackedVector2Array([center + Vector2(-17, 17), center + Vector2(0, 8), center + Vector2(17, 17), center + Vector2(0, 26)])
	draw_colored_polygon(arrow, Color("a59d82"))
	draw_line(center + Vector2(-11, 17), center + Vector2(0, 12), Color("ddd0ad"), 1.5, true)
	if state == "cleared":
		draw_polyline(PackedVector2Array([center + Vector2(-8, 16), center + Vector2(-2, 21), center + Vector2(9, 11)]), Color("40523c"), 3.0, true)
	elif boss and _boss == "sealed":
		draw_line(center + Vector2(-9, 11), center + Vector2(9, 23), Color("6a5642"), 2.0, true)
		draw_line(center + Vector2(9, 11), center + Vector2(-9, 23), Color("6a5642"), 2.0, true)

static func draw_ground(canvas: Node2D, landmarks: Dictionary) -> void:
	for camp: Dictionary in landmarks.get("outposts", landmarks.get("camps", [])):
		var center := Vector2(camp.center)
		# Flat, worn paving: decoration is not an unmodelled collision obstacle.
		canvas.draw_rect(Rect2(center - Vector2(122, 93), Vector2(244, 186)), Color(0.43, 0.37, 0.25, 0.10))
		for side: int in [-1, 1]:
			for y: int in [-1, 1]:
				var p := center + Vector2(side * 118, y * 90)
				canvas.draw_line(p, p + Vector2(-side * 35, 0), Color("897d61"), 5.0, true)
				canvas.draw_line(p, p + Vector2(0, -y * 22), Color("b0a17c"), 3.0, true)
	var boss: Dictionary = landmarks.get("boss", {})
	if not boss.is_empty():
		var p := Vector2(boss.center)
		canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-68, -42), p + Vector2(53, -47), p + Vector2(71, 32), p + Vector2(-52, 46)]), Color(0.70, 0.64, 0.49, 0.36))
		canvas.draw_polyline(PackedVector2Array([p + Vector2(-46, -30), p + Vector2(-8, -8), p + Vector2(3, 10), p + Vector2(48, 29)]), Color("857a60"), 2.0, true)
