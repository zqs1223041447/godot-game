class_name AmbushTrapRenderer
extends RefCounted
## At most three quiet stone sigils. No nodes, particles, or full trigger rings.
static func primitives(statuses: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not statuses is Array: return result
	var seen: Dictionary = {}
	for state: Variant in statuses:
		if result.size() >= 3: break
		if not state is Dictionary or not state.get("position") is Vector2 or not state.get("id") is int: continue
		if not state.position.is_finite() or not state.get("armed") is bool: continue
		if typeof(state.get("remaining_seconds")) not in [TYPE_INT, TYPE_FLOAT]: continue
		if not is_finite(float(state.remaining_seconds)) or float(state.remaining_seconds) <= 0.0 or seen.has(state.id): continue
		seen[state.id] = true
		var p: Vector2 = state.position
		var armed: bool = state.armed
		result.append({"position":p,"points":PackedVector2Array([p+Vector2(0,-12),p+Vector2(15,0),p+Vector2(0,12),p+Vector2(-15,0),p+Vector2(0,-12)]),"color":Color("bd955c") if armed else Color("8e8573"),"armed":armed})
	return result
static func draw(canvas: CanvasItem, statuses: Variant, _effects: int = 2) -> void:
	for mark: Dictionary in primitives(statuses):
		canvas.draw_colored_polygon(mark.points, Color(0.24,0.20,0.14,0.7))
		canvas.draw_polyline(mark.points, mark.color, 1.8, true)
		var p: Vector2 = mark.position
		canvas.draw_line(p+Vector2(-7,0),p+Vector2(7,0),mark.color,1.5,true)
		canvas.draw_line(p+Vector2(0,-6),p+Vector2(0,6),mark.color,1.5,true)
		if mark.armed: canvas.draw_circle(p,2.5,Color("e9c581"))
