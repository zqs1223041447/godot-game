extends SceneTree

const Model = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Currency = preload("res://scripts/items/currency_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Transfer = preload("res://scripts/items/item_transfer_plan.gd")
const Migration = preload("res://scripts/save/canonical_build_migration.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")

class FailingModel extends Model:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)

var checks := 0
var failures := 0
var socket_ids: Array = []


func _initialize() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-currency-dev/") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	socket_ids = Rules.SourceTree.Data.standard_socket_ids()
	check(_recovery_is_not_spendable(), "recovery currency is included in total but excluded from crafting balance")
	check(_crafting_moves_quantities_across_stacks_to_zero(), "calibration consumes bag stacks by stable UID and removes zero stacks")
	check(_salvage_merges_existing_stack(), "salvage deletes gear then credits an existing bag stack")
	check(_salvage_uses_released_cell_when_bag_is_full(), "full-pack salvage places a new currency item in the released real cell")
	check(_atomic_currency_merge_and_boundary(), "drag merge preserves totals, IDs and occupancy limits atomically")
	check(_write_failure_retry_is_deterministic(), "failed save preserves state and retry uses the same craft seed")
	check(_stale_quote_and_external_edit_are_atomic(), "stale quotes and external disk edits preserve memory")
	check(_global_quantity_limit_includes_recovery(), "the 1e9 cap includes recovery and is checked on persisted schema")
	print("Currency transactions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _model() -> Model:
	var state := Model.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99231
	for unused: int in range(4):
		if state.award_equipment(rng, 30, "rare", "nine_slot").is_empty():
			check(false, "fixture generates a real eligible equipment item")
	return state


func _eligible_gear(state: Model) -> String:
	for uid: String in state.snapshot().items:
		var item: Dictionary = state.item(uid)
		if item.get("kind", "") == "equipment" and not item.payload.is_empty() \
				and not item.payload.affixes.is_empty() and state.location(uid).kind == "bag":
			return uid
	return ""


func _save(state: Model, label: String) -> String:
	var path := "user://currency_%s_%d.json" % [label, Time.get_ticks_usec()]
	check(state.save_build(path) == OK, "fixture saves to isolated path: " + label)
	return path


func _seed_stacks(state: Model, path: String, stacks: Array[Dictionary]) -> void:
	var candidate: Dictionary = state.snapshot()
	for spec: Dictionary in stacks:
		var uid: String = spec.uid
		var item: Dictionary = Items.calibration_shard(uid, spec.quantity)
		check(not item.is_empty(), "currency fixture stack is valid")
		candidate.items[uid] = item
		if spec.get("recovery", false):
			candidate.locations[uid] = {"kind": "recovery", "index": candidate.items.size() - 1}
		else:
			var metadata: Dictionary = Items.metadata_for_items(candidate.items)
			var location: Dictionary = Transfer.first_bag_space_paged(metadata, candidate.locations,
				Migration.paged_location_context(candidate, socket_ids), uid)
			if location.is_empty():
				candidate.locations[uid] = {"kind": "recovery", "index": candidate.items.size() - 1}
			else:
				candidate.locations[uid] = location
	candidate.revision += 1
	state._accept_memory(candidate)
	check(Rules.reason(state.snapshot(), state._talent_validator, socket_ids).is_empty(), "injected currency fixture remains canonical")
	check(state.save_build(path) == OK, "injected currency fixture persists")


func _recovery_is_not_spendable() -> bool:
	var state := _model()
	var path: String = _save(state, "recovery")
	var target: String = _eligible_gear(state)
	if target.is_empty(): return false
	var source: Dictionary = state.item(target).payload
	var cost: int = int(Craft.recalibrate_plan(source, 0).cost.calibration_shard)
	_seed_stacks(state, path, [{"uid": "recovery_only_currency", "quantity": cost, "recovery": true}])
	var quote: Dictionary = state.crafting_quote("recalibrate", target, path)
	return state.crafting_balance() == 0 and not quote.ok and quote.code == "insufficient_materials" \
		and Currency.total_quantity(state.snapshot().items).quantity == cost


func _crafting_moves_quantities_across_stacks_to_zero() -> bool:
	var state: Model = _model()
	var target: String = _eligible_gear(state)
	if target.is_empty(): return false
	var source: Dictionary = state.item(target).payload
	var cost: int = int(Craft.recalibrate_plan(source, 0).cost.calibration_shard)
	var left: int = maxi(1, int(cost / 2))
	var right: int = cost - left
	if right <= 0: right = 1; left = cost - 1
	var path: String = _save(state, "multi_stack")
	_seed_stacks(state, path, [
		{"uid": "currency_pay_a", "quantity": left},
		{"uid": "currency_pay_b", "quantity": right},
	])
	var before_total: int = Currency.total_quantity(state.snapshot().items).quantity
	var quote: Dictionary = state.crafting_quote("recalibrate", target, path)
	if not quote.ok: return false
	var result: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	var after: Dictionary = state.snapshot()
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result.ok and state.crafting_balance() == 0 and not after.items.has("currency_pay_a") \
		and not after.items.has("currency_pay_b") and before_total - Currency.total_quantity(after.items).quantity == cost \
		and after.crafting == {"revision": 1} and not disk.crafting.has("materials") \
		and disk.version == 18 and Rules.reason(Rules.decode(disk)).is_empty()


func _salvage_merges_existing_stack() -> bool:
	var state: Model = _model()
	var target: String = _eligible_gear(state)
	if target.is_empty(): return false
	var path: String = _save(state, "salvage_merge")
	_seed_stacks(state, path, [{"uid": "existing_shards", "quantity": 11}])
	var before: int = state.crafting_balance()
	var quote: Dictionary = state.crafting_quote("salvage", target, path)
	if not quote.ok: return false
	var released: Dictionary = state.location(target)
	var result: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	var after: Dictionary = state.snapshot()
	return result.ok and state.item(target).is_empty() and after.items.has("existing_shards") \
		and after.items.existing_shards.payload.quantity == before + int(quote.materials.calibration_shard) \
		and state.crafting_balance() == before + int(quote.materials.calibration_shard) \
		and after.locations.existing_shards.kind == "bag" and released.kind == "bag"


func _salvage_uses_released_cell_when_bag_is_full() -> bool:
	var state: Model = _model()
	var target: String = _eligible_gear(state)
	if target.is_empty(): return false
	var path: String = _save(state, "salvage_full")
	var candidate: Dictionary = state.snapshot()
	var metadata: Dictionary = Items.metadata_for_items(candidate.items)
	var context: Dictionary = Migration.paged_location_context(candidate, socket_ids)
	var inspected: Dictionary = Locations.validate_current(metadata,candidate.locations,context)
	if not inspected.ok: push_error("full-pack initial layout: " + str(inspected)); return false
	var occupied: Dictionary = inspected.occupied_cells
	for page: int in range(2):
		for y: int in range(10):
			for x: int in range(12):
				var cell_key := "bag:%d:%d:%d" % [page, x, y]
				if occupied.has(cell_key): continue
				var uid := "full_pack_gem_%03d_%d" % [page, y * 12 + x]
				var gem: Dictionary = Gems.create_instance(uid, "support:focus")
				if gem.is_empty(): return false
				candidate.items[uid] = gem
				candidate.locations[uid] = {"kind": "bag", "page": page, "x": x, "y": y}
	candidate.revision += 1
	state._accept_memory(candidate)
	var candidate_reason: String = Rules.reason(state.snapshot(), state._talent_validator, socket_ids)
	if not candidate_reason.is_empty(): push_error("full-pack candidate invalid: " + candidate_reason); return false
	if state.save_build(path) != OK:
		push_error("full-pack candidate save failed: " + state.last_error)
		return false
	var before_layout: Dictionary = Locations.validate_current(Items.metadata_for_items(state.snapshot().items),state.snapshot().locations,context)
	if not before_layout.ok or before_layout.occupied_cells.size() != 240:
		push_error("full-pack occupancy mismatch: " + str(before_layout))
		return false
	var released: Dictionary = state.location(target)
	var quote: Dictionary = state.crafting_quote("salvage", target, path)
	if not quote.ok: push_error("full-pack quote rejected: " + str(quote)); return false
	var result: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	if not result.ok: push_error("full-pack salvage failed: " + str(result)); return false
	var shards: Array[String] = []
	for uid: String in state.snapshot().items:
		if state.item(uid).kind == "currency": shards.append(uid)
	var exact: bool = shards.size() == 1 and state.location(shards[0]) == released \
		and state.snapshot().items[shards[0]].payload.quantity == int(quote.materials.calibration_shard)
	if not exact: push_error("full-pack shard placement/count mismatch: " + str(shards) + " released=" + str(released))
	return exact


func _atomic_currency_merge_and_boundary() -> bool:
	var state: Model = _model()
	var path: String = _save(state, "merge")
	var limit: int = Currency.STACK_LIMIT
	_seed_stacks(state, path, [
		{"uid": "merge_target", "quantity": limit - 3},
		{"uid": "merge_source", "quantity": 3},
	])
	var source_location: Dictionary = state.location("merge_source")
	var target_location: Dictionary = state.location("merge_target")
	var total_before: int = Currency.total_quantity(state.snapshot().items).quantity
	var revision_before: int = state.revision()
	var blocked_gear: String = _eligible_gear(state)
	if blocked_gear.is_empty(): return false
	var rejected_other_kind: bool = state.can_move_item(blocked_gear, target_location, revision_before)
	var can_merge: bool = state.can_move_item("merge_source", target_location, revision_before)
	var moved: Dictionary = state.move_item("merge_source", target_location, revision_before, path)
	var after: Dictionary = state.snapshot()
	var reopened := Model.new()
	var loaded: bool = reopened.load_build(path)
	return can_merge and not rejected_other_kind and moved.ok and not after.items.has("merge_source") \
		and after.items.merge_target.payload.quantity == limit and state.location("merge_target") == target_location \
		and state.revision() == revision_before + 1 \
		and Currency.total_quantity(after.items).quantity == total_before \
		and source_location.kind == "bag" and loaded and reopened.snapshot() == after \
		and Currency.make_instance("over_stack", limit + 1).is_empty()


func _write_failure_retry_is_deterministic() -> bool:
	var state := FailingModel.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 27731
	var target := ""
	for unused: int in range(2): target = state.award_equipment(rng, 30, "rare", "nine_slot")
	if target.is_empty(): return false
	var source: Dictionary = state.item(target).payload
	var cost: int = int(Craft.recalibrate_plan(source, 0).cost.calibration_shard)
	var path: String = _save(state, "retry")
	_seed_stacks(state, path, [
		{"uid": "retry_a", "quantity": maxi(1, int(cost / 2))},
		{"uid": "retry_b", "quantity": cost - maxi(1, int(cost / 2))},
	])
	var quote: Dictionary = state.crafting_quote("recalibrate", target, path)
	if not quote.ok: return false
	var before: Dictionary = state.snapshot()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var seed_text := JSON.stringify({"rules": "original-crafting-prototype-v1", "revision": int(before.crafting.revision), "item": source}, "", true, true)
	var seed_value: int = seed_text.sha256_text().substr(0, 15).hex_to_int()
	var expected: Dictionary = Craft.recalibrate_plan(source, seed_value)
	seed(18177)
	var expected_random: int = randi()
	seed(18177)
	state.fail_writes = true
	var failed: Dictionary = state.execute_crafting(quote.handle, source)
	var preserved: bool = not failed.ok and state.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes
	state.fail_writes = false
	var retried: Dictionary = state.execute_crafting(quote.handle, source)
	var random_preserved: bool = randi() == expected_random
	return preserved and retried.ok and state.item(target).payload == expected.instance \
		and state.crafting_balance() == 0 and random_preserved


func _stale_quote_and_external_edit_are_atomic() -> bool:
	var state: Model = _model()
	var path: String = _save(state, "external")
	var target: String = _eligible_gear(state)
	if target.is_empty(): return false
	_seed_stacks(state, path, [{"uid": "stale_stack", "quantity": 100}])
	var quote: Dictionary = state.crafting_quote("salvage", target, path)
	if not quote.ok: return false
	state.add_xp(1)
	var after_xp: Dictionary = state.snapshot()
	var stale: Dictionary = state.execute_crafting(quote.handle, quote.source_instance)
	var stale_safe: bool = not stale.ok and state.snapshot() == after_xp

	var external_state: Model = _model()
	var external_path: String = _save(external_state, "external_disk")
	var external_target: String = _eligible_gear(external_state)
	if external_target.is_empty(): return false
	_seed_stacks(external_state, external_path, [{"uid": "external_stack", "quantity": 31}])
	quote = external_state.crafting_quote("salvage", external_target, external_path)
	if not quote.ok: return false
	var memory_before: Dictionary = external_state.snapshot()
	var external_candidate: Dictionary = memory_before.duplicate(true)
	external_candidate.progress.xp += 1
	var external_bytes: PackedByteArray = JSON.stringify(external_candidate, "\t", true, true).to_utf8_buffer()
	var file := FileAccess.open(external_path, FileAccess.WRITE)
	file.store_buffer(external_bytes)
	file.close()
	var held_disk: PackedByteArray = FileAccess.get_file_as_bytes(external_path)
	var changed: Dictionary = external_state.execute_crafting(quote.handle, quote.source_instance)
	return stale_safe and not changed.ok and changed.code == "save_changed" \
		and external_state.snapshot() == memory_before and FileAccess.get_file_as_bytes(external_path) == held_disk


func _global_quantity_limit_includes_recovery() -> bool:
	var state: Model = _model()
	var path: String = _save(state, "limit")
	_seed_stacks(state, path, [{"uid": "limit_bag", "quantity": Currency.INVENTORY_LIMIT}])
	var valid: Dictionary = state.snapshot()
	var excess: Dictionary = Items.calibration_shard("limit_recovery", 1)
	valid.items["limit_recovery"] = excess
	valid.locations["limit_recovery"] = {"kind": "recovery", "index": valid.items.size() - 1}
	var over_total: Dictionary = Currency.total_quantity(valid.items)
	var valid_error: String = Rules.reason(valid, state._talent_validator, socket_ids)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Currency.total_quantity(state.snapshot().items).quantity == Currency.INVENTORY_LIMIT \
		and not over_total.ok and not valid_error.is_empty() and Rules.reason(Rules.decode(disk)).is_empty() \
		and state.crafting_balance() == Currency.INVENTORY_LIMIT


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
