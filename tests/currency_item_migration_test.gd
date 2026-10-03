extends SceneTree

const Legacy = preload("res://scripts/build_state.gd")
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const PagedMigration = preload("res://scripts/save/paged_bag_migration.gd")
const CurrencyMigration = preload("res://scripts/save/currency_item_migration.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const BagLayout = preload("res://scripts/items/paged_bag_layout.gd")

class FailingStore extends Store:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)

var checks := 0
var failures := 0


func _initialize() -> void:
	for balance: int in [0, 117]:
		var v14: Dictionary = _v14(balance)
		check(Rules.reason_v14(v14).is_empty(), "v14 source passes its frozen validator")
		var v15: Dictionary = PagedMigration.migrate_v14(v14)
		check(not v15.is_empty() and Rules.reason_v15(v15).is_empty(), "v14 passes through the existing paged migration")
		var before: PackedByteArray = var_to_bytes(v15)
		var v16: Dictionary = CurrencyMigration.migrate_v15(v15)
		if v16.is_empty() or not Rules.reason(v16).is_empty():
			var metadata: Dictionary = Items.metadata_for_items(v15.items)
			var context: Dictionary = Migration.location_context(v15)
			var inspected: Dictionary = BagLayout.inspect_layout(metadata, v15.locations, context)
			print("migration failure balance=", balance, " empty=", v16.is_empty(), " reason=", Rules.reason(v16),
				" craft=", v15.crafting, " metadata=", metadata.size(), " items=", v15.items.size(), " layout=", inspected)
			check(false, "valid v15 candidate migrates to schema16")
			quit(1)
			return
		check(true, "valid v15 candidate migrates to schema16")
		check(var_to_bytes(v15) == before, "currency migration leaves its input unchanged")
		check(v16.version == 16 and v16.crafting == {"revision": v15.crafting.revision}, "v16 stores only the crafting revision")
		var currency_uids: Array[String] = _currency_uids(v16)
		if balance == 0:
			check(currency_uids.is_empty(), "zero old balance creates no currency item")
		else:
			check(currency_uids.size() == 1 and v16.items[currency_uids[0]].payload.quantity == balance,
				"nonzero old balance becomes one exact stack")
			check(v16.locations[currency_uids[0]].kind in ["bag", "recovery"], "migrated currency remains visible")
			check(v16.next_item_serial == v15.next_item_serial, "currency migration does not consume gear identity serial")
	check(_old_currency_injection_rejected(), "frozen v14/v15 validators reject currency injection")
	check(_old_full_bag_expands_with_currency(), "old full 96-cell bag gains space for its real balance item")
	check(_full_v15_registry_migrates_one_extra_item(), "1024-item v15 limit stays frozen and v16 accommodates one balance item")
	check(_v13_representative_preserves_wallet_items_and_talents(), "representative v13 source passes old chain and retains balances/identities")
	check(_store_migration_backup_and_failure_atomicity(), "v14/v15 file migration backs up exact bytes and preserves state on failure")
	print("Currency migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _v14(balance: int) -> Dictionary:
	var legacy := Legacy.new()
	legacy.crafting = {"materials": {"calibration_shard": balance}, "revision": 23}
	return Migration.migrate(legacy._snapshot())


func _old_currency_injection_rejected() -> bool:
	var v14: Dictionary = _v14(13)
	var v14_bad: Dictionary = _inject_recovery_currency(v14)
	var v15: Dictionary = PagedMigration.migrate_v14(_v14(13))
	var v15_bad: Dictionary = _inject_recovery_currency(v15)
	return not v14_bad.is_empty() and Rules.decode_v14(v14_bad).is_empty() \
		and not Rules.reason_v14(v14_bad).is_empty() and not v15_bad.is_empty() \
		and Rules.decode_v15(v15_bad).is_empty() and not Rules.reason_v15(v15_bad).is_empty()


func _inject_recovery_currency(source: Dictionary) -> Dictionary:
	var candidate: Dictionary = source.duplicate(true)
	var uid := "injected_currency_test"
	candidate.items[uid] = Items.calibration_shard(uid, 13)
	candidate.locations[uid] = {"kind": "recovery", "index": candidate.items.size() - 1}
	return candidate


func _old_full_bag_expands_with_currency() -> bool:
	var candidate: Dictionary = PagedMigration.migrate_v14(_v14(91))
	if candidate.is_empty(): return false
	candidate.locations = Transfer.compact_recovery(candidate.locations)
	var next_recovery := 0
	for uid: String in candidate.locations:
		if candidate.locations[uid].kind == "recovery":
			next_recovery = maxi(next_recovery, int(candidate.locations[uid].index) + 1)
	var prior_bags: Array[String] = []
	for uid: String in candidate.locations:
		if candidate.locations[uid].kind == "bag": prior_bags.append(uid)
	for uid: String in prior_bags:
		candidate.locations[uid] = {"kind": "recovery", "index": next_recovery}
		next_recovery += 1
	for cell: int in range(96):
		var uid := "full_bag_support_%03d" % cell
		var item: Dictionary = Gems.create_instance(uid, "support:focus")
		if item.is_empty(): return false
		candidate.items[uid] = item
		candidate.locations[uid] = {"kind": "bag", "page": int(cell / 48), "x": cell % 8, "y": int((cell % 48) / 8)}
	candidate.crafting.materials.calibration_shard = 91
	if not Rules.reason_v15(candidate).is_empty(): return false
	var migrated: Dictionary = CurrencyMigration.migrate_v15(candidate)
	if migrated.is_empty() or not Rules.reason(migrated).is_empty(): return false
	var uids := _currency_uids(migrated)
	return uids.size() == 1 and migrated.items[uids[0]].payload.quantity == 91 \
		and migrated.locations[uids[0]].kind == "bag"


func _full_v15_registry_migrates_one_extra_item() -> bool:
	var candidate: Dictionary = PagedMigration.migrate_v14(_v14(500))
	if candidate.is_empty(): return false
	candidate.next_item_serial = Rules.MAX_SERIAL
	while candidate.items.size() < Rules.LEGACY_MAX_ITEMS:
		var uid := "legacy_fill_%04d" % candidate.items.size()
		var item: Dictionary = Items.fixed_equipment(uid, "swift_blade")
		if item.is_empty(): return false
		var recovery_index: int = candidate.items.size()
		candidate.items[uid] = item
		candidate.locations[uid] = {"kind": "recovery", "index": recovery_index}
	if not Rules.reason_v15(candidate).is_empty(): return false
	var migrated: Dictionary = CurrencyMigration.migrate_v15(candidate)
	return not migrated.is_empty() and migrated.items.size() == Rules.LEGACY_MAX_ITEMS + 1 \
		and Rules.reason(migrated).is_empty() and _currency_uids(migrated).size() == 1


func _v13_representative_preserves_wallet_items_and_talents() -> bool:
	var legacy := Legacy.new()
	legacy.crafting = {"materials": {"calibration_shard": 73}, "revision": 8}
	var raw: Dictionary = legacy._snapshot()
	var v14: Dictionary = Migration.migrate(raw)
	if v14.is_empty() or not Rules.reason_v14(v14).is_empty(): return false
	var v15: Dictionary = PagedMigration.migrate_v14(v14)
	var v16: Dictionary = CurrencyMigration.migrate_v15(v15)
	if v16.is_empty() or not Rules.reason(v16).is_empty(): return false
	var currency: Array[String] = _currency_uids(v16)
	return currency.size() == 1 and v16.items[currency[0]].payload.quantity == 73 \
		and v16.migration_ledger.from_version == 13 and v16.progress == v14.progress \
		and v16.talents == v14.talents and v16.skill_groups == v14.skill_groups \
		and v16.next_item_serial == v14.next_item_serial


func _store_migration_backup_and_failure_atomicity() -> bool:
	var isolated: String = OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-currency-dev/") \
			or not OS.get_user_data_dir().begins_with(isolated + "/"):
		return false
	var ok := true
	for version: int in [14, 15]:
		var source: Dictionary = _v14(0 if version == 14 else 321)
		if version == 15: source = PagedMigration.migrate_v14(source)
		var path := "user://currency_source_v%d_%d.json" % [version, Time.get_ticks_usec()]
		var bytes := PackedByteArray([239, 187, 191]) + JSON.stringify(source, "  ", true, true).to_utf8_buffer()
		_write(path, bytes)
		var state := Store.new()
		var loaded: bool = state.load_build(path)
		var backup_path := path + ".v%d-backup.json" % version
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var expected_balance: int = 0 if version == 14 else 321
		var visible_balance := 0
		for uid: String in state.snapshot().items:
			if state.snapshot().items[uid].kind == "currency" and state.snapshot().locations[uid].kind == "bag":
				visible_balance += int(state.snapshot().items[uid].payload.quantity)
		ok = ok and loaded and FileAccess.get_file_as_bytes(backup_path) == bytes \
			and raw.version == 16 and Rules.decode(raw).crafting == {"revision": 23} \
			and visible_balance == expected_balance and state.successful_saves == 1 \
			and not raw.crafting.has("materials") and Rules.reason(state.snapshot()).is_empty()
	var conflict_source: Dictionary = PagedMigration.migrate_v14(_v14(18))
	var conflict_path := "user://currency_backup_conflict_%d.json" % Time.get_ticks_usec()
	var conflict_bytes: PackedByteArray = JSON.stringify(conflict_source).to_utf8_buffer()
	_write(conflict_path, conflict_bytes)
	_write(conflict_path + ".v15-backup.json", "different backup".to_utf8_buffer())
	var conflict := Store.new()
	var conflict_before: Dictionary = conflict.snapshot()
	ok = ok and not conflict.load_build(conflict_path) and conflict.snapshot() == conflict_before \
		and FileAccess.get_file_as_bytes(conflict_path) == conflict_bytes
	var failed_path := "user://currency_write_failure_%d.json" % Time.get_ticks_usec()
	var failed_bytes: PackedByteArray = JSON.stringify(conflict_source).to_utf8_buffer()
	_write(failed_path, failed_bytes)
	var failing := FailingStore.new()
	failing.fail_writes = true
	var before: Dictionary = failing.snapshot()
	var failed: bool = not failing.load_build(failed_path)
	ok = ok and failed and failing.snapshot() == before and FileAccess.get_file_as_bytes(failed_path) == failed_bytes \
		and FileAccess.get_file_as_bytes(failed_path + ".v15-backup.json") == failed_bytes
	return ok


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "migration fixture opens inside isolated userdata")
		return
	file.store_buffer(bytes)
	file.close()


func _currency_uids(candidate: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for uid: String in candidate.items:
		if candidate.items[uid].kind == "currency": result.append(uid)
	result.sort()
	return result


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
