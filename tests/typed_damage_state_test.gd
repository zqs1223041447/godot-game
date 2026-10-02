extends SceneTree
## v0.7 state contracts. Run with disposable XDG roots; fixtures use only user://.
## Literal v5 fixtures and frozen v0.6 sequences prevent circular migration oracles.
const Model = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const BaseCompiler = preload("res://scripts/combat/damage_base_compiler.gd")
const TYPES: Dictionary = {
	"attack_added_physical": ["attack", "physical"], "attack_added_fire": ["attack", "fire"],
	"spell_added_cold": ["spell", "cold"], "spell_added_lightning": ["spell", "lightning"],
}
const ZERO_ADDED: Dictionary = {"attack": {"physical": 0.0, "fire": 0.0}, "spell": {"cold": 0.0, "lightning": 0.0}}
const SAVE_FIELDS: Array[String] = ["version", "inventory", "equipped", "equipment_instances", "next_equipment_id", "skill_slots", "skill_supports", "level", "xp", "talent_points", "allocated_nodes", "jewels", "jewel_inventory", "socketed_jewels", "next_jewel_id", "backpack_positions"]

var checks: int = 0
var failures: int = 0
var changes: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_case(_test_typed_stats_and_sources, "all four fixed-point affixes, tiers, scopes and equipped-only sources")
	_case(_test_detached_views, "detached definitions, metadata, sources and snapshots")
	_case(_test_schema_six_roundtrip, "schema-six exact records and no persisted derived caches")
	_case(_test_true_v5_migration, "literal v5 fixture, safe save-as, byte-exact backups and conflicts")
	_case(_test_schema_rejection, "old-schema vocabulary gates and atomic rejection")
	_case(_test_failed_load_save_protection, "failed-load byte preservation and explicitly restored-save unlocking")
	_case(_test_fail_closed_metadata, "malformed semantic metadata and nonfinite values")
	_case(_test_owned_capacity_and_serials, "all-owned grid reservation, record cap and serial exhaustion")
	_case(_test_pool_and_frozen_legacy, "pool selection, invalid request RNG preservation and frozen legacy rolls")
	print("Typed damage state: %d checks, %d failures" % [checks, failures])
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
	_expect(is_finite(value) and absf(value - expected) < 0.00001, "%s (actual %.8f, expected %.8f)" % [label, value, expected])


func _changed() -> void:
	changes += 1


func _rng(seed_value: int = 703061) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = seed_value
	return result


func _install(state, affixes: Array = [], base_id: String = "runewood_focus", rarity: String = "magic", item_level: int = 16) -> String:
	var id: String = "gear_%06d" % state.next_equipment_id
	var instance: Dictionary = {"id": id, "base_id": base_id, "rarity": rarity, "item_level": item_level, "affixes": affixes.duplicate(true)}
	_expect(Catalog.validate_instance(instance), "Deterministic state fixture is catalog-valid: " + id)
	state.equipment_instances[id] = instance
	state.inventory.append(id)
	state.next_equipment_id += 1
	state._sync_backpack()
	return id


func _source(id: String, family: String, value: float) -> Dictionary:
	return {"item_id": id, "affix_id": family, "stat": family, "scope": TYPES[family][0], "damage_type": TYPES[family][1], "value": value}


func _write(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Fixture opens inside disposable user directory: " + path)
	if file == null:
		return false
	file.store_string(value if value is String else JSON.stringify(value, "\t", true, true))
	file.close()
	return true


func _layout_complete(state) -> bool:
	var keys: Array = state.get_backpack_items()
	if state.backpack_positions.size() != keys.size():
		return false
	var occupied: Dictionary = {}
	for key: String in keys:
		if not state.backpack_positions.has(key):
			return false
		var cell: Vector2i = state.backpack_positions[key]
		var size: Vector2i = state.item_size(key)
		if size.x <= 0 or size.y <= 0 or cell.x < 0 or cell.y < 0 or cell.x + size.x > Model.BACKPACK_COLUMNS or cell.y + size.y > Model.BACKPACK_ROWS:
			return false
		for x: int in range(cell.x, cell.x + size.x):
			for y: int in range(cell.y, cell.y + size.y):
				var position := Vector2i(x, y)
				if occupied.has(position):
					return false
				occupied[position] = key
	return true


func _test_typed_stats_and_sources() -> void:
	var empty = Model.new()
	_expect(empty.get_combat_snapshot().added_damage == ZERO_ADDED and empty.get_combat_snapshot().added_damage_sources.is_empty(), "Fresh build has explicit zeros and no phantom source records")
	_expect(Combat.snapshot({}, []).added_damage == ZERO_ADDED, "Absent direct snapshot stats receive both zero-default scopes")
	for family: String in TYPES:
		_near(empty.get_stats()[family], 0.0, "Base state includes zero default for " + family)
		for tier: int in [1, 2, 3]:
			for value: int in [tier * 2 - 1, tier * 2]:
				var state = Model.new()
				var id: String = _install(state, [{"id": family, "tier": tier, "value": value}])
				var definition: Dictionary = state.get_item_definition(id)
				_near(definition.stats[family], float(value), "Integer roll becomes fixed points, never percent: " + family)
				_expect(definition.added_sources == [_source(id, family, value)], "Definition carries exactly one complete scoped source")
				_expect(state.get_combat_snapshot().added_damage == ZERO_ADDED and state.get_combat_snapshot().added_damage_sources.is_empty(), "Owned but unequipped expanded roll has no combat contribution")
				var scalar: float = state.get_stats().damage
				_expect(state.equip(id), "Expanded weapon equips through existing transaction")
				_near(state.get_stats()[family], value, "Equipped roll propagates unchanged through BuildState stats")
				_near(state.get_stats().damage, scalar - 8.0, "Focus replaces the starter weapon without reinterpreting its old damage stat")
				var expected: Dictionary = ZERO_ADDED.duplicate(true)
				expected[TYPES[family][0]][TYPES[family][1]] = float(value)
				var snapshot: Dictionary = state.get_combat_snapshot()
				_expect(snapshot.added_damage == expected and snapshot.added_damage_sources == [_source(id, family, value)], "Only the matching attack/spell and damage type receive the roll")
				var attack: Dictionary = Combat.event_packet(snapshot, "basic", "projectile")
				var spell: Dictionary = Combat.event_packet(snapshot, "bolt", "projectile")
				var matching: Dictionary = attack if TYPES[family][0] == "attack" else spell
				var unrelated: Dictionary = spell if TYPES[family][0] == "attack" else attack
				_expect(matching.assembly.added_damage_sources == [_source(id, family, value)], "Matching hit records retain raw rolls without multiplying source value")
				_expect(unrelated.assembly.get("added_damage_sources", []).is_empty() and unrelated.assembly.added.is_empty(), "Opposite event scope cannot inherit points or attribution")
				_expect(Combat.secondary_packet(snapshot, "bolt").assembly.get("added_damage_sources", []).is_empty(), "Independent explosion never inherits equipped typed sources")
				_expect(state.unequip("weapon") and state.get_combat_snapshot().added_damage == ZERO_ADDED and state.get_combat_snapshot().added_damage_sources.is_empty(), "Unequip removes every typed contribution without deleting its stored roll")
				_expect(state.equipment_instances[id].affixes[0].value == value, "Equip/unequip never rerolls fixed points")
	_finished = true


func _rich_state():
	var state = Model.new()
	state.add_xp(85)
	for node: String in ["ember_1_0", "ember_2_0", "ember_3_0"]:
		_expect(state.allocate_passive(node), "Rich fixture allocates connected node: " + node)
	_expect(state.socket_jewel("ember_3_0", "jewel_000001"), "Rich fixture owns a socketed jewel")
	var id: String = _install(state, [
		{"id": "attack_added_physical", "tier": 3, "value": 6},
		{"id": "attack_added_fire", "tier": 2, "value": 4},
		{"id": "spell_added_cold", "tier": 1, "value": 2},
		{"id": "coalglow", "tier": 1, "value": 8},
	], "runewood_focus", "rare")
	_expect(state.equip(id), "Rich fixture wears a three-prefix typed rare")
	_install(state, [{"id": "spell_added_lightning", "tier": 3, "value": 5}])
	_expect(state.slot_skill(0, "tornado") and state.set_skill_supports("tornado", ["volley", "focus"]), "Rich fixture links both supports to tornado")
	_expect(state.set_skill_supports("bolt", ["focus"]) and state.set_skill_supports("frost", ["volley"]), "Rich fixture retains links for slotted and unslotted skills")
	_expect(state.move_in_backpack("item:gear_000002", Vector2i(10, 5)), "Unequipped typed weapon receives non-default saved coordinates")
	return state


func _test_detached_views() -> void:
	var state = _rich_state()
	var original: Dictionary = state._snapshot()
	var expected: Dictionary = state.get_combat_snapshot()
	var definition: Dictionary = state.get_item_definition("gear_000001")
	definition.stats.attack_added_physical = 999.0
	definition.added_sources[0].value = 999.0
	definition.added_sources[1].scope = "spell"
	definition.added_sources.clear()
	definition.affix_lines.clear()
	var snapshot: Dictionary = state.get_combat_snapshot()
	snapshot.added_damage.attack.physical = 999.0
	snapshot.added_damage.spell.clear()
	snapshot.added_damage_sources[0].item_id = "wrong"
	snapshot.added_damage_sources[1].value = 999.0
	var saved: Dictionary = state._snapshot()
	saved.equipment_instances.gear_000001.affixes[0].value = 999
	saved.skill_supports.tornado.clear()
	saved.backpack_positions.clear()
	var family: Dictionary = Catalog.affix_definition("attack_added_physical")
	family.allowed_base_ids.clear()
	family.required_tags.clear()
	family.tiers[0].max = 999
	var base: Dictionary = Catalog.base_definition("runewood_focus")
	base.stats.max_mana = 999.0
	_expect(state._snapshot() == original and state.get_combat_snapshot() == expected, "All exposed nested records are detached from ownership and recomputed combat")
	_expect(Catalog.affix_definition("attack_added_physical").allowed_base_ids == ["runewood_focus"] and Catalog.affix_definition("attack_added_physical").tiers[0].max == 2, "Detached semantic metadata cannot rewrite executable catalog")
	_near(Catalog.base_definition("runewood_focus").stats.max_mana, 8.0, "Detached base stats cannot rewrite catalog")
	var compiled: Dictionary = state.get_skill_cast("tornado")
	_expect(compiled.ok, "Typed points compile before snapshot freezing")
	var frozen: Dictionary = compiled.snapshot.duplicate(true)
	compiled.packets.parent.assembly.added_damage_sources[0].value = 444.0
	compiled.packets.parent.base.physical = 444.0
	_expect(compiled.snapshot == frozen, "Compiled output packet and frozen packet trees have independent attribution records")
	_expect(state.equip("gear_000002"), "Another expanded weapon swaps into the only weapon slot")
	_expect(state.get_combat_snapshot().added_damage_sources == [_source("gear_000002", "spell_added_lightning", 5)], "Replacing a weapon replaces rather than accumulates old typed sources")
	_expect(frozen.added_damage.attack.physical == 6.0 and frozen.added_damage.spell.cold == 2.0 and frozen.added_damage.spell.lightning == 0.0, "Previously cast snapshot stays frozen across an equipment swap")
	_finished = true


func _test_schema_six_roundtrip() -> void:
	var state = _rich_state()
	var before: Dictionary = state._snapshot()
	_expect(before.version == 6 and before.size() == SAVE_FIELDS.size() and before.has_all(SAVE_FIELDS), "Schema-six has exactly the same persisted field allowlist as v5")
	var cast_before: Dictionary = state.get_skill_cast("tornado")
	_expect(state._snapshot() == before, "Compiling typed sources and packets does not add persistent caches")
	var path: String = "user://typed_state_v6.json"
	_expect(state.save_build(path) == OK, "Schema-six typed build saves")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(raw is Dictionary and raw.size() == SAVE_FIELDS.size() and raw.has_all(SAVE_FIELDS), "Disk JSON contains only the sixteen persisted build fields")
	for id: String in raw.equipment_instances:
		_expect(raw.equipment_instances[id].size() == 5 and raw.equipment_instances[id].has_all(["id", "base_id", "rarity", "item_level", "affixes"]), "Saved expanded record excludes definition, source and packet caches")
		for affix: Dictionary in raw.equipment_instances[id].affixes:
			_expect(affix.size() == 3 and affix.has_all(["id", "tier", "value"]), "Saved roll stores only original affix identity, tier and fixed value")
	var loaded = Model.new()
	loaded.changed.connect(_changed)
	changes = 0
	_expect(loaded.load_build(path) and loaded._snapshot() == before and changes == 1, "Load retains exact IDs, tiers, values, equipment, supports, slots, progression and grid once")
	_expect(not loaded.migrated_from_v5 and not FileAccess.file_exists(path + ".v5-backup.json"), "Current schema load needs no legacy migration or backup")
	_expect(loaded.get_combat_snapshot() == state.get_combat_snapshot() and loaded.get_skill_cast("tornado") == cast_before, "Reload derives identical typed snapshots and compiled packets from persisted rolls")
	for instance: Dictionary in loaded.equipment_instances.values():
		_expect(instance.item_level is int, "JSON item level restores canonical integer type")
		for affix: Dictionary in instance.affixes:
			_expect(affix.tier is int and affix.value is int, "JSON affix tier and roll restore canonical integer types")
	_expect(loaded.equip("gear_000002") and loaded.save_build(path) == OK, "Stored fourth family can equip and resave without rerolling")
	var changed: Dictionary = loaded._snapshot()
	var second = Model.new()
	_expect(second.load_build(path) and second._snapshot() == changed and second.get_combat_snapshot().added_damage_sources == [_source("gear_000002", "spell_added_lightning", 5)], "Second round trip preserves the changed equipped source and every prior record")
	_finished = true


func _literal_v5() -> Dictionary:
	# Intentionally NOT derived from _snapshot(): this is an actual old vocabulary
	# record, with missing starter items, a gapped equipment serial and custom layout.
	return {
		"version": 5,
		"inventory": ["ember_wand", "guardian_robe", "azure_charm", "gear_000042"],
		"equipped": {"weapon": "ember_wand", "armor": "guardian_robe", "charm": "azure_charm"},
		"equipment_instances": {"gear_000042": {"id": "gear_000042", "base_id": "wayglass_token", "rarity": "magic", "item_level": 8, "affixes": [{"id": "runesong", "tier": 2, "value": 11}, {"id": "sparkthread", "tier": 1, "value": 7}]}},
		"next_equipment_id": 43,
		"skill_slots": ["tornado", "frost", "nova", "dash", "ward"],
		"skill_supports": {"tornado": ["focus", "volley"], "bolt": ["focus"]},
		"level": 4, "xp": 7, "talent_points": 5,
		"allocated_nodes": ["origin", "ember_1_0", "ember_2_0", "ember_3_0"],
		"jewels": {
			"jewel_000001": {"id": "jewel_000001", "base": "emberheart", "rarity": "magic", "affixes": [{"id": "force", "value": 4.0}, {"id": "tempo", "value": 0.08}]},
			"jewel_000002": {"id": "jewel_000002", "base": "tideglass", "rarity": "magic", "affixes": [{"id": "barrier", "value": 16.0}, {"id": "renewal", "value": 0.7}]},
		},
		"jewel_inventory": ["jewel_000002"], "socketed_jewels": {"ember_3_0": "jewel_000001"}, "next_jewel_id": 8,
		"backpack_positions": {"item:gear_000042": [10, 5], "jewel:jewel_000002": [11, 7]},
	}


func _test_true_v5_migration() -> void:
	var legacy: Dictionary = _literal_v5()
	_expect(legacy.size() == SAVE_FIELDS.size() and Catalog.validate_instance(legacy.equipment_instances.gear_000042, false), "Literal fixture has exactly legacy schema and legacy-only equipment vocabulary")
	var bytes: String = "\n  " + JSON.stringify(legacy, "  ", false, true) + "\n\n"
	var path: String = "user://typed_state_legacy_v5.json"
	var backup: String = path + ".v5-backup.json"
	_expect(_write(path, bytes), "Noncanonical literal v5 bytes are written")
	var loaded = Model.new()
	loaded.changed.connect(_changed)
	changes = 0
	_expect(loaded.load_build(path) and loaded.migrated_from_v5 and changes == 1, "Real v5 file migrates with one successful change signal")
	var expected: Dictionary = legacy.duplicate(true)
	expected.version = 6
	_expect(loaded._snapshot() == expected, "Migration changes only version: no auto-equip, grants, rerolls, changed supports, positions or counters")
	_expect(loaded.get_combat_snapshot().added_damage == ZERO_ADDED and loaded.get_combat_snapshot().added_damage_sources.is_empty(), "Legacy damage stays scalar with zero typed additions")
	_expect(FileAccess.get_file_as_string(path) == bytes and not FileAccess.file_exists(backup), "Read-only migration preserves original bytes without premature backup")
	var copy: String = "user://typed_state_legacy_copy.json"
	_expect(loaded.save_build(copy) == OK and FileAccess.get_file_as_string(path) == bytes and not FileAccess.file_exists(backup), "Save-as writes current schema without consuming pending original-byte protection")
	var copied = Model.new()
	_expect(copied.load_build(copy) and copied._snapshot() == expected and not copied.migrated_from_v5, "Save-as destination is a complete valid v6 build")
	var new_id: String = loaded.award_equipment(_rng(), 16, "rare", "expanded")
	_expect(new_id == "gear_000043" and loaded.equipped == legacy.equipped, "Opt-in postmigration award uses the saved serial and never auto-equips")
	expected = loaded._snapshot()
	_expect(loaded.save_build(path) == OK and FileAccess.get_file_as_string(backup) == bytes and loaded.migration_backup_path == backup, "First same-path save preserves byte-exact v5 source before committing v6")
	var reread = Model.new()
	_expect(reread.load_build(path) and reread._snapshot() == expected and not reread.migrated_from_v5, "Migrated current-schema reload preserves old rolls plus the explicitly new expanded award")
	_expect(loaded.save_build(path) == OK and reread.save_build(path) == OK and FileAccess.get_file_as_string(backup) == bytes, "Repeated writes from migrated and reloaded state cannot replace original backup")
	var conflict_path: String = "user://typed_state_v5_conflict.json"
	var conflict_backup: String = conflict_path + ".v5-backup.json"
	_write(conflict_path, bytes)
	_write(conflict_backup, "another independent original\n")
	var conflict = Model.new()
	_expect(conflict.load_build(conflict_path), "An unrelated preexisting backup permits read-only inspection")
	var before: Dictionary = conflict._snapshot()
	conflict.changed.connect(_changed)
	changes = 0
	_expect(conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS and conflict._snapshot() == before and changes == 0, "Conflicting backup rejects overwrite atomically and silently")
	_expect(FileAccess.get_file_as_string(conflict_path) == bytes and FileAccess.get_file_as_string(conflict_backup) == "another independent original\n", "Conflict leaves both independent files byte-for-byte untouched")
	var stale_path: String = "user://typed_state_v5_stale.json"
	_write(stale_path, bytes)
	var stale = Model.new()
	_expect(stale.load_build(stale_path), "Source-change fixture loads")
	before = stale._snapshot()
	_write(stale_path, "externally replaced source\n")
	_expect(stale.save_build(stale_path) == ERR_FILE_ALREADY_IN_USE and stale._snapshot() == before, "Concurrent source replacement prevents migration overwrite")
	_expect(FileAccess.get_file_as_string(stale_path) == "externally replaced source\n" and not FileAccess.file_exists(stale_path + ".v5-backup.json"), "Changed source is neither overwritten nor mislabeled as original backup")
	var matching_path: String = "user://typed_state_v5_matching.json"
	_write(matching_path, bytes)
	_write(matching_path + ".v5-backup.json", bytes)
	var matching = Model.new()
	_expect(matching.load_build(matching_path) and matching.save_build(matching_path) == OK and FileAccess.get_file_as_string(matching_path + ".v5-backup.json") == bytes, "An already byte-identical backup permits safe idempotent migration")
	_finished = true


func _reject_load(state, bad: Dictionary, before: Dictionary, label: String) -> void:
	_expect(state._validate_snapshot(bad).is_empty(), "Direct validation fails closed: " + label)
	if _write("user://typed_state_rejected.json", bad):
		_expect(not state.load_build("user://typed_state_rejected.json") and state._snapshot() == before and changes == 0, "Load rejects atomically with no signal: " + label)


func _test_schema_rejection() -> void:
	var state = _rich_state()
	var before: Dictionary = state._snapshot()
	state.changed.connect(_changed)
	changes = 0
	for version: int in [4, 5]:
		var legacy: Dictionary = _literal_v5()
		legacy.version = version
		if version == 4:
			legacy.erase("skill_supports")
		_expect(not state._validate_snapshot(legacy).is_empty(), "Control legacy schema is valid before vocabulary injection: v%d" % version)
		for has_affix: bool in [false, true]:
			var bad: Dictionary = legacy.duplicate(true)
			bad.equipment_instances.gear_000042.base_id = "runewood_focus"
			bad.equipment_instances.gear_000042.rarity = "magic" if has_affix else "normal"
			bad.equipment_instances.gear_000042.affixes = [{"id": "attack_added_fire", "tier": 1, "value": 2}] if has_affix else []
			_reject_load(state, bad, before, "v%d cannot contain new base, including affix-free normal" % version)
		for family: String in TYPES:
			var bad: Dictionary = legacy.duplicate(true)
			bad.equipment_instances.gear_000042.affixes = [{"id": family, "tier": 1, "value": 2}]
			_reject_load(state, bad, before, "v%d cannot contain expanded family %s" % [version, family])
	for old_base: String in Catalog.BASES:
		var bad: Dictionary = before.duplicate(true)
		bad.equipment_instances.gear_000001.base_id = old_base
		_reject_load(state, bad, before, "Typed prefixes cannot enter old base " + old_base)
	var bad: Dictionary = before.duplicate(true)
	bad.equipment_instances.gear_000002.affixes = [{"id": "rootwell", "tier": 1, "value": 10}]
	_reject_load(state, bad, before, "New weapon rejects legacy armor/charm-only family")
	for field: String in ["added_damage", "added_damage_sources", "compiled_packets", "stats"]:
		bad = before.duplicate(true)
		bad[field] = {}
		_reject_load(state, bad, before, "Derived top-level cache is not a persisted field: " + field)
	for field: String in ["added_sources", "stats", "stage", "scope"]:
		bad = before.duplicate(true)
		bad.equipment_instances.gear_000001[field] = "forged"
		_reject_load(state, bad, before, "Equipment record cannot carry executable derived metadata: " + field)
	_finished = true


func _test_failed_load_save_protection() -> void:
	var future: Dictionary = _literal_v5()
	future.version = 777
	var wrong_schema: Dictionary = _literal_v5()
	wrong_schema.equipment_instances.gear_000042.affixes[0].value = 999
	var fixtures: Array[Dictionary] = [
		{"name": "malformed", "bytes": "\n  {broken JSON; keep these original bytes\n"},
		{"name": "future", "bytes": "\n" + JSON.stringify(future, "  ", false, true) + "\n\n"},
		{"name": "invalid", "bytes": JSON.stringify(wrong_schema, "  ", false, true)},
		{"name": "oversized", "bytes": " ".repeat(Model.MAX_SAVE_BYTES + 1)},
	]
	for fixture: Dictionary in fixtures:
		var state = Model.new()
		var before: Dictionary = state._snapshot()
		var path: String = "user://typed_guard_" + fixture.name + ".json"
		var absolute: String = ProjectSettings.globalize_path(path)
		var copy: String = "user://typed_guard_" + fixture.name + "_copy.json"
		_expect(_write(path, fixture.bytes), "Write byte-sensitive protected source: " + fixture.name)
		state.changed.connect(_changed)
		changes = 0
		_expect(not state.load_build(path) and state._snapshot() == before and changes == 0, "Failed load keeps live build atomic: " + fixture.name)
		_expect(not state.last_load_error.is_empty() and not state.save_block_reason(path).is_empty() and not state.save_block_reason(absolute).is_empty(), "Failure identifies protected path through user and absolute forms: " + fixture.name)
		_expect(state.save_build(path) == ERR_INVALID_DATA and state.save_build(absolute) == ERR_INVALID_DATA, "Both aliases refuse overwrite of rejected original: " + fixture.name)
		_expect(FileAccess.get_file_as_string(path) == fixture.bytes and state._snapshot() == before and changes == 0, "Rejected autosave preserves exact invalid/future/oversized bytes without signals")
		_expect(state.save_build(copy) == OK and not state.save_block_reason(path).is_empty(), "Unrelated Save As is allowed while source guard stays armed")
		_expect(state.save_build(path) == ERR_INVALID_DATA and FileAccess.get_file_as_string(path) == fixture.bytes, "Save As never unlocks or rewrites protected source")
		_expect(state.load_build(copy) and not state.save_block_reason(path).is_empty(), "Loading another valid file does not unlock the failed original")
		_expect(state.save_build(path) == ERR_INVALID_DATA and FileAccess.get_file_as_string(path) == fixture.bytes, "Unrelated successful load cannot silently clear original protection")
		_expect(_write(path, before), "Explicitly restore a valid current-schema file at original location")
		_expect(state.save_build(path) == ERR_INVALID_DATA, "External replacement alone cannot unlock a still-unvalidated source")
		var prior_changes: int = changes
		_expect(state.load_build(absolute) and state._snapshot() == before and changes == prior_changes + 1, "Successful restored original load commits once using canonical alias")
		_expect(state.last_load_error.is_empty() and state.save_block_reason(path).is_empty() and state.save_block_reason(absolute).is_empty(), "Validated restoration clears the diagnostic and only its path guard")
		var restored_save: Error = state.save_build(path)
		_expect(restored_save == OK, "Validated restored source can save again: " + str(restored_save))
		var final_state = Model.new()
		_expect(final_state.load_build(path) and final_state._snapshot() == before, "Validated restored source reloads without data loss")
	_finished = true


func _test_fail_closed_metadata() -> void:
	var original: Dictionary = Catalog.affix_definition("attack_added_physical")
	var mutations: Dictionary = {"stage": ["local_weapon", "conversion", "hit_base", "", null, 9], "scope": ["global", "attack", "spell", "local_weapon", null], "required_tags": [["attack"], ["hit", "spell"], ["hit", "attack", "attack"]], "damage_type": ["fire", "chaos", null], "stat": ["damage", "spell_added_cold"], "allowed_base_ids": [["cinder_reed"], ["runewood_focus", "gale_spindle"]], "unit": ["percent"], "kind": ["suffix"], "slots": [["armor"]]}
	for field: String in mutations:
		for value: Variant in mutations[field]:
			var bad: Dictionary = original.duplicate(true)
			bad[field] = value
			_expect(not Catalog._valid_expansion_family(bad), "Malformed typed family metadata fails closed: " + field + "=" + str(value))
	var missing: Dictionary = original.duplicate(true)
	missing.erase("stage")
	_expect(not Catalog._valid_expansion_family(missing) and Catalog.affix_definition("attack_added_physical") == original, "Missing semantic field rejects without modifying catalog authority")
	var state = Model.new()
	var id: String = _install(state, [{"id": "attack_added_physical", "tier": 1, "value": 2}])
	state.equip(id)
	var before: Dictionary = state._snapshot()
	for value: Variant in [NAN, INF, -INF, -1, 1.5, "2", null]:
		var bad: Dictionary = state.equipment_instances[id].duplicate(true)
		bad.affixes[0].value = value
		_expect(not Catalog.validate_instance(bad) and Catalog.definition(bad).is_empty() and Catalog.get_stats(bad).is_empty(), "Public catalog gates reject malformed fixed roll: " + str(value))
		var invalid_save: Dictionary = before.duplicate(true)
		invalid_save.equipment_instances[id] = bad
		_expect(state._validate_snapshot(invalid_save).is_empty() and state._snapshot() == before, "Direct save validation rejects nonfinite/noninteger roll without live mutation")
	var snapshot: Dictionary = state.get_combat_snapshot()
	for scope: Variant in ["global", "equipped_character", "local_weapon", null]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.added_damage_sources[0].scope = scope
		_expect(Combat.event_packet(bad, "basic", "projectile").is_empty(), "Public event API rejects malformed source scope: " + str(scope))
	for value: float in [NAN, INF, -INF]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.added_damage.attack.physical = value
		_expect(Combat.event_packet(bad, "basic", "projectile").is_empty(), "Public event API rejects nonfinite point map")
		bad = snapshot.duplicate(true)
		bad.added_damage_sources[0].value = value
		_expect(Combat.event_packet(bad, "basic", "projectile").is_empty(), "Public event API rejects nonfinite source value")
	var recipe: Dictionary = {"stage": "hit_base", "intrinsic_distribution": {"physical": 1.0}, "base_coefficient": 1.0, "added_effectiveness": 1.0, "tags": ["hit", "attack"], "skill_id": "basic", "role": "direct"}
	for stage: String in ["skill_added_damage", "local_weapon", "conversion"]:
		recipe.stage = stage
		_expect(BaseCompiler.assemble(18.0, recipe, snapshot.added_damage, snapshot.added_damage_sources).is_empty(), "Public assembler rejects execution stage: " + stage)
	_finished = true


func _test_owned_capacity_and_serials() -> void:
	var state = Model.new()
	for node: String in ["ember_1_0", "ember_2_0", "ember_3_0"]:
		state.allocate_passive(node)
	_expect(state.socket_jewel("ember_3_0", "jewel_000001"), "Capacity fixture hides a still-owned jewel in a socket")
	var focus: String = _install(state, [{"id": "spell_added_lightning", "tier": 3, "value": 6}])
	_expect(state.equip(focus), "Capacity fixture hides a still-owned expanded weapon in its slot")
	# Original gear owns 30 cells, focus owns 3; 63 jewels fill all 96 cells.
	var rng := _rng(703064)
	for serial: int in range(4, 64):
		var id: String = "jewel_%06d" % serial
		state.jewels[id] = Jewels.generate(rng, id)
		state.jewel_inventory.append(id)
	state.next_jewel_id = 64
	state._sync_backpack()
	var before: Dictionary = state._snapshot()
	_expect(state.jewels.size() == 63 and _layout_complete(state) and not state._validate_snapshot(before).is_empty(), "Exactly-full all-owned fixture is valid despite visible free space from worn/socketed items")
	state.changed.connect(_changed)
	changes = 0
	for pool: String in ["legacy", "expanded", "loot"]:
		_expect(state.award_equipment(rng, 16, "rare", pool).is_empty(), "All-owned capacity blocks another item from pool " + pool)
	_expect(state.award_jewel(rng).is_empty(), "Jewel award cannot borrow the socketed jewel's reserved return cell")
	_expect(state._snapshot() == before and changes == 0, "Capacity refusals preserve every prior roll, identity, counter, position and change signal")
	for slot: String in Model.EQUIPMENT_SLOTS:
		state.unequip(slot)
	state.refund_talents()
	_expect(state.equipped.is_empty() and state.socketed_jewels.is_empty() and state.backpack_positions.size() == 73 and _layout_complete(state), "All worn gear and socketed jewels return simultaneously with no overlap or loss")
	_expect(not state._validate_snapshot(state._snapshot()).is_empty() and state.equipment_instances[focus] == before.equipment_instances[focus], "Full return remains save-valid and preserves exact typed rolls")
	_expect(state.discard_equipment(focus), "Discarding the unworn focus releases its whole footprint")
	var next: String = state.award_equipment(rng, 16, "rare", "expanded")
	_expect(next == "gear_000002" and _layout_complete(state), "A new expanded roll fits exactly the released three cells without serial reuse")
	var capped = Model.new()
	capped.inventory.clear()
	capped.equipped.clear()
	capped.jewels.clear()
	capped.jewel_inventory.clear()
	for serial: int in range(1, Model.MAX_EQUIPMENT + 1):
		var id: String = "gear_%06d" % serial
		capped.equipment_instances[id] = {"id": id, "base_id": "wayglass_token", "rarity": "normal", "item_level": 1, "affixes": []}
		capped.inventory.append(id)
	capped.next_equipment_id = Model.MAX_EQUIPMENT + 1
	capped._sync_backpack()
	capped.changed.connect(_changed)
	changes = 0
	before = capped._snapshot()
	var rng_before: int = rng.state
	_expect(not capped._validate_snapshot(before).is_empty(), "Record-cap fixture remains valid with unused grid space")
	_expect(capped.award_equipment(rng, 16, "rare", "expanded").is_empty() and capped._snapshot() == before and changes == 0 and rng.state == rng_before, "64-record cap rejects before rolling, consuming an ID or signaling")
	capped.discard_equipment("gear_000001")
	capped.next_equipment_id = Model.MAX_EQUIPMENT_ID
	var last: String = capped.award_equipment(rng, 16, "rare", "expanded")
	_expect(last == "gear_999999999" and capped.next_equipment_id == Model.MAX_EQUIPMENT_ID + 1, "Last legal serial can be awarded exactly once without rollover")
	capped.discard_equipment("gear_000002")
	before = capped._snapshot()
	rng_before = rng.state
	changes = 0
	_expect(not capped._validate_snapshot(before).is_empty(), "Exhausted serial sentinel remains persistable")
	for pool: String in ["legacy", "expanded", "loot"]:
		_expect(capped.award_equipment(rng, 16, "rare", pool).is_empty(), "Exhausted serial rejects pool " + pool)
	_expect(capped._snapshot() == before and changes == 0 and rng.state == rng_before, "Serial exhaustion preserves all records and RNG without reusing discarded IDs")
	_finished = true


func _test_pool_and_frozen_legacy() -> void:
	for pool: String in ["default", "legacy", "expanded", "loot"]:
		for seed_value: int in [1, 71, 703066]:
			var state = Model.new()
			var rng := _rng(seed_value)
			var oracle := _rng(seed_value)
			var expected: Dictionary
			match pool:
				"expanded": expected = Catalog.generate_expanded(oracle, "gear_000001", 16, "rare")
				"loot": expected = Catalog.generate_loot(oracle, "gear_000001", 16, "rare")
				_: expected = Catalog.generate(oracle, "gear_000001", 16, "rare")
			state.changed.connect(_changed)
			changes = 0
			var worn: Dictionary = state.equipped.duplicate()
			var id: String = state.award_equipment(rng, 16, "rare") if pool == "default" else state.award_equipment(rng, 16, "rare", pool)
			_expect(id == "gear_000001" and state.equipment_instances[id] == expected and rng.state == oracle.state, "BuildState routes pool without extra rolls: " + pool)
			_expect(changes == 1 and state.equipped == worn and state.inventory.count(id) == 1 and state.next_equipment_id == 2, "Pool award grants one un-equipped persistent identity and signals once")
	var state = Model.new()
	var rng := _rng()
	var before: Dictionary = state._snapshot()
	var rng_before: int = rng.state
	state.changed.connect(_changed)
	changes = 0
	for pool: String in ["", "Expanded", "unknown", "legacy,expanded"]:
		_expect(state.award_equipment(rng, 16, "rare", pool).is_empty(), "Unknown pool rejects: " + pool)
	for pool: String in ["legacy", "expanded", "loot"]:
		_expect(state.award_equipment(rng, 0, "rare", pool).is_empty() and state.award_equipment(rng, 31, "rare", pool).is_empty(), "Invalid item levels reject before any pool roll")
		_expect(state.award_equipment(rng, 16, "legendary", pool).is_empty() and state.award_equipment(null, 16, "rare", pool).is_empty(), "Invalid rarity or missing RNG rejects before mutation")
	_expect(state._snapshot() == before and rng.state == rng_before and changes == 0, "Every invalid pool/request leaves caller RNG and complete state unchanged")
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/typed_affix_legacy_rng.json"))
	_expect(fixture is Dictionary and fixture.has("sequences"), "Frozen v0.6 RNG fixture is available")
	if fixture is Dictionary and fixture.has("sequences"):
		# Replay through the public state award API. Discard between samples so grid
		# capacity does not change the historical call sequence or serial progression.
		var samples: int = 0
		for sequence: Dictionary in fixture.sequences:
			var replay = Model.new()
			var stream := _rng(int(sequence.seed))
			for sample: Dictionary in sequence.samples:
				var expected: Dictionary = sample.instance
				var id: String = replay.award_equipment(stream, int(expected.item_level), sample.requested_rarity)
				_expect(id == expected.id and JSON.parse_string(JSON.stringify(replay.equipment_instances.get(id, {}))) == expected, "Default public award retains frozen legacy identity and exact rolls")
				_expect(str(stream.state) == sample.rng_state, "Default public award retains frozen legacy RNG state")
				_expect(replay.discard_equipment(id), "Discard frees capacity without resetting legacy serial or RNG")
				samples += 1
		_expect(samples == 432, "All 432 independent pre-expansion golden rolls replay through BuildState")
	_finished = true
