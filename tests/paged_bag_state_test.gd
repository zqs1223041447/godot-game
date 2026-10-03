extends SceneTree

const State = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Legacy = preload("res://scripts/build_state.gd")
const LegacyMigration = preload("res://scripts/save/canonical_build_migration.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Layout = preload("res://scripts/items/item_location_rules.gd")
const BagLayout = preload("res://scripts/items/paged_bag_layout.gd")

class WriteFailState extends State:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_root := OS.get_environment("XDG_DATA_HOME")
	if not data_root.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(data_root + "/"):
		quit(78)
		return

	var source_v14 := LegacyMigration.migrate(Legacy.new()._snapshot())
	var source_bytes := PackedByteArray([239, 187, 191]) + ("\r\n" + JSON.stringify(source_v14, "  ", true, true) + "\r\n").to_utf8_buffer()
	var path := "user://paged_bag_v14_%d.json" % Time.get_ticks_usec()
	_write(path, source_bytes)
	var state := State.new()
	_expect(state.load_build(path), "valid v14 save loads and upgrades")
	_expect(FileAccess.get_file_as_bytes(path + ".v14-backup.json") == source_bytes
		and FileAccess.get_file_as_bytes(path) != source_bytes,
		"original v14 bytes are preserved before a current-schema replacement")
	_expect(state.snapshot().version == 16 and Rules.reason(state.snapshot()).is_empty(),
		"loaded state is a valid v15 build")
	_expect(state.snapshot().items == source_v14.items and state.snapshot().talents == source_v14.talents
		and state.snapshot().bindings == source_v14.bindings and state.snapshot().crafting == source_v14.crafting
		and state.snapshot().migration_ledger == source_v14.migration_ledger,
		"v14 migration preserves item payloads, talents, bindings, materials, and ledger")
	_expect(state.migrated_from_legacy and state.migration_message.contains("双页背包")
		and not state.migration_message.contains("天赋点"),
		"v14 migration message describes the backpack conversion without claiming a talent refund")
	_expect(state.bag_layout() == {"pages": 2, "columns": 8, "rows": 6},
		"state exposes the stable two-page layout contract")

	var bag_uid := _first_bag_uid(state.snapshot().locations)
	var bag_snapshot := state.snapshot()
	var bag_metadata := Items.metadata_for_items(bag_snapshot.items)
	var possible_return := state.first_bag_position(bag_uid)
	_expect(not bag_uid.is_empty() and possible_return.size() == 4 and possible_return.kind == "bag"
		and possible_return.has("page") and possible_return.page in [0, 1],
		"first_bag_position returns a complete page-aware location")
	var page_context := LegacyMigration.paged_location_context(bag_snapshot, Rules.SourceTree.Data.standard_socket_ids())
	var second_page := _page_one_free_location(bag_metadata, bag_snapshot.locations, page_context, bag_uid)
	_expect(not second_page.is_empty(), "fixture has a second-page return target")
	var moved := state.move_item(bag_uid, second_page, state.revision(), path)
	_expect(moved.ok and state.location(bag_uid) == second_page,
		"two-page movement saves a complete page-aware destination")
	var after_move := state.snapshot()
	var loaded := State.new()
	_expect(loaded.load_build(path) and loaded.snapshot() == after_move,
		"save and readback retain every UID, payload, skill group, cooldown identity, and material")
	_expect(loaded.location(bag_uid).page == 1 and loaded.item(bag_uid) == after_move.items[bag_uid],
		"page and selected instance payload round-trip exactly")

	var equip_uid := _first_bag_equipment_uid(state.snapshot())
	var equipped_ok := not equip_uid.is_empty() and state.equip(equip_uid)
	var equipped_slot := ""
	for slot_id: String in state.equipped_items():
		if state.equipped_items()[slot_id] == equip_uid:
			equipped_slot = slot_id
	var unequipped_ok := not equipped_slot.is_empty() and state.unequip(equipped_slot)
	_expect(equipped_ok and unequipped_ok and state.location(equip_uid).kind == "bag"
		and state.location(equip_uid).has_all(["kind", "page", "x", "y"])
		and Rules.reason(state.snapshot()).is_empty(),
		"equip and unequip return a complete location across the two pages")

	var arrange_before := state.snapshot()
	var arranged := state.arrange_items(state.revision(), path)
	_expect((arranged.ok or arranged.error_code in ["no_change", "cannot_arrange"])
		and state.snapshot().items == arrange_before.items and Rules.reason(state.snapshot()).is_empty()
		and _recovery_locations(state.snapshot().locations) == _recovery_locations(arrange_before.locations),
		"two-page arrangement preserves ownership and cannot create recovery entries")

	var craft_rng := RandomNumberGenerator.new()
	craft_rng.seed = 44182
	for index: int in range(3):
		var salvage_uid := _award_rare_page_one(state, path, craft_rng)
		var salvage_quote := state.crafting_quote("salvage", salvage_uid, path) if not salvage_uid.is_empty() else {}
		var salvage_result := state.execute_crafting(salvage_quote.handle, salvage_quote.source_instance) \
			if salvage_quote.get("ok", false) else {"ok": false}
		_expect(not salvage_uid.is_empty() and salvage_quote.get("ok", false) and salvage_result.get("ok", false)
			and state.item(salvage_uid).is_empty(),
			"salvage transaction accepts an item on page two and commits materials atomically")

	var calibrate_uid := _award_rare_page_one(state, path, craft_rng)
	var calibrate_quote: Dictionary = state.crafting_quote("recalibrate", calibrate_uid, path) \
		if not calibrate_uid.is_empty() else {}
	for attempt: int in range(3):
		if calibrate_quote.get("ok", false):
			break
		var extra_uid := _award_rare_page_one(state, path, craft_rng)
		var extra_quote: Dictionary = state.crafting_quote("salvage", extra_uid, path) if not extra_uid.is_empty() else {}
		if extra_quote.get("ok", false):
			state.execute_crafting(extra_quote.handle, extra_quote.source_instance)
		calibrate_quote = state.crafting_quote("recalibrate", calibrate_uid, path) \
			if not calibrate_uid.is_empty() else {}
	var calibrated := state.execute_crafting(calibrate_quote.handle, calibrate_quote.source_instance) \
		if calibrate_quote.get("ok", false) else {"ok": false}
	_expect(not calibrate_uid.is_empty() and calibrate_quote.get("ok", false) and calibrated.get("ok", false)
		and state.item(calibrate_uid).payload.id == calibrate_uid
		and Rules.decode(JSON.parse_string(FileAccess.get_file_as_string(path))) == state.snapshot(),
		"page-two calibration preserves item identity and round-trips its payload and wallet")

	var discard_uid := state.award_gem("support:focus")
	var discard_snapshot := state.snapshot()
	var discard_destination := _page_one_free_location(Items.metadata_for_items(discard_snapshot.items),
		discard_snapshot.locations, LegacyMigration.paged_location_context(discard_snapshot,
		Rules.SourceTree.Data.standard_socket_ids()), discard_uid)
	var discard_move := state.move_item(discard_uid, discard_destination, state.revision(), path) \
		if not discard_uid.is_empty() and not discard_destination.is_empty() else {"ok": false}
	var discarded := state.discard_item(discard_uid, state.revision(), path) if discard_move.get("ok", false) else {"ok": false}
	_expect(not discard_uid.is_empty() and discard_move.get("ok", false) and discarded.get("ok", false)
		and not state.snapshot().items.has(discard_uid),
		"discard remains available for a bag item on page two")

	var invalid_v14 := source_v14.duplicate(true)
	var source_bags: Array[String] = []
	for uid: String in invalid_v14.locations:
		if invalid_v14.locations[uid].kind == "bag":
			source_bags.append(uid)
	if source_bags.size() >= 2:
		invalid_v14.locations[source_bags[1]] = invalid_v14.locations[source_bags[0]].duplicate(true)
	var invalid_path := "user://paged_bag_invalid_v14_%d.json" % Time.get_ticks_usec()
	var invalid_bytes := JSON.stringify(invalid_v14, "\t", true, true).to_utf8_buffer()
	_write(invalid_path, invalid_bytes)
	var invalid_memory := loaded.snapshot()
	_expect(source_bags.size() >= 2 and not loaded.load_build(invalid_path),
		"invalid v14 overlap is rejected before deterministic repacking")
	_expect(loaded.snapshot() == invalid_memory and FileAccess.get_file_as_bytes(invalid_path) == invalid_bytes
		and not FileAccess.file_exists(invalid_path + ".v14-backup.json"),
		"invalid v14 source, memory, and backup path remain untouched")

	var conflict_path := "user://paged_bag_backup_conflict_%d.json" % Time.get_ticks_usec()
	var conflict_backup := "preexisting backup bytes\n".to_utf8_buffer()
	_write(conflict_path, source_bytes)
	_write(conflict_path + ".v14-backup.json", conflict_backup)
	var conflict_memory := loaded.snapshot()
	_expect(not loaded.load_build(conflict_path) and loaded.snapshot() == conflict_memory
		and FileAccess.get_file_as_bytes(conflict_path) == source_bytes
		and FileAccess.get_file_as_bytes(conflict_path + ".v14-backup.json") == conflict_backup,
		"conflicting backup blocks migration without changing source or memory")

	var fault_path := "user://paged_bag_write_fault_%d.json" % Time.get_ticks_usec()
	_write(fault_path, source_bytes)
	var fault := WriteFailState.new()
	fault.fail_writes = true
	var fault_memory := fault.snapshot()
	_expect(not fault.load_build(fault_path) and fault.snapshot() == fault_memory
		and FileAccess.get_file_as_bytes(fault_path) == source_bytes
		and FileAccess.get_file_as_bytes(fault_path + ".v14-backup.json") == source_bytes,
		"replacement write failure preserves memory and exact original after making its backup")

	var future_path := "user://paged_bag_future_%d.json" % Time.get_ticks_usec()
	var future := loaded.snapshot()
	future.version = 16
	var future_bytes := JSON.stringify(future, "\t", true, true).to_utf8_buffer()
	_write(future_path, future_bytes)
	var future_memory := loaded.snapshot()
	_expect(not loaded.load_build(future_path) and loaded.snapshot() == future_memory
		and FileAccess.get_file_as_bytes(future_path) == future_bytes,
		"future schema stays protected and cannot replace current memory")

	var full_state := loaded
	var capacity_rng := RandomNumberGenerator.new()
	capacity_rng.seed = 99174
	var rng_before_space_award: int = capacity_rng.state
	var space_award_uid := full_state.award_equipment(capacity_rng, 30, "rare")
	_expect(not space_award_uid.is_empty() and capacity_rng.state != rng_before_space_award
		and Rules.reason(full_state.snapshot()).is_empty(),
		"legal level-30 equipment reward succeeds and consumes RNG while space remains")
	var page_zero_filled := _fill_page(full_state, 0)
	var full_snapshot := full_state.snapshot()
	var full_validation := Layout.validate_paged(Items.metadata_for_items(full_snapshot.items),
		full_snapshot.locations, LegacyMigration.paged_location_context(full_snapshot))
	var first_page_end_uid := full_state.award_gem("support:focus")
	_expect(page_zero_filled and _page_cell_count(full_validation.occupied_cells, 0) == 48
		and not first_page_end_uid.is_empty() and full_state.location(first_page_end_uid).page == 1,
		"reward insertion fills page one first, then selects an available slot on page two")
	var page_one_filled := _fill_page(full_state, 1)
	var full_before := full_state.snapshot()
	var rng_before_full_award: int = capacity_rng.state
	var failed_drop := full_state.award_equipment(capacity_rng, 30, "rare")
	_expect(failed_drop.is_empty() and capacity_rng.state == rng_before_full_award
		and full_state.snapshot() == full_before,
		"last-cell overflow rejects atomically and restores the loot RNG stream")

	var full_layout := Layout.validate_paged(Items.metadata_for_items(full_before.items),
		full_before.locations, LegacyMigration.paged_location_context(full_before))
	_expect(page_one_filled and full_layout.ok and full_layout.occupied_cells.size() == 96,
		"both pages together expose exactly the original 96-cell capacity")

	var current := state.snapshot()
	var external_path := path
	var external_uid := _first_bag_uid(current.locations)
	var original_location: Dictionary = current.locations.get(external_uid, {}).duplicate(true)
	var external_context := LegacyMigration.paged_location_context(current,
		Rules.SourceTree.Data.standard_socket_ids())
	var alternative_location := _free_location_except(Items.metadata_for_items(current.items),
		current.locations, external_context, external_uid, original_location)
	var attempts_before_external := state.save_attempts
	var saves_before_external := state.successful_saves
	_expect(not external_uid.is_empty() and not alternative_location.is_empty()
		and state.can_move_item(external_uid, alternative_location, state.revision()),
		"state owner has a real movable source and a distinct free target before external rewrite")
	var move_away := state.move_item(external_uid, alternative_location, state.revision(), external_path)
	var move_back := state.move_item(external_uid, original_location, state.revision(), external_path) \
		if move_away.get("ok", false) else {"ok": false}
	_expect(move_away.get("ok", false) and move_back.get("ok", false)
		and state.location(external_uid) == original_location
		and state.can_move_item(external_uid, alternative_location, state.revision()),
		"same state fixture can move to the distinct target and return before external rewrite")
	attempts_before_external = state.save_attempts
	saves_before_external = state.successful_saves
	var external := state.snapshot()
	external.revision += 1
	var external_bytes := JSON.stringify(external, "\t", true, true).to_utf8_buffer()
	_write(external_path, external_bytes)
	var guarded_memory := state.snapshot()
	var rejected_external_move := state.move_item(external_uid, alternative_location, state.revision(), external_path)
	_expect(not rejected_external_move.ok and rejected_external_move.error_code == "save_failed"
		and rejected_external_move.reason.contains("外部修改") and state.snapshot() == guarded_memory
		and FileAccess.get_file_as_bytes(external_path) == external_bytes,
		"external rewrite blocks a real page transfer and preserves memory and external disk bytes")
	_expect(state.save_attempts == attempts_before_external and state.successful_saves == saves_before_external,
		"external modification check rejects before the save attempt counter advances")

	print("Paged bag state: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _first_bag_uid(locations: Dictionary) -> String:
	var ids: Array[String] = []
	for uid: String in locations:
		if locations[uid].kind == "bag":
			ids.append(uid)
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


func _first_bag_equipment_uid(snapshot: Dictionary) -> String:
	var ids: Array[String] = []
	for uid: String in snapshot.locations:
		if snapshot.locations[uid].kind == "bag" and snapshot.items[uid].kind == "equipment":
			ids.append(uid)
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


func _recovery_locations(locations: Dictionary) -> Dictionary:
	var result := {}
	for uid: String in locations:
		if locations[uid].kind == "recovery":
			result[uid] = locations[uid].index
	return result


func _page_one_free_location(metadata: Dictionary, locations: Dictionary, context: Dictionary, uid: String) -> Dictionary:
	var checked: Dictionary = Layout.validate_paged(metadata, locations, context)
	if not checked.ok:
		return {}
	for y: int in range(6):
		for x: int in range(8):
			var location := {"kind": "bag", "page": 1, "x": x, "y": y}
			var placement := BagLayout.check_placement(uid, metadata[uid].size, location, checked.occupied_cells)
			if placement.ok:
				return location
	return {}


func _free_location_except(metadata: Dictionary, locations: Dictionary, context: Dictionary,
		uid: String, excluded: Dictionary) -> Dictionary:
	var checked: Dictionary = Layout.validate_paged(metadata, locations, context)
	if not checked.ok or not metadata.has(uid):
		return {}
	var occupied: Dictionary = checked.occupied_cells.duplicate(true)
	for cell: Variant in occupied.keys():
		if occupied[cell] == uid:
			occupied.erase(cell)
	for page: int in range(2):
		for y: int in range(6):
			for x: int in range(8):
				var location := {"kind": "bag", "page": page, "x": x, "y": y}
				if location == excluded:
					continue
				var placement: Dictionary = BagLayout.check_placement(uid, metadata[uid].size, location, occupied)
				if placement.ok:
					return location
	return {}


func _award_rare_page_one(state: State, path: String, rng: RandomNumberGenerator) -> String:
	var uid := state.award_equipment(rng, 30, "rare", "nine_slot")
	if uid.is_empty():
		return ""
	var snapshot := state.snapshot()
	var destination := _page_one_free_location(Items.metadata_for_items(snapshot.items), snapshot.locations,
		LegacyMigration.paged_location_context(snapshot, Rules.SourceTree.Data.standard_socket_ids()), uid)
	if destination.is_empty():
		return ""
	var moved := state.move_item(uid, destination, state.revision(), path)
	return uid if moved.get("ok", false) and state.location(uid).page == 1 else ""


func _page_cell_count(occupied: Dictionary, page: int) -> int:
	var count := 0
	for key: String in occupied:
		if key.begins_with("bag:%d:" % page):
			count += 1
	return count


func _fill_page(state: State, page: int) -> bool:
	var candidate := state.snapshot()
	var metadata := Items.metadata_for_items(candidate.items)
	var layout := Layout.validate_paged(metadata, candidate.locations,
		LegacyMigration.paged_location_context(candidate, Rules.SourceTree.Data.standard_socket_ids()))
	if not layout.ok:
		return false
	var occupied: Dictionary = layout.occupied_cells.duplicate(true)
	var serial: int = int(candidate.next_item_serial)
	for y: int in range(6):
		for x: int in range(8):
			var key := "bag:%d:%d:%d" % [page, x, y]
			if occupied.has(key):
				continue
			var uid := "item_%06d" % serial
			serial += 1
			while candidate.items.has(uid):
				uid = "item_%06d" % serial
				serial += 1
			var gem: Dictionary = Gems.create_instance(uid, "support:focus")
			if gem.is_empty():
				return false
			candidate.items[uid] = gem
			candidate.locations[uid] = {"kind": "bag", "page": page, "x": x, "y": y}
			occupied[key] = uid
			candidate.next_item_serial = serial
			candidate.revision += 1
	if not Rules.reason(candidate).is_empty():
		return false
	state._accept_memory(candidate)
	return true


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
