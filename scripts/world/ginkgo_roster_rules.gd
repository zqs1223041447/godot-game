class_name GinkgoRosterRules
extends RefCounted
## Ginkgo-only composition after the unchanged ordinary roll. No RNG, rarity,
## mechanisms, descendants or reward decisions are changed by this mapping.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const BASE_TEMPLATES: Array[String] = ["crawler", "skitter", "brute"]
const PATTERNS: Dictionary = {
	"camp_west": ["skitter", "crawler", "skitter", "crawler", "brute", "skitter"],
	"camp_north": ["brute", "frost_guard", "crawler", "brute", "frost_guard", "crawler"],
	"camp_east": ["brute", "storm_skitter", "skitter", "brute", "crawler", "storm_skitter"],
}


## One-based formation slot, including reserved ember and fixed death-spawn
## templates. Those fixed templates retain their original slot unchanged.
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


## Patrol modifiers retain final precedence over the mapped base species.
static func species_roll(roll: Dictionary, template_id: String) -> Dictionary:
	var result: Dictionary = roll.duplicate(true)
	result.template = str(Monsters.ELEMENTAL_ENCOUNTERS[template_id].source_template) \
		if Monsters.ELEMENTAL_ENCOUNTERS.has(template_id) else template_id
	return result


## One normal root in the first west outpost gains an existing locked lightning
## attack. Final patrols, rarity, death-spawn templates and all other slots win.
static func west_storm_index(profile: Dictionary, camp_id: String, entries: Array[Dictionary]) -> int:
	if profile.get("id") != "ginkgo_arcade" or camp_id != "camp_west" or entries.size() < 3:
		return -1
	if not profile.get("normal_map") is bool or not profile.normal_map:
		return -1
	var tier: Variant = profile.get("journey_tier")
	var wave: Variant = profile.get("wave")
	if not tier is int or not wave is int or not ((tier == 2 and wave == 6) or (tier == 3 and wave == 10)):
		return -1
	var entry: Dictionary = entries[2]
	if entry.get("template_id") == "skitter" and entry.get("rarity") == "normal" \
			and entry.get("mechanisms") is Array and entry.mechanisms.is_empty():
		return 2
	return -1
