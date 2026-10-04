class_name TelegraphRenderer
extends RefCounted
## Read-only ground artwork for copied TelegraphedAreaRuntime.state_for snapshots.
## No retained states, clocks, events, damage, transforms, or gameplay RNG.

const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const MAX_SOURCES: int = Profiles.MAX_ACTIVE
const MAX_PRIMITIVES_PER_SOURCE: int = 8
const MAX_PRIMITIVES: int = MAX_SOURCES * MAX_PRIMITIVES_PER_SOURCE
const MAX_POLYLINE_POINTS: int = 6
const TIME_EPSILON: float = 0.000000001
const SOIL: Color = Color("72503b")
const INK: Color = Color("493a2d")
const CHALK: Color = Color("cfaa72")
const CHARGED: Color = Color("d08a57")
const ASH: Color = Color("a79b80")


static func draw(canvas: CanvasItem, states: Variant, settings: Settings = null) -> void:
	if not is_instance_valid(canvas):
		return
	for primitive: Dictionary in primitives(states, settings):
		match primitive.kind:
			"circle":
				canvas.draw_circle(primitive.center, primitive.radius, primitive.color,
					primitive.filled, primitive.width, true)
			"polyline":
				canvas.draw_polyline(primitive.points, primitive.color, primitive.width, true)


## Circles keep the exact world-space center/radius; line geometry has <= 6 points.
## Oversized input is rejected as a whole, matching the runtime's source limit.
static func primitives(states: Variant, settings: Settings = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not states is Array or states.size() > MAX_SOURCES:
		return result
	var accepted: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw: Variant in states:
		var state: Dictionary = _read_state(raw)
		if state.is_empty() or seen.has(state.source_id):
			continue
		seen[state.source_id] = true
		accepted.append(state)
	accepted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.source_id) < int(b.source_id))
	var effects: int = clampi(settings.effects_level, 0, 2) if settings != null else 2
	var fills: Array[Dictionary] = []
	var boundaries: Array[Dictionary] = []
	var marks: Array[Dictionary] = []
	for state: Dictionary in accepted:
		_append_state(state, effects, fills, boundaries, marks)
	# Later floor tints cannot cover an earlier source's essential boundary.
	result.append_array(fills)
	result.append_array(boundaries)
	result.append_array(marks)
	return result


static func _read_state(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var source_id: Variant = raw.get("source_id")
	var center: Variant = raw.get("center")
	var phase: Variant = raw.get("phase")
	var elapsed: Variant = raw.get("elapsed")
	var profile: Variant = raw.get("profile")
	if not source_id is int or int(source_id) <= 0 or not center is Vector2 or not center.is_finite():
		return {}
	if not phase is String or phase not in ["windup", "recovery"] or not profile is Dictionary:
		return {}
	if not _number(elapsed) or float(elapsed) < 0.0:
		return {}
	# Read only these scalar fields, never copy or inspect a damage packet.
	var radius: Variant = profile.get("radius")
	var windup: Variant = profile.get("windup_seconds")
	var recovery: Variant = profile.get("recovery_seconds")
	if not _profile_number(radius, "radius") or not _profile_number(windup, "windup_seconds"):
		return {}
	if not _profile_number(recovery, "recovery_seconds"):
		return {}
	var age: float = float(elapsed)
	var windup_seconds: float = float(windup)
	var recovery_seconds: float = float(recovery)
	# Runtime.advance enters recovery as soon as age + epsilon reaches windup.
	if phase == "windup" and age + TIME_EPSILON >= windup_seconds:
		return {}
	if phase == "recovery" and age + TIME_EPSILON < windup_seconds:
		return {}
	if age + TIME_EPSILON >= windup_seconds + recovery_seconds:
		return {}
	var progress: float = clampf(age / windup_seconds, 0.0, 1.0) if phase == "windup" else \
		clampf((age - windup_seconds) / recovery_seconds, 0.0, 1.0)
	return {"source_id": int(source_id), "center": center, "radius": float(radius),
		"phase": phase, "progress": progress,
		"pattern": raw.get("visual_pattern", "") if raw.get("visual_pattern", "") in ["garden_slam", "ruins_mark", "ember_burn"] else "",
		"element": raw.get("visual_element", "") if raw.get("visual_element", "") in ["cold", "lightning"] else ""}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _profile_number(value: Variant, field: String) -> bool:
	return _number(value) and float(value) >= float(Profiles.LIMITS[field].minimum) \
		and float(value) <= float(Profiles.LIMITS[field].maximum)


static func _append_state(state: Dictionary, effects: int, fills: Array[Dictionary],
		boundaries: Array[Dictionary], marks: Array[Dictionary]) -> void:
	var radius: float = state.radius
	var progress: float = state.progress
	var winding: bool = state.phase == "windup"
	var fade: float = 1.0 if winding else (1.0 - progress) * (1.0 - progress)
	var pigment: Color = CHALK.lerp(CHARGED, progress) if winding else ASH
	if state.element == "cold": pigment = Color("b3c5c8").lerp(Color("77969f"), progress) if winding else ASH
	elif state.element == "lightning": pigment = Color("d5c68e").lerp(Color("ae884e"), progress) if winding else ASH
	if state.pattern == "ember_burn": pigment = Color("c8905b").lerp(Color("b7643e"), progress) if winding else ASH
	var fill_alpha: float = lerpf(0.035, 0.085, progress) if winding else 0.065 * fade
	fills.append(_circle(state, "ground_tint", Color(SOIL, fill_alpha), true, -1.0))
	var role: String = "danger_boundary" if winding else "recovery_boundary"
	boundaries.append(_circle(state, role, Color(INK, 0.78 * fade), false, minf(3.8, radius * 0.14)))
	boundaries.append(_circle(state, role, Color(pigment, 0.94 * fade), false, minf(1.5, radius * 0.07)))
	# A traced, angular stone rune conveys charge without a spinning clock-face ring.
	# Element shape sits clear of the player standing on the locked center.
	# It remains strictly inside the true radius and does not change collision.
	var rune_center: Vector2 = state.center if state.element.is_empty() and state.pattern != "ruins_mark" else state.center + Vector2(0, -radius * 0.63)
	var rune: PackedVector2Array = _rune(rune_center, minf(13.0, radius * 0.18), -0.13, state.element)
	if state.pattern == "garden_slam":
		rune = _boss_rune(rune_center, radius * 0.48, "garden_slam")
	elif state.pattern == "ruins_mark":
		rune = _boss_rune(rune_center, minf(16.0,radius * 0.21), "ruins_mark")
	elif state.pattern == "ember_burn":
		var p: Vector2 = state.center + Vector2(0, -radius * 0.6)
		rune = PackedVector2Array([p + Vector2(-7, 6), p + Vector2(-2, -3), p + Vector2(0, 2), p + Vector2(5, -9), p + Vector2(8, 6)])
	marks.append(_line(state, "rune_base", rune, Color(INK, 0.6 * fade), minf(3.0, radius * 0.1)))
	var charged: PackedVector2Array = _trace(rune, progress if winding else 1.0)
	if charged.size() >= 2:
		marks.append(_line(state, "rune_charge", charged, Color(pigment, 0.92 * fade), minf(1.6, radius * 0.06)))
	# Sparse, uneven earth cuts stay inside the circle and do not animate or emit RNG.
	var count: int = 0 if effects == 0 else 1 if effects == 1 else 3
	var angles: Array[float] = [-0.72, 1.44, 3.6]
	for index: int in range(count):
		var direction: Vector2 = Vector2.RIGHT.rotated(angles[index])
		var tangent: Vector2 = direction.orthogonal()
		var at: Vector2 = state.center + direction * radius * 0.82
		var size: float = minf(6.0, radius * 0.055)
		var cut := PackedVector2Array([at - tangent * size, at - direction * size * 0.65,
			at + tangent * size * 0.65 - direction * size * 0.2])
		marks.append(_line(state, "earth_mark", cut, Color(pigment, 0.5 * fade), minf(1.5, radius * 0.06)))


static func _circle(state: Dictionary, role: String, color: Color, filled: bool, width: float) -> Dictionary:
	return {"kind": "circle", "role": role, "source_id": state.source_id, "phase": state.phase,
		"center": state.center, "radius": state.radius, "color": color, "filled": filled, "width": width}


static func _line(state: Dictionary, role: String, points: PackedVector2Array, color: Color, width: float) -> Dictionary:
	return {"kind": "polyline", "role": role, "source_id": state.source_id, "phase": state.phase,
		"points": points, "color": color, "width": width}


static func _rune(center: Vector2, size: float, angle: float, element: String = "") -> PackedVector2Array:
	var points := PackedVector2Array()
	var shape: Array[Vector2] = [Vector2(-0.5, 0.6), Vector2(-0.5, -0.18), Vector2(0.0, -0.65),
		Vector2(0.5, -0.12), Vector2(0.12, 0.18), Vector2(0.5, 0.62)]
	if element == "cold": shape = [Vector2(-0.7,0),Vector2(0.0,-0.8),Vector2(0.7,0),Vector2(0,0.8),Vector2(-0.7,0),Vector2(0.7,0)]
	elif element == "lightning": shape = [Vector2(0.15,-0.9),Vector2(-0.5,0.0),Vector2(0.2,-0.1),Vector2(-0.1,0.9),Vector2(0.6,-0.2)]
	for point: Vector2 in shape:
		points.append(center + point.rotated(angle) * size)
	return points


static func _trace(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var traced := PackedVector2Array()
	if fraction <= 0.0:
		return traced
	var length: float = 0.0
	for index: int in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	var remaining: float = length * fraction
	traced.append(points[0])
	for index: int in range(1, points.size()):
		var segment: float = points[index - 1].distance_to(points[index])
		if remaining < segment:
			traced.append(points[index - 1].lerp(points[index], remaining / segment))
			break
		traced.append(points[index])
		remaining -= segment
	return traced


static func _boss_rune(center: Vector2, size: float, pattern: String) -> PackedVector2Array:
	# Angular stone cracks and a small offset seal; never extend past the true danger circle.
	var shape: Array[Vector2] = [Vector2(-0.9,0.35),Vector2(-0.4,0.1),Vector2(-0.15,0.3),Vector2(0.1,-0.15),Vector2(0.45,-0.05),Vector2(0.8,-0.4)]
	if pattern == "ruins_mark":
		shape = [Vector2(-0.7,-0.65),Vector2(0.7,-0.65),Vector2(0.7,0.35),Vector2(0,0.8),Vector2(-0.7,0.35),Vector2(-0.7,-0.65)]
	var result := PackedVector2Array()
	for point: Vector2 in shape: result.append(center+point*size)
	return result
