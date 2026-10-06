extends RefCounted
## Freezes selection once, before any camp becomes active. Runtime root IDs are
## registered only after the caller successfully admits a complete camp.
const Maps = preload("res://scripts/world/map_compiler.gd")
const Monsters = preload("res://docs/qa/v075-integration-tests/frozen/catalog.gd")
const Sunwell = preload("res://scripts/world/sunwell_roster_rules.gd")
const MistSkitter = preload("res://scripts/world/mist_skitter_roster_rules.gd")
const CAMP_IDS: Array[String] = ["camp_west", "camp_north", "camp_east"]
var _state: Dictionary = {}


func begin(profile: Variant, landmarks: Variant, seed_value: Variant,
		monster_policy: String = Monsters.LEGACY_ROLL_POLICY) -> Dictionary:
	if monster_policy not in [Monsters.LEGACY_ROLL_POLICY, Monsters.CURRENT_ROLL_POLICY]:
		return {"ok": false, "reason": "Unknown monster source policy"}
	var reason := Maps.profile_reason(profile)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	if not seed_value is int:
		return {"ok": false, "reason": "据点种子必须为整数"}
	if not profile.get("wave") is int or not profile.get("ordinary_target") is int:
		return {"ok": false, "reason": "据点地图数量必须为整数"}
	reason = _landmark_reason(profile, landmarks)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var camps: Array[Dictionary] = []
	var admission_index := 0
	for camp_id: String in CAMP_IDS:
		var landmark: Dictionary = _landmark(landmarks.camps, camp_id)
		var roster: Array[Dictionary] = []
		var ordinal := 0
		for position: Vector2 in landmark.positions:
			admission_index += 1
			ordinal += 1
			var template_id := Monsters.encounter_for_admission(profile.wave, admission_index)
			var rarity := ""
			var mechanisms: Array = []
			if template_id.is_empty():
				var roll := Monsters.ordinary_roll_current(rng, profile.wave) if monster_policy == Monsters.CURRENT_ROLL_POLICY else Monsters.ordinary_roll(rng, profile.wave)
				template_id = roll.template
				rarity = roll.rarity
				mechanisms = roll.mechanisms.duplicate(true)
				var special_roll: Dictionary = roll
				if profile.id == "sunwell_terrace":
					template_id = Sunwell.template_for_roll(profile.wave, camp_id, ordinal, roll)
					special_roll = Sunwell.species_roll(roll, template_id)
				else:
					var elemental := Monsters.elemental_template_for_roll(profile.wave, admission_index, roll)
					if not elemental.is_empty():
						template_id = elemental
				var special := Maps.special_template(profile, special_roll)
				if not special.is_empty():
					template_id = special
			roster.append({"admission_index": admission_index, "template_id": template_id,
				"rarity": rarity, "mechanisms": mechanisms, "position": position})
		var mist_index := MistSkitter.replacement_index(profile, roster)
		if mist_index >= 0:
			roster[mist_index].template_id = "mist_skitter"
		camps.append({"id": camp_id, "entries": roster, "root_ids": []})
	# Publish only after validation and complete deterministic roster generation.
	_state = {"profile": profile.duplicate(true), "landmarks": landmarks.duplicate(true),
		"seed": seed_value, "camps": camps}
	return {"ok": true, "reason": ""}


func clear() -> void:
	_state = {}


func entries(camp_id: String) -> Array[Dictionary]:
	for camp: Dictionary in _state.get("camps", []):
		if camp.id == camp_id:
			return camp.entries.duplicate(true)
	return []


func activate(camp_id: Variant, root_ids: Variant) -> bool:
	if not camp_id is String or not root_ids is Array:
		return false
	var target: Dictionary = {}
	var used: Dictionary = {}
	for camp: Dictionary in _state.get("camps", []):
		if camp.id == camp_id:
			target = camp
		for root_id: int in camp.root_ids:
			used[root_id] = true
	if target.is_empty() or not target.root_ids.is_empty() or root_ids.size() != target.entries.size():
		return false
	for root_id: Variant in root_ids:
		if not root_id is int or root_id <= 0 or used.has(root_id):
			return false
		used[root_id] = true
	target.root_ids = root_ids.duplicate()
	return true


## The caller has already qualified these deaths. Descendants/unknown IDs and
## non-integer keys cannot complete a registered root's membership.
func states(defeated: Dictionary) -> Array[Dictionary]:
	var qualified: Dictionary = {}
	for root_id: Variant in defeated:
		if root_id is int and root_id > 0:
			qualified[root_id] = true
	var result: Array[Dictionary] = []
	for camp: Dictionary in _state.get("camps", []):
		var count := 0
		for root_id: int in camp.root_ids:
			if qualified.has(root_id):
				count += 1
		var spawned: int = camp.root_ids.size()
		var state := "dormant" if spawned == 0 else ("cleared" if count == spawned else "active")
		result.append({"id": camp.id, "state": state, "roots_spawned": spawned,
			"roots_defeated": count, "root_count": camp.entries.size(), "reason": ""})
	return result


func checkpoint() -> Dictionary:
	return _state.duplicate(true)


static func _landmark(camps: Array, camp_id: String) -> Dictionary:
	for camp: Dictionary in camps:
		if camp.id == camp_id:
			return camp
	return {}


static func _finite_point(value: Variant) -> bool:
	return value is Vector2 and value.is_finite()


static func _trigger_valid(landmark: Dictionary) -> bool:
	var radius: Variant = landmark.get("trigger_radius")
	return _finite_point(landmark.get("center")) and _finite_point(landmark.get("trigger_center")) \
		and typeof(radius) in [TYPE_INT, TYPE_FLOAT] and is_finite(radius) and radius > 0


static func _landmark_reason(profile: Dictionary, landmarks: Variant) -> String:
	if not landmarks is Dictionary or not _finite_point(landmarks.get("entry")):
		return "据点入口无效"
	var camps: Variant = landmarks.get("camps")
	if not camps is Array or camps.size() != CAMP_IDS.size():
		return "地图必须包含三个据点"
	var expected_count := 8 if profile.id == "old_garden" else 12
	var total := 0
	var seen: Dictionary = {}
	for camp: Variant in camps:
		if not camp is Dictionary or not camp.get("id") is String or not CAMP_IDS.has(camp.id) or seen.has(camp.id):
			return "据点标识无效或重复"
		seen[camp.id] = true
		if not camp.get("root_count") is int or camp.root_count != expected_count:
			return "据点根怪数量无效"
		if not _trigger_valid(camp):
			return "据点中心或触发范围无效"
		var positions: Variant = camp.get("positions")
		if not positions is Array or positions.size() != camp.root_count:
			return "据点出生位置数量无效"
		for position: Variant in positions:
			if not _finite_point(position):
				return "据点出生位置无效"
		total += camp.root_count
	if total != profile.ordinary_target:
		return "据点总根怪数量与地图不符"
	var boss: Variant = landmarks.get("boss")
	if not boss is Dictionary or not boss.get("id") is String or boss.id != profile.boss_id or not _trigger_valid(boss):
		return "首领地标无效"
	return ""
