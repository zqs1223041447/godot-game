class_name BurnStatusRenderer
extends RefCounted
## Small deterministic embers; no gameplay reads beyond supplied status records.
const MAX_TARGETS := 101
static func primitives(statuses: Variant, effects: int = 2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not statuses is Array or statuses.size() > MAX_TARGETS: return result
	var seen: Dictionary = {}
	for state: Variant in statuses:
		if not state is Dictionary or not state.get("position") is Vector2: continue
		if state.get("target_kind", "") not in ["player", "monster"] or not state.get("target_id") is int: continue
		if typeof(state.get("remaining_seconds")) not in [TYPE_INT, TYPE_FLOAT]: continue
		if not state.position.is_finite() or not is_finite(float(state.remaining_seconds)) or float(state.remaining_seconds) <= 0.0: continue
		var key := "%s:%s" % [str(state.get("target_kind", "")), str(state.get("target_id", -1))]
		if seen.has(key): continue
		seen[key] = true
		var ink := Color("897966") if bool(state.get("immune", false)) else Color("bd693c")
		var count := 1 if effects <= 0 else 2 if effects == 1 else 3
		for index: int in range(count):
			var p: Vector2 = state.position + Vector2(-10 + index * 9, -15 - (index % 2) * 6)
			result.append({"points":PackedVector2Array([p + Vector2(-2, 3), p + Vector2(0, -4), p + Vector2(3, 3)]), "color":Color(ink, 0.8)})
	return result
static func draw(canvas: CanvasItem, statuses: Variant, effects: int = 2) -> void:
	for mark: Dictionary in primitives(statuses, effects):
		canvas.draw_colored_polygon(mark.points, mark.color)
