extends SceneTree

const Model = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Currency = preload("res://scripts/items/currency_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const PATH := "user://build_save.json"
const TEST_PATH := "user://town_test_build_save.json"
const ACTIVE := "skill:bolt"
const SUPPORT := "support:efficiency"

class FaultModel extends Model:
	var fail_writes := false
	var corrupt_candidate := false
	var snapshot_calls := 0
	var stamp_calls := 0
	var notifications := 0
	var reenter := false
	var reenter_handle := ""
	var reenter_target := ""
	var reentered_quote: Dictionary = {}
	var reentered_execute: Dictionary = {}
	func snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.snapshot()
	func _canonical_disk_stamp(path: String) -> Dictionary:
		stamp_calls += 1
		return super._canonical_disk_stamp(path)
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)
	func _prepare_candidate(candidate: Dictionary) -> Dictionary:
		var prepared: Dictionary = super._prepare_candidate(candidate)
		if corrupt_candidate: prepared.progress.xp = -1
		return prepared
	func _on_changed() -> void:
		notifications += 1
		if reenter:
			reentered_quote = gem_trade_quote("buy", reenter_target, revision(), PATH)
			reentered_execute = execute_gem_trade(reenter_handle, reenter_target)

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func observed(state: FaultModel) -> Dictionary:
	return {"memory": var_to_bytes(state.snapshot()), "disk": FileAccess.get_file_as_bytes(PATH),
		"saves": state.successful_saves, "changed": state.notifications}


func _put(candidate: Dictionary, definition: String, location: Dictionary, quantity: int = 0) -> String:
	var uid := "item_%06d" % int(candidate.next_item_serial)
	candidate.items[uid] = Currency.make_instance(uid, quantity) if quantity > 0 else Gems.create_instance(uid, definition)
	candidate.locations[uid] = location
	candidate.next_item_serial += 1
	return uid


func _fixture(quantity: int = 0, full: bool = false) -> FaultModel:
	# Every fixture is built from the canonical migrated profile and is actually
	# saved to the literal normal path. The isolated runner owns this whole folder.
	if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var state := FaultModel.new()
	state.changed.connect(state._on_changed)
	var candidate: Dictionary = state.snapshot()
	for uid: String in candidate.locations.keys():
		if candidate.locations[uid].kind in ["bag", "recovery"]:
			candidate.locations.erase(uid)
			candidate.items.erase(uid)
	if full:
		for page: int in range(Locations.CURRENT_BAG_PAGES):
			for y: int in range(Locations.CURRENT_BAG_ROWS):
				for x: int in range(Locations.CURRENT_BAG_COLUMNS):
					var cell := {"kind": "bag", "page": page, "x": x, "y": y}
					_put(candidate, SUPPORT, cell, quantity if page == 0 and x == 0 and y == 0 else 0)
	elif quantity > 0:
		_put(candidate, "", {"kind": "bag", "page": 0, "x": 0, "y": 0}, quantity)
	candidate.revision += 1
	check(state._commit(candidate, PATH).ok, "Real canonical fixture commits to literal normal save")
	return state


func _commit_fixture(state: FaultModel, candidate: Dictionary, label: String) -> void:
	candidate.revision += 1
	check(state._commit(candidate, PATH).ok, label)


func _bag_gem(state: Model) -> String:
	var data: Dictionary = state.snapshot()
	for uid: String in data.items:
		if data.locations[uid].kind == "bag" and data.items[uid].kind in ["skill_gem", "support_gem"]:
			return uid
	return ""


func _bag_currency(state: Model) -> String:
	var data: Dictionary = state.snapshot()
	for uid: String in data.items:
		if data.locations[uid].kind == "bag" and data.items[uid].kind == "currency": return uid
	return ""


func _quote(state: FaultModel, operation: Variant, target: Variant) -> Dictionary:
	return state.gem_trade_quote(operation, target, state.revision(), PATH)


func _assert_rejected(state: FaultModel, operation: Variant, target: Variant, label: String) -> void:
	var before := observed(state)
	var result := _quote(state, operation, target)
	check(result.has("ok") and not result.ok and observed(state) == before, label)


func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	_all_definitions_and_economics()
	_input_and_profile_boundaries()
	_quote_authority_and_atomicity()
	_full_bag_boundaries()
	_inventory_and_serial_limits()
	print("Normal gem trade transactions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _all_definitions_and_economics() -> void:
	var state := _fixture(300)
	var before := observed(state)
	var snapshots := state.snapshot_calls
	var stamps := state.stamp_calls
	var attempts := state.save_attempts
	var issued_quotes := state._gem_trade_quotes.size()
	var quote_sequence: int = state._gem_trade_sequence
	var offers: Array = state.normal_gem_offers()
	var definitions: Dictionary = Gems.definitions()
	check(offers.size() == 26 and definitions.size() == 26, "Exactly all 26 live catalog definitions are offered")
	var found := {}
	var metadata_valid := true
	for offer: Dictionary in offers:
		var definition: Dictionary = definitions.get(offer.get("definition_id", ""), {})
		metadata_valid = metadata_valid and not definition.is_empty() and not found.has(offer.definition_id) \
			and offer.kind == definition.kind and offer.name == definition.name and offer.available is bool \
			and offer.available and offer.reason is String and offer.cost is int \
			and offer.cost == (8 if definition.kind == "skill_gem" else 4) \
			and not offer.has("handle") and not offer.has("candidate") and not offer.has("snapshot")
		found[offer.definition_id] = true
	check(metadata_valid and found.size() == definitions.size(), "Offer metadata has unique real IDs, typed prices, names and no transaction authority")
	check(state.snapshot_calls == snapshots and state.stamp_calls == stamps and state.save_attempts == attempts \
		and state._gem_trade_quotes.size() == issued_quotes and state._gem_trade_sequence == quote_sequence,
		"Reading offers issues no full snapshot, disk stamp, handle or write")
	check(observed(state) == before, "Offer projection changes neither canonical state nor persisted bytes")
	offers[0].cost = 0
	offers[0].definition_id = "forged"
	check(state.normal_gem_offers()[0].cost > 0 and state.normal_gem_offers()[0].definition_id != "forged", "Offer metadata is detached")
	var purchased: Array[String] = []
	var preserved: Dictionary = state.snapshot()
	for definition_id: String in definitions:
		var price := 8 if definitions[definition_id].kind == "skill_gem" else 4
		before = observed(state)
		var revision := state.revision()
		var balance := state.crafting_balance()
		var serial: int = state.snapshot().next_item_serial
		seed(944)
		var expected_random := randi()
		seed(944)
		var quote := _quote(state, "buy", definition_id)
		check(quote.ok and quote.operation == "buy" and quote.target == definition_id and quote.definition_id == definition_id \
			and quote.cost.get("calibration_shard", 0) == price and quote.materials.get("calibration_shard", 0) == 0 \
			and not quote.has("candidate") and not quote.has("snapshot") and observed(state) == before,
			"Buying %s quotes only detached economics without mutation" % definition_id)
		if not quote.ok: continue
		var result: Dictionary = state.execute_gem_trade(quote.handle, definition_id)
		check(result.ok and not purchased.has(result.get("uid", "")) and state.revision() == revision + 1 \
			and state.successful_saves == before.saves + 1 and state.notifications == before.changed + 1 \
			and state.crafting_balance() == balance - price and state.snapshot().next_item_serial == serial + 1,
			"Buying %s commits one UID, debit, revision, save and signal" % definition_id)
		if not result.ok: continue
		var owned: Dictionary = state.item(result.uid)
		check(Gems.validate_instance(owned) and owned.definition_id == definition_id and owned.payload == {"level": 1, "quality": 0} \
			and state.location(result.uid).kind == "bag" and randi() == expected_random,
			"Buying %s creates the fixed real instance without RNG" % definition_id)
		purchased.append(result.uid)
	check(purchased.size() == 26 and state.snapshot().crafting == preserved.crafting \
		and state.snapshot().journey == preserved.journey and state.snapshot().version == preserved.version,
		"All 26 actual purchases leave schema, journey and released crafting seed revision unchanged")
	for uid: String in purchased:
		before = observed(state)
		var revision := state.revision()
		snapshots = state.snapshot_calls
		stamps = state.stamp_calls
		issued_quotes = state._gem_trade_quotes.size()
		quote_sequence = state._gem_trade_sequence
		var info: Dictionary = state.gem_recycle_info(uid)
		check(info.available and info.credit is int and info.credit == 1 and info.uid == uid and info.name is String \
			and not info.has("handle") and not info.has("candidate") and state.snapshot_calls == snapshots and state.stamp_calls == stamps \
			and state._gem_trade_quotes.size() == issued_quotes and state._gem_trade_sequence == quote_sequence,
			"Recycle metadata for %s is lightweight and worth exactly one shard" % uid)
		var balance := state.crafting_balance()
		seed(719)
		var expected_random := randi()
		seed(719)
		var quote := _quote(state, "recycle", uid)
		if not quote.ok:
			check(false, "Purchased gem can be quoted for recycling: " + uid)
			continue
		check(quote.target == uid and quote.cost.get("calibration_shard", 0) == 0 \
			and quote.materials.get("calibration_shard", 0) == 1 and observed(state) == before,
			"Recycling %s quotes one exact credit without reserving or removing the item" % uid)
		var result: Dictionary = state.execute_gem_trade(quote.handle, uid)
		check(result.ok and state.item(uid).is_empty() and state.crafting_balance() == balance + 1 \
			and state.successful_saves == before.saves + 1 and state.notifications == before.changed + 1 \
			and state.revision() == revision + 1 and randi() == expected_random,
			"Recycling %s removes that actual UID for one persisted shard/revision/signal without RNG" % uid)
	var reopened := Model.new()
	check(reopened.load_build(PATH) and reopened.snapshot() == state.snapshot(), "All purchases and recycling round-trip through canonical schema 27")


func _input_and_profile_boundaries() -> void:
	var state := _fixture(20)
	for operation: Variant in [null, 1, true, {}, "sell", "BUY"]:
		_assert_rejected(state, operation, SUPPORT, "Malformed/unknown operation is atomic: " + str(operation))
	for target: Variant in [null, 1, true, [], {}, "efficiency", "support:missing", "currency:calibration_shard"]:
		_assert_rejected(state, "buy", target, "Malformed/unknown purchase ID is atomic: " + str(target))
	for target: Variant in [null, 1, true, [], {}, "not_owned"]:
		_assert_rejected(state, "recycle", target, "Malformed/unknown recycle UID is atomic: " + str(target))
	var before := observed(state)
	for revision: Variant in [null, true, str(state.revision()), float(state.revision()), state.revision() - 1]:
		check(not state.gem_trade_quote("buy", SUPPORT, revision, PATH).ok and observed(state) == before, "Invalid/stale revision is rejected without coercion")
	for path: String in [TEST_PATH, "user://other.json", ProjectSettings.globalize_path(PATH), "user://./build_save.json"]:
		check(not state.gem_trade_quote("buy", SUPPORT, state.revision(), path).ok and observed(state) == before, "Only literal normal request path is accepted: " + path)
	var unopened := Model.new()
	check(not unopened.gem_trade_quote("buy", SUPPORT, unopened.revision(), PATH).ok, "An unopened model cannot claim the normal profile")
	if FileAccess.file_exists(TEST_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var test_model := Model.new()
	check(test_model.save_build(TEST_PATH) == OK and not test_model.gem_trade_quote("buy", SUPPORT, test_model.revision(), PATH).ok,
		"An actually opened test profile cannot trade against the normal path")
	var alias_model := Model.new()
	check(alias_model.load_build(ProjectSettings.globalize_path(PATH)) and not alias_model.gem_trade_quote("buy", SUPPORT, alias_model.revision(), PATH).ok,
		"Opening an equivalent absolute path does not satisfy the literal normal-profile gate")
	var candidate: Dictionary = state.snapshot()
	var recovery := _put(candidate, SUPPORT, {"kind": "recovery", "index": 0})
	_commit_fixture(state, candidate, "Recovery gem fixture is canonical")
	_assert_rejected(state, "recycle", recovery, "Recovery gem cannot be recycled")
	var excluded := 0
	for uid: String in state.snapshot().items:
		var location: Dictionary = state.location(uid)
		if location.kind in ["equipment", "skill_main", "skill_support", "flask"]:
			_assert_rejected(state, "recycle", uid, "Equipped main/support/gear/flask UID cannot be recycled: " + uid)
			excluded += 1
	check(excluded > 0, "Canonical fixture supplies real equipped exclusions")
	_assert_rejected(state, "recycle", _bag_currency(state), "Currency is not a recyclable gem")
	state = _fixture(3)
	_assert_rejected(state, "buy", SUPPORT, "Three bag shards cannot buy a four-shard support")
	candidate = state.snapshot()
	_put(candidate, "", {"kind": "recovery", "index": 0}, 100)
	_commit_fixture(state, candidate, "Recovery-only funds are represented by a real stack")
	_assert_rejected(state, "buy", ACTIVE, "Recovery currency cannot finance a purchase")


func _quote_authority_and_atomicity() -> void:
	var state := _fixture(40)
	var before := observed(state)
	var quote := _quote(state, "buy", SUPPORT)
	check(quote.ok, "Authority tests obtain real quote")
	if not quote.ok: return
	check(not state.execute_gem_trade("forged", SUPPORT).ok and not state.execute_gem_trade(7, SUPPORT).ok \
		and not state.execute_gem_trade(quote.handle, ACTIVE).ok and not state.execute_gem_trade(quote.handle, 7).ok \
		and observed(state) == before, "Forged handles, wrong targets and invalid target types cannot mutate")
	quote = _quote(state, "buy", SUPPORT)
	var handle: String = quote.handle
	quote.cost.calibration_shard = 0
	quote.materials.calibration_shard = 999
	quote.target = ACTIVE
	quote.definition_id = ACTIVE
	var result: Dictionary = state.execute_gem_trade(handle, SUPPORT)
	check(result.ok and state.crafting_balance() == 36 and state.item(result.uid).definition_id == SUPPORT,
		"Mutating returned quote cannot change held price, credit or definition")
	before = observed(state)
	check(not state.execute_gem_trade(handle, SUPPORT).ok and observed(state) == before, "One quote cannot execute twice")
	quote = _quote(state, "buy", SUPPORT)
	state.cancel_gem_trade_quote(quote.handle)
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before, "Cancel revokes only quote authority without mutation")
	quote = _quote(state, "buy", SUPPORT)
	state.invalidate_gem_trade_quotes()
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before, "Explicit invalidation revokes all held quotes")
	quote = _quote(state, "buy", SUPPORT)
	check(state.load_build(PATH), "Reload canonical profile succeeds")
	before = observed(state)
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before, "Loading a model invalidates even an identical quote snapshot")
	quote = _quote(state, "buy", SUPPORT)
	state._current.progress.xp += 1
	before = observed(state)
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before, "Same-revision valid full-build change invalidates quote")
	check(state.load_build(PATH), "Restore canonical snapshot after deliberate same-revision edit")
	quote = _quote(state, "buy", SUPPORT)
	state.add_xp(1)
	before = observed(state)
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before, "Intervening revision invalidates quote atomically")
	check(state.load_build(PATH), "Reload after unsaved progression succeeds")
	quote = _quote(state, "buy", SUPPORT)
	state.fail_writes = true
	before = observed(state)
	var attempts := state.save_attempts
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before and state.save_attempts == attempts + 1,
		"Injected save failure preserves UID, balance, serial, revision, bytes and signal")
	state.fail_writes = false
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before, "Failed-write handle is consumed and cannot execute later")
	quote = _quote(state, "buy", SUPPORT)
	check(quote.ok and state.execute_gem_trade(quote.handle, SUPPORT).ok, "A fresh quote retries failed purchase with exact original economics")
	quote = _quote(state, "buy", SUPPORT)
	state.corrupt_candidate = true
	before = observed(state)
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before, "Commit fully validates an invalid prepared candidate before exposing it")
	state.corrupt_candidate = false
	state.invalidate_gem_trade_quotes()
	quote = _quote(state, "buy", SUPPORT)
	state.reenter = true
	state.reenter_handle = quote.handle
	state.reenter_target = SUPPORT
	before = observed(state)
	result = state.execute_gem_trade(quote.handle, SUPPORT)
	state.reenter = false
	check(result.ok and not state.reentered_quote.get("ok", true) and not state.reentered_execute.get("ok", true) \
		and state.successful_saves == before.saves + 1 and state.notifications == before.changed + 1,
		"Changed-signal reentry cannot issue or execute another transaction during commit")
	quote = _quote(state, "buy", SUPPORT)
	var disk := FileAccess.get_file_as_bytes(PATH)
	var output := FileAccess.open(PATH, FileAccess.WRITE)
	output.store_buffer(disk + " \n".to_utf8_buffer())
	output.close()
	before = observed(state)
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and observed(state) == before,
		"Same JSON with external whitespace changes invalidates exact disk receipt without overwrite")
	_assert_rejected(state, "buy", SUPPORT, "External bytes also prevent issuance of a replacement quote")
	state = _fixture(8)
	quote = _quote(state, "buy", SUPPORT)
	state.retire_profile()
	before = observed(state)
	check(not state.execute_gem_trade(quote.handle, SUPPORT).ok and not _quote(state, "buy", SUPPORT).ok \
		and observed(state) == before, "A retired profile cannot use delayed or new trade callbacks")


func _full_bag_boundaries() -> void:
	var state := _fixture(4, true)
	var currency_uid := _bag_currency(state)
	var freed: Dictionary = state.location(currency_uid)
	var quote := _quote(state, "buy", SUPPORT)
	var support_available := false
	for offer: Dictionary in state.normal_gem_offers():
		if offer.definition_id == SUPPORT: support_available = offer.available
	check(quote.ok and support_available, "Full bag permits metadata and quote when exact payment removes the final currency stack")
	if quote.ok:
		var result: Dictionary = state.execute_gem_trade(quote.handle, SUPPORT)
		check(result.ok and state.item(currency_uid).is_empty() and state.location(result.uid) == freed and state.crafting_balance() == 0,
			"Debit occurs before placement so bought gem reuses the exact last-currency cell")
	state = _fixture(5, true)
	_assert_rejected(state, "buy", SUPPORT, "Affordable purchase fails atomically when payment leaves a stack in every occupied cell")
	for offer: Dictionary in state.normal_gem_offers():
		if offer.definition_id == SUPPORT: check(not offer.available, "Full-bag purchase metadata also reports the occupied-cell failure")
	state = _fixture(2, true)
	var split: Dictionary = state.snapshot()
	var second_stack := _bag_gem(state)
	split.items[second_stack] = Currency.make_instance(second_stack, 2)
	_commit_fixture(state, split, "Two actual bag currency stacks can pay one gem price")
	quote = _quote(state, "buy", SUPPORT)
	check(quote.ok and state.execute_gem_trade(quote.handle, SUPPORT).ok and state.crafting_balance() == 0 \
		and state.item(second_stack).is_empty(), "Purchase debits across real stacks before testing full-bag placement")
	state = _fixture(0, true)
	var selected := _bag_gem(state)
	freed = state.location(selected)
	var before := observed(state)
	quote = _quote(state, "recycle", selected)
	check(quote.ok and observed(state) == before, "Full bag recycling reserves the selected gem's actual cell without mutation")
	if quote.ok:
		var result: Dictionary = state.execute_gem_trade(quote.handle, selected)
		currency_uid = _bag_currency(state)
		check(result.ok and state.item(selected).is_empty() and not currency_uid.is_empty() and state.location(currency_uid) == freed \
			and state.item(currency_uid).payload.quantity == 1 and state.successful_saves == before.saves + 1,
			"Removing selected UID first permits a single shard stack in exactly its released cell")
	state = _fixture(10, true)
	selected = _bag_gem(state)
	var other := ""
	for uid: String in state.snapshot().items:
		if uid != selected and state.item(uid).definition_id == state.item(selected).definition_id and state.location(uid).kind == "bag":
			other = uid
			break
	var twin: Dictionary = state.item(other)
	var twin_location: Dictionary = state.location(other)
	quote = _quote(state, "recycle", selected)
	check(quote.ok and not other.is_empty() and state.execute_gem_trade(quote.handle, selected).ok and state.item(selected).is_empty() \
		and state.item(other) == twin and state.location(other) == twin_location and state.crafting_balance() == 11,
		"Recycling one of duplicate-definition gems preserves the unselected UID and merges exact credit")


func _inventory_and_serial_limits() -> void:
	var state := _fixture(Currency.INVENTORY_LIMIT)
	var candidate: Dictionary = state.snapshot()
	var selected := _put(candidate, SUPPORT, {"kind": "bag", "page": 0, "x": 1, "y": 0})
	_commit_fixture(state, candidate, "Global currency-cap fixture is valid")
	_assert_rejected(state, "recycle", selected, "Recycling cannot exceed global shard inventory cap")
	state = _fixture()
	candidate = state.snapshot()
	selected = _put(candidate, SUPPORT, {"kind": "bag", "page": 0, "x": 0, "y": 0})
	_put(candidate, "", {"kind": "recovery", "index": 0}, Currency.INVENTORY_LIMIT)
	_commit_fixture(state, candidate, "Recovery currency contributes to the global cap")
	_assert_rejected(state, "recycle", selected, "Recycle credit cannot exceed the cap even when all existing shards are in recovery")
	state = _fixture(10)
	candidate = state.snapshot()
	var recovery_index := 0
	while candidate.items.size() < Rules.MAX_ITEMS:
		_put(candidate, SUPPORT, {"kind": "recovery", "index": recovery_index})
		recovery_index += 1
	_commit_fixture(state, candidate, "Registry-limit fixture is valid without thousands of per-item assertions")
	_assert_rejected(state, "buy", SUPPORT, "Registry-cap purchase cannot allocate another UID")
	state = _fixture(10)
	candidate = state.snapshot()
	candidate.next_item_serial = Rules.MAX_SERIAL
	_commit_fixture(state, candidate, "Terminal next-item serial remains a valid readable profile")
	_assert_rejected(state, "buy", SUPPORT, "Purchase cannot overflow item serial")
	state = _fixture()
	candidate = state.snapshot()
	selected = _put(candidate, SUPPORT, {"kind": "bag", "page": 0, "x": 0, "y": 0})
	candidate.next_item_serial = Rules.MAX_SERIAL
	_commit_fixture(state, candidate, "Recycle-without-stack terminal serial fixture is valid")
	_assert_rejected(state, "recycle", selected, "Recycle cannot allocate a new shard stack past the serial limit")
	state = _fixture(1)
	candidate = state.snapshot()
	selected = _put(candidate, SUPPORT, {"kind": "bag", "page": 0, "x": 1, "y": 0})
	candidate.next_item_serial = Rules.MAX_SERIAL
	_commit_fixture(state, candidate, "Recycle-with-existing-stack terminal serial fixture is valid")
	var quote := _quote(state, "recycle", selected)
	check(quote.ok and state.execute_gem_trade(quote.handle, selected).ok and state.crafting_balance() == 2 \
		and state.snapshot().next_item_serial == Rules.MAX_SERIAL, "Recycle can merge its credit without allocating at the terminal serial")
	state = _fixture(10)
	candidate = state.snapshot()
	candidate.revision = Rules.MAX_SERIAL - 1
	_commit_fixture(state, candidate, "Terminal build revision remains a valid readable profile")
	_assert_rejected(state, "buy", SUPPORT, "Purchase cannot overflow build revision")
	state = _fixture(10)
	var uid := _bag_currency(state)
	state._current.next_item_serial = int(uid.trim_prefix("item_"))
	_assert_rejected(state, "buy", SUPPORT, "Duplicate allocator UID in invalid current state cannot overwrite owned instance")
	state = _fixture(10)
	uid = _bag_currency(state)
	state._current.items[uid].payload.quantity = 10.0
	_assert_rejected(state, "buy", SUPPORT, "Float currency payload is rejected by full current-state validation")
	state = _fixture(10)
	state._current.progress.xp = -1
	_assert_rejected(state, "buy", SUPPORT, "Unrelated corrupt progression is rejected by full current-state validation")
	state = _fixture(10)
	candidate = state.snapshot()
	selected = _put(candidate, SUPPORT, {"kind": "bag", "page": 0, "x": 1, "y": 0})
	_commit_fixture(state, candidate, "Typed real gem fixture is valid before deliberate corruption")
	state._current.items[selected].payload.level = 1.0
	_assert_rejected(state, "recycle", selected, "Recycle rejects a numerically equal float in the fixed integer gem envelope")
