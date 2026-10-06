extends SceneTree
## Strict native46→47, old gear preservation, exact backups and existing gem economy.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/frost_lock_gem_migration.gd")
const Prior = preload("res://scripts/save/glove_ring_affix_migration.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const GemTrade = preload("res://scripts/items/gem_trade_rules.gd")
const TownCatalog = preload("res://scripts/town/town_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const FIXTURES := "res://docs/qa/v072-gameplay/fixtures/"
var checks := 0
var failures := 0
var evidence := {}
var completed := false

class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error: return ERR_CANT_CREATE

class ExternalIO extends Store.Legacy:
	func _backup_legacy_save(path: String) -> Error:
		var result := super._backup_legacy_save(path)
		if result == OK:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string("external writer")
			file.close()
		return result


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 47
	return result


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v073-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	call_deferred("_run")


func _run() -> void:
	check(Rules.VERSION == 47 and Rules.V46_VERSION == 46 and Source.CURRENT_SAVE_VERSION == 45 and Equipment.CURRENT_VOCABULARY == 46, "Gem-only schema47 keeps source45 and equipment46")
	for version: int in [45, 46, 47]: check(Source._execution_policy(version) == 45, "Source policy stays45")
	check(Rules.equipment_vocabulary_for_save_version(46) == 46 and Rules.equipment_vocabulary_for_save_version(47) == 46, "Equipment mapping stays46")
	var source := {}
	var bytes := PackedByteArray()
	for label: String in ["glove-finesse", "rings-triple-default", "rings-source-cap83", "precise-above", "precise-equal"]:
		bytes = FileAccess.get_file_as_bytes(FIXTURES + label + ".json")
		source = Rules.decode_v46(JSON.parse_string(bytes.get_string_from_utf8()))
		if not check(not source.is_empty() and Rules.reason_v46(source).is_empty(), "Released native46 validates before migration: " + label):
			quit(1)
			return
		completed = false
		migrate_case(source, bytes, label)
		check(completed, "Native fixture case completes: " + label)
	for entry: Array in [[strict_checks, "strict envelope"], [chain_checks, "constructor and old45 chain"], [current_checks, "current47 envelopes"], [economy_checks, "existing economy"]]:
		completed = false
		entry[0].call(source)
		check(completed, "Case completes without script errors: " + entry[1])
	completed = false
	failure_checks(source, bytes)
	check(completed, "Atomic failure cases complete")
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V073_MIGRATION_REPORT")
	if not output.is_empty(): write(output, (JSON.stringify(evidence, "\t", true, true) + "\n").to_utf8_buffer())
	print("Frost Lock migration/economy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func migrate_case(source: Dictionary, bytes: PackedByteArray, label: String) -> void:
	var before := var_to_bytes(source)
	var expected := current(source)
	seed(734647)
	var next_rng := randi()
	seed(734647)
	var result := Migration.migrate_v46(source)
	check(randi() == next_rng and result == expected and var_to_bytes(source) == before, "Only version changes; source and RNG untouched: " + label)
	for field: String in Rules.FIELDS:
		if field != "version": check(result[field] == source[field], "Preserved field: " + label + "/" + field)
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + label + "-expected.json"))
	check(Game._stats_for(result) == Game._stats_for(source) and JSON.parse_string(JSON.stringify(Game._stats_for(result), "\t", true, true)) == oracle.stats, "Native46 stat oracle unchanged: " + label)
	for uid: String in source.items:
		if source.items[uid].kind == "equipment" and not source.items[uid].payload.is_empty():
			check(result.items[uid] == source.items[uid] and Equipment.validate_instance_for_version(result.items[uid].payload, 46), "All native46 equipment rolls survive")
	var path := "user://native46-" + label + ".json"
	write(path, bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	if not check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "One atomic migration and event: " + label): return
	check(FileAccess.get_file_as_bytes(path + ".v46-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Backup contains exact original bytes")
	check(game.migrated_from_legacy and game.migration_message.contains("霜锁辅助") and game.migration_message.contains("寒意延长辅助") and game.migration_message.contains("不额外赠物或赠点"), "Latest migration feedback describes support and no gifts")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk and not game.migrated_from_legacy and game.migration_message.is_empty(), "Repeated47 load does not rewrite or repeat migration message")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v46-backup.json") == bytes, "Independent47 reopen preserves original backup")
	evidence[label] = {"source_sha256":digest(bytes), "source_bytes":bytes.size(), "items":source.items.size(), "source_version":46}
	completed = true


func with_gem(source: Dictionary, placement: String) -> Dictionary:
	var value := source.duplicate(true)
	var uid := "item_%06d" % int(value.next_item_serial)
	value.next_item_serial += 1
	value.items[uid] = Gems.create_instance(uid, "support:frost_lock")
	var index := 0
	for location: Dictionary in value.locations.values():
		if location.kind == "recovery": index += 1
	value.locations[uid] = {"kind":"skill_support", "group_id":"group_000002", "index":0} if placement == "skill_support" else {"kind":"recovery", "index":index}
	return value


func reject_bytes(value: Dictionary, label: String) -> void:
	var path := "user://reject-" + label + ".json"
	var bytes := JSON.stringify(value).to_utf8_buffer()
	write(path, bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source preserves memory and disk: " + label)
	check(store.save_attempts == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v46-backup.json"), "Rejection precedes backup/write/notification")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected path remains protected")


func strict_checks(source: Dictionary) -> void:
	var calls := [0]
	var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	for placement: String in ["recovery", "skill_support"]:
		var injected := with_gem(source, placement)
		check(Rules.reason(current(injected)).is_empty(), "Current47 allows fixed Frost Lock gem: " + placement)
		Store.Items.metadata_for_items(injected.items)
		calls[0] = 0
		check(not Rules.reason_v46(injected, permissive).is_empty() and Rules.decode_v46(injected).is_empty() and Migration.migrate_v46(injected, permissive).is_empty() and calls[0] == 0, "Warm metadata and callback cannot smuggle new gem into46")
		reject_bytes(injected, "new-gem-" + placement)
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "unknown_node", "over_budget", "wrong_source", "missing_location", "bad_binding", "bad_ledger", "runtime_policy"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.extra = true
			"missing_journey": bad.erase("journey")
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"over_budget": bad.talents.normal_points += 1
			"wrong_source": bad.talents.source_version = "3.29.2"
			"missing_location": bad.locations.erase(bad.locations.keys()[0])
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.normal_budget_at_migration += 1
			"runtime_policy": bad.freeze_policy = {}
		calls[0] = 0
		check(not Rules.reason_v46(bad, permissive).is_empty() and Rules.decode_v46(bad).is_empty() and Migration.migrate_v46(bad, permissive).is_empty() and calls[0] == 0, "Complete native legality precedes callbacks: " + mutation)
		reject_bytes(bad, mutation)
	check(Migration.migrate_v46(current(source)).is_empty() and Rules.decode(source).is_empty() and Rules.decode_v46(current(source)).is_empty(), "Exact decoder and migration version gates")
	var reject := func(_value: Dictionary) -> String: return "extra restriction"
	check(Migration.migrate_v46(source, reject).is_empty(), "Optional callback can add restrictions")
	completed = true


func chain_checks(_source: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v070-gameplay/fixtures/selected-above.json")
	var old45 := Rules.decode_v45(JSON.parse_string(bytes.get_string_from_utf8()))
	if not check(not old45.is_empty(), "Released native45 fixture found"): return
	var source46 := Prior.migrate_v45(old45)
	var expected46 := old45.duplicate(true)
	expected46.version = 46
	check(source46 == expected46 and Rules.reason_v46(source46).is_empty(), "Prior glove/ring migration stays fixed at46")
	check(Migration.migrate_v46(source46) == current(old45), "45→46→47 changes only version")
	var path := "user://native45-chain.json"
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == current(old45) and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v45-backup.json") == bytes and not FileAccess.file_exists(path + ".v46-backup.json"), "Old45 loader chain writes once with original45 backup only")
	var fresh := Store.new().snapshot()
	check(fresh.version == 47 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0 and fresh.items.values().filter(func(item: Dictionary) -> bool: return item.definition_id == "support:frost_lock").is_empty(), "Complete default chain reaches47 without Frost Lock or currency gifts")
	completed = true


func current_checks(source: Dictionary) -> void:
	for placement: String in ["recovery", "skill_support"]:
		var value := current(with_gem(source, placement))
		var uid := "item_%06d" % (int(value.next_item_serial) - 1)
		var path := "user://current47-" + placement + ".json"
		var store := Store.new()
		store._accept_memory(value)
		check(Rules.decode(JSON.parse_string(JSON.stringify(value))) == value and store.save_build(path) == OK, "Current47 fixed gem serializes")
		var reopened := Store.new()
		check(reopened.load_build(path) and reopened.snapshot() == value and reopened.save_attempts == 0 and reopened.item(uid).payload == {"level":1,"quality":0}, "Current47 gem and location round trip without migration")
		for field: String in ["freeze_policy", "freeze_profile", "freeze_remaining", "freeze_immunity_remaining"]:
			var bad := value.duplicate(true)
			bad.items[uid].payload[field] = 1
			check(not Rules.reason(bad).is_empty() and Rules.decode(bad).is_empty(), "Runtime freeze fields cannot enter persistent payload")
	completed = true


func economy_checks(source: Dictionary) -> void:
	var old_oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v067-migration/fixtures/v42-oracle.json"))
	check(Journey.GEM_DEFINITIONS == old_oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26 and not Journey.GEM_DEFINITIONS.has("support:frost_lock"), "Frozen26 normal reward catalog unchanged")
	for index: int in old_oracle.gem_milestones.size(): check(Journey.gem_definition(index + 1) == old_oracle.gem_milestones[index], "Normal reward ordinal unchanged")
	check(Gems.minimum_save_version("support:frost_lock") == 47 and Gems.definitions().has("support:frost_lock"), "New gem exposed only at47")
	var offers := GemTrade.offers().filter(func(offer: Dictionary) -> bool: return offer.definition_id == "support:frost_lock")
	check(offers.size() == 1 and offers[0].cost == 4 and GemTrade.quote("buy", "support:frost_lock").cost == {"calibration_shard":4}, "One dynamic four-fragment formal offer")
	var path := "user://build_save.json"
	var game := Game.new()
	game._accept_memory(current(source))
	if not check(game.save_build(path) == OK, "Initialize isolated formal profile"): return
	for uid: String in game.pending_items():
		if not check(game.move_item(uid, game.first_bag_position(uid), game.revision(), path).ok, "Place existing pending item before trade"): return
	var funded := game.snapshot()
	if not check(game._set_bag_currency_balance(funded, 12).ok, "Prepare narrow existing currency fixture"): return
	game._accept_memory(funded)
	if not check(game.save_build(path) == OK, "Persist funded fixture"): return
	var before := game.snapshot()
	var quote := game.gem_trade_quote("buy", "support:frost_lock", game.revision(), path)
	if not check(quote.ok and quote.cost == {"calibration_shard":4} and game.snapshot() == before, "Quote is mutation free"): return
	var purchase := game.execute_gem_trade(quote.handle, "support:frost_lock")
	if not check(purchase.ok and game.crafting_balance() == 8 and game.item(purchase.uid).definition_id == "support:frost_lock", "Formal purchase costs exactly four fragments"): return
	var bought := game.snapshot()
	check(not game.execute_gem_trade(quote.handle, "support:frost_lock").ok and game.snapshot() == bought, "Trade handle cannot charge twice")
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == bought, "Purchased Frost Lock survives reload")
	var formal_bytes := FileAccess.get_file_as_bytes(path)
	check(not game.town_claim_offer("support:frost_lock", game.revision(), path).ok and game.snapshot() == bought and FileAccess.get_file_as_bytes(path) == formal_bytes, "Test-only free supply cannot touch formal profile")
	var test_offers := TownCatalog.offers("skill_merchant").filter(func(offer: Dictionary) -> bool: return offer.id == "support:frost_lock")
	check(test_offers.size() == 1 and TownCatalog.offer("support:frost_lock").id == "support:frost_lock", "Existing test merchant discovers dynamic new gem")
	var test_game := Game.new()
	test_game._accept_memory(bought)
	var test_path := "user://town_test_build_save.json"
	if not check(test_game.save_build(test_path) == OK, "Initialize test-only profile"): return
	var old_revision := test_game.revision()
	var supplied := test_game.town_claim_offer("support:frost_lock", old_revision, test_path)
	if not check(supplied.ok and test_game.item(supplied.uid).definition_id == "support:frost_lock" and test_game.crafting_balance() == 8, "Test merchant supplies fixed gem at zero cost"): return
	check(not test_game.town_claim_offer("support:frost_lock", old_revision, test_path).ok, "Stale test supply cannot duplicate grant")
	var ids: Array = Gems.definitions().keys()
	ids.sort()
	var selected_seed := -1
	for candidate_seed: int in range(4096):
		var random := RandomNumberGenerator.new()
		random.seed = candidate_seed
		if ids[random.randi_range(0, ids.size() - 1)] == "support:frost_lock": selected_seed = candidate_seed; break
	if not check(selected_seed >= 0, "Find seed selecting new gem through existing random catalog"): return
	var random := RandomNumberGenerator.new()
	random.seed = selected_seed
	var awarded := test_game.award_random_gem(random)
	check(not awarded.is_empty() and test_game.item(awarded).definition_id == "support:frost_lock", "Existing test random reward uses dynamic catalog")
	var owed := game.snapshot()
	owed.journey.normal_root_kills = 30
	game._accept_memory(owed)
	if not check(game.save_build(path) == OK, "Persist first existing normal milestone"): return
	var old_uids: Array = game.snapshot().items.keys()
	var reward := game.normal_claim_rewards(game.revision(), path, false)
	if not check(reward.ok, "Existing formal reward transaction succeeds"): return
	var new_items: Array = game.snapshot().items.values().filter(func(item: Dictionary) -> bool: return not old_uids.has(item.uid))
	check(reward.claimed_gems == 1 and new_items.size() == 1 and new_items[0].definition_id == old_oracle.gem_milestones[0], "Actual first normal reward keeps frozen ordinal")
	evidence.shop_cost = 4
	evidence.test_reward_seed = selected_seed
	evidence.actual_normal_reward = new_items[0].definition_id if not new_items.is_empty() else ""
	completed = true


func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path, bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "collision": write(path + ".v46-backup.json", "retained backup".to_utf8_buffer())
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject real atomic-write failure")
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration never publishes memory: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Original or external-writer bytes preserved")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup and concurrency checks precede write")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v46-backup.json") == "retained backup", "Conflicting backup preserved")
		if failure in ["external", "atomic"]: check(FileAccess.get_file_as_bytes(path + ".v46-backup.json") == bytes, "Failed commit retains exact original backup")
		if failure == "atomic": check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and events[0] == 1, "Fault removal permits one successful atomic retry")
		else: check(store.save_build(path) != OK, "Failed path protected from overwrite")
	completed = true
