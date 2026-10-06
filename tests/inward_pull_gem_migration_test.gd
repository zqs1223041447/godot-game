extends SceneTree
## Strict42→43 gem migration from independent frozen-v066 serializer bytes.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/inward_pull_gem_migration.gd")
const Prior = preload("res://scripts/save/ambush_gem_migration.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const GemTrade = preload("res://scripts/items/gem_trade_rules.gd")
const TownCatalog = preload("res://scripts/town/town_catalog.gd")
const ROOT := "res://docs/qa/v067-migration/"
var checks := 0
var failures := 0
var evidence := {}


class FaultStore extends Store:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)


class BackupFailIO extends Store.Legacy:
	func _backup_legacy_save(_path: String) -> Error:
		return ERR_CANT_CREATE


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
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func current(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result.version = 43
	return result


func reject_bytes(name: String, bytes: PackedByteArray, version: int = 42) -> void:
	var path := "user://" + name + ".json"
	write(path,bytes)
	var store := Store.new()
	var before := store.snapshot()
	var events := [0]
	store.changed.connect(func(): events[0] += 1)
	check(not store.load_build(path) and store.snapshot() == before and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source leaves original bytes and live state unchanged: " + name)
	check(store.save_attempts == 0 and store.successful_saves == 0 and events[0] == 0 and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Invalid input causes no backup, write or event")
	check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected source cannot be overwritten by a later save")


func strict_checks(source: Dictionary) -> void:
	var calls := [0]
	var permissive := func(_value: Dictionary) -> String: calls[0] += 1; return ""
	for placement: String in ["recovery", "skill_support"]:
		var injected := with_inward_pull(source, placement)
		if not check(Rules.reason(current(injected)).is_empty(), "Injected Inward Pull is otherwise valid in current43: " + placement): return
		calls[0] = 0
		check(not Rules.reason_v42(injected,permissive).is_empty() and Rules.decode_v42(injected).is_empty() and Migration.migrate_v42(injected,permissive).is_empty() and calls[0] == 0, "Frozen42 rejects new gem or link before callback: " + placement)
		reject_bytes("injected42-inward_pull-" + placement, JSON.stringify(injected).to_utf8_buffer())
	var rating_items: Array = source.items.keys().filter(func(uid: String) -> bool:
		var item: Dictionary = source.items[uid]
		return item.kind == "equipment" and item.payload.get("base_id", "") == "emberhide_vest" and item.payload.get("affixes", []).any(func(affix: Dictionary) -> bool: return affix.id == "ironhide"))
	if not check(not rating_items.is_empty(), "Frozen fixture contains a defensive rating item"): return
	var gear_uid: String = rating_items[0]
	for mutation: String in ["fractional_revision", "bool_revision", "unknown_field", "missing_journey", "invalid_journey", "bad_uid", "unknown_node", "duplicate_node", "wrong_nodes_type", "unknown_stat", "over_budget", "bad_source", "nan_revision", "nan_mastery", "fractional_roll", "unknown_affix", "missing_location", "reused_serial", "bad_binding", "bad_ledger"]:
		var bad := source.duplicate(true)
		match mutation:
			"fractional_revision": bad.revision = 0.5
			"bool_revision": bad.revision = true
			"unknown_field": bad.zealots_oath = 1.0
			"missing_journey": bad.erase("journey")
			"invalid_journey": bad.journey.best_tiers.sunwell_terrace = true
			"bad_uid": bad.items[gear_uid].uid = "other"
			"unknown_node": bad.talents.allocated.append("unknown"); bad.talents.normal_points -= 1
			"duplicate_node": bad.talents.allocated.append(bad.talents.allocated[0]); bad.talents.normal_points -= 1
			"wrong_nodes_type": bad.talents.allocated = {"47175":true}
			"unknown_stat": bad.talents.zealots_oath = 1.0
			"over_budget": bad.talents.normal_points += 1
			"bad_source": bad.talents.source_version = "3.29.2"
			"nan_revision": bad.revision = NAN
			"nan_mastery": bad.talents.masteries["123"] = NAN
			"fractional_roll": bad.items[gear_uid].payload.affixes[0].value = 9.5
			"unknown_affix": bad.items[gear_uid].payload.affixes[0].id = "unrecognized_affix"
			"missing_location": bad.locations.erase(gear_uid)
			"reused_serial": bad.next_item_serial -= 1
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_ledger": bad.migration_ledger.normal_budget_at_migration += 1
		calls[0] = 0
		check(not Rules.reason_v42(bad,permissive).is_empty() and Rules.decode_v42(bad).is_empty() and Migration.migrate_v42(bad,permissive).is_empty() and calls[0] == 0, "Complete native frozen42 rejects before callback: " + mutation)
		if mutation == "nan_revision": bad.revision = null
		if mutation == "nan_mastery": bad.talents.masteries["123"] = null
		reject_bytes("invalid42-" + mutation,JSON.stringify(bad).to_utf8_buffer())
	for value: Variant in [null,[],true,42,"42",NAN,INF]:
		check(not Rules.reason_v42(value).is_empty() and Rules.decode_v42(value).is_empty() and Migration.migrate_v42(value).is_empty(), "Wrong envelope types fail before migration")
	reject_bytes("broken-json","{ broken42\r\n".to_utf8_buffer())
	var future := current(source)
	future.version = 44
	reject_bytes("future44",JSON.stringify(future).to_utf8_buffer(),44)
	check(Rules.decode(source).is_empty() and not Rules.reason(source).is_empty() and Rules.decode_v42(current(source)).is_empty(), "Current decoder accepts exactly43; frozen decoder accepts exactly42")
	var reject := func(_value: Dictionary) -> String: return "additional restriction"
	check(Migration.migrate_v42(source,reject).is_empty(), "Optional callbacks may add a further restriction")


func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure-" + failure + ".json"
		write(path,bytes)
		var store := Store.new()
		var before := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "collision": write(path + ".v42-backup.json","retained backup".to_utf8_buffer())
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic" and not check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject actual temporary-file collision"): return
		check(not store.load_build(path) and store.snapshot() == before and store.successful_saves == 0 and events[0] == 0, "Failed migration publishes nothing: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes), "Failed migration preserves original or independent writer bytes")
		check(store.save_attempts == (1 if failure == "atomic" else 0), "Backup must succeed before first commit attempt")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v42-backup.json") == "retained backup", "Conflicting backup remains verbatim")
		if failure in ["external","atomic"]: check(FileAccess.get_file_as_bytes(path + ".v42-backup.json") == bytes, "Failed commit retains exact raw backup")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == current(source) and store.successful_saves == 1 and events[0] == 1, "Identical-backup retry commits once after fault removal")
		else: check(store.save_build(path) != OK, "Failed load protects the same target from a later save")
	var accepted := current(source)
	var accepted_bytes := JSON.stringify(accepted).to_utf8_buffer()
	var accepted_path := "user://accepted43.json"
	write(accepted_path,accepted_bytes)
	var retained := FaultStore.new()
	if not check(retained.load_build(accepted_path), "Establish current43 live state and disk receipt"): return
	var failed_path := "user://failed42-replacement.json"
	write(failed_path,bytes)
	retained.fail_save = true
	check(not retained.load_build(failed_path) and retained.snapshot() == accepted and retained._path == accepted_path and retained._disk_bytes == accepted_bytes and FileAccess.get_file_as_bytes(failed_path) == bytes, "Failed old42 commit preserves prior accepted live state and disk receipt")


func with_inward_pull(source: Dictionary, placement: String) -> Dictionary:
	var value := source.duplicate(true)
	var uid := "item_%06d" % int(value.next_item_serial)
	value.next_item_serial += 1
	value.items[uid] = Gems.create_instance(uid, "support:inward_pull")
	var recovery := 0
	for location: Dictionary in value.locations.values():
		if location.kind == "recovery": recovery += 1
	value.locations[uid] = {"kind":"skill_support", "group_id":"group_000003", "index":0} if placement == "skill_support" else {"kind":"recovery", "index":recovery}
	return value


func literal_checks(label: String, source: Dictionary, bytes: PackedByteArray, oracle: Dictionary) -> void:
	var expected := current(source)
	var before := var_to_bytes(source)
	seed(674243)
	var next_rng := randi()
	seed(674243)
	var migrated := Migration.migrate_v42(source)
	if not check(randi() == next_rng and migrated == expected and var_to_bytes(source) == before, "Only version changes; native fixture and global RNG untouched: " + label): return
	for field: String in Rules.FIELDS:
		if field != "version": check(migrated[field] == source[field], "Preserve native " + label + " field: " + field)
	var migrated_stats := Game._stats_for(migrated)
	var source_stats := Game._stats_for(source)
	# The frozen oracle crossed JSON. Give current stats the identical boundary;
	# native source/current stats still compare exactly before serialization.
	var serialized_stats: Dictionary = JSON.parse_string(JSON.stringify(migrated_stats,"\t",true,true))
	check(migrated_stats == source_stats and serialized_stats == oracle.stats, "Exact native source/current stats and same-JSON-boundary old oracle: " + label)
	var old_ambush: Array = source.items.values().filter(func(item: Dictionary) -> bool: return item.definition_id == "support:ambush")
	check(old_ambush.size() == 2 and source.locations[old_ambush[0].uid] == migrated.locations[old_ambush[0].uid] and source.locations[old_ambush[1].uid] == migrated.locations[old_ambush[1].uid], "Both native42 Ambush ownership and equipped link are preserved")
	check(migrated.items.keys() == source.items.keys() and migrated.locations.keys() == source.locations.keys() and Store.Currency.total_quantity(migrated.items).quantity == 73, "No gift, UID reorder or currency change: " + label)
	check(Migration.migrate_v42(migrated).is_empty(), "Current envelope cannot be migrated twice")
	migrated.journey.best_tiers.sunwell_terrace = 3
	check(var_to_bytes(source) == before, "Migration deep-copies nested content")
	var path := "user://native42-" + label + ".json"
	write(path, bytes)
	var game := Game.new()
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	if not check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and game.successful_saves == 1 and events[0] == 1, "Native42 migration commits and notifies exactly once: " + label): return
	check(FileAccess.get_file_as_bytes(path + ".v42-backup.json") == bytes and not FileAccess.file_exists(path + ".tmp"), "Exact native42 byte backup precedes atomic replacement")
	check(game.migrated_from_legacy, "Game reports completed migration")
	var disk := FileAccess.get_file_as_bytes(path)
	check(game.load_build(path) and game.snapshot() == expected and game.save_attempts == 1 and FileAccess.get_file_as_bytes(path) == disk, "Repeat43 load performs no rewrite")
	var reopened := Store.new()
	if not check(reopened.load_build(path) and reopened.snapshot() == expected and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path + ".v42-backup.json") == bytes, "Independent43 reopen preserves every field and original backup"): return
	var payload: Dictionary = source.items[oracle.rating_item].payload
	check(reopened.item(oracle.rating_item).payload == payload and Equipment.validate_instance_for_version(payload,39), "Vocabulary39 rolls remain unchanged")
	for version: int in [37,40,41,42,43]: check(not Equipment.validate_instance_for_version(payload,version), "No broadened or invented equipment vocabulary " + str(version))
	check(payload.affixes.any(func(a:Dictionary)->bool:return a.id=="ironhide") and payload.affixes.any(func(a:Dictionary)->bool:return a.id=="mistweave"), "Both vocabulary39 defensive rating affixes retained")
	evidence[label] = {"native42_sha256":digest(bytes), "bytes":bytes.size(), "items":source.items.size(), "native_stats":oracle.stats}


func chain_checks() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://docs/qa/v066-migration/fixtures/v41-ir-frozen-v065.json")
	var old41 := Rules.decode_v41(JSON.parse_string(bytes.get_string_from_utf8()))
	if not check(not old41.is_empty(), "Independent native41 fixture remains valid"): return
	var frozen42 := Prior.migrate_v41(old41)
	var expected42 := old41.duplicate(true)
	expected42.version = 42
	if not check(frozen42 == expected42 and Rules.reason_v42(frozen42).is_empty(), "Prior Ambush migration stops at strict42, changing only version"): return
	for placement: String in ["recovery", "skill_support"]:
		var injected41 := with_inward_pull(old41, placement)
		check(not Rules.reason_v41(injected41).is_empty() and Rules.decode_v41(injected41).is_empty() and Prior.migrate_v41(injected41).is_empty(), "Earlier41 source cannot smuggle Inward Pull through prior migration: " + placement)
		reject_bytes("injected41-inward-pull-" + placement, JSON.stringify(injected41).to_utf8_buffer(),41)
	check(Migration.migrate_v42(frozen42) == current(old41), "Old41 to42 to43 chain preserves every nonversion field")
	var path := "user://native41-chain.json"
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot() == current(old41) and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v41-backup.json") == bytes and not FileAccess.file_exists(path + ".v42-backup.json"), "Actual41 chain commits once with only original41 backup")
	var fresh := Store.new().snapshot()
	check(fresh.version == 43 and Rules.reason(fresh).is_empty() and Store.Currency.total_quantity(fresh.items).quantity == 0 and fresh.items.values().filter(func(item:Dictionary)->bool:return item.definition_id=="support:inward_pull").is_empty(), "Built-in chain reaches43 without currency or Inward Pull gifts")


func current_checks(source: Dictionary) -> void:
	for placement: String in ["recovery", "skill_support"]:
		var candidate := current(with_inward_pull(source, placement))
		var uid := "item_%06d" % (int(candidate.next_item_serial)-1)
		var store := Store.new()
		store._accept_memory(candidate)
		var path := "user://current43-" + placement + ".json"
		if not check(Rules.reason(candidate).is_empty() and Rules.decode(JSON.parse_string(JSON.stringify(candidate))) == candidate and store.save_build(path) == OK, "Current43 Inward Pull envelope serializes: " + placement): return
		var reopened := Store.new()
		if not check(reopened.load_build(path) and reopened.snapshot() == candidate and reopened.save_attempts == 0 and not FileAccess.file_exists(path + ".v42-backup.json"), "Current43 gem/link reopens without migration: " + placement): return
		check(reopened.item(uid).payload == {"level":1,"quality":0} and reopened.location(uid) == candidate.locations[uid], "Only fixed gem payload and exact location are persisted")
		for field: String in ["pull_distance", "pull_targets", "runtime_owner"]:
			var bad := candidate.duplicate(true)
			bad.items[uid].payload[field] = 1
			check(not Rules.reason(bad).is_empty() and Rules.decode(bad).is_empty(), "Runtime pull state cannot leak into gem payload: " + field)


func recover_pending(game: RefCounted, path: String) -> bool:
	for uid: String in game.pending_items():
		var destination: Dictionary = game.first_bag_position(uid)
		var result: Dictionary = game.move_item(uid,destination,game.revision(),path)
		if not result.ok:
			check(false, "Real recovery move failed: " + str(result.reason))
			return false
	return game.pending_items().is_empty()


func catalog_reward_checks(source: Dictionary, oracle: Dictionary) -> void:
	check(Journey.GEM_DEFINITIONS == oracle.gem_definitions and Journey.GEM_DEFINITIONS.size() == 26 and not Journey.GEM_DEFINITIONS.has("support:inward_pull"), "Normal reward26 vocabulary unchanged")
	for index: int in oracle.gem_milestones.size(): check(Journey.gem_definition(index+1) == oracle.gem_milestones[index], "Old native reward ordinal remains exact: " + str(index+1))
	for id: String in oracle.minimum_save_versions: check(Gems.minimum_save_version(id) == int(oracle.minimum_save_versions[id]), "Existing gem schema minimum unchanged: " + id)
	check(Gems.minimum_save_version("support:inward_pull") == 43 and Gems.definitions().has("support:inward_pull"), "Only new support opens at43 through actual catalog")
	var offers := GemTrade.offers().filter(func(offer:Dictionary)->bool:return offer.definition_id=="support:inward_pull")
	check(offers.size() == 1 and offers[0].cost == 4 and GemTrade.quote("buy","support:inward_pull").cost == {"calibration_shard":4}, "Actual catalog dynamically supplies one four-shard support offer")
	var path := "user://build_save.json"
	var game := Game.new()
	game._accept_memory(current(source))
	if not check(game.save_build(path) == OK and recover_pending(game,path), "Prepare existing native items through real formal save and recovery transactions"): return
	var before := game.snapshot()
	var balance := game.crafting_balance()
	var quote: Dictionary = game.gem_trade_quote("buy","support:inward_pull",game.revision(),path)
	check(quote.ok and quote.cost == {"calibration_shard":4} and game.snapshot() == before, "Inward Pull quote charges nothing and leaves the current save untouched")
	if not quote.ok: return
	var bought: Dictionary = game.execute_gem_trade(quote.handle,"support:inward_pull")
	if not check(bought.ok and game.crafting_balance() == balance-4 and game.item(bought.get("uid","")).get("definition_id","") == "support:inward_pull", "Normal purchase consumes exactly four shards and creates one Inward Pull"): return
	var bought_snapshot := game.snapshot()
	check(not game.execute_gem_trade(quote.handle,"support:inward_pull").ok and game.snapshot() == bought_snapshot, "Repeated purchase handle cannot charge twice")
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == bought_snapshot, "Purchased current43 Inward Pull survives native reload")
	var ids: Array = Gems.definitions().keys()
	ids.sort()
	var selected_seed := -1
	for candidate_seed: int in range(4096):
		var selection := RandomNumberGenerator.new()
		selection.seed = candidate_seed
		if ids[selection.randi_range(0,ids.size()-1)] == "support:inward_pull": selected_seed=candidate_seed; break
	if not check(selected_seed >= 0, "Find bounded deterministic seed selecting Inward Pull from the actual dynamic catalog"): return
	var random := RandomNumberGenerator.new()
	random.seed = selected_seed
	var test_game := Game.new()
	test_game._accept_memory(bought_snapshot)
	if not check(test_game.save_build("user://town_test_build_save.json") == OK, "Prepare isolated actual test profile"): return
	var test_offers: Array = TownCatalog.offers("skill_merchant").filter(func(offer: Dictionary) -> bool: return offer.id == "support:inward_pull")
	check(test_offers.size() == 1 and TownCatalog.offer("support:inward_pull").get("id", "") == "support:inward_pull", "Existing dynamic test merchant supplies exactly one Inward Pull offer")
	var formal_bytes := FileAccess.get_file_as_bytes(path)
	var formal_snapshot := game.snapshot()
	var test_balance := test_game.crafting_balance()
	var supply_revision := test_game.revision()
	var supplied: Dictionary = test_game.town_claim_offer("support:inward_pull",supply_revision,"user://town_test_build_save.json")
	if not check(supplied.get("ok", false), "Actual test merchant claim succeeds before inspecting supplied UID"): return
	check(test_game.item(supplied.uid).get("definition_id", "") == "support:inward_pull" and test_game.location(supplied.uid).get("kind", "") == "bag" and test_game.crafting_balance() == test_balance, "Actual test supply creates the fixed gem in the bag at zero shard cost")
	var supplied_snapshot := test_game.snapshot()
	check(not test_game.town_claim_offer("support:inward_pull",supply_revision,"user://town_test_build_save.json").ok and test_game.snapshot() == supplied_snapshot, "Stale test claim cannot duplicate supply")
	check(not game.town_claim_offer("support:inward_pull",game.revision(),path).ok and game.snapshot() == formal_snapshot and FileAccess.get_file_as_bytes(path) == formal_bytes, "Free test supply cannot enter or alter the formal save")
	var test_reopened := Game.new()
	check(test_reopened.load_build("user://town_test_build_save.json") and test_reopened.snapshot() == supplied_snapshot, "Free test supply survives native43 reopen")
	var awarded: String = test_game.award_random_gem(random)
	check(not awarded.is_empty() and test_game.item(awarded).get("definition_id", "") == "support:inward_pull" and test_game.crafting_balance() == balance-4, "Existing dynamic test reward supplies Inward Pull for free without a new economy path")
	var owed := game.snapshot()
	owed.journey.normal_root_kills = 30
	game._accept_memory(owed)
	if not check(game.save_build(path) == OK, "Persist narrow owed first normal milestone"): return
	var old_uids: Array = game.snapshot().items.keys()
	var reward: Dictionary = game.normal_claim_rewards(game.revision(),path,false)
	if not check(reward.get("ok", false), "Normal reward transaction succeeds before inspecting awarded fields"): return
	var new_items: Array = game.snapshot().items.values().filter(func(item:Dictionary)->bool:return not old_uids.has(item.uid))
	check(reward.ok and reward.claimed_gems == 1 and new_items.size() == 1 and new_items[0].definition_id == oracle.gem_milestones[0] and new_items[0].definition_id != "support:inward_pull", "Actual normal reward transaction retains native frozen first ordinal")
	evidence.shop_cost = 4
	evidence.test_reward_seed = selected_seed
	evidence.actual_normal_reward = new_items[0].definition_id if not new_items.is_empty() else ""


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v067-migration-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	check(Rules.VERSION == 43 and Rules.V42_VERSION == 42 and Source.CURRENT_SAVE_VERSION == 41 and Equipment.CURRENT_VOCABULARY == 39, "Gem schema43 keeps source41 and equipment39")
	check(Source._execution_policy(40) == 40 and Source._execution_policy(41) == 41 and Source._execution_policy(42) == 41 and Source._execution_policy(43) == 41, "Schema43 opens no new source consumer")
	check(Rules.equipment_vocabulary_for_save_version(42) == 39 and Rules.equipment_vocabulary_for_save_version(43) == 39, "Save43 maps explicitly to equipment39")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/manifest.json"))
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/v42-oracle.json"))
	var source := {}
	var bytes := PackedByteArray()
	for label: String in ["zo", "ir"]:
		var filename := "v42-" + label + "-frozen-v066.json"
		bytes = FileAccess.get_file_as_bytes(ROOT + "fixtures/" + filename)
		check(digest(bytes) == manifest.files[filename].sha256 and bytes.size() == int(manifest.files[filename].bytes), "Native unchanged v66 serializer fixture matches capture hash: " + label)
		source = Rules.decode_v42(JSON.parse_string(bytes.get_string_from_utf8()))
		check(not source.is_empty() and Rules.reason_v42(source).is_empty(), "Native42 completely validates before migration: " + label)
		if source.is_empty(): quit(1); return
		literal_checks(label,source,bytes,oracle.fixtures[label])
	strict_checks(source)
	failure_checks(source,bytes)
	chain_checks()
	current_checks(source)
	catalog_reward_checks(source,oracle)
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V067_MIGRATION_REPORT")
	if not output.is_empty(): write(output,(JSON.stringify(evidence,"\t",true,true)+"\n").to_utf8_buffer())
	print("Inward Pull gem migration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
