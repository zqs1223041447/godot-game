class_name WeaponLocalRules
extends RefCounted
## Pure item-local physical stage. The catalog owns instance/tier validation;
## this contract owns the only raw profile admitted by the hit compiler. No RNG.
const STAGE: String = "weapon_local"
const BASE_ID: String = "ashwood_bow"
const BASE_PHYSICAL_BY_ID: Dictionary = {"ashwood_bow": 4.0, "forgeblade": 4.0}
const SOURCE_STATS: Dictionary = {
	"whetstone_edge": "weapon_added_physical", "tempered_edge": "weapon_physical_increased",
}


static func supports_stat(stat: String, stage: String = STAGE) -> bool:
	return support_reason(stat, stage).is_empty()


static func support_reason(stat: String, stage: String = STAGE) -> String:
	if stage != STAGE:
		return "武器局部阶段不受支持"
	if not SOURCE_STATS.values().has(stat):
		return "武器局部属性不受支持"
	return ""


## Both assembly and frozen-packet admission use this base-specific boundary.
## Keep the bow's original tag semantics; the blade admits only the authored
## direct cleave event, never a projectile, spell or independent secondary.
static func consumes_hit(base_id: String, skill_id: String, role: String, tags: Variant) -> bool:
	if base_id == BASE_ID:
		return tags is Array and tags.has("hit") and tags.has("attack") and tags.has("projectile") \
			and not tags.has("spell") and not tags.has("secondary") and not tags.has("explosion") \
			and ((skill_id == "basic" and role == "projectile") or (skill_id == "tornado" and role in ["parent", "child"]))
	if base_id == "forgeblade":
		return skill_id == "cleave" and role == "direct" and tags is Array and tags.size() == 4 \
			and tags.has("hit") and tags.has("attack") and tags.has("melee") and tags.has("area")
	return false


static func metadata() -> Dictionary:
	return {"id": STAGE, "name": "武器局部物理伤害", "stage": STAGE,
		"scope": "equipped_weapon", "damage_type": "physical", "schema_version": 1,
		"base_ids": BASE_PHYSICAL_BY_ID.keys(), "stats": SOURCE_STATS.values(), "origin": "adapted",
		"source_refs": ["https://www.pathofexile.com/forum/view-thread/1676002/filter-account-type/staff",
			"https://www.pathofexile.com/forum/view-thread/3165009"],
		"balance_version": "original-local-weapon-v1", "formula": "(base + flat) * (1 + increased)",
		"hit_formula": "B * original_distribution * base_coefficient + W * base_coefficient + external_added * added_effectiveness",
		"consumers": {"basic": ["projectile"], "tornado": ["parent", "child"], "cleave": ["direct"]},
		"consumers_by_base": {"ashwood_bow": {"basic": ["projectile"], "tornado": ["parent", "child"]}, "forgeblade": {"cleave": ["direct"]}},
		"description": "局部点伤与局部物理提高先结算本武器；长弓仅加入普通攻击与龙卷箭体，锻纹短刃仅加入裂刃斩直接命中，均按技能基础倍率加入物理点数。保留原有角色基伤，不是完整武器基伤替换。",
		"unsupported": ["conversion", "quality", "local_attack_speed", "local_critical_strike", "damage_ranges", "spell", "secondary"]}


static func resolve(value: Variant) -> Dictionary:
	var reason: String = profile_error(value)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "profile": {}, "components": {}}
	if value.is_empty():
		return {"ok": true, "reason": "", "profile": {}, "components": {}}
	var physical: float = (float(value.base.physical) + float(value.flat.physical)) * (1.0 + float(value.increased.physical))
	return {"ok": true, "reason": "", "profile": value.duplicate(true), "components": {"physical": physical}}


static func profile_error(value: Variant) -> String:
	if not value is Dictionary:
		return "武器局部配置必须是对象"
	if value.is_empty():
		return ""
	if not _exact_keys(value, ["stage", "item_id", "base_id", "base", "flat", "increased", "sources"]):
		return "武器局部配置结构无效"
	if not value.stage is String or value.stage != STAGE or not value.base_id is String or not BASE_PHYSICAL_BY_ID.has(value.base_id) or not _item_id(value.item_id):
		return "武器局部阶段或来源无效"
	for key: String in ["base", "flat", "increased"]:
		if not physical_map(value[key]):
			return "武器局部配置只支持有限非负物理数值"
	if float(value.base.physical) != float(BASE_PHYSICAL_BY_ID[value.base_id]):
		return "武器固有物理点数与底材不一致"
	if not value.sources is Array:
		return "武器局部来源必须是数组"
	var seen: Dictionary = {}
	var flat: float = 0.0
	var increased: float = 0.0
	for source: Variant in value.sources:
		if not _exact_keys(source, ["affix_id", "stat", "value"]):
			return "武器局部来源结构无效"
		if not source.affix_id is String or not SOURCE_STATS.has(source.affix_id) or seen.has(source.affix_id):
			return "武器局部来源词缀未知或重复"
		if not source.stat is String or source.stat != SOURCE_STATS[source.affix_id] or not _nonnegative(source.value):
			return "武器局部来源属性或数值无效"
		seen[source.affix_id] = true
		if source.stat == "weapon_added_physical":
			flat += float(source.value)
		else:
			increased += float(source.value)
	if not is_finite(flat) or not is_finite(increased) or flat != float(value.flat.physical) or increased != float(value.increased.physical):
		return "武器局部数值与来源不一致"
	var physical: float = (float(value.base.physical) + flat) * (1.0 + increased)
	if not is_finite(physical):
		return "武器局部伤害溢出"
	return ""


static func physical_map(value: Variant) -> bool:
	return _exact_keys(value, ["physical"]) and _nonnegative(value.physical)


static func _exact_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size() or not value.has_all(keys):
		return false
	for key: Variant in value:
		if not key is String:
			return false
	return true


static func _nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0


static func _item_id(value: Variant) -> bool:
	if not value is String or not value.begins_with("gear_") or value.length() > 14:
		return false
	var suffix: String = value.substr(5)
	if not suffix.is_valid_int():
		return false
	var serial: int = suffix.to_int()
	return serial >= 1 and serial <= 999999999 and value == "gear_%06d" % serial
