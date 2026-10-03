class_name SourceStatPatterns
extends RefCounted
## Pure, closed-world parsing for a small set of raw PoE passive stat lines.
## This parser does not apply the returned grants to a character or passive tree.

const POSITIVE_PATTERNS: Array[Dictionary] = [
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

const NEGATIVE_PATTERN: String = "^-([0-9]+(?:\\.[0-9]+)?)(?: to maximum (?:Life|Mana|Energy Shield)|% increased (?:Damage|Projectile Damage|Spell Damage|Fire Damage|Cold Damage|Lightning Damage|Elemental Damage|Area Damage|Attack Speed|Movement Speed|Mana Regeneration Rate|maximum Life|maximum Mana|maximum Energy Shield))$"
const NO_EXACT_MATCH_REASON: String = "整行不匹配任何受支持的完整格式；未知 stat、附加词语、条件、武器限定、DoT、Minion 或标点变体均拒绝"


static func parse_line(raw_line: Variant) -> Dictionary:
	if not raw_line is String:
		return _unsupported("输入必须是单行英文字符串")
	var line: String = raw_line
	if line.contains("\n") or line.contains("\r"):
		return _unsupported("多行文本不支持")
	if line.strip_edges().is_empty():
		return _unsupported("空行不支持")

	for definition: Dictionary in POSITIVE_PATTERNS:
		var expression := RegEx.new()
		if expression.compile(str(definition.expression)) != OK:
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

	var negative_expression := RegEx.new()
	if negative_expression.compile(NEGATIVE_PATTERN) != OK:
		return _unsupported("解析器负值诊断模式无效")
	if negative_expression.search(line) != null:
		return _unsupported("负值语义未定义")
	return _unsupported(NO_EXACT_MATCH_REASON)


static func _unsupported(reason: String) -> Dictionary:
	return {"supported": false, "grants": [], "reason": reason}
