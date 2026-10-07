extends RefCounted
## Authored exploration world, independent of the historical small camp arena.
## Trigger fields remain compatible landmark metadata; they never spawn actors.
const WORLD_BOUNDS := Rect2(42.0, 104.0, 3600.0, 2400.0)
const MINIMUM_SIZE := Vector2(3600.0, 2400.0)
const CAMP_IDS: Array[String] = ["camp_west", "camp_north", "camp_east"]
const CAMP_CENTERS: Array[Vector2] = [Vector2(950, 1300), Vector2(1900, 600), Vector2(2800, 1580)]
const ENTRY := Vector2(320, 2080)
## Keep the complete initial roster beyond the default 800-unit auto-targeting
## range, so entering the world does not wake a group before the player moves.
const ENTRY_CLEARANCE := 850.0
const BOSS_CENTER := Vector2(3180, 320)
const LANDMARK_RADIUS := 64.0


static func layout(map_id: Variant, bounds: Rect2) -> Dictionary:
	if not map_id is String or map_id not in ["old_garden", "broken_ruins", "sunwell_terrace", "ginkgo_arcade"]:
		return _failure("未知探索地图")
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.end.is_finite():
		return _failure("探索地图边界必须有限")
	if bounds.size.x < MINIMUM_SIZE.x or bounds.size.y < MINIMUM_SIZE.y:
		return _failure("探索地图边界不足，不能缩放固定布局")
	var names: Array[String] = ["西侧据点", "北侧据点", "东侧据点"]
	var relative_walls: Array[Rect2] = []
	var obstacle_style := ""
	if map_id == "broken_ruins":
		# Two staggered long walls leave broad routes at both ends.
		relative_walls.assign([Rect2(1120, 500, 100, 1260), Rect2(2380, 900, 100, 1100)])
	elif map_id == "sunwell_terrace":
		names = ["西泉据点", "北门据点", "东阶据点"]
		obstacle_style = "spring_basin"
		relative_walls.assign([Rect2(980, 780, 540, 360), Rect2(2080, 780, 540, 360),
			Rect2(980, 1560, 540, 360), Rect2(2080, 1560, 540, 360)])
	elif map_id == "ginkgo_arcade":
		names = ["西叶据点", "北廊据点", "东荫据点"]
		obstacle_style = "ginkgo_planters"
		relative_walls.assign([Rect2(1300, 1050, 1000, 480), Rect2(640, 820, 280, 280),
			Rect2(2700, 940, 280, 280)])
	var rows: Array[float] = []
	rows.assign([-28.0, 28.0] if map_id == "old_garden" else [-56.0, 0.0, 56.0])
	var camps: Array[Dictionary] = []
	var offsets: Array[Vector2] = [ENTRY, BOSS_CENTER]
	for index: int in range(CAMP_IDS.size()):
		var positions: Array[Vector2] = []
		for y: float in rows:
			for x: float in [-84.0, -28.0, 28.0, 84.0]:
				var offset := CAMP_CENTERS[index] + Vector2(x, y)
				positions.append(bounds.position + offset)
				offsets.append(offset)
		offsets.append(CAMP_CENTERS[index])
		var center := bounds.position + CAMP_CENTERS[index]
		camps.append({"id": CAMP_IDS[index], "name": names[index], "center": center,
			"sign_position": center + Vector2(0, 220),
			"trigger_center": center, "trigger_radius": LANDMARK_RADIUS,
			"root_count": positions.size(), "positions": positions})
	var walls: Array[Rect2] = []
	for wall: Rect2 in relative_walls:
		offsets.append_array([wall.position, wall.end])
		walls.append(Rect2(bounds.position + wall.position, wall.size))
	# Do not silently lose formation spacing at extreme finite origins.
	for offset: Vector2 in offsets:
		var point := bounds.position + offset
		if not point.is_finite() or (point - bounds.position).distance_to(offset) > 0.01:
			return _failure("探索地图坐标精度不足")
	var boss_center := bounds.position + BOSS_CENTER
	return {"ok": true, "reason": "", "walls": walls, "obstacle_style": obstacle_style,
		"landmarks": {"entry": bounds.position + ENTRY, "camps": camps,
			"boss": {"id": "rift_warden", "name": "裂隙守卫", "center": boss_center,
				"sign_position": boss_center + Vector2(-180, 150),
				"trigger_center": boss_center, "trigger_radius": LANDMARK_RADIUS}}}


static func description(map_id: String) -> String:
	var descriptions: Dictionary = {
		"old_garden": "开阔的大庭院，自由探索西、北、东三处怪群。入图时24个普通根怪与首领全部在场，靠近后投入战斗；可先挑战首领。清理全部怪物及后代后完成。首领近身震地锁定起手位置，及时离开圆圈。",
		"broken_ruins": "两道错位长残墙划分探索路线，沿墙端绕行；墙体阻挡移动、弹体与视线。入图时三处怪群共36个普通根怪与首领全部在场，可自由选择顺序或先挑战首领；清理全部怪物及后代后完成。首领落印锁定你的起手位置。",
		"sunwell_terrace": "四座实体泉池形成宽阔的池间通道，阻挡移动、弹体与视线。西泉偏重壳与霜纹，北门混合编排，东阶偏掠行与雷纹。36个普通根怪与首领入图时全部在场，可自由探索或先挑战首领；清理全部怪物及后代后完成。首领两次回响均锁定起手位置。",
		"ginkgo_arcade": "中央花圃与两座银杏基台形成内外绕行路线，阻挡移动、弹体与视线。三处怪群共36个普通根怪与首领入图时全部在场，可自由探索或先挑战首领；清理全部怪物及后代后完成。回廊震击锁定首领起手位置，可退圈或借花圃阻断视线。",
	}
	return str(descriptions.get(map_id, ""))


static func _failure(reason: String) -> Dictionary:
	var walls: Array[Rect2] = []
	return {"ok": false, "reason": reason, "landmarks": {}, "walls": walls, "obstacle_style": ""}
