class_name KillRewardPolicy
extends RefCounted
## Pure reward decisions. No actors, lineage ledger, RNG, state or save writes.
## Routes belong to admitted map birth records, never mutable actor hints.
const Flasks = preload("res://scripts/items/flask_catalog.gd")

static func resolve_route(enemy: Dictionary, in_map: bool, birth_records: Dictionary) -> Dictionary:
	if not in_map:
		return {"ok":true, "reason":"", "route":"standard"}
	var record: Variant = birth_records.get(int(enemy.get("root_id", 0)), {})
	if not record is Dictionary or record.is_empty() or not record.get("spawn_key") is String or not enemy.get("map_spawn_key") is String or record.spawn_key != enemy.map_spawn_key:
		return {"ok":false, "reason":"地图怪物来源记录无效，不能结算奖励"}
	if not record.get("reward_route") is String or record.reward_route != "standard":
		return {"ok":false, "reason":"地图掉落路径尚未实装，不能回退为普通掉落"}
	return {"ok":true, "reason":"", "route":record.reward_route}

static func plan(route: String, enemy: Dictionary, rewarded: bool, demo: bool,
		reward_kills: int, test_profile: bool) -> Dictionary:
	if route != "standard":
		return {"ok":false, "reason":"地图掉落路径尚未实装，不能回退为普通掉落"}
	# Preserve the executor's original short circuit: rewardless descendants and
	# demo actors do not need XP/rarity payloads to finish their death effects.
	if not rewarded or demo:
		return {"ok":true, "reason":"", "route":route, "eligible":false,
			"reward_kills":reward_kills, "charge_flasks":false,
			"xp":0, "normal_xp":false, "equipment":false, "jewel":false,
			"gem":false, "flask":false, "normal_milestone":false,
			"special_jewel":false, "pickup":false}
	var next_count: int = reward_kills + 1
	var rarity: String = str(enemy.get("rarity", ""))
	return {"ok":true, "reason":"", "route":route, "eligible":true,
		"reward_kills":next_count, "charge_flasks":true,
		"xp":int(enemy.get("xp_reward", 0)), "normal_xp":not test_profile,
		"equipment":next_count % 8 == 0 or rarity in ["rare", "boss"],
		"jewel":next_count % 20 == 0,
		"gem":test_profile and next_count % 30 == 0,
		"flask":test_profile and next_count % Flasks.REWARD_INTERVAL == 0,
		"normal_milestone":not test_profile,
		"special_jewel":rarity == "boss", "pickup":next_count % 4 == 0}

## Inspect the actual post-XP count: add_normal_root_xp can decline a write.
static func milestone_due(reward_plan: Dictionary, normal_root_kills: int) -> bool:
	return bool(reward_plan.normal_milestone) and normal_root_kills % 30 == 0
