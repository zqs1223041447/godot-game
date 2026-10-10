class_name BrokenRuinsRosterRules
extends RefCounted
## One frost guard can join the eight-root inner-corridor outpost, using a
## final normal brute slot. Never stack another guard on an existing frost roll.
static func corridor_frost_index(profile: Dictionary, camp_id: String, entries: Array[Dictionary]) -> int:
	if profile.get("id") != "broken_ruins" or camp_id != "camp_north" or entries.size() != 12:
		return -1
	if not profile.get("normal_map") is bool or not profile.normal_map:
		return -1
	var tier: Variant = profile.get("journey_tier")
	var wave: Variant = profile.get("wave")
	if not tier is int or not wave is int or not ((tier == 2 and wave == 5) or (tier == 3 and wave == 9)):
		return -1
	for index: int in range(4, 12):
		if entries[index].get("template_id") == "frost_guard":
			return -1
	for index: int in range(4, 12):
		var entry: Dictionary = entries[index]
		if entry.get("template_id") == "brute" and entry.get("rarity") == "normal" \
				and entry.get("mechanisms") is Array and entry.mechanisms.is_empty():
			return index
	return -1
