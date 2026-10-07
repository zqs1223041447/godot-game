class_name ExplorationMapLayout
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
	if not map_id is String or map_id not in ["old_garden", "broken_ruins", "sunwell_terrace", "ginkgo_arcade", "ruins_garden"]:
		return _failure("未知探索地图")
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.end.is_finite():
		return _failure("探索地图边界必须有限")
	if bounds.size.x < MINIMUM_SIZE.x or bounds.size.y < MINIMUM_SIZE.y:
		return _failure("探索地图边界不足，不能缩放固定布局")
	var names: Array[String] = ["西侧据点", "北侧据点", "东侧据点"]
	if map_id == "ruins_garden": names = ["西壁驻点", "北拱驻点", "东岩驻点"]
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
	var sites: Array = _site_centers(map_id)
	var counts: Array[int] = []
	counts.assign([3,5] if map_id in ["old_garden", "ruins_garden"] else [4,8])
	var camps: Array[Dictionary] = []
	var outposts: Array[Dictionary] = []
	var offsets: Array[Vector2] = [ENTRY, BOSS_CENTER]
	for index: int in range(CAMP_IDS.size()):
		var positions: Array[Vector2] = []
		for part: int in range(2):
			var center: Vector2 = sites[index*2+part]
			var ordinals: Array[int] = []
			var local_positions: Array[Vector2] = []
			for formation: Vector2 in _formation(counts[part]):
				var offset: Vector2 = center+formation
				positions.append(bounds.position+offset)
				local_positions.append(bounds.position+offset)
				offsets.append(offset);ordinals.append(positions.size())
			var sign_offset: Vector2 = center+Vector2(0,150)
			offsets.append_array([center,sign_offset])
			outposts.append({"id":CAMP_IDS[index]+"_"+str(part+1),"source_group":CAMP_IDS[index],
				"name":names[index]+" · "+str(part+1),"center":bounds.position+center,
				"sign_position":bounds.position+sign_offset,"root_count":counts[part],
				"ordinals":ordinals,"positions":local_positions})
		var first_center: Vector2 = bounds.position+Vector2(sites[index*2])
		camps.append({"id":CAMP_IDS[index],"name":names[index],"center":first_center,
			"sign_position":first_center+Vector2(0,150),"trigger_center":first_center,
			"trigger_radius":LANDMARK_RADIUS,"root_count":positions.size(),"positions":positions})
	var routes: Array[Dictionary] = []
	for line: Array in _route_lines(map_id):
		for index: int in range(1,line.size()):
			var from: Vector2 = line[index-1];var to: Vector2 = line[index]
			offsets.append_array([from,to])
			routes.append({"from":bounds.position+from,"to":bounds.position+to,"width":72.0})
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
		"landmarks": {"distribution_version":"route_outposts_v1","entry": bounds.position + ENTRY, "camps": camps,
			"outposts":outposts,"route_segments":routes,
			"boss": {"id": "rift_warden", "name": "裂隙守卫", "center": boss_center,
				"sign_position": boss_center + Vector2(-180, 150),
				"trigger_center": boss_center, "trigger_radius": LANDMARK_RADIUS}}}


static func _formation(count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var shapes: Dictionary = {
		3:[Vector2(0,-44),Vector2(-48,34),Vector2(52,28)],
		5:[Vector2(-84,0),Vector2(-34,-64),Vector2(38,-60),Vector2(88,8),Vector2(0,50)],
		4:[Vector2(-78,-20),Vector2(-25,43),Vector2(27,-40),Vector2(80,24)],
		8:[Vector2(-105,-28),Vector2(-66,-86),Vector2(8,-106),Vector2(80,-73),Vector2(108,0),Vector2(65,73),Vector2(-10,102),Vector2(-86,52)]}
	result.assign(shapes.get(count,[]))
	return result


static func _site_centers(map_id: String) -> Array:
	var sites: Dictionary = {
		"old_garden":[Vector2(1300,2000),Vector2(700,1080),Vector2(850,500),Vector2(1840,360),Vector2(2680,820),Vector2(2990,1750)],
		"broken_ruins":[Vector2(1320,2120),Vector2(670,1180),Vector2(1420,370),Vector2(1790,1150),Vector2(2760,2100),Vector2(3010,1120)],
		"sunwell_terrace":[Vector2(1340,2140),Vector2(650,1160),Vector2(1740,1350),Vector2(1810,420),Vector2(2920,2070),Vector2(3010,1220)],
		"ginkgo_arcade":[Vector2(1290,2100),Vector2(420,1080),Vector2(1120,750),Vector2(1820,470),Vector2(2690,1810),Vector2(3150,1320)]}
	if map_id == "ruins_garden":
		return [Vector2(1300,2000),Vector2(700,1080),Vector2(850,500),Vector2(1840,360),Vector2(2680,820),Vector2(2990,1750)]
	return sites.get(map_id,[]).duplicate()


static func _route_lines(map_id: String) -> Array:
	var routes: Dictionary = {
		"old_garden":[[ENTRY,Vector2(1300,2000),Vector2(2000,2000),Vector2(2990,1750),Vector2(2680,820),BOSS_CENTER],
			[Vector2(1300,2000),Vector2(650,1700),Vector2(700,1080),Vector2(850,500),Vector2(1840,360),Vector2(2680,820)],
			[Vector2(1300,2000),Vector2(1840,1300),Vector2(1840,360)]],
		"broken_ruins":[[ENTRY,Vector2(700,2100),Vector2(1320,2120),Vector2(1880,2180),Vector2(2760,2100),Vector2(3050,1680),Vector2(3010,1120),BOSS_CENTER],
			[ENTRY,Vector2(650,1800),Vector2(670,1180),Vector2(700,350),Vector2(1420,370),Vector2(1840,370),BOSS_CENTER],
			[Vector2(1320,2120),Vector2(1740,1850),Vector2(1790,1150),Vector2(1840,370)],
			[Vector2(1790,1150),Vector2(2230,720),Vector2(2720,720),Vector2(3010,1120)]],
		"sunwell_terrace":[[ENTRY,Vector2(650,2100),Vector2(1340,2140),Vector2(1790,2140),Vector2(2920,2070),Vector2(3010,1220),Vector2(2910,500),BOSS_CENTER],
			[ENTRY,Vector2(650,1160),Vector2(650,500),Vector2(1810,420),Vector2(2910,500)],
			[Vector2(1790,2140),Vector2(1740,1350),Vector2(1810,420)],
			[Vector2(650,1160),Vector2(650,1350),Vector2(1740,1350),Vector2(3010,1220)]],
		"ginkgo_arcade":[[ENTRY,Vector2(570,1800),Vector2(1290,2100),Vector2(1940,2020),Vector2(2690,1810),Vector2(3150,1320),Vector2(3250,750),BOSS_CENTER],
			[Vector2(570,1800),Vector2(420,1080),Vector2(460,720),Vector2(1120,750),Vector2(1820,470),Vector2(2530,470),BOSS_CENTER],
			[Vector2(420,1080),Vector2(1120,1320),Vector2(1120,750)],
			[Vector2(1820,470),Vector2(2520,750),Vector2(2530,1810),Vector2(2690,1810)]]}
	if map_id == "ruins_garden":
		return [[ENTRY,Vector2(1300,2000),Vector2(2000,2000),Vector2(2990,1750),Vector2(2680,820),BOSS_CENTER],
			[Vector2(1300,2000),Vector2(650,1700),Vector2(700,1080),Vector2(850,500),Vector2(1840,360),Vector2(2680,820)],
			[Vector2(1300,2000),Vector2(1840,1300),Vector2(1840,360)]]
	return routes.get(map_id,[]).duplicate(true)


static func description(map_id: String) -> String:
	var descriptions: Dictionary = {
		"ruins_garden": "遗迹断墙、石拱与岩石共享原生碰撞轮廓；沿草土和旧石路绕行。六处3或5怪驻点分布于庭园，24普通根怪与首领入场时全部在场；可先挑战首领，清理全部怪物及后代后完成。首领庭园缠印锁定玩家起手位置：先离开内圈，再进入环内或继续远离外环；两段不追踪。",
		"old_garden": "开阔的大庭院，六处大小不同的驻点沿开阔环线与中央通路分布。入图时24个普通根怪与首领全部在场，靠近后投入战斗；可先挑战首领。清理全部怪物及后代后完成。首领近身震地锁定起手位置，及时离开圆圈。",
		"broken_ruins": "两道错位长残墙划分探索路线，沿墙端绕行；墙体阻挡移动、弹体与视线。六处4或8怪驻点分列墙端与内廊；共36个普通根怪与首领入图全部在场，可自由选择顺序或先挑战首领；清理全部怪物及后代后完成。首领落印锁定你的起手位置。",
		"sunwell_terrace": "四座实体泉池形成宽阔的池间通道，阻挡移动、弹体与视线。六处4或8怪驻点分列池间十字与外环；西泉偏重壳与霜纹，北门混合编排，东阶偏掠行与雷纹。36个普通根怪与首领入图时全部在场，可自由探索或先挑战首领；清理全部怪物及后代后完成。首领两次回响均锁定起手位置。",
		"ginkgo_arcade": "中央花圃与两座银杏基台形成内外绕行路线，阻挡移动、弹体与视线。六处4或8怪驻点沿内外廊分布，共36个普通根怪与首领入图时全部在场，可自由探索或先挑战首领；清理全部怪物及后代后完成。回廊震击锁定起手位置，先震击内圈，再攻击外环；可先退后进或继续远离，也可借花圃阻断视线。",
	}
	return str(descriptions.get(map_id, ""))


static func _failure(reason: String) -> Dictionary:
	var walls: Array[Rect2] = []
	return {"ok": false, "reason": reason, "landmarks": {}, "walls": walls, "obstacle_style": ""}
