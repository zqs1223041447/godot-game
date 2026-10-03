extends SceneTree

const Legacy = preload("res://scripts/build_state.gd")
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const PagedMigration = preload("res://scripts/save/paged_bag_migration.gd")
const CurrencyMigration = preload("res://scripts/save/currency_item_migration.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const BagLayout = preload("res://scripts/items/paged_bag_layout.gd")

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
	check(_full_bag_routes_currency_to_recovery(), "full paged bag retains old balance in visible recovery")
	check(_full_v15_registry_migrates_one_extra_item(), "1024-item v15 limit stays frozen and v16 accommodates one balance item")
	check(_v13_representative_preserves_wallet_items_and_talents(), "representative v13 source passes old chain and retains balances/identities")
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


func _full_bag_routes_currency_to_recovery() -> bool:
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
		and migrated.locations[uids[0]].kind == "recovery"


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
