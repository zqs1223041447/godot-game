extends SceneTree
## Schema51→52 only: frozen identities, exact byte backups and existing gem economy.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/encircling_cleave_gem_migration.gd")
const Prior = preload("res://scripts/save/chaos_resistance_affix_migration.gd")
const FourthMap = preload("res://scripts/save/fourth_map_migration.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const GemTrade = preload("res://scripts/items/gem_trade_rules.gd")
const TownCatalog = preload("res://scripts/town/town_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const SOURCE_PATH := "res://docs/qa/v093-integration/equipped-fixture.json"
const GEM_ID := "support:encircling_cleave"
var checks := 0
var failures := 0
var evidence := {}
var completed := false

class FaultGame extends Game:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)

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
	result.version = 52
	return result


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func consumers(source: Dictionary) -> Dictionary:
	var game := Game.new()
	game._accept_memory(source)
	var casts := {}
	for group: Dictionary in source.skill_groups: casts[group.id] = game.get_group_cast(group.id)
	return {"stats":game.get_stats(), "snapshot":game.get_combat_snapshot(), "basic":game.get_basic_cast(),
		"casts":casts, "equipped":game.equipped_items(), "pending":game.pending_items(), "wallet":Store.Currency.total_quantity(source.items)}


func migrate_case(source: Dictionary, bytes: PackedByteArray, label: String) -> void:
	var before := var_to_bytes(source)
	var expected := current(source)
	seed(945152)
	var next_rng := randi()
	seed(945152)
	var result := Migration.migrate_v51(source)
	check(result == expected and var_to_bytes(source) == before and randi() == next_rng, "Only version changes; source and RNG untouched: " + label)
	for field: String in Rules.FIELDS:
		if field != "version": check(result[field] == source[field], "Every nonversion field preserved: " + field)
	check(consumers(result) == consumers(source), "Old stats, casts, gear, wallet, point budgets and recovery unchanged")
	for item: Dictionary in source.items.values():
		if item.kind == "equipment" and not item.payload.is_empty():
			check(Equipment.validate_instance_for_version(item.payload, 51) and not Equipment.validate_instance_for_version(item.payload, 52) and not Equipment.validate_instance(item.payload, 52), "Gem-only52 maps equipment to51; explicit equipment52 stays rejected")
	var path := "user://native51-" + label + ".json"
	write(path, bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	if not check(game.load_build(path) and game.snapshot() == expected, "Actual loader migrates51→52: " + label): return
	check(game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "One atomic write and notification")
	check(FileAccess.get_file_as_bytes(path + ".v51-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Original exact bytes backed up before commit")
	check(game.migrated_from_legacy and game.migration_message.contains("环斩辅助") and game.migration_message.contains("裂刃斩") and game.migration_message.contains("不额外赠物或赠点"), "Narrow migration feedback is accurate")
	var saved := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == saved and not game.migrated_from_legacy and game.migration_message.is_empty(), "Repeated52 load neither rewrites nor repeats migration notice")
	var reopened := Store.new()
	check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v51-backup.json") == bytes, "Independent52 reopen keeps exact51 backup")
	evidence[label] = {"source_path":SOURCE_PATH, "sha256":digest(bytes), "bytes":bytes.size(), "items":source.items.size(), "revision":source.revision}
	completed = true


func with_gem(source: Dictionary, placement: String) -> Dictionary:
	var value := source.duplicate(true)
	if placement == "skill_support":
		# Explicit test fixture: existing cleave in otherwise empty ninth row.
		var skill_uid := "item_%06d" % int(value.next_item_serial)
		value.next_item_serial += 1
		value.items[skill_uid] = Gems.create_instance(skill_uid, "skill:cleave")
		value.locations[skill_uid] = {"kind":"skill_main", "group_id":"group_000009"}
	var uid := "item_%06d" % int(value.next_item_serial)
	value.next_item_serial += 1
	value.items[uid] = Gems.create_instance(uid, GEM_ID)
	var index := 0
	for location: Dictionary in value.locations.values():
		if location.kind == "recovery": index += 1
	value.locations[uid] = {"kind":"skill_support", "group_id":"group_000009", "index":0} if placement == "skill_support" else {"kind":"recovery", "index":index}
	return value


func reject_bytes(bytes: PackedByteArray, label: String, version: int = 51) -> void:
	var path := "user://reject-" + label + ".json"
	write(path, bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Invalid source preserves memory and bytes: " + label)
	check(store.save_attempts == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v%d-backup.json" % version) and not FileAccess.file_exists(path + ".tmp"), "Invalid source rejected before backup/write/event")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected destination stays protected")


func strict_checks(source: Dictionary) -> void:
	var calls := [0]
	var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	for placement: String in ["recovery", "skill_support"]:
		var injected := with_gem(source, placement)
		check(Rules.reason(current(injected)).is_empty(), "Current52 accepts fixed new gem: " + placement)
		Store.Items.metadata_for_items(injected.items)
		calls[0] = 0
		check(not Rules.reason_v51(injected, permissive).is_empty() and Rules.decode_v51(injected).is_empty() and Migration.migrate_v51(injected, permissive).is_empty() and calls[0] == 0, "Warm cache and permissive callback cannot admit new gem or link into51")
		reject_bytes(JSON.stringify(injected).to_utf8_buffer(), "new-gem-" + placement)
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "bad_journey", "unknown_node", "over_budget", "wrong_source", "missing_location", "bad_binding", "bad_ledger", "runtime_policy", "bad_currency", "unknown_gem"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.extra = true
			"missing_journey": bad.erase("journey")
			"bad_journey": bad.journey.best_tiers.unknown_map = 1
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"over_budget": bad.talents.normal_points += 1
			"wrong_source": bad.talents.source_version = "3.29.2"
			"missing_location": bad.locations.erase(bad.locations.keys()[0])
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.normal_budget_at_migration += 1
			"runtime_policy": bad.encircling_cleave_profile = {}
			"bad_currency":
				for item: Dictionary in bad.items.values():
					if item.kind == "currency": item.payload.quantity = -1; break
			"unknown_gem":
				for item: Dictionary in bad.items.values():
					if item.kind == "skill_gem": item.definition_id = "skill:unknown"; break
		calls[0] = 0
		check(not Rules.reason_v51(bad, permissive).is_empty() and Rules.decode_v51(bad).is_empty() and Migration.migrate_v51(bad, permissive).is_empty() and calls[0] == 0, "All native legality precedes callbacks: " + mutation)
		reject_bytes(JSON.stringify(bad).to_utf8_buffer(), mutation)
	reject_bytes("{\"version\":51,\"broken\":".to_utf8_buffer(), "broken-json")
	check(Migration.migrate_v51(current(source)).is_empty() and Rules.decode(source).is_empty() and Rules.decode_v51(current(source)).is_empty(), "Decoder/migration versions are exact")
	check(Migration.migrate_v51(source, func(_value: Dictionary) -> String: return "extra restriction").is_empty(), "Optional callback adds restrictions")
	completed = true


func current_checks(source: Dictionary) -> void:
	for placement: String in ["recovery", "skill_support"]:
		var value := current(with_gem(source, placement))
		var uid := "item_%06d" % (int(value.next_item_serial) - 1)
		var path := "user://current52-" + placement + ".json"
		var store := Store.new()
		store._accept_memory(value)
		check(Rules.decode(JSON.parse_string(JSON.stringify(value))) == value and store.save_build(path) == OK, "Current52 gem serializes with complete envelope")
		var reopened := Store.new()
		check(reopened.load_build(path) and reopened.snapshot() == value and reopened.save_attempts == 0 and reopened.item(uid).payload == {"level":1,"quality":0}, "Fixed gem and its ownership/link roundtrip without rewrite")
		for field: String in ["encircling_cleave_profile", "hit_angle_degrees", "damage_multiplier", "mana_multiplier"]:
			var bad := value.duplicate(true)
			bad.items[uid].payload[field] = 1
			check(not Rules.reason(bad).is_empty() and Rules.decode(bad).is_empty(), "Runtime support fields never enter saved payload: " + field)
	completed = true


func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path, bytes)
		var game := FaultGame.new()
		var before := game.snapshot()
		var events := [0]
		game.changed.connect(func(): events[0] += 1)
		if failure == "backup": game._io = BackupFailIO.new()
		if failure == "collision": write(path + ".v51-backup.json", "retained backup".to_utf8_buffer())
		if failure == "external": game._io = ExternalIO.new()
		if failure == "atomic": game.fail_save = true
		check(not game.load_build(path) and game.snapshot() == before and game.successful_saves == 0 and events[0] == 0, "Failed migration never publishes memory: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Original or concurrent-writer bytes preserved")
		check(game.save_attempts == (1 if failure == "atomic" else 0), "Backup/concurrency guards precede write")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v51-backup.json") == "retained backup", "Conflicting backup preserved")
		if failure in ["external", "atomic"]: check(FileAccess.get_file_as_bytes(path + ".v51-backup.json") == bytes, "Failed commit keeps exact source backup")
		if failure == "atomic":
			game.fail_save = false
			check(game.load_build(path) and game.snapshot() == current(source) and events[0] == 1, "Safe retry reuses exact backup and commits once")
		else: check(game.save_build(path) != OK, "Failed migration path remains protected")
	completed = true


func chain_checks(_source: Dictionary) -> void:
	for label: String in ["old_garden-pending", "sunwell_terrace-active"]:
		var fixture_path := "res://docs/qa/v083-save/fixtures/v49-" + label + ".json"
		var bytes := FileAccess.get_file_as_bytes(fixture_path)
		var old49 := Rules.decode_v49(JSON.parse_string(bytes.get_string_from_utf8()))
		if not check(not old49.is_empty(), "Released49 active/pending fixture validates: " + label): return
		var source50 := FourthMap.migrate_v49(old49)
		if not check(not source50.is_empty() and source50.version == 50 and Rules.reason_v50(source50).is_empty(), "FourthMap remains fixed49→50"): return
		var source51 := Prior.migrate_v50(source50)
		var expected51 := source50.duplicate(true)
		expected51.version = 51
		check(source51 == expected51 and Rules.reason_v51(source51).is_empty(), "Chaos affix migration remains fixed50→51")
		var expected := current(source50)
		check(Migration.migrate_v51(source51) == expected and expected.journey.active_run == old49.journey.active_run and expected.journey.pending_map_reward == old49.journey.pending_map_reward, "49→50→51→52 preserves ongoing run and claim identity")
		var path := "user://chain49-" + label + ".json"
		write(path, bytes)
		var store := Store.new()
		check(store.load_build(path) and store.snapshot() == expected and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v49-backup.json") == bytes and not FileAccess.file_exists(path + ".v50-backup.json") and not FileAccess.file_exists(path + ".v51-backup.json"), "49 loader chain commits once with original49 backup only")
		var injected := with_gem(old49, "recovery")
		check(Rules.decode_v49(injected).is_empty() and FourthMap.migrate_v49(injected).is_empty(), "Schema49 cannot pre-admit52 gem")
		injected = with_gem(source50, "recovery")
		check(Rules.decode_v50(injected).is_empty() and Prior.migrate_v50(injected).is_empty(), "Schema50 cannot pre-admit52 gem")
		evidence["chain49-" + label] = {"source_path":fixture_path, "sha256":digest(bytes), "bytes":bytes.size()}
	var fresh := Store.new().snapshot()
	check(fresh.version == 52 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0 and fresh.items.values().filter(func(item: Dictionary) -> bool: return item.definition_id == GEM_ID).is_empty(), "Complete built-in chain reaches52 without new gem or currency gifts")
	completed = true


func journey_checks(_source: Dictionary) -> void:
	var old50 := Rules.decode_v50(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v091-root-ui/main-after-reforge.json")))
	if not check(not old50.is_empty(), "Released50 is still accepted"): return
	old50.journey.best_tiers.ginkgo_arcade = 1
	var compiled := Journey.Maps.compile_normal("ginkgo_arcade", 2, [], ["chaos_patrol"])
	if not check(compiled.ok, "Controlled chaos patrol profile compiles"): return
	var started := Journey.start(old50.journey, compiled.profile)
	if not check(started.ok, "Controlled chaos patrol active run starts"): return
	old50.journey = started.journey
	check(Journey.reason(old50.journey).is_empty() and Rules.reason_v50(old50) == "此存档版本不能包含新增地图特殊词缀" and Rules.decode_v50(old50).is_empty() and Prior.migrate_v50(old50).is_empty(), "Old≤50 chaos patrol vocabulary gate survives new gem schema")
	reject_bytes(JSON.stringify(old50).to_utf8_buffer(), "old50-chaos-patrol", 50)
	var old51 := old50.duplicate(true)
	old51.version = 51
	check(Rules.reason_v51(old51).is_empty() and Rules.decode_v51(old51) == old51 and Migration.migrate_v51(old51) == current(old51), "Frozen51 keeps its legitimate chaos patrol encounter")
	completed = true


func economy_checks(source: Dictionary) -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v067-migration/fixtures/v42-oracle.json"))
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26 and not Journey.GEM_DEFINITIONS.has(GEM_ID), "Frozen26 normal reward table is unchanged")
	for index: int in oracle.gem_milestones.size(): check(Journey.gem_definition(index + 1) == oracle.gem_milestones[index], "Every normal reward ordinal is unchanged")
	var metadata := Gems.definition(GEM_ID)
	check(Gems.minimum_save_version(GEM_ID) == 52 and Gems.definitions().has(GEM_ID) and metadata.name == "环斩辅助" and metadata.skills == ["cleave"] and metadata.icon == "res://assets/ui/grimoire/encircling_cleave.png" and metadata.icon_texture != null, "Dynamic gem metadata carries stable identity, exact support scope and real art")
	var offers := GemTrade.offers().filter(func(offer: Dictionary) -> bool: return offer.definition_id == GEM_ID)
	check(offers.size() == 1 and offers[0].cost == 4 and GemTrade.quote("buy", GEM_ID).cost == {"calibration_shard":4}, "One dynamic four-fragment formal offer")
	var path := "user://build_save.json"
	var game := FaultGame.new()
	game._accept_memory(current(source))
	var funded := game.snapshot()
	if not check(game._set_bag_currency_balance(funded, 12).ok, "Controlled existing-currency fixture is funded"): return
	game._accept_memory(funded)
	if not check(game.save_build(path) == OK, "Persist isolated formal fixture"): return
	var before := game.snapshot()
	var disk := FileAccess.get_file_as_bytes(path)
	var quote := game.gem_trade_quote("buy", GEM_ID, game.revision(), path)
	if not check(quote.ok and quote.cost == {"calibration_shard":4} and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == disk, "Formal quote is mutation free"): return
	game.cancel_gem_trade_quote(quote.handle)
	check(not game.execute_gem_trade(quote.handle, GEM_ID).ok and game.snapshot() == before, "Cancel spends nothing and issues no gem")
	quote = game.gem_trade_quote("buy", GEM_ID, game.revision(), path)
	if not check(quote.ok, "Fresh quote issued after cancellation"): return
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	game.fail_save = true
	check(not game.execute_gem_trade(quote.handle, GEM_ID).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(path) == disk and events[0] == 0, "Failed purchase preserves currency, items, revisions, bytes and events")
	game.fail_save = false
	check(not game.execute_gem_trade(quote.handle, GEM_ID).ok and game.snapshot() == before, "Failed confirmation consumes its single-use handle without charging")
	quote = game.gem_trade_quote("buy", GEM_ID, game.revision(), path)
	if not check(quote.ok and quote.cost == {"calibration_shard":4}, "Fresh quote allows retry after failed persistence"): return
	var purchase := game.execute_gem_trade(quote.handle, GEM_ID)
	if not check(purchase.ok and game.crafting_balance() == 8 and game.item(purchase.uid).definition_id == GEM_ID and game.item(purchase.uid).payload == {"level":1,"quality":0} and events[0] == 1, "Fresh quote commits atomically for exactly four fragments"): return
	var bought := game.snapshot()
	check(not game.execute_gem_trade(quote.handle, GEM_ID).ok and game.snapshot() == bought, "Repeated confirmation cannot spend twice")
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == bought, "Purchased gem survives canonical52 reload")
	var formal_bytes := FileAccess.get_file_as_bytes(path)
	check(not game.town_claim_offer(GEM_ID, game.revision(), path).ok and game.snapshot() == bought and FileAccess.get_file_as_bytes(path) == formal_bytes, "Test-only supply cannot gift a formal profile")
	var test_offers := TownCatalog.offers("skill_merchant").filter(func(offer: Dictionary) -> bool: return offer.id == GEM_ID)
	check(test_offers.size() == 1 and test_offers[0].available and TownCatalog.offer(GEM_ID).id == GEM_ID, "Test merchant discovers new gem through dynamic catalog")
	var test_game := Game.new()
	test_game._accept_memory(bought)
	var test_path := "user://town_test_build_save.json"
	if not check(test_game.save_build(test_path) == OK, "Initialize isolated test-only profile"): return
	var old_revision := test_game.revision()
	var supplied := test_game.town_claim_offer(GEM_ID, old_revision, test_path)
	check(supplied.ok and test_game.item(supplied.uid).definition_id == GEM_ID and test_game.crafting_balance() == 8, "Existing test merchant supplies fixed new gem")
	check(not test_game.town_claim_offer(GEM_ID, old_revision, test_path).ok, "Stale test supply cannot duplicate grant")
	var ids: Array = Gems.definitions().keys()
	ids.sort()
	var selected_seed := -1
	for candidate_seed: int in range(4096):
		var random := RandomNumberGenerator.new()
		random.seed = candidate_seed
		if ids[random.randi_range(0, ids.size() - 1)] == GEM_ID: selected_seed = candidate_seed; break
	if not check(selected_seed >= 0, "Find seed selecting gem through test random catalog"): return
	var random := RandomNumberGenerator.new()
	random.seed = selected_seed
	var awarded := test_game.award_random_gem(random)
	check(not awarded.is_empty() and test_game.item(awarded).definition_id == GEM_ID, "Existing test random reward uses dynamic catalog")
	var owed := game.snapshot()
	owed.journey.normal_root_kills = 30
	game._accept_memory(owed)
	if not check(game.save_build(path) == OK, "Persist existing first normal milestone"): return
	var old_uids: Array = game.snapshot().items.keys()
	var reward := game.normal_claim_rewards(game.revision(), path, false)
	if not check(reward.ok, "Existing formal milestone transaction succeeds"): return
	var awarded_items: Array = game.snapshot().items.values().filter(func(item: Dictionary) -> bool: return not old_uids.has(item.uid))
	check(reward.claimed_gems == 1 and awarded_items.size() == 1 and awarded_items[0].definition_id == oracle.gem_milestones[0], "Actual normal reward preserves old first gem ordinal")
	evidence.shop_cost = 4
	evidence.test_reward_seed = selected_seed
	evidence.actual_normal_reward = awarded_items[0].definition_id if not awarded_items.is_empty() else ""
	completed = true


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v094-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	call_deferred("_run")


func _run() -> void:
	check(Rules.VERSION == 52 and Rules.V51_VERSION == 51 and Source.CURRENT_SAVE_VERSION == 49 and Equipment.CURRENT_VOCABULARY == 51, "Gem-only52 keeps source49 and equipment51")
	for version: int in [49, 50, 51, 52]: check(Source._execution_policy(version) == 49, "Source execution policy stays49")
	for version: int in range(1, 53):
		check(Rules.equipment_vocabulary_for_save_version(version) == (51 if version >= 51 else 46 if version >= 46 else 39 if version >= 39 else 37 if version >= 37 else 34 if version >= 34 else version), "All save-equipment mappings stay explicit and frozen")
	var bytes := FileAccess.get_file_as_bytes(SOURCE_PATH)
	var source := Rules.decode_v51(JSON.parse_string(bytes.get_string_from_utf8()))
	if not check(not source.is_empty() and Rules.reason_v51(source).is_empty(), "Released51 integration fixture validates before migration"):
		quit(1)
		return
	if OS.get_environment("V094_MIGRATION_SECTION") == "economy":
		completed = false
		economy_checks(source)
		check(completed, "Corrected formal and test gem economy completes")
		finish("economy")
		return
	completed = false
	migrate_case(source, bytes, "released-v093-equipped")
	check(completed, "Released51 migration case completes")
	for entry: Array in [[strict_checks, "strict envelopes"], [current_checks, "current52 roundtrips"], [chain_checks, "49→50→51→52 chains"], [journey_checks, "old encounter boundary"], [economy_checks, "formal and test gem economy"]]:
		completed = false
		entry[0].call(source)
		check(completed, "Case completes without script errors: " + entry[1])
	completed = false
	failure_checks(source, bytes)
	check(completed, "All atomic failure cases complete")
	finish("all")


func finish(section: String) -> void:
	evidence.section = section
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V094_MIGRATION_REPORT")
	if not output.is_empty(): write(output, (JSON.stringify(evidence, "\t", true, true) + "\n").to_utf8_buffer())
	print("Encircling Cleave migration/economy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
