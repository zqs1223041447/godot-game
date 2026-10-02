class_name PassiveData
extends RefCounted
## Original radial constellation. Geometry and links are deterministic and planar.
## Rings provide alternate routes; spoke paths branch into six distinct disciplines.

const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Balance = preload("res://scripts/mechanics/passive_balance_adapter.gd")
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
	"global_increased": "全局伤害提高", "projectile_increased": "投射物伤害提高",
	"elemental_increased": "元素伤害提高", "area_increased": "范围伤害提高",
	"spell_increased": "法术伤害提高", "fire_increased": "火焰伤害提高",
	"cold_increased": "冰霜伤害提高", "lightning_increased": "闪电伤害提高",
	"attack_elemental_increased": "攻击元素伤害提高",
	"attack_speed_increased": "普通攻击速度提高", "move_speed_increased": "移动速度提高",
	"mana_regen_increased": "魔力恢复速度提高",
}
static var _nodes: Dictionary = {}
static var _edges: Array = []
static var _presentation_revision: int = -1


static func get_nodes() -> Dictionary:
	_ensure_graph()
	_refresh_presentations()
	return _nodes


static func get_node_mechanisms(id: String) -> Array[String]:
	_ensure_graph()
	var result: Array[String] = []
	if _nodes.has(id):
		result.assign(_nodes[id]["mechanism_ids"])
	return result


static func get_node_stats(id: String) -> Dictionary:
	# Gameplay reads registry definitions live, never the UI's derived stats field.
	return Registry.resolve_grants(get_node_mechanisms(id), "player")["stats"]


static func get_allocated_stats(ids: Array[String]) -> Dictionary:
	var grants: Array[String] = []
	for id: String in ids:
		grants.append_array(get_node_mechanisms(id))
	return Balance.cap_player_passives(Registry.resolve_grants(grants, "player")["stats"])


static func get_node_description(id: String) -> String:
	get_nodes()
	return str(_nodes.get(id, {}).get("description", ""))


static func _refresh_presentations() -> void:
	if _presentation_revision == Registry.get_revision():
		return
	for id: String in _nodes:
		var node: Dictionary = _nodes[id]
		# Compatibility projection for existing tree widgets, not numeric authority.
		node["stats"] = get_node_stats(id)
		if node["type"] not in ["start", "socket"]:
			node["description"] = describe_stats(node["stats"])
	_presentation_revision = Registry.get_revision()


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
		var amount: String = str(snappedf(value, 0.00001))
		var unit: String = " / 秒" if stat in ["attack_speed", "mana_regen", "shield_regen"] else ""
		if stat.ends_with("_increased"):
			amount = str(snappedf(value * 100.0, 0.01))
			unit = "%"
		lines.append("%s +%s%s" % [STAT_LABELS.get(stat, stat), amount, unit])
	return "\n".join(lines)


static func _ensure_graph() -> void:
	if not _nodes.is_empty():
		return
	_nodes[START_ID] = {
		"id": START_ID, "name": "启明之核", "type": "start", "position": Vector2.ZERO,
		"mechanism_ids": [], "stats": {}, "description": "旅程的起点，免费且永久激活。沿连线逐点分配天赋。\n同类天赋加成合计受安全上限约束；装备与珠宝额外结算。",
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
				var mechanisms: Array[String] = []
				var override_id: String = Balance.node_override(id)
				if kind != "socket":
					mechanisms.append(override_id if not override_id.is_empty() else _mechanism_for(sector_index, ring, index, kind == "notable"))
				var display_name: String = _name_for(sector_index, ring, index, kind)
				if not override_id.is_empty():
					display_name = str(Registry.get_definition(override_id).get("name", display_name))
				_nodes[id] = {
					"id": id, "name": display_name, "type": kind,
					"position": Vector2(cos(angle), sin(angle)) * float(ring * 170),
					"mechanism_ids": mechanisms, "stats": {},
					"description": "激活后可镶嵌一颗基础珠宝，获得全部词缀。" if kind == "socket" else "",
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


static func _mechanism_for(sector: int, ring: int, index: int, notable: bool) -> String:
	var variant: int = (ring + index) % 3
	var small: Array[String] = [
		"ember_power" if variant != 1 else "ember_fervor",
		"grove_vitality" if variant != 1 else "grove_guard",
		"tide_capacity" if variant != 1 else "tide_flow",
		"gale_alacrity" if variant != 1 else "gale_stride",
		"aegis_capacity" if variant != 1 else "aegis_recovery",
		"prism_vigor" if variant == 0 else ("prism_reserve" if variant == 1 else "prism_recovery"),
	]
	var major: Array[String] = [
		"ember_mastery", "grove_mastery", "tide_mastery", "gale_mastery", "aegis_mastery", "prism_mastery",
	]
	return major[sector] if notable else small[sector]


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
