class_name MapCampLayout
extends RefCounted
## Fixed world-space encounter landmarks. Collision remains MapGeometry's job.
## Larger arenas preserve the same offsets; smaller arenas are not rescaled.
const MINIMUM_SIZE := Vector2(1840.0, 710.0)
const TRIGGER_RADIUS := 64.0
const CAMP_IDS: Array[String] = ["camp_west", "camp_north", "camp_east"]
const CAMP_NAMES: Array[String] = ["西侧据点", "北侧据点", "东侧据点"]


static func layout(map_id: Variant, bounds: Rect2) -> Dictionary:
	if not map_id is String or map_id not in ["old_garden", "broken_ruins", "sunwell_terrace"]:
		return _rejected("未知据点地图")
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.end.is_finite():
		return _rejected("据点地图边界必须有限")
	if bounds.size.x < MINIMUM_SIZE.x or bounds.size.y < MINIMUM_SIZE.y:
		return _rejected("据点地图边界不足，不能缩放固定布局")
	var garden: bool = map_id == "old_garden"
	var centers: Array[Vector2] = []
	centers.assign([Vector2(290, 170), Vector2(920, 130), Vector2(1550, 170)] if garden else [Vector2(270, 150), Vector2(920, 150), Vector2(1570, 150)])
	var triggers: Array[Vector2] = []
	triggers.assign([Vector2(290, 590), Vector2(920, 550), Vector2(1550, 590)] if garden else [Vector2(270, 570), Vector2(920, 570), Vector2(1570, 570)])
	var names: Array[String] = CAMP_NAMES
	if map_id == "sunwell_terrace":
		centers.assign([Vector2(290, 160), Vector2(920, 130), Vector2(1550, 540)])
		triggers.assign([Vector2(290, 590), Vector2(920, 550), Vector2(1550, 120)])
		names = ["西泉据点", "北门据点", "东阶据点"]
	var rows: Array[float] = []
	rows.assign([-28.0, 28.0] if garden else [-56.0, 0.0, 56.0])
	var origin := bounds.position
	var camps: Array[Dictionary] = []
	var relative_points: Array[Vector2] = [Vector2(920, 670)]
	for index: int in range(CAMP_IDS.size()):
		var positions: Array[Vector2] = []
		for y: float in rows:
			for x: float in [-84.0, -28.0, 28.0, 84.0]:
				var offset := centers[index] + Vector2(x, y)
				positions.append(origin + offset)
				relative_points.append(offset)
		relative_points.append_array([centers[index], triggers[index]])
		camps.append({"id": CAMP_IDS[index], "name": names[index],
			"center": origin + centers[index], "trigger_center": origin + triggers[index],
			"trigger_radius": TRIGGER_RADIUS, "root_count": positions.size(), "positions": positions})
	var boss_center := Vector2(920, 355) if garden else Vector2(1530, 320)
	var boss_trigger := Vector2(920, 670) if garden else Vector2(1530, 650)
	if map_id == "sunwell_terrace":
		boss_center = Vector2(920, 355)
		boss_trigger = Vector2(920, 670)
	relative_points.append_array([boss_center, boss_trigger])
	# A finite but enormous origin can erase formation offsets in Vector2's
	# float precision. Reject that input instead of returning overlapping roots.
	for offset: Vector2 in relative_points:
		var point := origin + offset
		if not point.is_finite() or (point - origin).distance_to(offset) > 0.01:
			return _rejected("据点地图坐标精度不足")
	return {"ok": true, "reason": "", "landmarks": {"entry": origin + Vector2(920, 670),
		"camps": camps, "boss": {"id": "rift_warden", "name": "裂隙守卫",
			"center": origin + boss_center, "trigger_center": origin + boss_trigger,
			"trigger_radius": TRIGGER_RADIUS}}}


## Inclusive intersection of the actual movement segment and a trigger disk.
## Endpoint-only checks would miss a 175-unit dash through a 128-unit disk.
static func trigger_crossed(previous: Vector2, current: Vector2, center: Vector2, radius: float) -> bool:
	if not previous.is_finite() or not current.is_finite() or not center.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	# Scalar doubles avoid Vector2 length_squared overflow for finite coordinates.
	var dx: float = float(current.x) - float(previous.x)
	var dy: float = float(current.y) - float(previous.y)
	var cx: float = float(center.x) - float(previous.x)
	var cy: float = float(center.y) - float(previous.y)
	var length_squared: float = dx * dx + dy * dy
	var fraction: float = clampf((cx * dx + cy * dy) / length_squared, 0.0, 1.0) if length_squared > 0.0 else 0.0
	var nearest_x: float = cx - dx * fraction
	var nearest_y: float = cy - dy * fraction
	return sqrt(nearest_x * nearest_x + nearest_y * nearest_y) <= radius


static func _rejected(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "landmarks": {}}
