extends RefCounted
## Pure critical profiles. Runtime owns the random stream and hit resolution.
## Chance increases add before scaling the base; multiplier additions are points.
const STAT_KEYS: Array[String] = [
	"crit_chance_increased", "attack_crit_chance_increased", "spell_crit_chance_increased",
	"melee_crit_chance_increased", "projectile_attack_crit_chance_increased",
	"crit_multiplier_add", "spell_crit_multiplier_add", "melee_crit_multiplier_add",
	"projectile_attack_crit_multiplier_add",
]
const MAX_MODIFIER: float = 1000000.0
const MAX_MULTIPLIER: float = 1000000.0


static func from_stats(stats: Dictionary) -> Dictionary:
	var modifiers: Dictionary = {}
	for stat: String in STAT_KEYS:
		var value: Variant = stats.get(stat, 0.0)
		# Keep malformed values so validation rejects them instead of silently
		# converting an invalid source into a valid zero-modifier profile.
		if not _number(value) or float(value) != 0.0:
			modifiers[stat] = value
	if modifiers.is_empty() and not stats.has("crit_base_chance") and not stats.has("crit_base_multiplier"):
		return {}
	modifiers["base_chance"] = stats.get("crit_base_chance", 0.0)
	modifiers["base_multiplier"] = stats.get("crit_base_multiplier", 1.5)
	return modifiers.duplicate(true)


static func error(snapshot: Dictionary) -> String:
	if not snapshot.has("critical_modifiers"):
		return ""
	var values: Variant = snapshot.critical_modifiers
	if not values is Dictionary or values.is_empty():
		return "暴击增幅必须为非空属性字典"
	if not values.has_all(["base_chance", "base_multiplier"]):
		return "暴击增幅缺少基础几率或基础倍率"
	for key: Variant in values:
		if not key is String or (key not in STAT_KEYS and key not in ["base_chance", "base_multiplier"]):
			return "暴击增幅包含未知或非字符串字段"
		if not _number(values[key]):
			return "暴击增幅数值必须为有限数字"
		var value: float = float(values[key])
		if key == "base_chance":
			if value < 0.0 or value > 1.0:
				return "基础暴击几率超出零至一边界"
		elif key == "base_multiplier":
			if value < 1.0 or value > 1000.0:
				return "基础暴击倍率超出一至一千边界"
		elif value < 0.0 or value > MAX_MODIFIER:
			return "暴击增幅超出非负数值边界"
	return ""


static func compile(snapshot: Dictionary, primary_tags: Array, has_secondary: bool) -> Dictionary:
	var reason: String = error(snapshot)
	if not reason.is_empty():
		return _compiled({}, reason)
	if not snapshot.has("critical_modifiers") or not primary_tags.has("hit"):
		return _compiled({})
	var values: Dictionary = snapshot.critical_modifiers
	var chance_increased: float = float(values.get("crit_chance_increased", 0.0))
	var multiplier_add: float = float(values.get("crit_multiplier_add", 0.0))
	# Fixed scope order keeps arithmetic independent of input key/tag order.
	if primary_tags.has("attack"):
		chance_increased += float(values.get("attack_crit_chance_increased", 0.0))
	if primary_tags.has("spell"):
		chance_increased += float(values.get("spell_crit_chance_increased", 0.0))
		multiplier_add += float(values.get("spell_crit_multiplier_add", 0.0))
	if primary_tags.has("melee"):
		chance_increased += float(values.get("melee_crit_chance_increased", 0.0))
		multiplier_add += float(values.get("melee_crit_multiplier_add", 0.0))
	if primary_tags.has("projectile") and primary_tags.has("attack"):
		chance_increased += float(values.get("projectile_attack_crit_chance_increased", 0.0))
		multiplier_add += float(values.get("projectile_attack_crit_multiplier_add", 0.0))
	var primary: Dictionary = _profile(values, chance_increased, multiplier_add)
	reason = profile_error(primary)
	if not reason.is_empty():
		return _compiled({}, reason)
	var critical: Dictionary = {"primary": primary}
	if has_secondary:
		var secondary: Dictionary = _profile(values, float(values.get("crit_chance_increased", 0.0)), float(values.get("crit_multiplier_add", 0.0)))
		reason = profile_error(secondary)
		if not reason.is_empty():
			return _compiled({}, reason)
		critical["secondary"] = secondary
	return _compiled(critical)


static func profile_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != 2 or not value.has_all(["chance", "multiplier"]):
		return "暴击命中配置必须恰含几率与倍率"
	for key: Variant in value:
		if not key is String or key not in ["chance", "multiplier"] or not _number(value[key]):
			return "暴击命中配置字段或数值无效"
	if float(value.chance) < 0.0 or float(value.chance) > 1.0:
		return "暴击命中几率超出零至一边界"
	if float(value.multiplier) < 1.0 or float(value.multiplier) > MAX_MULTIPLIER:
		return "暴击命中倍率超出数值边界"
	return ""


static func roll(profile: Dictionary, sample: float) -> Dictionary:
	var reason: String = profile_error(profile)
	if reason.is_empty() and (not is_finite(sample) or sample < 0.0 or sample >= 1.0):
		reason = "暴击样本必须为零至一之间且不含一的有限数字"
	if not reason.is_empty():
		return {"ok": false, "error": reason, "critical": false, "multiplier": 1.0, "chance": 0.0}
	var chance: float = float(profile.chance)
	var critical: bool = sample < chance
	return {"ok": true, "error": "", "critical": critical, "multiplier": float(profile.multiplier) if critical else 1.0, "chance": chance}


static func _profile(values: Dictionary, chance_increased: float, multiplier_add: float) -> Dictionary:
	var chance: float = float(values.base_chance) * (1.0 + chance_increased)
	var multiplier: float = float(values.base_multiplier) + multiplier_add
	# Check before clamping so nonfinite arithmetic can never become a valid cap.
	if not is_finite(chance) or not is_finite(multiplier):
		return {}
	return {"chance": clampf(chance, 0.0, 1.0), "multiplier": multiplier}


static func _compiled(critical: Dictionary, reason: String = "") -> Dictionary:
	return {"ok": reason.is_empty(), "error": reason, "critical": critical}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
