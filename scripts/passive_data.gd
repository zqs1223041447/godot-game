class_name PassiveData
extends RefCounted
## Original radial constellation. Geometry and links are deterministic and planar.
## Rings provide alternate routes; spoke paths branch into six distinct disciplines.

const START_ID: String = "origin"
const RING_COUNTS: Array[int] = [1, 2, 4, 6, 8, 9]
const SECTORS: Array[Dictionary] = [
	{"id": "ember", "name": "烬火 · 威力", "color": Color("ee9279"), "angle": -90.0},
	{"id": "grove", "name": "苍林 · 生机", "color": Color("99c57e"), "angle": -30.0},
	{"id": "tide", "name": "星潮 · 魔力", "color": Color("7cb8ed"), "angle": 30.0},
	{"id": "gale", "name": "流岚 · 迅捷", "color": Color("81d5bb"), "angle": 90.0},
	{"id": "aegis", "name": "辉壁 · 护盾", "color": Color("c3a1ee"), "angle": 150.0},
	{"id": "prism", "name": "棱光 · 均衡", "color": Color("e3c578"), "angle": 210.0},
]
const STAT_LABELS: Dictionary = {
	"damage": "伤害", "max_health": "最大生命", "max_mana": "最大魔力",
	"max_shield": "最大护盾", "attack_speed": "攻击速度", "move_speed": "移动速度",
	"mana_regen": "魔力恢复", "shield_regen": "护盾恢复",
}
static var _nodes: Dictionary = {}
static var _edges: Array = []


static func get_nodes() -> Dictionary:
	_ensure_graph()
	return _nodes


static func get_edges() -> Array:
	_ensure_graph()
	return _edges


static func get_neighbors(node_id: String) -> Array[String]:
	_ensure_graph()
	var result: Array[String] = []
	if _nodes.has(node_id):
		result.assign(_nodes[node_id]["neighbors"])
	return result


static func node_id(sector_id: String, ring: int, index: int) -> String:
	return "%s_%d_%d" % [sector_id, ring, index]


static func describe_stats(stats: Dictionary) -> String:
	var lines: PackedStringArray = []
	for stat: String in stats:
		var value: float = float(stats[stat])
		var amount: String = str(snappedf(value, 0.01))
		var unit: String = " / 秒" if stat in ["attack_speed", "mana_regen", "shield_regen"] else ""
		lines.append("%s +%s%s" % [STAT_LABELS.get(stat, stat), amount, unit])
	return "\n".join(lines)


static func _ensure_graph() -> void:
	if not _nodes.is_empty():
		return
	_nodes[START_ID] = {
		"id": START_ID, "name": "启明之核", "type": "start", "position": Vector2.ZERO,
		"stats": {}, "description": "旅程的起点，免费且永久激活。沿连线逐点分配天赋。",
		"sector": "origin", "color": Color("f2dab0"), "neighbors": [],
	}
	for sector_index: int in range(SECTORS.size()):
		var sector: Dictionary = SECTORS[sector_index]
		var sector_id: String = sector["id"]
		for ring_index: int in range(RING_COUNTS.size()):
			var count: int = RING_COUNTS[ring_index]
			var ring: int = ring_index + 1
			for index: int in range(count):
				var id: String = node_id(sector_id, ring, index)
				var angle: float = deg_to_rad(float(sector["angle"]) - 30.0 + (float(index) + 0.5) * 60.0 / float(count))
				var kind: String = "small"
				if (ring == 3 and index == 0) or (ring == 5 and index == 3):
					kind = "socket"
				elif (ring == 3 and index == 2) or (ring == 4 and index == 3) or (ring == 5 and index == 6) or (ring == 6 and index == 4):
					kind = "notable"
				var stats: Dictionary = {} if kind == "socket" else _stats_for(sector_index, ring, index, kind == "notable")
				var display_name: String = _name_for(sector_index, ring, index, kind)
				_nodes[id] = {
					"id": id, "name": display_name, "type": kind,
					"position": Vector2(cos(angle), sin(angle)) * float(ring * 170),
					"stats": stats, "description": "激活后可镶嵌一颗基础珠宝，获得全部词缀。" if kind == "socket" else describe_stats(stats),
					"sector": sector_id, "color": sector["color"], "neighbors": [],
				}
	# Every ring is a continuous loop, including six cross-discipline boundaries.
	for ring_index: int in range(RING_COUNTS.size()):
		var ring_nodes: Array[String] = []
		for sector: Dictionary in SECTORS:
			for index: int in range(RING_COUNTS[ring_index]):
				ring_nodes.append(node_id(sector["id"], ring_index + 1, index))
		for index: int in range(ring_nodes.size()):
			_link(ring_nodes[index], ring_nodes[(index + 1) % ring_nodes.size()])
	# Monotonically map outward nodes to inward nodes. Edges never cross.
	for sector: Dictionary in SECTORS:
		var sector_id: String = sector["id"]
		_link(START_ID, node_id(sector_id, 1, 0))
		for ring_index: int in range(1, RING_COUNTS.size()):
			var count: int = RING_COUNTS[ring_index]
			var previous_count: int = RING_COUNTS[ring_index - 1]
			for index: int in range(count):
				var previous_index: int = mini(previous_count - 1, int((float(index) + 0.5) * float(previous_count) / float(count)))
				_link(node_id(sector_id, ring_index + 1, index), node_id(sector_id, ring_index, previous_index))


static func _link(first: String, second: String) -> void:
	if _nodes[first]["neighbors"].has(second):
		return
	_nodes[first]["neighbors"].append(second)
	_nodes[second]["neighbors"].append(first)
	_edges.append([first, second])


static func _stats_for(sector: int, ring: int, index: int, notable: bool) -> Dictionary:
	var variant: int = (ring + index) % 3
	var small: Array[Dictionary] = [
		{"damage": 2.0} if variant != 1 else {"damage": 1.0, "attack_speed": 0.025},
		{"max_health": 9.0} if variant != 1 else {"max_health": 5.0, "max_shield": 3.0},
		{"max_mana": 7.0} if variant != 1 else {"max_mana": 3.0, "mana_regen": 0.4},
		{"attack_speed": 0.045, "move_speed": 2.0} if variant != 1 else {"move_speed": 5.0},
		{"max_shield": 7.0} if variant != 1 else {"max_shield": 3.0, "shield_regen": 0.55},
		{"damage": 1.0, "max_health": 4.0} if variant == 0 else ({"max_mana": 4.0, "max_shield": 4.0} if variant == 1 else {"mana_regen": 0.3, "shield_regen": 0.4}),
	]
	var major: Array[Dictionary] = [
		{"damage": 7.0, "attack_speed": 0.08},
		{"max_health": 30.0, "max_shield": 8.0},
		{"max_mana": 22.0, "mana_regen": 1.2},
		{"attack_speed": 0.16, "move_speed": 12.0},
		{"max_shield": 22.0, "shield_regen": 1.7},
		{"damage": 3.0, "max_health": 12.0, "max_mana": 8.0, "max_shield": 8.0},
	]
	return (major[sector] if notable else small[sector]).duplicate()


static func _name_for(sector: int, ring: int, index: int, kind: String) -> String:
	if kind == "socket":
		return "%s珠宝孔" % ("内环" if ring == 3 else "外环")
	var notable_names: Array[Array] = [
		["余烬之心", "炽烈回响", "焰冠", "烈星升腾"],
		["深根", "苍木之躯", "生息繁茂", "万叶庇护"],
		["潮汐储能", "澄澈思维", "星海脉动", "灵泉不息"],
		["随风而行", "迅捷节律", "乘岚", "流光疾影"],
		["凝光护体", "晶壁复苏", "辉盾之核", "不灭棱壁"],
		["谐振", "棱光交汇", "均衡法则", "万象共鸣"],
	]
	if kind == "notable":
		return notable_names[sector][ring - 3]
	var small_names: Array[String] = ["烬火", "苍林", "星潮", "流岚", "辉壁", "棱光"]
	return "%s · %d-%d" % [small_names[sector], ring, index + 1]
