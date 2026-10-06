class_name MistSkitterRosterRules
extends RefCounted
## Only normal-progression Sunwell II/III receive this final roster substitution.
## Fixed-wave test maps have no journey tier, even when their wave is also six.
## These helpers inspect values only; no RNG, slot, rarity or reward changes.


static func eligible_profile(profile: Dictionary) -> bool:
	if profile.get("id") != "sunwell_terrace" or not profile.get("normal_map") is bool or not profile.normal_map:
		return false
	var tier: Variant = profile.get("journey_tier")
	var wave: Variant = profile.get("wave")
	return tier is int and wave is int and ((tier == 2 and wave == 6) or (tier == 3 and wave == 10))


## Called on complete root rosters, after Sunwell/elemental/patrol precedence.
## No matching normal skitter means no replacement, rather than a new roll.
static func replacement_index(profile: Dictionary, entries: Array[Dictionary]) -> int:
	if not eligible_profile(profile):
		return -1
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		if entry.get("template_id") == "skitter" and entry.get("rarity") == "normal":
			return index
	return -1
