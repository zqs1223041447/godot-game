class_name SourceStatPatterns
extends RefCounted
## Pure, closed-world parsing for a small set of raw PoE passive stat lines.
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

const NEGATIVE_PATTERN: String = "^-([0-9]+(?:\\.[0-9]+)?)(?: to maximum (?:Life|Mana|Energy Shield)|% increased (?:Damage|Projectile Damage|Spell Damage|Fire Damage|Cold Damage|Lightning Damage|Elemental Damage|Area Damage|Attack Speed|Movement Speed|Mana Regeneration Rate|maximum Life|maximum Mana|maximum Energy Shield))$"
const NO_EXACT_MATCH_REASON: String = "整行不匹配任何受支持的完整格式；未知 stat、附加词语、条件、武器限定、DoT、Minion 或标点变体均拒绝"
static var _regex_cache: Dictionary = {}


static func _expression(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var compiled := RegEx.new()
		if compiled.compile(pattern) != OK: return null
		_regex_cache[pattern] = compiled
	return _regex_cache[pattern]


static func parse_line(raw_line: Variant, allow_spatial:bool=true,allow_recharge:bool=true,allow_resource:bool=true) -> Dictionary:
	if not raw_line is String:
		return _unsupported("输入必须是单行英文字符串")
	var line: String = raw_line
	if line.contains("\n") or line.contains("\r"):
		return _unsupported("多行文本不支持")
	if line.strip_edges().is_empty():
		return _unsupported("空行不支持")
	for definition: Dictionary in COMPOUND_PATTERNS:
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
