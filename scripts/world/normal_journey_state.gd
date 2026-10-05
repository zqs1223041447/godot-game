class_name NormalJourneyState
extends RefCounted
## Pure persistent normal-map progress. Combat actors, timers and RNG never belong here.
const Maps = preload("res://scripts/world/map_compiler.gd")
const Flasks = preload("res://scripts/items/flask_catalog.gd")
const MAX_KILLS := 1000000000
const MAX_SERIAL := 1000000000
const GEM_INTERVAL := 30
const FLASK_INTERVAL := 60
const LEGACY_MAP_IDS := ["old_garden", "broken_ruins"] # Frozen schema26..29 vocabulary.
const MAP_IDS := ["old_garden", "broken_ruins", "sunwell_terrace"]
const FIELDS := ["normal_root_kills", "best_tiers", "next_run_id", "active_run", "pending_map_reward", "claimed_gems", "claimed_flasks"]
const ACTIVE_FIELDS := ["run_id", "map_id", "tier", "normal_ids", "special_ids", "fee_paid"]
const PENDING_FIELDS := ["run_id", "map_id", "tier", "shards"]
## Schema26 freezes this sorted vocabulary. Future catalog additions cannot reroll an owed ordinal.
const GEM_DEFINITIONS := [
	"skill:bolt", "skill:chain", "skill:cleave", "skill:dash", "skill:frost",
	"skill:meteor", "skill:nova", "skill:shade_bolt", "skill:tornado", "skill:ward",
	"support:breadth", "support:chain_extension", "support:chain_reach", "support:cold_focus",
	"support:concentrate", "support:efficiency", "support:fire_focus", "support:focus",
	"support:heavy_projectiles", "support:lightning_focus", "support:lingering_chill",
	"support:physical_focus", "support:pierce", "support:quickcast", "support:swift_projectiles", "support:volley",
]


static func empty() -> Dictionary:
	var value := empty_legacy()
	value.best_tiers["sunwell_terrace"] = 0
	return value


static func empty_legacy() -> Dictionary:
	return {"normal_root_kills": 0, "best_tiers": {"old_garden": 0, "broken_ruins": 0},
		"next_run_id": 1, "active_run": {}, "pending_map_reward": {}, "claimed_gems": 0, "claimed_flasks": 0}


## JSON permits floating point numbers; accept only finite integral values within their domain.
## Pure planners and reason() still require real integers, never coercing their callers.
static func decode(raw: Variant) -> Dictionary:
	return _decode(raw, MAP_IDS)


static func decode_legacy(raw: Variant) -> Dictionary:
	return _decode(raw, LEGACY_MAP_IDS)


static func _decode(raw: Variant, map_ids: Array) -> Dictionary:
	if not _keys(raw, FIELDS): return {}
	var value: Dictionary = raw.duplicate(true)
	for field: String in ["normal_root_kills", "claimed_gems", "claimed_flasks"]:
		if not _decode_integer(value, field, 0, MAX_KILLS): return {}
	if not _decode_integer(value, "next_run_id", 1, MAX_SERIAL): return {}
	if not _keys(value.best_tiers, map_ids): return {}
	for id: String in map_ids:
		if not _decode_integer(value.best_tiers, id, 0, 3): return {}
	if not value.active_run is Dictionary or not value.pending_map_reward is Dictionary: return {}
	if not value.active_run.is_empty():
		if not _keys(value.active_run, ACTIVE_FIELDS): return {}
		if not _decode_integer(value.active_run, "run_id", 1, MAX_SERIAL): return {}
		if not _decode_integer(value.active_run, "tier", 1, 3): return {}
		if not _decode_integer(value.active_run, "fee_paid", 0, 8): return {}
	if not value.pending_map_reward.is_empty():
		if not _keys(value.pending_map_reward, PENDING_FIELDS): return {}
		if not _decode_integer(value.pending_map_reward, "run_id", 1, MAX_SERIAL): return {}
		if not _decode_integer(value.pending_map_reward, "tier", 1, 3): return {}
		if not _decode_integer(value.pending_map_reward, "shards", 4, 16): return {}
	return value if _reason(value, map_ids).is_empty() else {}


static func reason(journey: Variant) -> String:
	return _reason(journey, MAP_IDS)


static func reason_legacy(journey: Variant) -> String:
	return _reason(journey, LEGACY_MAP_IDS)


static func _reason(journey: Variant, map_ids: Array) -> String:
	if not _keys(journey, FIELDS): return "普通旅程结构无效"
	if not _integer(journey.normal_root_kills, 0, MAX_KILLS): return "普通根怪计数无效"
	if not _keys(journey.best_tiers, map_ids): return "地图层级记录无效"
	for id: String in map_ids:
		if not _integer(journey.best_tiers[id], 0, 3): return "地图层级记录无效"
	if not _integer(journey.next_run_id, 1, MAX_SERIAL): return "地图行程序号无效"
	if not _integer(journey.claimed_gems, 0, journey.normal_root_kills / GEM_INTERVAL): return "已领宝石序号无效"
	if not _integer(journey.claimed_flasks, 0, journey.normal_root_kills / FLASK_INTERVAL): return "已领药剂序号无效"
	if not journey.active_run is Dictionary or not journey.pending_map_reward is Dictionary: return "地图行程或待领奖励无效"
	if not journey.active_run.is_empty() and not journey.pending_map_reward.is_empty(): return "进行中地图与待领奖励不能并存"
	if not journey.active_run.is_empty():
		var active: Dictionary = journey.active_run
		if not _keys(active, ACTIVE_FIELDS): return "进行中地图结构无效"
		if not _integer(active.run_id, 1, journey.next_run_id - 1): return "进行中地图序号无效"
		if not active.map_id is String or not map_ids.has(active.map_id): return "进行中地图身份无效"
		if not _integer(active.tier, 1, mini(journey.best_tiers[active.map_id] + 1, 3)): return "进行中地图尚未解锁"
		if not _strings(active.normal_ids) or not _strings(active.special_ids): return "地图词缀身份无效"
		var compiled: Dictionary = Maps.compile_normal(active.map_id, active.tier, active.normal_ids, active.special_ids)
		if not compiled.ok: return str(compiled.reason)
		if active.normal_ids != compiled.profile.normal_ids or active.special_ids != compiled.profile.special_ids: return "地图词缀顺序不是规范顺序"
		if not active.fee_paid is int or active.fee_paid != compiled.profile.fee: return "地图已付成本无效"
	if not journey.pending_map_reward.is_empty():
		var pending: Dictionary = journey.pending_map_reward
		if not _keys(pending, PENDING_FIELDS): return "待领地图奖励结构无效"
		if not _integer(pending.run_id, 1, journey.next_run_id - 1): return "待领地图奖励序号无效"
		if not pending.map_id is String or not map_ids.has(pending.map_id): return "待领地图奖励身份无效"
		if not _integer(pending.tier, 1, journey.best_tiers[pending.map_id]): return "待领地图奖励层级无效"
		var compiled: Dictionary = Maps.compile_normal(pending.map_id, pending.tier, [], [])
		if not compiled.ok: return str(compiled.reason)
		var base: int = compiled.profile.base_completion_reward
		if not _integer(pending.shards, base, base + 4): return "待领地图碎片数量无效"
	return ""


static func start(journey: Variant, profile: Variant) -> Dictionary:
	var error: String = reason(journey)
	if not error.is_empty(): return _failure(error)
	if not profile is Dictionary or not profile.get("normal_map") is bool or not profile.normal_map \
			or not profile.get("journey_tier") is int or not profile.get("fee") is int \
			or not profile.get("base_completion_reward") is int or not profile.get("completion_reward") is int: return _failure("普通地图配置无效")
	error = Maps.profile_reason(profile)
	if not error.is_empty(): return _failure(error)
	if not journey.active_run.is_empty(): return _failure("已有进行中的地图")
	if not journey.pending_map_reward.is_empty(): return _failure("请先领取上一张地图奖励")
	if profile.journey_tier > mini(journey.best_tiers[profile.id] + 1, 3): return _failure("地图层级尚未解锁")
	if journey.next_run_id >= MAX_SERIAL: return _failure("地图行程序号已用尽")
	var candidate: Dictionary = journey.duplicate(true)
	var run_id: int = candidate.next_run_id
	candidate.next_run_id += 1
	candidate.active_run = {"run_id": run_id, "map_id": profile.id, "tier": profile.journey_tier,
		"normal_ids": profile.normal_ids.duplicate(), "special_ids": profile.special_ids.duplicate(), "fee_paid": profile.fee}
	return {"ok": true, "reason": "", "journey": candidate, "run_id": run_id, "cost": profile.fee}


static func complete(journey: Variant, run_id: Variant) -> Dictionary:
	var error: String = reason(journey)
	if not error.is_empty(): return _failure(error)
	if not run_id is int or journey.active_run.is_empty() or run_id != journey.active_run.run_id: return _failure("地图行程已变化，不能重复结算")
	var active: Dictionary = journey.active_run
	var compiled: Dictionary = Maps.compile_normal(active.map_id, active.tier, active.normal_ids, active.special_ids)
	var candidate: Dictionary = journey.duplicate(true)
	candidate.best_tiers[active.map_id] = maxi(candidate.best_tiers[active.map_id], active.tier)
	candidate.active_run = {}
	var reward: int = compiled.profile.completion_reward
	candidate.pending_map_reward = {"run_id": run_id, "map_id": active.map_id, "tier": active.tier, "shards": reward}
	return {"ok": true, "reason": "", "journey": candidate, "reward": reward}


static func abandon(journey: Variant, run_id: Variant) -> Dictionary:
	var error: String = reason(journey)
	if not error.is_empty(): return _failure(error)
	if not run_id is int or journey.active_run.is_empty() or run_id != journey.active_run.run_id: return _failure("地图行程已变化，不能重复放弃")
	var candidate: Dictionary = journey.duplicate(true)
	candidate.active_run = {}
	return {"ok": true, "reason": "", "journey": candidate}


static func gem_definition(ordinal: int) -> String:
	if ordinal < 1 or ordinal > MAX_KILLS / GEM_INTERVAL: return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x47454D31 ^ ordinal
	return GEM_DEFINITIONS[rng.randi_range(0, GEM_DEFINITIONS.size() - 1)]


static func flask_definition(ordinal: int) -> String:
	if ordinal < 1 or ordinal > MAX_KILLS / FLASK_INTERVAL: return ""
	return Flasks.reward_definition(ordinal * FLASK_INTERVAL)


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "reason": error, "journey": {}}


static func _integer(value: Variant, low: int, high: int) -> bool:
	return value is int and value >= low and value <= high


static func _decode_integer(value: Dictionary, field: String, low: int, high: int) -> bool:
	if not value.has(field): return false
	var number: Variant = value[field]
	if not (number is int or number is float) or not is_finite(float(number)) \
			or float(number) != floor(float(number)) or number < low or number > high: return false
	value[field] = int(number)
	return true


static func _keys(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for key: Variant in value:
		if not key is String or not fields.has(key): return false
	return true


static func _strings(value: Variant) -> bool:
	if not value is Array: return false
	for id: Variant in value:
		if not id is String: return false
	return true
