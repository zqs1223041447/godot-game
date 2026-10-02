extends SceneTree
## Deterministic model contracts: identity, grid conservation, schema-v4 and scoped stats.
## Run with disposable XDG roots, as all fixtures live below user://.
const Model = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")

var checks: int = 0
var failures: int = 0
var changes: int = 0
var _finished: bool = false


func _initialize() -> void:
	_case(_test_identity_and_grid, "identity and grid transactions")
	_case(_test_detached_and_fixed, "detached views and fixed mechanic gear")
	_case(_test_families, "each affix reaches the stat/damage pipeline")
	_case(_test_snapshot_rejection, "adversarial schema rejection")
	_case(_test_migration_and_roundtrip, "v3 migration and byte preservation")
	_case(_test_capacity, "total-owned capacity and no-loss return")
	print("Equipment state: %d checks, %d failures" % [checks, failures])
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


func _rng(seed_value: int = 5005) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = seed_value
	return result


func _install(state, affixes: Array = [], base_id: String = "wayglass_token") -> String:
	var id: String = "gear_%06d" % state.next_equipment_id
	var instance: Dictionary = {"id": id, "base_id": base_id, "rarity": "normal" if affixes.is_empty() else "magic", "item_level": 1, "affixes": affixes.duplicate(true)}
	_expect(Catalog.validate_instance(instance), "Explicit deterministic instance is catalog-valid: " + str(affixes))
	state.equipment_instances[id] = instance
	state.inventory.append(id)
	state.next_equipment_id += 1
	state._sync_backpack()
	return id


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


func _test_identity_and_grid() -> void:
	var state = Model.new()
	state.changed.connect(_changed)
	changes = 0
	var rng := _rng()
	var first: String = state.award_equipment(rng, 16, "rare")
	var second: String = state.award_equipment(rng, 16, "rare")
	_expect(first == "gear_000001" and second == "gear_000002" and changes == 2, "Awards create unique persistent serials and exactly one change each")
	_expect(state.inventory.count(first) == 1 and state.equipment_instances.size() == 2 and state.next_equipment_id == 3, "Awards commit record, owned identity, and counter together")
	var definition: Dictionary = state.get_item_definition(first)
	var slot: String = definition.slot
	var old: String = state.equipped[slot]
	_expect(state.equip(first), "Generated item equips into its catalog slot")
	_expect(not state.backpack_positions.has("item:" + first) and state.backpack_positions.has("item:" + old) and _layout_complete(state), "Equipping removes only worn position and returns previous item without overlap")
	var before: Dictionary = state._snapshot()
	var before_changes: int = changes
	_expect(not state.equip(first) and not state.equip("gear_999999") and not state.discard_equipment(first), "Repeated equip, unknown equip, and equipped discard reject")
	_expect(state._snapshot() == before and changes == before_changes, "Rejected item actions are atomic and silent")
	_expect(not state.unequip_to_backpack(slot, Vector2i(12, 8)) and state._snapshot() == before, "Out-of-grid equipment drop preserves slot and layout")
	var free := Vector2i(10, 5)
	_expect(state.can_place_in_backpack("item:" + first, free) and state.unequip_to_backpack(slot, free), "Generated equipment can return at explicit free grid coordinates")
	_expect(state.backpack_positions["item:" + first] == free and _layout_complete(state), "Unequip drop keeps selected coordinates with valid dimensions")
	_expect(state.move_in_backpack("item:" + first, Vector2i(8, 5)), "Generated item drag updates real backpack position")
	var blocked: Vector2i = state.backpack_positions["item:" + old]
	before = state._snapshot()
	_expect(not state.move_in_backpack("item:" + first, blocked) and state._snapshot() == before, "Overlapping generated-item drag is transactionally rejected")
	_expect(state.discard_equipment(first) and not state.inventory.has(first) and not state.equipment_instances.has(first), "Discard removes unequipped generated identity and its record")
	var next: String = state.award_equipment(rng, 1, "normal")
	_expect(next == "gear_000003" and state.equipment_instances.has(second), "Discard never reuses old serials or overwrites unrelated rolls")
	before = state._snapshot()
	for id: String in Data.ITEMS:
		_expect(not state.discard_equipment(id), "Original fixed item cannot be discarded: " + id)
	_expect(state._snapshot() == before and _layout_complete(state), "Fixed-item discard refusals preserve ownership and valid grid")
	_finished = true


func _test_detached_and_fixed() -> void:
	var state = Model.new()
	var id: String = _install(state, [{"id": "runesong", "tier": 1, "value": 7}])
	state.equip(id)
	var original: Dictionary = state._snapshot()
	var generated: Dictionary = state.get_item_definition(id)
	generated.stats.spell_increased = 99.0
	generated.affix_lines.clear()
	generated.effects.append("return_on_range")
	var fixed: Dictionary = state.get_item_definition("return_mantle")
	fixed.stats.max_shield = 9000.0
	fixed.effects.clear()
	var snapshot: Dictionary = state._snapshot()
	snapshot.equipment_instances[id].affixes[0].value = 999
	snapshot.inventory.clear()
	snapshot.backpack_positions.clear()
	var combat: Dictionary = state.get_combat_snapshot()
	combat.modifiers[0].all_tags.clear()
	combat.modifiers[0].value = 999.0
	combat.effects.append("explode_on_flight_end")
	combat.tornado_recipe.child.coefficient = 99.0
	_expect(state._snapshot() == original, "Nested item definitions, serialized snapshots, and combat snapshots are detached from live ownership")
	_near(state.get_item_definition(id).stats.spell_increased, 0.07, "Generated definition rereads original stored affix after external mutation")
	_expect(state.get_item_definition("return_mantle").effects == ["return_on_range"], "Fixed definitions cannot mutate shared mechanic effects")
	_near(state.get_item_definition("return_mantle").stats.max_shield, 15.0, "Fixed nested stats are detached from the immutable catalog")
	for fixed_id: String in Data.ITEMS:
		var resolved: Dictionary = state.get_item_definition(fixed_id)
		_expect(resolved.stats == Data.ITEMS[fixed_id].stats and resolved.slot == Data.ITEMS[fixed_id].slot and resolved.size == Data.ITEMS[fixed_id].size, "Original fixed item retains exact gameplay definition: " + fixed_id)
	for fixed_id: String in Data.COMBAT_STARTER_ITEMS:
		state.equip(fixed_id)
	var special: Dictionary = state.get_combat_snapshot()
	_expect(special.projectile_count == 2 and special.effects.has("return_on_range") and special.effects.has("explode_on_flight_end"), "Original tornado combination still grants count, return, and explosion independently")
	_near(Damage.resolve(Combat.tornado_packet(special, "parent"), special.modifiers).total, 37.84, "Original tornado mixed-damage scalar remains unchanged")
	_near(Damage.resolve(Combat.tornado_packet(special, "explosion"), special.modifiers).total, 29.7, "Original independent explosion excludes projectile damage")
	_finished = true


func _test_families() -> void:
	var cases: Dictionary = {
		"rootwell": ["max_health", 14, 14.0], "deepwell": ["max_mana", 9, 9.0],
		"lanternveil": ["max_shield", 9, 9.0], "runesong": ["spell_increased", 7, 0.07],
		"prismedge": ["attack_elemental_increased", 7, 0.07], "farweave": ["projectile_increased", 7, 0.07],
		"coalglow": ["fire_increased", 8, 0.08], "rimeecho": ["cold_increased", 8, 0.08],
		"sparkthread": ["lightning_increased", 8, 0.08], "wellturn": ["mana_regen_increased", 5, 0.05],
		"trailstep": ["move_speed_increased", 2, 0.02], "beatlink": ["attack_speed_increased", 3, 0.03],
	}
	_expect(cases.size() == Catalog.AFFIXES.size(), "Every original affix family has an explicit independent runtime expectation")
	for family: String in cases:
		var state = Model.new()
		state.equipped.clear()
		var expected: Array = cases[family]
		var id: String = _install(state, [{"id": family, "tier": 1, "value": expected[1]}])
		state.equip(id)
		var stats: Dictionary = state.get_stats()
		var stat: String = expected[0]
		var base: float = float(Model.BASE_STATS[stat]) + float(Catalog.BASES.wayglass_token.stats.get(stat, 0.0))
		_near(stats[stat], base + float(expected[2]), "Family reaches equipped runtime stats: " + family)
		if stat.ends_with("_increased") and stat in ["mana_regen_increased", "attack_speed_increased", "move_speed_increased"]:
			var rate: String = stat.trim_suffix("_increased")
			_near(stats[rate], (float(Model.BASE_STATS[rate]) + float(Catalog.BASES.wayglass_token.stats.get(rate, 0.0))) * (1.0 + float(expected[2])), "Rate uses flat total times percentage, not flat addition: " + family)
	# Multiple flat and percentage sources must combine once, after all equipment.
	var state = Model.new()
	var mana_id: String = _install(state, [{"id": "wellturn", "tier": 1, "value": 5}])
	state.equip(mana_id)
	_near(state.get_stats().mana_regen, (9.0 + 1.0 + 0.3) * 1.05, "Mana percentage multiplies base plus fixed-weapon and generated-base flat regeneration")
	var rate_id: String = _install(state, [{"id": "beatlink", "tier": 1, "value": 3}], "cinder_reed")
	state.equip(rate_id)
	var rate_charm: String = _install(state, [{"id": "beatlink", "tier": 1, "value": 3}])
	state.equip(rate_charm)
	_near(state.get_stats().attack_speed, 1.7 * 1.06, "Two attack-speed increases add before multiplying base")
	_finished = true


func _write(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Fixture opens inside disposable user directory")
	if file == null:
		return false
	file.store_string(value if value is String else JSON.stringify(value, "\t", true, true))
	file.close()
	return true


func _test_snapshot_rejection() -> void:
	var state = Model.new()
	var id: String = _install(state, [{"id": "runesong", "tier": 1, "value": 7}])
	state.equip(id)
	var valid: Dictionary = state._snapshot()
	var attacks: Array[Dictionary] = []
	var bad: Dictionary = valid.duplicate(true)
	bad.equipment_instances[id].base_id = "untrusted_base"
	attacks.append({"label": "unknown base", "value": bad})
	bad = valid.duplicate(true)
	bad.equipment_instances[id].affixes[0].value = 8
	attacks.append({"label": "affix outside inclusive tier range", "value": bad})
	bad = valid.duplicate(true)
	bad.equipment_instances[id].affixes[0].tier = 2
	attacks.append({"label": "tier unavailable at item level", "value": bad})
	bad = valid.duplicate(true)
	bad.equipment_instances[id].affixes.append(bad.equipment_instances[id].affixes[0].duplicate())
	attacks.append({"label": "duplicate affix family/group", "value": bad})
	bad = valid.duplicate(true)
	bad.equipment_instances[id].id = "gear_000002"
	attacks.append({"label": "dictionary key and record identity disagree", "value": bad})
	bad = valid.duplicate(true)
	bad.inventory.append(id)
	attacks.append({"label": "duplicated ownership", "value": bad})
	bad = valid.duplicate(true)
	bad.inventory.erase(id)
	bad.equipped.erase("charm")
	attacks.append({"label": "orphan instance outside ownership", "value": bad})
	bad = valid.duplicate(true)
	bad.next_equipment_id = 1
	attacks.append({"label": "counter would reuse a live identity", "value": bad})
	bad = valid.duplicate(true)
	bad.next_equipment_id = 2.5
	attacks.append({"label": "fractional identity counter", "value": bad})
	bad = valid.duplicate(true)
	bad.backpack_positions["item:" + id] = [11, 7]
	attacks.append({"label": "worn item also has backpack location", "value": bad})
	bad = valid.duplicate(true)
	bad.equipped.weapon = id
	attacks.append({"label": "generated charm in wrong equipment slot", "value": bad})
	bad = valid.duplicate(true)
	bad.equipment_instances[id].effects = ["explode_on_flight_end"]
	attacks.append({"label": "unexpected record payload", "value": bad})
	bad = valid.duplicate(true)
	bad.version = 3
	bad.erase("crafting")
	attacks.append({"label": "legacy schema carrying v4 instances", "value": bad})
	state.changed.connect(_changed)
	changes = 0
	var path: String = "user://equipment_invalid.json"
	for attack: Dictionary in attacks:
		if _write(path, attack.value):
			_expect(not state.load_build(path) and state._snapshot() == valid and changes == 0, "Malformed load wholly rejects without partial state or signal: " + attack.label)
	var valid_written: bool = _write(path, valid)
	var valid_loaded: bool = state.load_build(path)
	_expect(valid_written and valid_loaded and state._snapshot() == valid and changes == 1, "Valid JSON numeric values round-trip generated instances and emit exactly once")
	_finished = true


func _test_migration_and_roundtrip() -> void:
	var original = Model.new()
	original.add_xp(85)
	for node: String in ["ember_1_0", "ember_2_0", "ember_3_0"]:
		original.allocate_passive(node)
	original.socket_jewel("ember_3_0", "jewel_000001")
	original.move_in_backpack("item:swift_blade", Vector2i(10, 5))
	var legacy: Dictionary = original._snapshot()
	legacy.version = 3
	legacy.erase("crafting")
	legacy.erase("equipment_instances")
	legacy.erase("next_equipment_id")
	legacy.erase("skill_supports")
	var text: String = "\n  " + JSON.stringify(legacy, "  ", false, true) + "\n\n"
	var path: String = "user://equipment_schema3.json"
	var backup: String = path + ".v3-backup.json"
	for file: String in [path, backup, "user://equipment_copy.json"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_expect(_write(path, text), "Byte-sensitive v3 fixture is written")
	var loaded = Model.new()
	_expect(loaded.load_build(path) and loaded.migrated_from_v3, "Original fixed-item v3 build migrates to v4")
	_expect(FileAccess.get_file_as_string(path) == text and not FileAccess.file_exists(backup), "Loading migration does not write or back up before same-path save")
	var migrated: Dictionary = loaded._snapshot()
	for field: String in legacy:
		if field != "version":
			_expect(migrated[field] == legacy[field], "v3 migration preserves exact original field: " + field)
	_expect(migrated.equipment_instances.is_empty() and migrated.next_equipment_id == 1, "Migration never silently rerolls the original nine fixed items")
	_expect(loaded.save_build("user://equipment_copy.json") == OK and not FileAccess.file_exists(backup) and FileAccess.get_file_as_string(path) == text, "Save-as does not overwrite legacy source or consume pending backup")
	var id: String = loaded.award_equipment(_rng(731), 30, "rare")
	var rolled: Dictionary = loaded._snapshot()
	_expect(not id.is_empty() and loaded.save_build(path) == OK, "First same-path save retains new rolls and migrates safely")
	_expect(FileAccess.get_file_as_string(backup) == text and loaded.migration_backup_path == backup, "v3 backup is byte-exact, including whitespace and key order")
	var reloaded = Model.new()
	_expect(reloaded.load_build(path) and reloaded._snapshot() == rolled and not reloaded.migrated_from_v3, "v4 reload preserves affix values, identity, grid, counter and stats without reroll")
	_expect(reloaded.get_item_definition(id) == loaded.get_item_definition(id) and reloaded.get_combat_snapshot() == loaded.get_combat_snapshot(), "Reloaded display and combat values derive from the same persisted instance")
	_expect(reloaded.save_build(path) == OK and FileAccess.get_file_as_string(backup) == text, "Subsequent current-schema save cannot alter original backup")
	var conflict_path: String = "user://equipment_conflict.json"
	var conflict_backup: String = conflict_path + ".v3-backup.json"
	_write(conflict_path, text)
	_write(conflict_backup, "another original save\n")
	var conflict = Model.new()
	_expect(conflict.load_build(conflict_path), "Backup conflict does not prevent read-only legacy loading")
	var before: Dictionary = conflict._snapshot()
	_expect(conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS and conflict._snapshot() == before, "Conflicting backup fails closed without changing live state")
	_expect(FileAccess.get_file_as_string(conflict_path) == text and FileAccess.get_file_as_string(conflict_backup) == "another original save\n", "Backup conflict preserves both original files byte-for-byte")
	var stale_path: String = "user://equipment_changed_source.json"
	_write(stale_path, text)
	var stale = Model.new()
	_expect(stale.load_build(stale_path), "Concurrent-source fixture loads")
	_write(stale_path, "externally replaced save\n")
	_expect(stale.save_build(stale_path) == ERR_FILE_ALREADY_IN_USE and FileAccess.get_file_as_string(stale_path) == "externally replaced save\n", "Migration refuses to overwrite externally changed source bytes")
	_finished = true


func _test_capacity() -> void:
	var state = Model.new()
	for node: String in ["ember_1_0", "ember_2_0", "ember_3_0"]:
		state.allocate_passive(node)
	_expect(state.socket_jewel("ember_3_0", "jewel_000001"), "Capacity fixture hides an owned jewel inside an allocated socket")
	var rng := _rng(44)
	while state.jewels.size() < Model.MAX_JEWELS:
		if state.award_jewel(rng).is_empty():
			break
	_expect(state.jewels.size() == Model.MAX_JEWELS, "Jewel grant reaches its actual record limit with all worn gear space reserved")
	# Original nine equipment occupy 30 cells; 64 jewels leave two charm cells.
	var first: String = _install(state)
	var second: String = _install(state)
	state.equip(first)
	state.changed.connect(_changed)
	changes = 0
	var before: Dictionary = state._snapshot()
	_expect(_layout_complete(state) and not state._validate_snapshot(before).is_empty(), "Exactly full total-owned fixture remains a valid save while equipment and jewel are hidden")
	_expect(state.award_equipment(rng, 30, "rare").is_empty() and state.award_equipment(rng, 1, "normal").is_empty() and state.award_jewel(rng).is_empty(), "Full ownership rejects every equipment size and additional jewel")
	_expect(state._snapshot() == before and changes == 0, "Capacity rejection consumes no identity, inventory, prior roll or change event")
	for slot: String in Model.EQUIPMENT_SLOTS:
		state.unequip(slot)
	state.refund_talents()
	_expect(state.socketed_jewels.is_empty() and state.equipped.is_empty() and state.backpack_positions.size() == 75 and _layout_complete(state), "Every equipped item and socketed jewel can return simultaneously into the 96-cell grid")
	_expect(state.inventory.has(first) and state.inventory.has(second) and state.jewels.size() == 64 and not state._validate_snapshot(state._snapshot()).is_empty(), "Full return loses no items and remains save-valid")
	_expect(state.discard_equipment(second), "Full grid can release a single generated charm")
	var awarded: String = ""
	for attempt: int in range(64):
		awarded = state.award_equipment(rng, 1, "normal")
		if not awarded.is_empty():
			break
	_expect(not awarded.is_empty() and state.get_item_definition(awarded).size == Vector2i.ONE and _layout_complete(state), "A later fitting roll uses the freed cell without overwriting any existing item")
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
	before = capped._snapshot()
	_expect(not capped._validate_snapshot(before).is_empty() and capped.award_equipment(rng, 1).is_empty() and capped._snapshot() == before, "Equipment record cap rejects atomically even with free grid cells")
	capped.discard_equipment("gear_000001")
	capped.next_equipment_id = Model.MAX_EQUIPMENT_ID + 1
	before = capped._snapshot()
	_expect(capped.award_equipment(rng, 1).is_empty() and capped._snapshot() == before, "Exhausted serial range refuses identity rollover")
	_finished = true
