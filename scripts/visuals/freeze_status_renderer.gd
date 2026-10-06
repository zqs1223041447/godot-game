class_name FreezeStatusRenderer
extends RefCounted
## Restrained ivory ice facets, visible in low effects mode; no extra nodes.
static func primitives(statuses: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not statuses is Array: return result
	var seen := {}
	for state: Variant in statuses:
		if result.size() >= 100: break
		if not state is Dictionary or not state.get("position") is Vector2: continue
		if state.get("target_kind", "") != "monster" or not state.get("target_id") is int: continue
		if typeof(state.get("remaining_seconds")) not in [TYPE_INT, TYPE_FLOAT]: continue
		if not state.position.is_finite() or not is_finite(float(state.remaining_seconds)) or float(state.remaining_seconds) <= 0.0 or seen.has(state.target_id): continue
		seen[state.target_id] = true
		var p: Vector2 = state.position + Vector2(-14,-19)
		result.append({"points":PackedVector2Array([p+Vector2(0,-5),p+Vector2(3,0),p+Vector2(0,5),p+Vector2(-3,0),p+Vector2(0,-5)]),"color":Color("d6e0dc")})
	return result
static func draw(canvas: CanvasItem, statuses: Variant, _effects: int = 2) -> void:
	for mark: Dictionary in primitives(statuses):
		canvas.draw_colored_polygon(mark.points, Color(0.45,0.51,0.54,0.65))
		canvas.draw_polyline(mark.points, mark.color, 1.5, true)
