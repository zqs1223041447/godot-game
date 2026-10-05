class_name ShockStatusRenderer
extends RefCounted
## One restrained status mark per affected actor, including low effects mode.
const MAX_TARGETS := 101
static func primitives(statuses: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not statuses is Array: return result
	var seen: Dictionary = {}
	for state: Variant in statuses:
		if result.size() >= MAX_TARGETS: break
		if not state is Dictionary or not state.get("position") is Vector2: continue
		if state.get("target_kind", "") not in ["player", "monster"] or not state.get("target_id") is int: continue
		if typeof(state.get("remaining_seconds")) not in [TYPE_INT, TYPE_FLOAT]: continue
		if not state.position.is_finite() or not is_finite(float(state.remaining_seconds)) or float(state.remaining_seconds) <= 0.0: continue
		var key := "%s:%s" % [str(state.target_kind), str(state.target_id)]
		if seen.has(key): continue
		seen[key] = true
		var p: Vector2 = state.position + Vector2(14, -21)
		result.append({"points":PackedVector2Array([p + Vector2(2,-5), p + Vector2(-3,0), p + Vector2(2,0), p + Vector2(-2,6)]), "color":Color("d7b765"), "width":1.8})
	return result
static func draw(canvas: CanvasItem, statuses: Variant, _effects: int = 2) -> void:
	for mark: Dictionary in primitives(statuses):
		canvas.draw_polyline(mark.points, mark.color, mark.width, true)
