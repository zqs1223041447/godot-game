extends SceneTree
## Skill-keyed transactions and schema-v5 preservation. Run with disposable XDG roots.
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")

var checks: int = 0
var failures: int = 0
var changes: int = 0
var _finished: bool = false


func _initialize() -> void:
	_case(_test_assignments, "atomic support assignment and compatibility")
	_case(_test_identity_and_detachment, "skill identity and detached views")
	_case(_test_compiled_contract, "compiled cost, count and commutativity")
	_case(_test_reject_snapshots, "malformed snapshot rejection")
	_case(_test_roundtrip, "schema-five round trip")
	_case(_test_v4_migration, "true schema-four migration and byte preservation")
	print("Skill support state: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Case completes without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.00001, "%s (actual %.8f, expected %.8f)" % [label, value, expected])


func _changed() -> void:
	changes += 1


func _same_set(actual: Array, expected: Array) -> bool:
	var left: Array = actual.duplicate()
	var right: Array = expected.duplicate()
	left.sort()
	right.sort()
	return left == right


func _test_assignments() -> void:
	var state = Model.new()
	_expect(state._snapshot().version == Model.SAVE_VERSION and state._snapshot().skill_supports.is_empty(), "Fresh schema-five build starts with no implicit support links")
	state.changed.connect(_changed)
	changes = 0
	for skill: String in ["tornado", "bolt", "frost"]:
		_expect(state.support_reason(skill, "volley").is_empty(), "Projectile skill explicitly accepts volley: " + skill)
		_expect(state.add_skill_support(skill, "volley"), "First linked support commits: " + skill)
		_expect(state.add_skill_support(skill, "focus"), "Second linked support commits independently: " + skill)
		_expect(_same_set(state.get_skill_supports(skill), ["volley", "focus"]), "Each supported skill owns both links: " + skill)
	_expect(changes == 6, "Six successful assignments emit exactly six changes")
	var before: Dictionary = state._snapshot()
	_expect(not state.set_skill_supports("tornado", ["volley", "focus"]) and not state.set_skill_supports("tornado", ["focus", "volley"]), "Repeated or reordered identical links are semantic no-ops")
	for skill: String in ["tornado", "bolt", "frost"]:
		_expect(not state.support_reason(skill, "volley").is_empty(), "Duplicate support has a visible rejection reason: " + skill)
		_expect(not state.add_skill_support(skill, "volley"), "Duplicate assignment rejects: " + skill)
		_expect(not state.set_skill_supports(skill, ["volley", "volley"]), "Duplicate replacement rejects wholly: " + skill)
		_expect(not state.set_skill_supports(skill, ["focus", "volley", "focus"]), "A third link rejects wholly: " + skill)
		_expect(not state.set_skill_supports(skill, ["volley", 7]), "Mixed-type support list rejects wholly: " + skill)
	_expect(not state.add_skill_support("unknown", "volley") and not state.add_skill_support("bolt", "unknown"), "Unknown skill and support IDs reject")
	_expect(not state.set_skill_supports("unknown", []) and not state.remove_skill_support("unknown", "volley"), "Empty replacement or removal cannot manufacture an unknown skill")
	for skill: String in ["nova", "dash", "ward", "meteor", "chain", "basic"]:
		for support: String in ["volley", "focus"]:
			_expect(not state.support_reason(skill, support).is_empty() and not state.add_skill_support(skill, support), "Unsupported delivery rejects with a reason: " + skill + "/" + support)
	_expect(state._snapshot() == before and changes == 6, "Every failed assignment preserves all build fields and emits no signal")
	_expect(state.remove_skill_support("bolt", "volley") and state.get_skill_supports("bolt") == ["focus"] and changes == 7, "Remove changes only the selected link and signals once")
	before = state._snapshot()
	_expect(not state.remove_skill_support("bolt", "volley") and not state.remove_skill_support("bolt", "unknown"), "Repeated or unknown removal rejects")
	_expect(state._snapshot() == before and changes == 7, "Failed removal is atomic and silent")
	_expect(state.set_skill_supports("bolt", []) and changes == 8 and state.get_skill_supports("bolt").is_empty(), "Empty replacement removes a skill's links once")
	_expect(not state.set_skill_supports("bolt", []) and changes == 8, "Repeated empty assignment is silent")
	_finished = true


func _test_identity_and_detachment() -> void:
	var state = Model.new()
	state.set_skill_supports("bolt", ["volley"])
	state.set_skill_supports("frost", ["focus"])
	_expect(state.slot_skill(1, "bolt") and state.skill_slots[0] == "frost" and state.skill_slots[1] == "bolt", "Real hotbar operation swaps the two skill IDs")
	_expect(state.get_skill_supports("bolt") == ["volley"] and state.get_skill_supports("frost") == ["focus"], "Support links follow the skill rather than the former hotbar slot")
	_expect(state.slot_skill(1, "meteor") and not state.skill_slots.has("bolt"), "Linked skill can leave the hotbar")
	_expect(state.get_skill_supports("bolt") == ["volley"] and state.slot_skill(4, "bolt"), "Unslotted skill retains links when equipped again")
	state.set_skill_supports("tornado", ["volley", "focus"])
	var input_links: Array = ["focus"]
	_expect(state.set_skill_supports("bolt", input_links), "Caller-owned input fixture changes the selected skill links")
	input_links.append("volley")
	_expect(state.get_skill_supports("bolt") == ["focus"], "Caller-owned input list is detached after assignment")
	var saved: Dictionary = state._snapshot()
	var compiled: Dictionary = state.get_skill_cast("tornado")
	var detached: Array = state.get_skill_supports("tornado")
	detached.clear()
	var snapshot: Dictionary = state._snapshot()
	snapshot.skill_supports.tornado.clear()
	snapshot.skill_supports.bolt.append("focus")
	var exposed: Dictionary = state.get_skill_cast("tornado")
	exposed.support_ids.clear()
	exposed.snapshot.modifiers.clear()
	exposed.snapshot.tornado_recipe.child.coefficient = 100.0
	exposed.recipe.clear()
	_expect(state._snapshot() == saved and state.get_skill_cast("tornado") == compiled, "Support getters, serialized arrays, compiled modifiers and nested recipes are fully detached")
	_expect(state.get_skill_supports("unknown").is_empty(), "Unknown support getter returns harmless empty view")
	_finished = true


func _test_compiled_contract() -> void:
	var state = Model.new()
	var specs: Dictionary = {"tornado": [3, 18.0, 28.08], "bolt": [3, 7.0, 10.92], "frost": [5, 16.0, 24.96]}
	for skill: String in specs:
		var base: Dictionary = state.get_skill_cast(skill)
		_expect(base.ok and base.error.is_empty() and base.skill_id == skill and base.support_ids.is_empty(), "Unlinked known skill compiles cleanly: " + skill)
		_expect(base.initial_count == specs[skill][0], "Unlinked initial count is unchanged: " + skill)
		_near(base.mana, specs[skill][1], "Unlinked mana remains base cost: " + skill)
		_expect(state.set_skill_supports(skill, ["volley", "focus"]), "Both supported links can be assigned atomically: " + skill)
		var first: Dictionary = state.get_skill_cast(skill)
		_expect(first.ok and first.initial_count == int(specs[skill][0]) + 2 and _same_set(first.support_ids, ["volley", "focus"]), "Combined cast adds exactly two initial carriers: " + skill)
		_near(first.mana, specs[skill][2], "Combined mana preserves unrounded product: " + skill)
		_near(first.cooldown, Data.SKILLS[skill].cooldown, "Support links preserve original cooldown: " + skill)
		state.set_skill_supports(skill, ["focus", "volley"])
		var reverse: Dictionary = state.get_skill_cast(skill)
		_near(reverse.mana, first.mana, "Reordering supports cannot change cost: " + skill)
		_expect(reverse.initial_count == first.initial_count and reverse.recipe == first.recipe, "Reordering cannot change recipe or count: " + skill)
	state.equip("prism_bow")
	_expect(state.get_skill_cast("tornado").initial_count == 7, "Tornado combines three base, two bow and two support parents")
	_expect(state.get_skill_cast("bolt").initial_count == 5 and state.get_skill_cast("frost").initial_count == 7, "Bow count never leaks into spell volleys")
	_expect(state.get_skill_cast("tornado").snapshot.tornado_recipe.child_count == 3, "Initial volley support never multiplies per-parent children")
	var invalid: Dictionary = state.get_skill_cast("unknown")
	_expect(not invalid.get("ok", true) and not str(invalid.get("error", "")).is_empty(), "Unknown skill compilation fails closed with a diagnostic")
	_finished = true


func _write(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Fixture opens inside disposable user directory")
	if file == null:
		return false
	file.store_string(value if value is String else JSON.stringify(value, "\t", true, true))
	file.close()
	return true


func _test_reject_snapshots() -> void:
	var state = Model.new()
	state.set_skill_supports("bolt", ["focus"])
	state.set_skill_supports("tornado", ["volley"])
	state.changed.connect(_changed)
	changes = 0
	var valid: Dictionary = state._snapshot()
	var attacks: Array[Dictionary] = [
		{"name": "unknown skill", "links": {"unknown": ["focus"]}},
		{"name": "unknown empty skill", "links": {"unknown": []}},
		{"name": "unknown support", "links": {"bolt": ["unknown"]}},
		{"name": "duplicate support", "links": {"bolt": ["focus", "focus"]}},
		{"name": "more than two links", "links": {"bolt": ["volley", "focus", "volley"]}},
		{"name": "incompatible skill", "links": {"meteor": ["focus"]}},
		{"name": "valid before incompatible sibling", "links": {"frost": ["focus"], "ward": ["volley"]}},
		{"name": "string instead of array", "links": {"bolt": "focus"}},
		{"name": "nonstring support", "links": {"bolt": [false]}},
		{"name": "nested support payload", "links": {"bolt": [{"id": "focus"}]}},
		{"name": "nondictionary links", "links": []},
		{"name": "null links", "links": null},
	]
	var path: String = "user://skill_support_invalid.json"
	for attack: Dictionary in attacks:
		var bad: Dictionary = valid.duplicate(true)
		bad.skill_supports = attack.links
		_expect(state._validate_snapshot(bad).is_empty(), "Malformed in-memory snapshot rejects: " + attack.name)
		if _write(path, bad):
			_expect(not state.load_build(path) and state._snapshot() == valid and changes == 0, "Malformed load is wholly atomic and silent: " + attack.name)
	var missing: Dictionary = valid.duplicate(true)
	missing.erase("skill_supports")
	_expect(state._validate_snapshot(missing).is_empty(), "Schema-five snapshot requires its support field")
	if _write(path, missing):
		_expect(not state.load_build(path) and state._snapshot() == valid and changes == 0, "Missing schema-five support field rejects load without resetting links")
	missing = valid.duplicate(true)
	missing.version = 4
	_expect(state._validate_snapshot(missing).is_empty(), "A purported schema-four snapshot cannot smuggle the new support field")
	if _write(path, missing):
		_expect(not state.load_build(path) and state._snapshot() == valid and changes == 0, "Rejecting schema-smuggled links preserves the entire current build")
	_finished = true


func _rich_state():
	var state = Model.new()
	state.add_xp(85)
	for node: String in ["ember_1_0", "ember_2_0", "ember_3_0"]:
		state.allocate_passive(node)
	_expect(state.socket_jewel("ember_3_0", "jewel_000001"), "Rich save fixture owns a socketed original jewel")
	var rng := RandomNumberGenerator.new()
	rng.seed = 606004
	var id: String = state.award_equipment(rng, 16, "rare")
	_expect(not id.is_empty() and Catalog.validate_instance(state.equipment_instances[id]) and state.equip(id), "Rich fixture includes real rolled and equipped gear")
	state.slot_skill(0, "tornado")
	state.move_in_backpack("item:swift_blade", Vector2i(10, 5))
	return state


func _test_roundtrip() -> void:
	var state = _rich_state()
	state.set_skill_supports("tornado", ["volley", "focus"])
	state.set_skill_supports("bolt", ["focus"])
	state.set_skill_supports("frost", ["volley"])
	var before: Dictionary = state._snapshot()
	var path: String = "user://skill_support_v5.json"
	_expect(state.save_build(path) == OK, "Valid schema-five build with all three linked skills saves")
	var loaded = Model.new()
	loaded.changed.connect(_changed)
	changes = 0
	_expect(loaded.load_build(path) and changes == 1 and loaded._snapshot() == before, "Schema-five round trip preserves complete ownership, skill-keyed links, slots, grid and progression")
	for skill: String in ["tornado", "bolt", "frost"]:
		_expect(loaded.get_skill_cast(skill) == state.get_skill_cast(skill), "Reloaded cast uses identical gear, passives, jewels and support numbers: " + skill)
	_expect(not FileAccess.file_exists(path + ".v4-backup.json"), "Current-schema save creates no spurious legacy backup")
	_finished = true


func _test_v4_migration() -> void:
	var original = _rich_state()
	var legacy: Dictionary = original._snapshot()
	legacy.version = 4
	legacy.erase("skill_supports")
	var bytes: String = "\n  " + JSON.stringify(legacy, "  ", false, true) + "\n\n"
	var path: String = "user://skill_support_v4.json"
	var backup: String = path + ".v4-backup.json"
	_expect(_write(path, bytes), "True v4 fixture excludes support field and retains noncanonical bytes")
	var loaded = Model.new()
	_expect(loaded.load_build(path), "True schema-four equipment build migrates successfully")
	var migrated: Dictionary = loaded._snapshot()
	_expect(migrated.version == Model.SAVE_VERSION and migrated.skill_supports.is_empty(), "Migration adds only empty links at current schema version")
	for field: String in legacy:
		if field != "version":
			_expect(migrated[field] == legacy[field], "v4 migration preserves exact original field: " + field)
	_expect(FileAccess.get_file_as_string(path) == bytes and not FileAccess.file_exists(backup), "Read-only migration does not prematurely overwrite source or create backup")
	_expect(loaded.save_build("user://skill_support_v4_copy.json") == OK and not FileAccess.file_exists(backup), "Save-as retains pending original-byte protection")
	loaded.set_skill_supports("tornado", ["volley", "focus"])
	var expected: Dictionary = loaded._snapshot()
	_expect(loaded.save_build(path) == OK and FileAccess.get_file_as_string(backup) == bytes, "First same-path save makes a byte-exact v4 backup before schema-five write")
	var reread = Model.new()
	_expect(reread.load_build(path) and reread._snapshot() == expected, "Migrated save retains new links alongside all original content")
	_expect(reread.save_build(path) == OK and FileAccess.get_file_as_string(backup) == bytes, "Later current-schema saves cannot change original backup")
	var conflict_path: String = "user://skill_support_v4_conflict.json"
	var conflict_backup: String = conflict_path + ".v4-backup.json"
	_write(conflict_path, bytes)
	_write(conflict_backup, "another original build\n")
	var conflict = Model.new()
	_expect(conflict.load_build(conflict_path), "Conflicting backup permits read-only legacy inspection")
	var before: Dictionary = conflict._snapshot()
	_expect(conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS and conflict._snapshot() == before, "Backup conflict rejects migration overwrite without mutating live build")
	_expect(FileAccess.get_file_as_string(conflict_path) == bytes and FileAccess.get_file_as_string(conflict_backup) == "another original build\n", "Backup conflict preserves both independent files byte-for-byte")
	var stale_path: String = "user://skill_support_v4_stale.json"
	_write(stale_path, bytes)
	var stale = Model.new()
	_expect(stale.load_build(stale_path), "Concurrent-change fixture migrates read-only")
	_write(stale_path, "externally replaced build\n")
	_expect(stale.save_build(stale_path) == ERR_FILE_ALREADY_IN_USE and FileAccess.get_file_as_string(stale_path) == "externally replaced build\n", "Migration refuses to overwrite externally changed v4 source")
	_finished = true
