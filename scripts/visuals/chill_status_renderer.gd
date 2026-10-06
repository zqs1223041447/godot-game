class_name ChillStatusRenderer
extends RefCounted
## One ivory snowflake above the player; no particles or extra scene nodes.
static func primitives(statuses: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not statuses is Array: return result
	for state: Variant in statuses:
		if not state is Dictionary or state.get("target_kind", "") != "player" or state.get("target_id", -1) != 0: continue
		if not state.get("position") is Vector2: continue
		if typeof(state.get("remaining_seconds")) not in [TYPE_INT, TYPE_FLOAT]: continue
		if not state.position.is_finite() or not is_finite(float(state.remaining_seconds)) or float(state.remaining_seconds) <= 0.0: continue
		var p: Vector2 = state.position + Vector2(-14, -21)
		for direction: Vector2 in [Vector2(0, 5), Vector2(4, 2.5), Vector2(4, -2.5)]:
			result.append({"from":p-direction,"to":p+direction,"color":Color("d6e0dc"),"width":1.6})
		break
	return result
static func draw(canvas: CanvasItem, statuses: Variant, _effects: int = 2) -> void:
	for mark: Dictionary in primitives(statuses):
		canvas.draw_line(mark.from, mark.to, mark.color, mark.width, true)
