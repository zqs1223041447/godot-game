extends SceneTree
## Pure profile contract only; no catalog, save, scene, texture, or RNG dependency.

const Profile = preload("res://scripts/items/build_affix_profile.gd")
const IDS: Array[String] = ["attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier"]
const BASE_IDS: Array[String] = ["wayglass_token", "pulse_seed", "nine_slot_etched_ring", "nine_slot_threaded_gloves"]
const SLOTS: Array[String] = ["charm", "ring", "gloves"]
const LEVELS: Array[int] = [1, 8, 16]
const WEIGHTS: Array[int] = [100, 60, 30]
const FIELDS: Array[String] = ["name", "kind", "group", "stat", "unit", "label", "slots", "allowed_base_ids", "tiers"]
const TIER_FIELDS: Array[String] = ["tier", "level", "weight", "min", "max"]
const EXPECTED: Array[Dictionary] = [
	{"name": "血汲", "kind": "prefix", "stat": "attack_life_leech", "unit": "basis_points", "label": "攻击伤害偷取为生命", "ranges": [[20, 30], [31, 45], [46, 60]]},
	{"name": "灵汲", "kind": "prefix", "stat": "attack_mana_leech", "unit": "basis_points", "label": "攻击伤害偷取为魔力", "ranges": [[10, 15], [16, 25], [26, 35]]},
	{"name": "锐察", "kind": "suffix", "stat": "crit_chance_increased", "unit": "percent", "label": "全局暴击几率提高", "ranges": [[15, 20], [21, 30], [31, 40]]},
	{"name": "重创", "kind": "suffix", "stat": "crit_multiplier_add", "unit": "percent", "label": "全局暴击伤害倍率", "ranges": [[5, 7], [8, 11], [12, 15]]},
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_check_vocabulary()
	_check_families()
	_check_detached_copies()
	print("Build affix profile: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_vocabulary() -> void:
	_expect(Profile.MIN_SAVE_VERSION == 27, "Profile begins at save version 27")
	_expect(Profile.AFFIX_IDS == IDS and Profile.affix_ids() == IDS, "Four affix IDs retain the exact approved order")
	_expect(Profile.ALLOWED_BASE_IDS == BASE_IDS and Profile.allowed_base_ids() == BASE_IDS, "Exactly the four approved existing bases are allowed")
	_expect(Profile.affix_ids().get_typed_builtin() == TYPE_STRING, "Affix ID accessor retains Array[String]")
	_expect(Profile.allowed_base_ids().get_typed_builtin() == TYPE_STRING, "Base ID accessor retains Array[String]")
	_expect(Profile.AFFIXES.keys() == IDS and Profile.affixes().keys() == IDS, "Family dictionary contains exactly the ordered four IDs")
	_expect(_unique(Profile.affix_ids()) and _unique(Profile.allowed_base_ids()), "Public ID lists contain no duplicates")


func _check_families() -> void:
	var families: Dictionary = Profile.affixes()
	var groups: Array[String] = []
	var kinds: Dictionary = {"prefix": 0, "suffix": 0}
	for family_index: int in range(IDS.size()):
		var id: String = IDS[family_index]
		if not families.has(id):
			_expect(false, "Missing family: " + id)
			continue
		var family: Dictionary = families[id]
		var expected: Dictionary = EXPECTED[family_index]
		var is_multiplier: bool = id == "global_critical_multiplier"
		_expect(family.has_all(FIELDS) and family.size() == FIELDS.size() + int(is_multiplier), "Exact family fields: " + id)
		for field: String in ["name", "kind", "stat", "unit", "label"]:
			_expect(family.get(field) == expected[field], "Approved %s: %s" % [field, id])
		_expect(family.group == id and not groups.has(family.group), "Family owns one distinct exclusion group: " + id)
		groups.append(family.group)
		kinds[family.kind] = int(kinds.get(family.kind, 0)) + 1
		_expect(family.slots == SLOTS and _unique(family.slots), "Exact duplicate-free allowed slots: " + id)
		_expect(family.allowed_base_ids == BASE_IDS and _unique(family.allowed_base_ids), "Exact duplicate-free base allowlist: " + id)
		_expect(family.has("display_unit") == is_multiplier, "Only multiplier requires display-unit metadata: " + id)
		if is_multiplier:
			_expect(family.display_unit == "percentage_points", "Multiplier adds percentage points while retaining percent storage")
		_expect(family.tiers.size() == 3, "Family declares exactly T1/T2/T3: " + id)
		for tier_index: int in range(family.tiers.size()):
			var tier: Dictionary = family.tiers[tier_index]
			_expect(tier.has_all(TIER_FIELDS) and tier.size() == TIER_FIELDS.size(), "Tier has only the five supported fields and inherits its family group: " + id)
			for field: String in TIER_FIELDS:
				_expect(tier.get(field) is int, "Tier field is an integer %s: %s" % [field, id])
			if tier_index >= 3:
				continue
			_expect(tier.tier == tier_index + 1, "Tier number matches the approved order: " + id)
			_expect(tier.level == LEVELS[tier_index], "Tier unlocks at approved item level: " + id)
			_expect(tier.weight == WEIGHTS[tier_index], "Tier has exact prototype weight: " + id)
			_expect([tier.min, tier.max] == expected.ranges[tier_index], "Tier retains exact prototype integer bounds: " + id)
	_expect(groups.size() == 4 and _unique(groups), "All four families coexist without mutual group conflicts")
	_expect(kinds == {"prefix": 2, "suffix": 2}, "Four-family combination uses two prefix and two suffix slots")


func _check_detached_copies() -> void:
	var baseline: Dictionary = Profile.affixes()
	var first: Dictionary = Profile.affixes()
	var second: Dictionary = Profile.affixes()
	first[IDS[0]].tiers[0].min = 999
	first[IDS[0]].tiers.append({"tier": 99})
	first[IDS[0]].slots.clear()
	first[IDS[0]].allowed_base_ids.append("unapproved_base")
	first[IDS[0]].name = "changed"
	_expect(first[IDS[1]].slots == SLOTS and first[IDS[1]].allowed_base_ids == BASE_IDS, "Mutating one family's nested arrays cannot change another family")
	first.erase(IDS[1])
	first["unapproved_affix"] = {}
	_expect(second == baseline, "Independent affix returns do not alias nested records or arrays")
	_expect(Profile.affixes() == baseline and Profile.AFFIXES == baseline, "Nested and top-level edits cannot alter canonical affixes or fresh reads")
	var ids: Array[String] = Profile.affix_ids()
	ids[0] = "unapproved_affix"
	ids.append(ids[0])
	ids.erase(IDS[1])
	_expect(Profile.affix_ids() == IDS and Profile.AFFIX_IDS == IDS, "Affix ID edits and duplicates stay local to the caller")
	var bases: Array[String] = Profile.allowed_base_ids()
	bases[0] = "unapproved_base"
	bases.append(bases[0])
	bases.clear()
	_expect(Profile.allowed_base_ids() == BASE_IDS and Profile.ALLOWED_BASE_IDS == BASE_IDS, "Base ID edits, duplicates, and clearing stay local to the caller")
	_expect(Profile.MIN_SAVE_VERSION == 27, "Detached edits cannot affect the version gate")


func _unique(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		if seen.has(value):
			return false
		seen[value] = true
	return true


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
