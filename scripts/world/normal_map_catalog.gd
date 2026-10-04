class_name NormalMapCatalog
extends RefCounted
## Pure, detached progression metadata. No save, inventory or RNG access.
const Maps = preload("res://scripts/world/map_catalog.gd")
const WAVES: Dictionary = {"old_garden": [1, 4, 8], "broken_ruins": [2, 5, 9]}
const LABELS: Array[String] = ["I", "II", "III"]
const COSTS: Array[int] = [0, 4, 8]
const BASE_REWARDS: Array[int] = [4, 8, 12]


static func definition(map_id: Variant, tier: Variant) -> Dictionary:
	if not map_id is String or not WAVES.has(map_id):
		return {}
	if not tier is int or tier < 1 or tier > 3:
		return {}
	var index: int = tier - 1
	return {"map_id": map_id, "tier": tier,
		"label": "%s · %s" % [Maps.MAPS[map_id].name, LABELS[index]],
		"wave": WAVES[map_id][index], "ordinary_target": Maps.MAPS[map_id].ordinary_target,
		"cost": COSTS[index], "base_reward": BASE_REWARDS[index]}


## best_completed belongs to this map, never the other map's progression.
static func tiers(map_id: Variant, best_completed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tier: int in range(1, 4):
		var row := definition(map_id, tier)
		if row.is_empty():
			return []
		row.unlocked = tier == 1 or best_completed >= tier - 1
		row.reason = "" if row.unlocked else "先完成本地图 %s" % LABELS[tier - 2]
		rows.append(row)
	return rows
