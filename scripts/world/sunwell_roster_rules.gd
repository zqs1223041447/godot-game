class_name SunwellRosterRules
extends RefCounted
## Only replaces basic species after the existing ordinary roll. No RNG,
## rarity, mechanisms, attributes, death spawns or reward decisions live here.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const BASE_TEMPLATES: Array[String] = ["crawler", "skitter", "brute"]
const PATTERNS: Dictionary = {
	"camp_west": ["brute", "frost_guard", "brute", "crawler", "frost_guard", "skitter"],
	"camp_north": ["crawler", "brute", "skitter", "frost_guard", "crawler", "storm_skitter"],
	"camp_east": ["skitter", "storm_skitter", "skitter", "crawler", "storm_skitter", "brute"],
}


## ordinal is one-based within the camp, including its reserved ember slots.
## Splitters and brood hosts retain the original roll and consume their slot.
static func template_for_roll(wave: int, camp_id: String, ordinal: int, roll: Dictionary) -> String:
	var original: String = str(roll.get("template", ""))
	if original not in BASE_TEMPLATES or not PATTERNS.has(camp_id) or ordinal < 1:
		return original
	var pattern: Array = PATTERNS[camp_id]
	var selected: String = pattern[(ordinal - 1) % pattern.size()]
	if Monsters.ELEMENTAL_ENCOUNTERS.has(selected):
		var policy: Dictionary = Monsters.ELEMENTAL_ENCOUNTERS[selected]
		if wave < int(policy.minimum_wave):
			return str(policy.source_template)
	return selected


## The map's selected patrol modifier gets final precedence, using the
## composed species. Its actual replacement still belongs to MapCompiler.
static func species_roll(roll: Dictionary, template_id: String) -> Dictionary:
	var result: Dictionary = roll.duplicate(true)
	result.template = str(Monsters.ELEMENTAL_ENCOUNTERS[template_id].source_template) \
		if Monsters.ELEMENTAL_ENCOUNTERS.has(template_id) else template_id
	return result
