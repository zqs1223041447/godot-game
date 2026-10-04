extends SceneTree
const State = preload("res://scripts/world/map_camp_state.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const CAMP_IDS: Array[String] = ["camp_west", "camp_north", "camp_east"]
const ORDERS: Array = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
var checks := 0
var failures := 0
var reference_roots := 0
var reference_profiles := 0
var coverage: Dictionary = {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	seed(430043)
	var expected_global := randi()
	seed(430043)
	var caller_rng := RandomNumberGenerator.new()
	caller_rng.seed = 630063
	var caller_state := caller_rng.state
	_test_reference_profiles()
	_test_real_layouts()
	_test_orders()
	_test_activation_rejections()
	_test_begin_rejections()
	_test_detached_state()
	_test_natural_coverage()
	check(randi() == expected_global, "Every helper call and rejection preserves global RNG")
	check(caller_rng.state == caller_state, "Roster generation does not consume a caller-owned RNG")
	print("Map camp roster/state: %d checks, %d failures; %d reference profiles; %d reference roots" % [checks, failures, reference_profiles, reference_roots])
	quit(1 if failures else 0)


## Deliberately plain landmark fixture: geometry legality is tested separately by
## MapCampLayout. This suite checks validation, roster assignment and root state.
func _landmarks(profile: Dictionary) -> Dictionary:
	var camps: Array[Dictionary] = []
	var root_count := 8 if profile.id == "old_garden" else 12
	for index: int in range(3):
		var center := Vector2(100 + index * 300, 100)
		var positions: Array[Vector2] = []
		for root: int in range(root_count):
			positions.append(center + Vector2(root * 10, 40))
		camps.append({"id": CAMP_IDS[index], "name": "test", "center": center,
			"trigger_center": center, "trigger_radius": 64.0,
			"root_count": root_count, "positions": positions})
	return {"entry": Vector2(200, 200), "camps": camps,
		"boss": {"id": "rift_warden", "name": "test boss", "center": Vector2(900, 100),
			"trigger_center": Vector2(900, 100), "trigger_radius": 64.0}}


func _roster(state: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in CAMP_IDS:
		result.append_array(state.entries(id))
	return result


func _ids(camp_index: int, root_count: int) -> Array[int]:
	var result: Array[int] = []
	for index: int in range(root_count):
		result.append(1 + camp_index * 100 + index)
	return result


func _profiles(include_specials: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for map_id: String in ["old_garden", "broken_ruins"]:
		for tier: int in range(1, 4):
			result.append(Maps.compile_normal(map_id, tier, [], []).profile)
			if include_specials:
				for special: String in Maps.Catalog.SPECIAL:
					var compiled := Maps.compile_normal(map_id, tier, ["enemy_max_health_120", "enemy_move_speed_110"], [special])
					if compiled.ok:
						result.append(compiled.profile)
		result.append(Maps.compile(map_id, [], []).profile)
		if include_specials:
			for special: String in Maps.Catalog.SPECIAL:
				var compiled := Maps.compile(map_id, ["enemy_max_health_120", "enemy_move_speed_110"], [special])
				if compiled.ok:
					result.append(compiled.profile)
	return result


func _test_reference_profiles() -> void:
	var profiles := _profiles(true)
	check(profiles.size() == 24, "Six progression tiers and two fixed-wave maps include every legal special gate")
	for profile: Dictionary in profiles:
		reference_profiles += 1
		for seed_value: int in [0, 43, -1701]:
			var first := State.new()
			var second := State.new()
			var landmarks := _landmarks(profile)
			check(first.begin(profile, landmarks, seed_value).ok and second.begin(profile, landmarks, seed_value).ok, "Valid profile and strict integer seed begin")
			var roster := _roster(first)
			check(var_to_bytes(roster) == var_to_bytes(_roster(second)), "Same seed/profile produces a byte-identical full roster")
			check(roster.size() == profile.ordinary_target, "Entire 24/36 root roster is frozen before activation")
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			for offset: int in range(roster.size()):
				var index := offset + 1
				var entry: Dictionary = roster[offset]
				var fixed := Monsters.encounter_for_admission(profile.wave, index)
				check(entry.size() == 5 and entry.admission_index is int and entry.admission_index == index, "Only canonical admission data is stored, without runtime IDs")
				var camp_index: int = offset / (8 if profile.id == "old_garden" else 12)
				var position_index: int = offset % (8 if profile.id == "old_garden" else 12)
				check(entry.position == landmarks.camps[camp_index].positions[position_index], "Positions retain canonical camp/admission order")
				if not fixed.is_empty():
					check(entry.template_id == fixed and entry.rarity == "" and entry.mechanisms.is_empty(), "Fixed ember admission preserves the template's own rarity and consumes no ordinary roll")
				else:
					var roll := Monsters.ordinary_roll(rng, profile.wave)
					var elemental := Monsters.elemental_template_for_roll(profile.wave, index, roll)
					var special := Maps.special_template(profile, roll)
					var expected: String = special if not special.is_empty() else (elemental if not elemental.is_empty() else roll.template)
					check(entry.template_id == expected and entry.rarity == roll.rarity and entry.mechanisms == roll.mechanisms, "Independent ordinary reference preserves rarity/mechanisms and elemental then special precedence")
				reference_roots += 1
			for camp: Dictionary in first.states({}):
				check(camp.state == "dormant" and camp.roots_spawned == 0 and camp.roots_defeated == 0 and camp.reason == "", "Freezing a roster allocates no root IDs and starts dormant")
	check(not Maps.compile_normal("old_garden", 1, [], ["frost_patrol"]).ok, "Tier I cannot gain a wave-gated frost patrol")
	check(not Maps.compile("old_garden", [], ["storm_patrol"]).ok, "Fixed Old Garden cannot gain the wave-5 storm patrol")


func _test_real_layouts() -> void:
	for profile: Dictionary in _profiles(false):
		for origin: Vector2 in [Vector2(42, 104), Vector2(-317, 801)]:
			var layout := Layout.layout(profile.id, Rect2(origin, Vector2(1196, 462) / 0.65))
			var state := State.new()
			check(layout.ok and state.begin(profile, layout.landmarks, 43).ok, "Real layout output is accepted for all six tiers and both fixed maps")
			for camp: Dictionary in layout.landmarks.camps:
				var entries: Array[Dictionary] = state.entries(camp.id)
				check(entries.size() == camp.root_count, "Real camp count matches frozen roster count")
				for index: int in range(entries.size()):
					check(entries[index].position == camp.positions[index], "Real layout positions survive roster freezing exactly")
			var reversed: Dictionary = layout.landmarks.duplicate(true)
			reversed.camps.reverse()
			var other := State.new()
			check(other.begin(profile, reversed, 43).ok and var_to_bytes(_roster(other)) == var_to_bytes(_roster(state)), "Camp-ID order is canonical even if a caller reorders landmark records")


func _test_orders() -> void:
	for profile: Dictionary in _profiles(false):
		var root_count := 8 if profile.id == "old_garden" else 12
		var baseline_roster := PackedByteArray()
		var baseline_states := PackedByteArray()
		for order: Array in ORDERS:
			var state := State.new()
			check(state.begin(profile, _landmarks(profile), 4343).ok, "Activation permutation begins")
			var frozen := var_to_bytes(_roster(state))
			var defeated: Dictionary = {99999: true, 100000: true}
			var activated := 0
			for camp_index: int in order:
				check(state.activate(CAMP_IDS[camp_index], _ids(camp_index, root_count)), "Each dormant group activates exactly once")
				activated += 1
				var active_count := 0
				for row: Dictionary in state.states(defeated):
					active_count += 1 if row.state == "active" else 0
				check(active_count == activated, "Multiple camps remain active simultaneously without implicit clear")
				check(var_to_bytes(_roster(state)) == frozen, "Activation never rolls or edits roster entries")
			for camp_index: int in range(3):
				for root_id: int in _ids(camp_index, root_count):
					defeated[root_id] = false
				for row: Dictionary in state.states(defeated):
					var expected := "cleared" if CAMP_IDS.find(row.id) <= camp_index else "active"
					check(row.state == expected, "Only own authoritative root membership clears a camp; dictionary values are not requantified")
			var final_states := var_to_bytes(state.states(defeated))
			if baseline_roster.is_empty():
				baseline_roster = frozen
				baseline_states = final_states
			check(frozen == baseline_roster and final_states == baseline_states, "All six activation orders have identical full rosters and final states")


func _reject_activation(state: RefCounted, camp_id: Variant, root_ids: Variant, label: String) -> void:
	var before := var_to_bytes(state.checkpoint())
	check(not state.activate(camp_id, root_ids) and var_to_bytes(state.checkpoint()) == before, label)


func _test_activation_rejections() -> void:
	var profile: Dictionary = Maps.compile("old_garden", [], []).profile
	var state := State.new()
	_reject_activation(state, "camp_west", _ids(0, 8), "Cannot activate before begin")
	check(state.begin(profile, _landmarks(profile), 43).ok, "Rejection fixture begins")
	for id: Variant in [null, true, 1, 1.0, &"camp_west", "missing"]:
		_reject_activation(state, id, _ids(0, 8), "Non-string, coerced and unknown camp IDs reject atomically")
	for roots: Variant in [null, true, 8, {}, PackedInt64Array([1, 2, 3, 4, 5, 6, 7, 8]), [], [1], [1, 2, 3, 4, 5, 6, 7], [1, 2, 3, 4, 5, 6, 7, 8, 9]]:
		_reject_activation(state, "camp_west", roots, "Partial, oversized and non-array root sets reject atomically")
	for invalid: Variant in [0, -1, true, 1.0, "1", null, {}, []]:
		var roots: Array = [1, 2, 3, 4, 5, 6, 7, invalid]
		_reject_activation(state, "camp_west", roots, "Every root ID must be a positive genuine integer")
	_reject_activation(state, "camp_west", [1, 2, 3, 4, 5, 6, 7, 1], "Duplicate root at end rejects the entire group")
	check(state.activate("camp_west", _ids(0, 8)), "Valid group activates after rejected attempts")
	_reject_activation(state, "camp_west", _ids(2, 8), "Repeated activation does not replace recorded IDs")
	_reject_activation(state, "camp_north", [101, 102, 103, 104, 105, 106, 107, 1], "IDs cannot be reused by another camp")
	var before := var_to_bytes(state.checkpoint())
	check(state.states({10001: true, 10002: true})[0].roots_defeated == 0, "Descendant and unknown deaths cannot credit a camp")
	check(state.states({1.0: true, true: true, "2": true})[0].roots_defeated == 0, "Non-integer death keys cannot stand in for root IDs")
	check(state.states({1: true, 8: true, 10001: true})[0].roots_defeated == 2, "Only registered root membership counts once")
	check(var_to_bytes(state.checkpoint()) == before, "State projection itself never mutates authoritative state")
	var all_dead: Dictionary = {}
	for root_id: int in _ids(0, 8):
		all_dead[root_id] = true
	check(state.states(all_dead)[0].state == "cleared" and state.states(all_dead)[1].state == "dormant", "Root-complete camp clears without changing dormant camps")
	_reject_activation(state, "camp_west", _ids(2, 8), "A cleared group still cannot activate again")
	_reject_activation(state, "camp_north", _ids(0, 8), "Cleared camp root IDs remain reserved")


func _reject_begin(state: RefCounted, profile: Variant, landmarks: Variant, seed_value: Variant, label: String) -> void:
	var before := var_to_bytes(state.checkpoint())
	var result: Dictionary = state.begin(profile, landmarks, seed_value)
	check(not result.ok and not result.reason.is_empty() and var_to_bytes(state.checkpoint()) == before, label)


func _test_begin_rejections() -> void:
	var state := State.new()
	var profile: Dictionary = Maps.compile("old_garden", [], []).profile
	var landmarks := _landmarks(profile)
	_reject_begin(state, {}, landmarks, 43, "Rejected first begin leaves empty state")
	check(state.begin(profile, landmarks, 43).ok and state.activate("camp_west", _ids(0, 8)), "Live state is preserved across rejected replacement attempts")
	for invalid: Variant in [null, false, 43.0, "43", {}, []]:
		_reject_begin(state, profile, landmarks, invalid, "Non-integer seeds cannot be coerced")
	var caller_rng := RandomNumberGenerator.new()
	caller_rng.seed = 987
	var caller_state := caller_rng.state
	_reject_begin(state, profile, landmarks, caller_rng, "Caller RNG cannot be coerced into a seed or consumed")
	check(caller_rng.state == caller_state, "Rejecting a caller RNG preserves its state")
	for invalid: Variant in [null, true, 1, [], {}, {"id": "missing"}]:
		_reject_begin(state, invalid, landmarks, 43, "Compiler-invalid profiles reject without mutation")
	for key: String in ["wave", "ordinary_target"]:
		var changed := profile.duplicate(true)
		changed[key] = float(changed[key])
		_reject_begin(state, changed, landmarks, 43, "Fixed-wave profile numeric equality cannot coerce counts or wave")
	for invalid: Variant in [null, false, [], {}, {"entry": Vector2.ZERO}]:
		_reject_begin(state, profile, invalid, 43, "Malformed landmark containers reject atomically")
	for invalid: Variant in [null, Vector2(INF, 1), Vector2(1, NAN), Vector2i(1, 2), [1, 2]]:
		var changed := landmarks.duplicate(true)
		changed.entry = invalid
		_reject_begin(state, profile, changed, 43, "Entry must be a finite Vector2")
	for invalid: Variant in [null, {}, [], landmarks.camps.slice(0, 2), landmarks.camps + [landmarks.camps[0]]]:
		var changed := landmarks.duplicate(true)
		changed.camps = invalid
		_reject_begin(state, profile, changed, 43, "Exactly three camp dictionaries are required")
	for invalid: Variant in [null, true, 8, "camp_west", [], {}]:
		var changed := landmarks.duplicate(true)
		changed.camps = [invalid, landmarks.camps[1], landmarks.camps[2]]
		_reject_begin(state, profile, changed, 43, "Invalid camp records reject before typed iteration")
	for invalid: Variant in [true, 1, 1.0, &"camp_west", "missing", "camp_north"]:
		var changed := landmarks.duplicate(true)
		changed.camps[0].id = invalid
		_reject_begin(state, profile, changed, 43, "Camp IDs must be genuine, unique known strings")
	for invalid: Variant in [true, 8.0, "8", 0, 7, 9, 12]:
		var changed := landmarks.duplicate(true)
		changed.camps[0].root_count = invalid
		_reject_begin(state, profile, changed, 43, "Counts must be exact map-specific integers")
	for key: String in ["center", "trigger_center", "trigger_radius", "positions"]:
		var invalids: Array = [null]
		if key == "positions":
			invalids = [null, {}, [], landmarks.camps[0].positions.slice(0, 7)]
		elif key == "trigger_radius":
			invalids = [null, true, "64", 0.0, -1.0, INF, NAN]
		else:
			invalids = [null, Vector2(INF, 0), Vector2(0, NAN), Vector2i(1, 1)]
		for invalid: Variant in invalids:
			var changed := landmarks.duplicate(true)
			changed.camps[0][key] = invalid
			_reject_begin(state, profile, changed, 43, "Camp geometry and position shape must be finite and valid")
	var bad_positions := landmarks.duplicate(true)
	bad_positions.camps[0].positions[7] = Vector2(INF, 0)
	_reject_begin(state, profile, bad_positions, 43, "A final invalid spawn point rejects the whole begin")
	for invalid: Variant in [null, true, 1, Vector2i(10, 10), "position"]:
		var changed := landmarks.duplicate(true)
		var positions: Array = []
		positions.append_array(changed.camps[0].positions.slice(0, 7))
		positions.append(invalid)
		changed.camps[0].positions = positions
		_reject_begin(state, profile, changed, 43, "Spawn positions cannot coerce incompatible variant types")
	for invalid: Variant in [null, true, [], {}, "rift_warden"]:
		var changed := landmarks.duplicate(true)
		changed.boss = invalid
		_reject_begin(state, profile, changed, 43, "Malformed boss records reject before field access")
	for key: String in ["id", "center", "trigger_center", "trigger_radius"]:
		var changed := landmarks.duplicate(true)
		changed.boss[key] = null
		_reject_begin(state, profile, changed, 43, "Boss metadata must retain identity and finite trigger geometry")
	var normal: Dictionary = Maps.compile_normal("old_garden", 2, [], []).profile
	normal.journey_tier = 2.0
	_reject_begin(state, normal, landmarks, 43, "Current compiler canonical validation rejects changed progression profile types")


func _test_detached_state() -> void:
	var state := State.new()
	var profile: Dictionary = Maps.compile("broken_ruins", [], []).profile
	var landmarks := _landmarks(profile)
	check(state.begin(profile, landmarks, 43).ok, "Detached-state fixture begins")
	var before := var_to_bytes(state.checkpoint())
	var entries: Array[Dictionary] = state.entries("camp_west")
	entries[0].mechanisms.append("external")
	entries[0].position = Vector2.ZERO
	entries.clear()
	var detached: Dictionary = state.checkpoint()
	detached.camps[0].root_ids.append(111)
	detached.camps[1].entries[0].template_id = "external"
	detached.landmarks.camps.clear()
	var projected: Array[Dictionary] = state.states({})
	projected[0].state = "cleared"
	projected.clear()
	profile.wave = 999
	landmarks.camps[0].positions[0] = Vector2.ZERO
	landmarks.camps.clear()
	check(var_to_bytes(state.checkpoint()) == before, "Inputs and all getter depths are detached from authority")
	check(state.entries("missing").is_empty(), "Unknown roster lookup is empty")
	var roots := _ids(0, 12)
	check(state.activate("camp_west", roots), "Detached root-id fixture activates")
	roots[0] = 999
	check(state.states({1: true})[0].roots_defeated == 1, "Caller cannot mutate IDs after successful activation")
	var fresh: Dictionary = Maps.compile("old_garden", [], []).profile
	check(state.begin(fresh, _landmarks(fresh), 44).ok and state.states({})[0].state == "dormant", "A valid new begin replaces prior state with a complete fresh roster")
	state.clear()
	check(state.checkpoint().is_empty() and state.entries("camp_west").is_empty() and state.states({1: true}).is_empty(), "Clear removes every roster and registration")
	state.clear()
	check(state.checkpoint().is_empty(), "Repeated clear is harmless")


func _test_natural_coverage() -> void:
	for map_id: String in ["old_garden", "broken_ruins"]:
		var profile: Dictionary = Maps.compile(map_id, [], []).profile
		for seed_value: int in range(32):
			var state := State.new()
			check(state.begin(profile, _landmarks(profile), seed_value).ok, "Natural coverage seed begins")
			for entry: Dictionary in _roster(state):
				coverage[entry.template_id] = true
				coverage[entry.rarity] = true
				if entry.template_id in ["frost_guard", "storm_skitter"]:
					coverage[entry.template_id + ":" + entry.rarity] = true
	for key: String in ["normal", "magic", "rare", "crawler", "skitter", "brute", "splitter", "brood_host", "ember_guard", "frost_guard", "storm_skitter", "frost_guard:normal", "storm_skitter:normal"]:
		check(coverage.has(key), "Natural seed samples retain " + key + " without forced up-tiering")
	var profile: Dictionary = Maps.compile("broken_ruins", [], []).profile
	var first := State.new()
	var second := State.new()
	check(first.begin(profile, _landmarks(profile), 11).ok and second.begin(profile, _landmarks(profile), 12).ok, "Distinct deterministic seeds begin")
	check(var_to_bytes(_roster(first)) != var_to_bytes(_roster(second)), "Distinct seeds can yield distinct frozen rosters")
