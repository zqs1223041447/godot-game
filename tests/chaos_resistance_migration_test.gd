extends SceneTree
## Frozen50→51 atomic migration, model equipment supply and existing craft economy.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/chaos_resistance_affix_migration.gd")
const FourthMap = preload("res://scripts/save/fourth_map_migration.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Fixture = preload("res://tests/chaos_resistance_equipment_test.gd")
const SOURCE_PATH := "res://docs/qa/v091-root-ui/main-after-reforge.json"
var checks := 0
var failures := 0
var evidence := {}

class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)

class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error: return ERR_CANT_CREATE

class ExternalIO extends Store.Legacy:
	func _backup_legacy_save(path: String) -> Error:
		var result := super._backup_legacy_save(path)
		if result == OK:
			var file := FileAccess.open(path, FileAccess.WRITE); file.store_string("external writer"); file.close()
		return result

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(bytes); file.close()

func upgraded(source: Dictionary) -> Dictionary:
	var copy := source.duplicate(true); copy.version = 51; return copy

func consumers(source: Dictionary) -> Dictionary:
	var game := Model.new(); game._accept_memory(source)
	var casts := {}
	for group: Dictionary in source.skill_groups: casts[group.id] = game.get_group_cast(group.id)
	return {"stats":game.get_stats(), "snapshot":game.get_combat_snapshot(), "basic":game.get_basic_cast(),
		"casts":casts, "equipped":game.equipped_items(), "pending":game.pending_items(), "wallet":Store.Currency.total_quantity(source.items)}

func migration_case(source: Dictionary, bytes: PackedByteArray, label: String) -> void:
	if not check(not source.is_empty() and Rules.reason_v50(source).is_empty(), "Complete source50 valid: " + label): return
	var before := var_to_bytes(source); var old_consumers := consumers(source)
	seed(935051); var next_rng := randi(); seed(935051)
	var result := Migration.migrate_v50(source)
	check(result == upgraded(source) and var_to_bytes(source) == before and randi() == next_rng, "Migration changes only version and consumes no RNG")
	for field: String in Rules.FIELDS:
		if field != "version": check(result[field] == source[field], "Preserve nonversion field: " + field)
	check(consumers(result) == old_consumers, "Old stats, casts, gear, points, wallet and recovery are preserved")
	var path := "user://migration-" + label + ".json"; write(path, bytes)
	var model := Model.new(); var changed := [0]; model.changed.connect(func(): changed[0] += 1)
	if not check(model.load_build(path) and model.snapshot() == upgraded(source), "Actual loader completes50→51: " + label): return
	check(changed[0] == 1 and model.save_attempts == 1 and model.successful_saves == 1, "One atomic commit and notification")
	check(FileAccess.get_file_as_bytes(path + ".v50-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Exact original bytes backed up")
	check(model.migrated_from_legacy and model.migration_message.contains("混沌抗性") and model.migration_message.contains("不额外赠物、材料或天赋点"), "No-gift affix migration is reported")
	var saved := FileAccess.get_file_as_bytes(path)
	check(model.load_build(path) and model.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == saved, "Repeated current load is read-only")
	var reopened := Model.new()
	check(reopened.load_build(path) and reopened.snapshot() == upgraded(source) and reopened.save_attempts == 0, "Independent current reopen unchanged")
	evidence[label] = {"source_bytes":bytes.size(), "source_items":source.items.size(), "wallet":old_consumers.wallet, "source_revision":source.revision}

func strict_checks(source: Dictionary) -> void:
	var calls := [0]; var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	var injected := source.duplicate(true)
	var ring := Fixture.legal_ring("gear_%06d" % int(injected.next_item_serial))
	injected.items[ring.id] = Store.Items.wrap_equipment(ring); injected.next_item_serial += 1
	var recovery_index := 0
	for location: Dictionary in injected.locations.values():
		if location.kind == "recovery": recovery_index += 1
	injected.locations[ring.id] = {"kind":"recovery", "index":recovery_index}
	check(Rules.reason(upgraded(injected)).is_empty(), "Chaos ring is valid only in current schema")
	Store.Items.metadata_for_items(injected.items)
	var bad_inputs := {"new_affix":injected}
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_location", "over_budget", "bad_journey", "unknown_node", "bad_binding", "bad_ledger"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.extra = true
			"missing_location": bad.locations.erase(bad.locations.keys()[0])
			"over_budget": bad.talents.normal_points += 1
			"bad_journey": bad.journey.best_tiers["unknown"] = 1
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.normal_budget_at_migration += 1
		bad_inputs[mutation] = bad
	for label: String in bad_inputs:
		var bad: Dictionary = bad_inputs[label]; calls[0] = 0
		check(not Rules.reason_v50(bad, permissive).is_empty() and Rules.decode_v50(bad).is_empty() and Migration.migrate_v50(bad, permissive).is_empty() and calls[0] == 0, "Frozen native validation precedes callbacks/cache: " + label)
		var path := "user://reject-" + label + ".json"; var bytes := JSON.stringify(bad).to_utf8_buffer(); write(path, bytes)
		var store := Store.new(); var before := store.snapshot()
		check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes and store.save_attempts == 0 and not FileAccess.file_exists(path + ".v50-backup.json"), "Invalid50 fails before backup/commit: " + label)
		check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected destination remains protected")
	check(Migration.migrate_v50(upgraded(source)).is_empty() and Rules.decode_v50(upgraded(source)).is_empty() and Rules.decode(source).is_empty(), "Version boundaries are exact")
	check(Migration.migrate_v50(source, func(_value: Dictionary) -> String: return "extra restriction").is_empty(), "Optional callback adds restrictions")

func failures_and_chain(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"; write(path, bytes)
		var model := FaultModel.new(); var before := model.snapshot(); var changed := [0]
		model.changed.connect(func(): changed[0] += 1)
		if failure == "backup": model._io = BackupFailIO.new()
		if failure == "collision": write(path + ".v50-backup.json", "retained backup".to_utf8_buffer())
		if failure == "external": model._io = ExternalIO.new()
		if failure == "atomic": model.fail_save = true
		check(not model.load_build(path) and model.snapshot() == before and model.successful_saves == 0 and changed[0] == 0, "Failed migration is atomic: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Original/external bytes retained: " + failure)
		check(model.save_attempts == (1 if failure == "atomic" else 0), "Guards precede commit")
		if failure in ["external", "atomic"]: check(FileAccess.get_file_as_bytes(path + ".v50-backup.json") == bytes, "Failed commit preserves exact backup")
		if failure == "atomic":
			model.fail_save = false
			check(model.load_build(path) and model.snapshot() == upgraded(source) and changed[0] == 1, "Safe retry reuses exact backup and commits once")
	var old49 := source.duplicate(true); old49.version = 49; old49.journey.best_tiers.erase("ginkgo_arcade")
	# The released fixture is idle; its old three-map form proves the retained map chain.
	if check(Rules.reason_v49(old49).is_empty(), "Prior frozen49 fixture is legal"):
		var mapped := FourthMap.migrate_v49(old49)
		check(mapped == source and Rules.reason_v50(mapped).is_empty(), "FourthMap remains exactly49→50")
		var path := "user://chain49.json"; var raw := JSON.stringify(old49).to_utf8_buffer(); write(path, raw)
		var model := Model.new()
		check(model.load_build(path) and model.snapshot() == upgraded(source) and model.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v49-backup.json") == raw and not FileAccess.file_exists(path + ".v50-backup.json"), "Older map+affix chain commits once from original bytes")
	var fresh := Model.new().snapshot()
	check(fresh.version == 51 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0, "Built-in complete migration chain reaches51 with no currency gift")

func model_equipment() -> void:
	var model := Model.new(); var baseline := model.get_stats()
	check(not baseline.has("chaos_resistance") and model.get_chaos_resistance_profile() == {"ok":true, "reason":"", "raw":0.0, "cap":0.75, "effective":0.0}, "Old no-source shape and zero profile remain explicit")
	var ids: Array[String] = []
	for index: int in range(2):
		var ring := Fixture.legal_ring("gear_%06d" % int(model.snapshot().next_item_serial)); ids.append(ring.id)
		check(model._admit_reward_item(Store.Items.wrap_equipment(ring)), "Controlled legal ring fixture admitted")
	check(not model.get_stats().has("chaos_resistance"), "Bag supply does not affect character")
	var path := "user://two-rings.json"; check(model.save_build(path) == OK, "Save two-ring fixture")
	for index: int in range(2):
		check(model.equip(ids[index]), "Actual equip transaction")
		var profile := model.get_chaos_resistance_profile()
		check(profile.ok and profile.raw == 0.25 * (index + 1) and profile.effective == profile.raw and profile.cap == 0.75, "Final model stats add each equipped ring once")
	check(model.equipped_items().has_all(["ring_1", "ring_2"]) and not model.equipped_items().has("ring_3"), "Only two legal ring slots, maximum gear supply50%")
	var saved := model.snapshot(); var reopened := Model.new()
	check(reopened.load_build(path) and reopened.snapshot() == saved and reopened.get_chaos_resistance_profile().raw == 0.5, "Real equipment51 roundtrip retains50%")
	var view := model.get_chaos_resistance_profile(); view.raw = 99.0
	check(model.get_chaos_resistance_profile().raw == 0.5, "Getter returns detached profile")
	check(model.unequip("ring_1") and model.get_chaos_resistance_profile().raw == 0.25, "Actual unequip removes one source")
	check(model.unequip("ring_2") and model.get_stats() == baseline and not model.get_stats().has("chaos_resistance"), "Removing final source restores old complete stats and field shape")

func craft_transactions() -> void:
	for operation: String in ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]:
		var model := FaultModel.new(); var uid := "gear_%06d" % int(model.snapshot().next_item_serial)
		var ring := Fixture.legal_ring(uid)
		if operation == "enchant": ring.rarity = "normal"; ring.affixes.clear()
		if operation == "augment": ring.affixes = [{"id":"nine_slot_prefix_vitality", "tier":3, "value":12}]
		if operation == "reforge": ring = Fixture.legal_rare_ring(uid)
		check(model._admit_reward_item(Store.Items.wrap_equipment(ring)), "Legal craft source admitted")
		var quote := Craft.operation_quote(ring, operation); var cost := int(quote.cost.get(Craft.MATERIAL_ID, 0)); var credit := int(quote.materials.get(Craft.MATERIAL_ID, 0))
		var candidate := model.snapshot(); check(model._set_bag_currency_balance(candidate, cost).ok, "Controlled exact-cost currency fixture")
		model._accept_memory(candidate); var path := "user://craft-" + operation + ".json"; check(model.save_build(path) == OK, "Persist coherent craft fixture")
		var before := model.snapshot(); var bytes := FileAccess.get_file_as_bytes(path)
		var issued := model.crafting_quote(operation, uid, path)
		if not check(issued.ok, "Existing operation issues current quote: " + operation): continue
		model.cancel_crafting_quote(issued.handle)
		check(not model.execute_crafting(issued.handle, ring).ok and model.snapshot() == before, "Cancelled quote never spends")
		issued = model.crafting_quote(operation, uid, path)
		var changed := [0]; model.changed.connect(func(): changed[0] += 1); var saves := model.successful_saves
		model.fail_save = true
		check(not model.execute_crafting(issued.handle, ring).ok and model.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes and changed[0] == 0 and model.successful_saves == saves, "Failed craft preserves item, currency, revisions, disk and notification")
		model.fail_save = false
		check(model.execute_crafting(issued.handle, ring).ok and model.crafting_balance() == credit and changed[0] == 1 and model.successful_saves == saves + 1, "Retry commits once with exact unchanged economics")
		var after := model.snapshot()
		check(after.version == 51 and after.crafting.revision == before.crafting.revision + 1 and after.journey == before.journey, "Craft changes only requested ownership/economy")
		check(not model.execute_crafting(issued.handle, ring).ok and model.snapshot() == after, "Repeat confirm cannot spend twice")
		var reopened := Model.new(); check(reopened.load_build(path) and reopened.snapshot() == after, "Current crafted output reopens exactly")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v093-equipment-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78); return
	check(Rules.VERSION == 51 and Rules.V50_VERSION == 50 and Gear.CURRENT_VOCABULARY == 51 and Source.CURRENT_SAVE_VERSION == 49 and Source._execution_policy(51) == 49, "Only equipment vocabulary advances; source policy49 retained")
	for version: int in range(1, 52):
		check(Rules.equipment_vocabulary_for_save_version(version) == (51 if version == 51 else 46 if version >= 46 else 39 if version >= 39 else 37 if version >= 37 else 34 if version >= 34 else version), "Save-equipment mapping remains frozen")
	var bytes := FileAccess.get_file_as_bytes(SOURCE_PATH)
	var source := Rules.decode_v50(JSON.parse_string(bytes.get_string_from_utf8()))
	if not source.is_empty():
		migration_case(source, bytes, "actual-v091")
		strict_checks(source)
		failures_and_chain(source, bytes)
	else: check(false, "Released actual-Main schema50 fixture decoded")
	model_equipment()
	craft_transactions()
	evidence.checks = checks; evidence.failures = failures
	var report := OS.get_environment("V093_MIGRATION_REPORT")
	if not report.is_empty(): write(report, (JSON.stringify(evidence, "\t") + "\n").to_utf8_buffer())
	print("Chaos migration/model: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
