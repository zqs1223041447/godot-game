extends RefCounted
## Pure, closed-world parsing for a small set of raw PoE passive stat entries.
## This parser does not apply the returned grants to a character or passive tree.

const POSITIVE_PATTERNS: Array[Dictionary] = [
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to Armour$", "stat": "armour", "mode": "flat", "scale": 1.0},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Armour$", "stat": "armour_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?)% to Fire Resistance$", "stat": "fire_resistance", "mode": "flat", "scale": 0.01},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?)% to Cold Resistance$", "stat": "cold_resistance", "mode": "flat", "scale": 0.01},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?)% to Lightning Resistance$", "stat": "lightning_resistance", "mode": "flat", "scale": 0.01},
	{"expression": "^Regenerate ([0-9]+(?:\\.[0-9]+)?)% of Life per second$", "stat": "life_regen_percent", "mode": "flat", "scale": 0.01},
	{"expression": "^Regenerate ([0-9]+(?:\\.[0-9]+)?) Life per second$", "stat": "life_regen", "mode": "flat", "scale": 1.0},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to Strength$", "stat": "strength", "mode": "flat", "scale": 1.0},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to Dexterity$", "stat": "dexterity", "mode": "flat", "scale": 1.0},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to Intelligence$", "stat": "intelligence", "mode": "flat", "scale": 1.0},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Physical Damage$", "stat": "physical_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Chaos Damage$", "stat": "chaos_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Melee Physical Damage$", "stat": "melee_physical_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Attack Physical Damage$", "stat": "attack_physical_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to Accuracy Rating$", "stat": "accuracy", "mode": "flat", "scale": 1.0},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to Evasion Rating$", "stat": "evasion", "mode": "flat", "scale": 1.0},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Accuracy Rating$", "stat": "accuracy_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Evasion Rating$", "stat": "evasion_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to maximum Life$", "stat": "max_health", "mode": "flat", "scale": 1.0},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to maximum Mana$", "stat": "max_mana", "mode": "flat", "scale": 1.0},
	{"expression": "^\\+([0-9]+(?:\\.[0-9]+)?) to maximum Energy Shield$", "stat": "max_shield", "mode": "flat", "scale": 1.0},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Damage$", "stat": "global_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Projectile Damage$", "stat": "projectile_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Spell Damage$", "stat": "spell_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Fire Damage$", "stat": "fire_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Cold Damage$", "stat": "cold_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Lightning Damage$", "stat": "lightning_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Elemental Damage$", "stat": "elemental_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Area Damage$", "stat": "area_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Attack Speed$", "stat": "attack_speed_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Movement Speed$", "stat": "move_speed_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased Mana Regeneration Rate$", "stat": "mana_regen_increased", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased maximum Life$", "stat": "max_health", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased maximum Mana$", "stat": "max_mana", "mode": "increased", "scale": 0.01},
	{"expression": "^([0-9]+(?:\\.[0-9]+)?)% increased maximum Energy Shield$", "stat": "max_shield", "mode": "increased", "scale": 0.01},
]

const COMPOUND_PATTERNS: Array[Dictionary] = [
	{"expression":"^\\+([0-9]+)% to all Elemental Resistances$","stats":["fire_resistance","cold_resistance","lightning_resistance"],"mode":"flat","scale":0.01},
	{"expression":"^([0-9]+)% increased Evasion Rating and Armour$","stats":["evasion_increased","armour_increased"],"mode":"increased","scale":0.01},
	{"expression":"^([0-9]+)% increased Armour and Evasion Rating$","stats":["armour_increased","evasion_increased"],"mode":"increased","scale":0.01},
	{"expression":"^\\+([0-9]+) to all Attributes$","stats":["strength","dexterity","intelligence"],"mode":"flat","scale":1.0},
	{"expression":"^\\+([0-9]+) to Strength and Dexterity$","stats":["strength","dexterity"],"mode":"flat","scale":1.0},
	{"expression":"^\\+([0-9]+) to Strength and Intelligence$","stats":["strength","intelligence"],"mode":"flat","scale":1.0},
	{"expression":"^\\+([0-9]+) to Dexterity and Intelligence$","stats":["dexterity","intelligence"],"mode":"flat","scale":1.0},
]

# Separate vocabulary gate: v19 and earlier use the unchanged lists above.
const SPATIAL_PATTERNS:Array[Dictionary]=[
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Area of Effect$","stat":"area_size_increased","mode":"increased","scale":0.01},
	{"expression":"^Spell Skills have ([0-9]+(?:\\.[0-9]+)?)% increased Area of Effect$","stat":"spell_area_size_increased","mode":"increased","scale":0.01},
	{"expression":"^Melee Skills have ([0-9]+(?:\\.[0-9]+)?)% increased Area of Effect$","stat":"melee_area_size_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Projectile Speed$","stat":"projectile_speed_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% reduced Projectile Speed$","stat":"projectile_speed_increased","mode":"increased","scale":-0.01},
]

const RECHARGE_PATTERNS:Array[Dictionary]=[
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Energy Shield Recharge Rate$","stat":"shield_recharge_rate_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% faster start of Energy Shield Recharge$","stat":"shield_recharge_start_faster","mode":"increased","scale":0.01},
]

const RESOURCE_PATTERNS:Array[Dictionary]=[
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Mana Cost Efficiency$","stat":"mana_cost_efficiency_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Mana Cost of Skills$","stat":"mana_cost_increased","mode":"increased","scale":0.01},
]

const FLASK_PATTERNS:Array[Dictionary]=[
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Life Recovery from Flasks$","stat":"flask_life_recovery_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Mana Recovery from Flasks$","stat":"flask_mana_recovery_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Flask Charges gained$","stat":"flask_charges_gained_increased","mode":"increased","scale":0.01},
]

# Schema24 only: scoped increased chance and additive multiplier; no base chance.
const CRITICAL_PATTERNS:Array[Dictionary]=[
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Critical Strike Chance$","stat":"crit_chance_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Spell Critical Strike Chance$","stat":"spell_crit_chance_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Melee Critical Strike Chance$","stat":"melee_crit_chance_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Critical Strike Chance for Attacks$","stat":"attack_crit_chance_increased","mode":"increased","scale":0.01},
	{"expression":"^Projectile Attack Skills have ([0-9]+(?:\\.[0-9]+)?)% increased Critical Strike Chance$","stat":"projectile_attack_crit_chance_increased","mode":"increased","scale":0.01},
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to Critical Strike Multiplier$","stat":"crit_multiplier_add","mode":"flat","scale":0.01},
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to Critical Strike Multiplier for Spell Damage$","stat":"spell_crit_multiplier_add","mode":"flat","scale":0.01},
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to Melee Critical Strike Multiplier$","stat":"melee_crit_multiplier_add","mode":"flat","scale":0.01},
	{"expression":"^Projectile Attack Skills have \\+([0-9]+(?:\\.[0-9]+)?)% to Critical Strike Multiplier$","stat":"projectile_attack_crit_multiplier_add","mode":"flat","scale":0.01},
]

# Schema25 only: exact attack leech and unconditional recovery rate/cap forms.
const LEECH_PATTERNS:Array[Dictionary]=[
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% of Attack Damage Leeched as Life$","stat":"attack_life_leech","mode":"flat","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% of Attack Damage Leeched as Mana$","stat":"attack_mana_leech","mode":"flat","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% of Physical Attack Damage Leeched as Life$","stat":"physical_attack_life_leech","mode":"flat","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% of Physical Attack Damage Leeched as Mana$","stat":"physical_attack_mana_leech","mode":"flat","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased total Recovery per second from Life Leech$","stat":"life_leech_rate_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased total Recovery per second from Mana Leech$","stat":"mana_leech_rate_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Maximum total Life Recovery per second from Leech$","stat":"life_leech_max_rate_increased","mode":"increased","scale":0.01},
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% increased Maximum total Mana Recovery per second from Leech$","stat":"mana_leech_max_rate_increased","mode":"increased","scale":0.01},
]

# Schema32 only: exact, unconditional Fire DoT additive multiplier.
const FIRE_DOT_PATTERNS: Array[Dictionary] = [
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to Fire Damage over Time Multiplier$","stat":"fire_dot_multiplier_add","mode":"flat","scale":0.01},
]

# Schema33 only: unconditional damaging ailments faster; summed as a fraction.
const FASTER_BURN_PATTERNS: Array[Dictionary] = [
	{"expression":"^Damaging Ailments deal damage ([0-9]+(?:\\.[0-9]+)?)% faster$","stat":"damaging_ailments_faster","mode":"flat","scale":0.01},
]

# Schema35 only: exact, unconditional damage taken from mana before life.
const MANA_GUARD_PATTERNS: Array[Dictionary] = [
	{"expression":"^([0-9]+(?:\\.[0-9]+)?)% of Damage is taken from Mana before Life$","stat":"damage_taken_from_mana_before_life","mode":"flat","scale":0.01},
]

# Schema36 only: unconditional maximum elemental resistance percentage points.
const ELEMENTAL_RESISTANCE_CAP_PATTERNS: Array[Dictionary] = [
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to maximum Fire Resistance$","stat":"maximum_fire_resistance_add","mode":"flat","scale":0.01},
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to maximum Cold Resistance$","stat":"maximum_cold_resistance_add","mode":"flat","scale":0.01},
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to maximum Lightning Resistance$","stat":"maximum_lightning_resistance_add","mode":"flat","scale":0.01},
]
const ELEMENTAL_RESISTANCE_CAP_COMPOUND_PATTERNS: Array[Dictionary] = [
	{"expression":"^\\+([0-9]+(?:\\.[0-9]+)?)% to all maximum Elemental Resistances$","stats":["maximum_fire_resistance_add","maximum_cold_resistance_add","maximum_lightning_resistance_add"],"mode":"flat","scale":0.01},
]

# Schema38 only: one indivisible source entry, including its exact newline and case.
const RESOLUTE_TECHNIQUE_ENTRY := "Your hits can't be Evaded\nNever deal Critical Strikes"

const NEGATIVE_PATTERN: String = "^-([0-9]+(?:\\.[0-9]+)?)(?: to maximum (?:Life|Mana|Energy Shield)|% increased (?:Damage|Projectile Damage|Spell Damage|Fire Damage|Cold Damage|Lightning Damage|Elemental Damage|Area Damage|Attack Speed|Movement Speed|Mana Regeneration Rate|maximum Life|maximum Mana|maximum Energy Shield))$"
const NO_EXACT_MATCH_REASON: String = "整行不匹配任何受支持的完整格式；未知 stat、附加词语、条件、武器限定、DoT、Minion 或标点变体均拒绝"
static var _regex_cache: Dictionary = {}


static func _expression(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var compiled := RegEx.new()
		if compiled.compile(pattern) != OK: return null
		_regex_cache[pattern] = compiled
	return _regex_cache[pattern]


static func parse_line(raw_line: Variant, allow_spatial:bool=true,allow_recharge:bool=true,allow_resource:bool=true,allow_flask:bool=true,allow_critical:bool=true,allow_leech:bool=true,allow_fire_dot:bool=true,allow_faster_burn:bool=true,allow_mana_guard:bool=true,allow_elemental_resistance_cap:bool=true,allow_resolute:bool=true) -> Dictionary:
	if not raw_line is String:
		return _unsupported("输入必须是单行英文字符串")
	var line: String = raw_line
	# Do not split arbitrary multiline entries: both effects must enter together.
	if allow_spatial and allow_recharge and allow_resource and allow_flask and allow_critical and allow_leech and allow_fire_dot and allow_faster_burn and allow_mana_guard and allow_elemental_resistance_cap and allow_resolute and line == RESOLUTE_TECHNIQUE_ENTRY:
		return {"supported":true,"reason":"","grants":[{"stat":"resolute_technique","value":1.0,"mode":"flat"}]}
	if line.contains("\n") or line.contains("\r"):
		return _unsupported("多行文本不支持")
	if line.strip_edges().is_empty():
		return _unsupported("空行不支持")
	if allow_spatial and allow_recharge and allow_resource and allow_flask:
		var both:=_expression("^([0-9]+(?:\\.[0-9]+)?)% increased Life and Mana Recovery from Flasks$").search(line)
		if both!=null:
			var value:float=float(both.get_string(1))*0.01
			if not is_finite(value):return _unsupported("数值超出有限范围")
			return {"supported":true,"reason":"","grants":[{"stat":"flask_life_recovery_increased","value":value,"mode":"increased"},{"stat":"flask_mana_recovery_increased","value":value,"mode":"increased"}]}
	var allow_caps: bool = allow_spatial and allow_recharge and allow_resource and allow_flask and allow_critical and allow_leech and allow_fire_dot and allow_faster_burn and allow_mana_guard and allow_elemental_resistance_cap
	var compound_patterns: Array = COMPOUND_PATTERNS + ELEMENTAL_RESISTANCE_CAP_COMPOUND_PATTERNS if allow_caps else COMPOUND_PATTERNS
	for definition: Dictionary in compound_patterns:
		var expression := _expression(str(definition.expression))
		if expression == null: return _unsupported("解析器模式配置无效")
		var matched := expression.search(line)
		if matched == null: continue
		var value := float(matched.get_string(1))*float(definition.scale)
		if not is_finite(value): return _unsupported("数值超出有限范围")
		var grants: Array = []
		for stat: String in definition.stats: grants.append({"stat":stat,"value":value,"mode":definition.mode})
		return {"supported":true,"grants":grants,"reason":""}

	var patterns:Array=POSITIVE_PATTERNS+SPATIAL_PATTERNS if allow_spatial else POSITIVE_PATTERNS
	if allow_spatial and allow_recharge:patterns=patterns+RECHARGE_PATTERNS
	if allow_spatial and allow_recharge and allow_resource:patterns=patterns+RESOURCE_PATTERNS
	if allow_spatial and allow_recharge and allow_resource and allow_flask:patterns=patterns+FLASK_PATTERNS
	if allow_spatial and allow_recharge and allow_resource and allow_flask and allow_critical:patterns=patterns+CRITICAL_PATTERNS
	if allow_spatial and allow_recharge and allow_resource and allow_flask and allow_critical and allow_leech:patterns=patterns+LEECH_PATTERNS
	if allow_spatial and allow_recharge and allow_resource and allow_flask and allow_critical and allow_leech and allow_fire_dot:patterns=patterns+FIRE_DOT_PATTERNS
	if allow_spatial and allow_recharge and allow_resource and allow_flask and allow_critical and allow_leech and allow_fire_dot and allow_faster_burn:patterns=patterns+FASTER_BURN_PATTERNS
	if allow_spatial and allow_recharge and allow_resource and allow_flask and allow_critical and allow_leech and allow_fire_dot and allow_faster_burn and allow_mana_guard:patterns=patterns+MANA_GUARD_PATTERNS
	if allow_caps: patterns = patterns + ELEMENTAL_RESISTANCE_CAP_PATTERNS
	for definition: Dictionary in patterns:
		var expression := _expression(str(definition.expression))
		if expression == null:
			return _unsupported("解析器模式配置无效")
		var matched: RegExMatch = expression.search(line)
		if matched == null:
			continue
		var source_value: float = float(matched.get_string(1))
		var value: float = source_value * float(definition.scale)
		if not is_finite(source_value) or not is_finite(value):
			return _unsupported("数值超出有限范围")
		return {
			"supported": true,
			"grants": [{"stat": str(definition.stat), "value": value, "mode": str(definition.mode)}],
			"reason": "",
		}

	var negative_expression := _expression(NEGATIVE_PATTERN)
	if negative_expression == null:
		return _unsupported("解析器负值诊断模式无效")
	if negative_expression.search(line) != null:
		return _unsupported("负值语义未定义")
	return _unsupported(NO_EXACT_MATCH_REASON)


static func _unsupported(reason: String) -> Dictionary:
	return {"supported": false, "grants": [], "reason": reason}
