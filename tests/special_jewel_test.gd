extends SceneTree
## Unified final-candidate legality and schema7 regression tests, isolated user://.
const Model = preload("res://scripts/build_state.gd")
const P = preload("res://scripts/passive_data.gd")
const J = preload("res://scripts/jewel_data.gd")
const Rules = preload("res://scripts/passives/allocation_rules.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
var checks: int = 0
var failures: int = 0
var changes: int = 0
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_catalog_and_frozen_rng, _pure_boundaries_and_circles, _all_socket_geometry,
		_remote_allocation_and_transactions, _alternate_support_and_atomic_swap,
		_capacity_and_reset, _schema_roundtrip_and_legacy, _schema_rejections]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	print("Special jewel rules/state: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _changed() -> void:
	changes += 1


func _build() -> Model:
	var state := Model.new()
	state.add_xp(1000000000)
	state.changed.connect(_changed)
	changes = 0
	return state


func _path(target: String) -> Array[String]:
	var queue: Array[String] = [P.START_ID]
	var previous: Dictionary = {P.START_ID: ""}
	var cursor: int = 0
	while cursor < queue.size() and not previous.has(target):
		var id: String = queue[cursor]
		cursor += 1
		for neighbor: String in P.get_neighbors(id):
			if not previous.has(neighbor):
				previous[neighbor] = id
				queue.append(neighbor)
	var result: Array[String] = []
	var id: String = target
	while id != P.START_ID and previous.has(id):
		result.push_front(id)
		id = previous[id]
	return result


func _allocate_path(state: Model, target: String) -> void:
	for id: String in _path(target):
		if not state.allocated_nodes.has(id):
			_expect(state.allocate_passive(id), "Allocate physical path " + id)


func _special(state: Model, socket: String = "ember_3_0") -> String:
	_allocate_path(state, socket)
	var id: String = state.award_special_jewel()
	_expect(not id.is_empty() and state.socket_jewel(socket, id), "Award and insert fixed special jewel " + socket)
	return id


func _silent_reject(state: Model, action: Callable, label: String) -> void:
	var before: Dictionary = state._snapshot()
	var count: int = changes
	var stats: Dictionary = state.get_stats()
	_expect(not action.call(), label)
	_expect(state._snapshot() == before and changes == count and state.get_stats() == stats, "Rejected operation preserves full state, stats and signals: " + label)


func _catalog_and_frozen_rng() -> void:
	var fresh := Model.new()
	_expect(fresh.jewels.size() == 3 and fresh.next_jewel_id == 4, "No starter special jewel is silently awarded")
	var fixed: Dictionary = J.generate_special("jewel_000042")
	_expect(fixed == {"id": "jewel_000042", "base": "branchfinder", "rarity": "special", "affixes": []}, "Special instance has only fixed four-field identity")
	_expect(J.validate_instance(fixed) and not J.validate_instance(fixed, false), "Special vocabulary is explicitly version gated")
	_expect(J.get_stats(fixed).is_empty() and J.allocation_rule(fixed) == {"id": "disconnected_radius", "radius": 280.0, "types": ["small", "notable"]}, "Intrinsic rule carries no direct stat modifiers")
	_expect(J.display_name(fixed).contains("寻枝晶玉") and J.get_description(fixed).contains("280") and J.get_description(fixed).contains("1 点"), "Player text states radius and point cost")
	var definition: Dictionary = J.base_definition("branchfinder")
	definition.radius = 10000.0
	var rule: Dictionary = J.allocation_rule(fixed)
	rule.types.append("socket")
	_expect(J.base_definition("branchfinder").radius == 280.0 and not J.allocation_rule(fixed).types.has("socket"), "Returned metadata cannot mutate executable intrinsic rules")
	for invalid: Dictionary in [{"id":"jewel_000042","base":"branchfinder","rarity":"magic","affixes":[]},
		{"id":"jewel_000042","base":"branchfinder","rarity":"special","affixes":[{"id":"force","value":4.0}]},
		{"id":"jewel_000042","base":"branchfinder","rarity":"special","affixes":[],"radius":9999},
		{"id":"jewel_000042","base":"unknown_rule","rarity":"special","affixes":[]},
		{"id":"jewel_000042","base":"emberheart","rarity":"special","affixes":[]}]:
		_expect(not J.validate_instance(invalid) and J.allocation_rule(invalid).is_empty(), "Malformed special identity cannot supply a rule")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/special_jewel_legacy_rng.json"))
	_expect(J.BASES == str_to_var(fixture.bases) and J.RARITIES == str_to_var(fixture.rarities) and J.AFFIXES == str_to_var(fixture.affixes), "All ordinary definitions equal independently frozen v0.8 metadata")
	for sequence: Dictionary in fixture.sequences:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(sequence.seed)
		for sample: Dictionary in sequence.samples:
			var actual: Dictionary = J.generate(rng, sample.instance.id)
			_expect(actual == sample.instance and str(rng.state) == sample.rng_state, "Legacy roll and complete RNG state equal frozen v0.8 golden sequence")
	var replay := Model.new()
	var stream := RandomNumberGenerator.new()
	stream.seed = 71
	var oracle := RandomNumberGenerator.new()
	oracle.seed = 71
	var first: String = replay.award_jewel(stream)
	_expect(replay.jewels[first] == J.generate(oracle, first), "Ordinary public award uses unchanged legacy generator")
	var rng_state: int = stream.state
	replay.changed.connect(_changed)
	changes = 0
	var special: String = replay.award_special_jewel()
	_expect(special == "jewel_000005" and changes == 1 and stream.state == rng_state, "Special award shares serials, signals once, and consumes no ordinary RNG")
	var next: String = replay.award_jewel(stream)
	_expect(next == "jewel_000006" and replay.jewels[next] == J.generate(oracle, next) and stream.state == oracle.state, "Ordinary sequence resumes unchanged after fixed special reward")
	completed = true


func _node(kind: String, position: Vector2, neighbors: Array) -> Dictionary:
	return {"name": kind, "type": kind, "position": position, "neighbors": neighbors}


func _pure_boundaries_and_circles() -> void:
	var graph: Dictionary = {
		"origin": _node("start", Vector2(-500, 0), ["socket"]),
		"socket": _node("socket", Vector2.ZERO, ["origin"]),
		"on": _node("small", Vector2(280, 0), ["beyond"]),
		"inside": _node("notable", Vector2(0, -279.999), []),
		"beyond": _node("small", Vector2(280.001, 0), ["on"]),
		"remote_socket": _node("socket", Vector2(100, 0), ["circular_socket"]),
		"circular_socket": _node("socket", Vector2(200, 0), ["remote_socket"]),
	}
	var jewels: Dictionary = {"jewel_000001": J.generate_special("jewel_000001"), "jewel_000002": J.generate_special("jewel_000002"), "jewel_000003": J.generate_special("jewel_000003")}
	var sockets: Dictionary = {"socket": "jewel_000001"}
	var allocated: Array = ["origin", "socket", "on", "inside"]
	var before: Array = [allocated.duplicate(true), sockets.duplicate(true), jewels.duplicate(true), graph.duplicate(true)]
	var result: Dictionary = Rules.analyze(allocated, sockets, jewels, graph)
	_expect(result.legal and result.remote_nodes == ["on", "inside"], "At-boundary and just-inside nodes are individually legal remote nodes")
	_expect(result.granted_by.has("on") and not result.granted_by.has("beyond") and not result.granted_by.has("remote_socket"), "Exact <=280 boundary excludes just-outside nodes and all sockets")
	_expect(not result.eligible_nodes.has("beyond"), "A covered allocated neighbor cannot grow an outward branch")
	_expect(not Rules.analyze(allocated + ["beyond"], sockets, jewels, graph).legal, "Final analyzer rejects unsupported outward extension")
	sockets["remote_socket"] = "jewel_000002"
	sockets["circular_socket"] = "jewel_000003"
	result = Rules.analyze(allocated + ["remote_socket", "circular_socket"], sockets, jewels, graph)
	_expect(not result.legal and result.active_sources.size() == 1 and result.unsupported_nodes.has("remote_socket") and result.unsupported_nodes.has("circular_socket"), "Neither source coverage nor circular remote sockets can activate a jewel")
	sockets.erase("remote_socket")
	sockets.erase("circular_socket")
	_expect(before == [allocated, sockets, jewels, graph], "Pure analyses never mutate caller-owned collections")
	result.granted_by.clear()
	_expect(Rules.analyze(allocated, sockets, jewels, graph).granted_by.has("on"), "Returned results are detached and recomputed")
	completed = true


func _all_socket_geometry() -> void:
	var nodes: Dictionary = P.get_nodes()
	var count: int = 0
	for socket: String in nodes:
		if nodes[socket].type != "socket":
			continue
		count += 1
		var state := _build()
		var jewel_id: String = state.award_special_jewel()
		var inactive: Dictionary = state.jewel_radius_preview(socket, jewel_id)
		_expect(not inactive.active and inactive.radius == 280.0, "Unallocated socket previews intrinsic coverage without activating it")
		_allocate_path(state, socket)
		var preview: Dictionary = state.socket_preview_analysis(socket, jewel_id)
		_expect(preview.legal and preview.active_sources.has(socket) and state.socketed_jewels.is_empty(), "Candidate preview is read-only and uses final socket state")
		_expect(state.socket_jewel(socket, jewel_id), "Insert special in each original socket")
		var analysis: Dictionary = state.allocation_analysis()
		var covered: int = 0
		for id: String in nodes:
			var expected: bool = nodes[id].type in ["small", "notable"] and nodes[socket].position.distance_to(nodes[id].position) <= 280.0
			_expect(analysis.granted_by.has(id) == expected, "All12 geometry agrees with independent distance/type oracle: " + socket + "/" + id)
			if expected:
				covered += 1
		_expect(covered == (10 if socket.contains("_3_") else 11), "Stable original geometry has bounded inner/outer coverage")
		_expect(analysis.active_sources[socket].covered_nodes.size() == covered, "Preview source coverage matches granted eligibility")
	_expect(count == 12, "Every original socket exercised")
	completed = true


func _remote_allocation_and_transactions() -> void:
	var state := _build()
	var jewel_id: String = _special(state)
	_allocate_path(state, "gale_3_0")
	_expect(state.socket_jewel("gale_3_0", "jewel_000001"), "Set up occupied destination with ordinary jewel")
	var stats: Dictionary = state.get_stats()
	var points: int = state.talent_points
	var count: int = changes
	_expect(state.allocate_passive("ember_3_2"), "A covered distant notable allocates without physical neighbors")
	_expect(state.talent_points == points - 1 and changes == count + 1 and state.allocation_analysis().remote_nodes.has("ember_3_2"), "Remote allocation spends exactly one point and signals once")
	_expect(state.get_stats().damage > stats.damage and state.get_combat_snapshot().base_damage > stats.damage, "Remote notable changes real derived stats and combat snapshot")
	_expect(state.allocation_sources("ember_3_2") == ["ember_3_0"], "Rule source can be inspected for a remote node")
	var remaining_points: int = state.talent_points
	state.talent_points = 0
	_silent_reject(state, func(): return state.allocate_passive("ember_4_2"), "Covered remote allocation still refuses zero point budget")
	state.talent_points = remaining_points
	_silent_reject(state, func(): return state.allocate_passive("ember_4_3"), "Covered remote node cannot open uncovered next branch")
	_silent_reject(state, func(): return state.allocate_passive("ember_5_3"), "Remote socket cannot be unlocked")
	_silent_reject(state, func(): return state.allocate_passive("ember_6_0"), "Uncovered distant node refuses allocation")
	_expect(state.remove_jewel_reason("ember_3_0").contains(P.get_nodes().ember_3_2.name), "Unsupported removal identifies affected node by player-visible name")
	_silent_reject(state, func(): return state.remove_jewel("ember_3_0"), "Cannot remove sole support")
	_silent_reject(state, func(): return state.socket_jewel("ember_3_0", "jewel_000002"), "Cannot replace sole support with ordinary inventory jewel")
	_silent_reject(state, func(): return state.socket_jewel("gale_3_0", jewel_id), "Cannot swap sole support to uncovered occupied destination")
	_expect(state.remove_jewel("gale_3_0"), "Unrelated ordinary jewel removes normally")
	_silent_reject(state, func(): return state.socket_jewel("gale_3_0", jewel_id), "Cannot move sole support to empty distant socket")
	_silent_reject(state, func(): return state.refund_passive("ember_3_0"), "Cannot refund supporting source socket")
	_silent_reject(state, func(): return state.refund_passive("ember_2_0"), "Cannot refund bridge that disconnects supporting socket")
	_expect(state.allocate_passive("ember_3_1") and state.allocation_analysis().connected.has("ember_3_2"), "Later physical bridge makes remote notable ordinary connected allocation")
	_expect(state.refund_passive("ember_3_1") and state.allocation_analysis().remote_nodes.has("ember_3_2"), "Bridge refund can retain individually covered remote nodes")
	_expect(state.allocate_passive("ember_3_1") and state.remove_jewel("ember_3_0"), "Physical route permits removing formerly needed jewel")
	_silent_reject(state, func(): return state.refund_passive("ember_3_1"), "Without coverage same bridge refund refuses")
	var analysis: Dictionary = state.allocation_analysis()
	state.allocated_nodes.erase("ember_3_1")
	_expect(analysis.legal and not state.allocation_analysis().legal, "Direct state mutations cannot leave a stale legality cache")
	completed = true


func _alternate_support_and_atomic_swap() -> void:
	var state := _build()
	var first: String = _special(state)
	var alternate: String = _special(state, "grove_3_0")
	_expect(state.allocate_passive("ember_3_2") and state.allocation_sources("ember_3_2").size() == 2, "Overlapping active sources independently cover one remote notable")
	_expect(state.remove_jewel("ember_3_0") and state.allocation_analysis().legal, "Alternative source preserves legality after first source removal")
	_silent_reject(state, func(): return state.remove_jewel("grove_3_0"), "Last supporting source remains protected")
	_expect(state.socket_jewel("ember_3_0", first), "Restore alternative support")
	_expect(state.refund_passive("ember_3_0") and state.jewel_inventory.has(first), "Socket refund returns its jewel when alternative coverage survives")
	_expect(state.remove_jewel_reason("grove_3_0").contains("ember_3_2"), "Reason includes unambiguous node identity")
	state = _build()
	first = _special(state)
	alternate = _special(state, "gale_3_0")
	_expect(state.allocate_passive("ember_3_2") and state.allocate_passive("gale_3_2"), "Distant separate source regions each have dependent remote allocation")
	_silent_reject(state, func(): return state.remove_jewel("ember_3_0"), "First half of special swap would be invalid")
	_silent_reject(state, func(): return state.remove_jewel("gale_3_0"), "Second half of special swap would be invalid")
	var count: int = changes
	_expect(state.socket_jewel("gale_3_0", first), "Atomic special/special swap validates final coverage instead of invalid intermediate removals")
	_expect(state.socketed_jewels.ember_3_0 == alternate and state.socketed_jewels.gale_3_0 == first and changes == count + 1, "Atomic swap preserves identities and emits one signal")
	var third: String = state.award_special_jewel()
	_expect(state.socket_jewel("ember_3_0", third) and state.jewel_inventory.has(alternate), "Special replacement returns old identity while retaining coverage")
	completed = true


func _capacity_and_reset() -> void:
	var state := _build()
	var special: String = _special(state)
	state.allocate_passive("ember_3_2")
	var points: int = state.talent_points + state.allocated_nodes.size() - 1
	var owned: Dictionary = state.jewels.duplicate(true)
	var count: int = changes
	state.refund_talents()
	_expect(state.allocated_nodes == ["origin"] and state.socketed_jewels.is_empty() and state.jewels == owned and state.jewel_inventory.has(special) and state.talent_points == points and changes == count + 1, "Full reset atomically returns all points and jewels despite dependency")
	var before: Dictionary = state._snapshot()
	state.refund_talents()
	_expect(state._snapshot() == before and changes == count + 1, "Repeated reset is a silent no-op")
	while state.jewels.size() < Model.MAX_JEWELS:
		var id: String = state.award_special_jewel()
		_expect(not id.is_empty(), "Special award obeys available owned capacity")
		if id.is_empty(): break
	_silent_reject(state, func(): return not state.award_special_jewel().is_empty(), "Owned-record capacity refuses special award without consuming identity")
	state = _build()
	var gear: Dictionary = {"id":"gear_000001","base_id":"runewood_focus","rarity":"normal","item_level":1,"affixes":[]}
	_expect(Equipment.validate_instance(gear), "Capacity fixture uses valid typed base")
	state.equipment_instances[gear.id] = gear
	state.inventory.append(gear.id)
	state.next_equipment_id = 2
	state.equip(gear.id)
	_special(state)
	while state.jewels.size() < 63:
		var id: String = state.award_special_jewel()
		if id.is_empty(): break
	_expect(state.jewels.size() == 63 and not state._validate_snapshot(state._snapshot()).is_empty(), "All-owned 96-cell reservation includes hidden equipped/socketed items")
	_silent_reject(state, func(): return not state.award_special_jewel().is_empty(), "Special award cannot borrow reserved return space")
	for slot: String in Model.EQUIPMENT_SLOTS: state.unequip(slot)
	state.refund_talents()
	_expect(not state._validate_snapshot(state._snapshot()).is_empty(), "All items can return at full reserved capacity without loss")
	state = _build()
	state.next_jewel_id = Model.MAX_JEWEL_ID
	_expect(state.award_special_jewel() == "jewel_999999999" and state.next_jewel_id == Model.MAX_JEWEL_ID + 1, "Last special serial is issued exactly once")
	_silent_reject(state, func(): return not state.award_special_jewel().is_empty(), "Exhausted special serial cannot wrap or reuse identity")
	state.next_jewel_id = 1
	_silent_reject(state, func(): return not state.award_special_jewel().is_empty(), "Stale special serial cannot replace an existing jewel")
	completed = true


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Open isolated fixture " + path)
	if file != null:
		file.store_buffer(bytes)
		file.close()


func _legacy_six() -> Dictionary:
	# Literal schema6 vocabulary: real typed gear/supports and ordinary jewel only.
	return {"version":6,"inventory":["gear_000042"],"equipped":{"weapon":"gear_000042"},
		"equipment_instances":{"gear_000042":{"id":"gear_000042","base_id":"runewood_focus","rarity":"magic","item_level":16,"affixes":[{"id":"attack_added_physical","tier":3,"value":6}]}},
		"next_equipment_id":43,"skill_slots":["tornado","frost","nova","dash","ward"],"skill_supports":{"tornado":["focus","volley"]},
		"level":4,"xp":7,"talent_points":5,"allocated_nodes":["origin","ember_1_0","ember_2_0","ember_3_0"],
		"jewels":{"jewel_000009":{"id":"jewel_000009","base":"emberheart","rarity":"magic","affixes":[{"id":"force","value":4.0},{"id":"tempo","value":0.08}]}},
		"jewel_inventory":[],"socketed_jewels":{"ember_3_0":"jewel_000009"},"next_jewel_id":12,"backpack_positions":{}}


func _schema_roundtrip_and_legacy() -> void:
	var state := _build()
	_special(state)
	state.allocate_passive("ember_3_2")
	state.set_skill_supports("tornado", ["volley", "focus"])
	var before: Dictionary = state._snapshot()
	var path: String = "user://special_jewel_v7.json"
	_expect(Model.SAVE_VERSION == 11 and before.size() == 17 and state.save_build(path) == OK, "Current schema retains the 17-field save shape")
	for iteration: int in range(3):
		var restored := Model.new()
		restored.changed.connect(_changed)
		changes = 0
		_expect(restored.load_build(path) and restored._snapshot() == before and changes == 1 and not restored.migrated_from_v6, "Special remote save reloads atomically without migration")
		_expect(restored.get_stats() == state.get_stats() and restored.get_skill_cast("tornado") == state.get_skill_cast("tornado"), "Special roundtrip preserves actual stats and compiled combat")
		_expect(restored.save_build(path) == OK, "Repeated special roundtrip stays save-valid")
	var legacy: Dictionary = _legacy_six()
	_expect(Equipment.validate_instance(legacy.equipment_instances.gear_000042), "Literal v6 typed gear is valid")
	var bytes: PackedByteArray = PackedByteArray([239,187,191])
	bytes.append_array(("\r\n  " + JSON.stringify(legacy, "  ", false, true).replace("\n", "\r\n") + "\r\n\r\n").to_utf8_buffer())
	path = "user://special_jewel_legacy_v6.json"
	var backup: String = path + ".v6-backup.json"
	DirAccess.remove_absolute(backup)
	_write_bytes(path, bytes)
	var loaded := Model.new()
	loaded.changed.connect(_changed)
	changes = 0
	_expect(loaded.load_build(path) and loaded.migrated_from_v6 and changes == 1, "Literal v6 typed build with BOM/CRLF migrates once")
	var expected: Dictionary = legacy.duplicate(true)
	expected.version = Model.SAVE_VERSION
	expected.crafting = {"materials":{"calibration_shard":0},"revision":0}
	_expect(loaded._snapshot() == expected and loaded.jewels.size() == 1 and loaded.next_jewel_id == 12, "Migration changes version only, preserving gear/supports/points/locations and granting no special")
	_expect(FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(backup), "Read-only migration preserves exact bytes without premature backup")
	var copy: String = "user://special_jewel_save_as.json"
	_expect(loaded.save_build(copy) == OK and not FileAccess.file_exists(backup) and FileAccess.get_file_as_bytes(path) == bytes, "Save-as does not consume source-byte protection")
	_expect(loaded.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Original-path upgrade preserves BOM, CRLF and all source bytes")
	_expect(loaded.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Repeated saving cannot rewrite original backup")
	var conflict_path: String = "user://special_jewel_backup_conflict.json"
	_write_bytes(conflict_path, bytes)
	_write_bytes(conflict_path + ".v6-backup.json", (bytes.get_string_from_utf8().trim_prefix("\ufeff")).to_utf8_buffer())
	var conflict := Model.new()
	_expect(conflict.load_build(conflict_path) and conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(conflict_path) == bytes, "Different bytes with identical parsed content still block conflicting migration backup")
	var stale_path: String = "user://special_jewel_source_stale.json"
	_write_bytes(stale_path, bytes)
	var stale := Model.new()
	_expect(stale.load_build(stale_path), "Stale-source guard fixture loads")
	var rewritten: PackedByteArray = JSON.stringify(legacy).to_utf8_buffer()
	_write_bytes(stale_path, rewritten)
	_expect(stale.save_build(stale_path) == ERR_FILE_ALREADY_IN_USE and FileAccess.get_file_as_bytes(stale_path) == rewritten, "Source changed only in encoding/formatting is still protected byte-exactly")
	var alias_path: String = "user://special_jewel_source_alias.json"
	DirAccess.remove_absolute(alias_path + ".v6-backup.json")
	_write_bytes(alias_path, bytes)
	var alias_state := Model.new()
	_expect(alias_state.load_build(alias_path) and alias_state.save_build(ProjectSettings.globalize_path(alias_path)) == OK and FileAccess.get_file_as_bytes(alias_path + ".v6-backup.json") == bytes, "Absolute alias of original user path cannot bypass legacy byte backup")
	completed = true


func _reject_snapshot(state: Model, candidate: Dictionary, label: String) -> void:
	var path: String = "user://special_jewel_rejected.json"
	var bytes: PackedByteArray = JSON.stringify(candidate, "\t", true, true).to_utf8_buffer()
	_write_bytes(path, bytes)
	var before: Dictionary = state._snapshot()
	var count: int = changes
	_expect(not state.load_build(path) and state._snapshot() == before and changes == count, "Rejected load is atomic and silent: " + label)
	_expect(state.save_build(path) == ERR_INVALID_DATA and not state.save_block_reason(path).is_empty() and FileAccess.get_file_as_bytes(path) == bytes, "Rejected file remains protected from default/old state autosave: " + label)


func _schema_rejections() -> void:
	var state := _build()
	var id: String = _special(state)
	state.allocate_passive("ember_3_2")
	var valid: Dictionary = state._snapshot()
	var candidate: Dictionary
	for version: int in [2,3,4,5,6]:
		candidate = valid.duplicate(true)
		candidate.version = version
		candidate.erase("crafting")
		if version < 5: candidate.erase("skill_supports")
		if version < 4:
			candidate.erase("equipment_instances")
			candidate.erase("next_equipment_id")
		_reject_snapshot(state, candidate, "Special identity spoofed into old version %d" % version)
	candidate = valid.duplicate(true)
	candidate.version = Model.SAVE_VERSION + 1
	_reject_snapshot(state, candidate, "Future version")
	for key: String in ["rule_id", "radius", "rules", "grants"]:
		candidate = valid.duplicate(true)
		candidate.jewels[id][key] = "untrusted"
		_reject_snapshot(state, candidate, "Injected executable field " + key)
	candidate = valid.duplicate(true)
	candidate.jewels[id].base = "unknown_special"
	_reject_snapshot(state, candidate, "Unknown special base/rule")
	candidate = valid.duplicate(true)
	candidate.jewels[id].rarity = "rare"
	_reject_snapshot(state, candidate, "Special base with forged ordinary rarity")
	candidate = valid.duplicate(true)
	candidate.jewels[id].affixes = [{"id":"force","value":4.0}]
	_reject_snapshot(state, candidate, "Special with forged stat affix")
	candidate = valid.duplicate(true)
	candidate.allocated_nodes.erase("ember_2_0")
	candidate.talent_points += 1
	_reject_snapshot(state, candidate, "Disconnected source socket cannot support itself")
	candidate = valid.duplicate(true)
	candidate.allocated_nodes.append("ember_4_3")
	candidate.talent_points -= 1
	_reject_snapshot(state, candidate, "Unsupported outward node despite adjacent remote node")
	candidate = valid.duplicate(true)
	candidate.jewel_inventory.append(id)
	_reject_snapshot(state, candidate, "Special ownership duplicated between socket and inventory")
	candidate = _legacy_six()
	candidate.version = 5
	candidate.erase("crafting")
	_reject_snapshot(state, candidate, "Schema5 still refuses schema6 typed gear")
	candidate = _legacy_six()
	candidate.allocated_nodes.append("ember_3_2")
	candidate.talent_points -= 1
	_reject_snapshot(state, candidate, "Schema6 ordinary jewel cannot authorize disconnected allocation")
	completed = true
