extends SceneTree
## Focused schema49→50 and real Normal transaction boundary checks.
const Store = preload("res://scripts/save/canonical_build_store.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Migration = preload("res://scripts/save/fourth_map_migration.gd")
const Cold = preload("res://scripts/save/cold_ailment_duration_migration.gd")
const Journey = preload("res://scripts/world/normal_journey_state.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Normal = preload("res://scripts/world/normal_map_catalog.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Fixture = preload("res://tests/fixtures/v083/ginkgo_journey_fixture.gd")
const ROOT := "res://docs/qa/v083-save/"
const PATH := "user://build_save.json"
const MAP_ID := "ginkgo_arcade"
var checks := 0
var failures := 0
var labels: Array[String] = []

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
		labels.append(label)
		push_error(label)
	return ok

func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func serialized(value: Dictionary) -> PackedByteArray:
	return (JSON.stringify(value, "  ", false, true) + "\n").to_utf8_buffer()

func expected(source: Dictionary) -> Dictionary:
	var value := source.duplicate(true)
	value.version = 50
	value.journey.best_tiers[MAP_ID] = 0
	return value

func observed(game) -> Dictionary:
	return {"memory": var_to_bytes(game.snapshot()), "disk": FileAccess.get_file_as_bytes(PATH), "saves": game.successful_saves}

func migration_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	var before := var_to_bytes(source)
	seed(83049)
	var control := randi()
	seed(83049)
	check(Migration.migrate_v49(source) == expected(source) and var_to_bytes(source) == before and randi() == control, "Pure49→50 changes only version and new zero key; source and global RNG preserved")
	check(Rules.SourceTree.CURRENT_SAVE_VERSION == 49 and Rules.SourceTree._execution_policy(50) == 49 and Rules.equipment_vocabulary_for_save_version(50) == 46, "Map schema50 preserves source policy49 and equipment46")
	var selected49 := Rules.decode_v49(JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v082-source/fixtures/witch-selected.json")))
	check(not selected49.is_empty() and Migration.migrate_v49(selected49) == expected(selected49), "Already allocated cold-duration native49 route survives exact two-field migration")
	var source_game := Game.new()
	source_game._accept_memory(selected49)
	var source_stats := source_game.get_stats()
	source_game._accept_memory(Migration.migrate_v49(selected49))
	check(source_game.get_stats() == source_stats and is_equal_approx(source_stats.cold_ailment_duration_increased, 0.20), "Map-only50 preserves every gameplay stat including allocated20percent cold duration")
	check(Journey.empty().best_tiers.size() == 4 and Journey.empty_v49().best_tiers.size() == 3 and Journey.empty_legacy().best_tiers.size() == 2, "Each journey era has an explicit frozen default")
	for map_id: String in Journey.V49_MAP_IDS:
		for state: String in ["active", "pending"]:
			var old := source.duplicate(true)
			old.journey.normal_root_kills = 180
			old.journey.claimed_gems = 4
			old.journey.claimed_flasks = 2
			old.journey.next_run_id = 18
			old.journey.best_tiers[map_id] = 2
			if state == "active": old.journey.active_run = {"run_id": 17, "map_id": map_id, "tier": 3, "normal_ids": ["enemy_max_health_120", "enemy_move_speed_110"], "special_ids": ["elemental_aegis"], "fee_paid": 8}
			else: old.journey.pending_map_reward = {"run_id": 17, "map_id": map_id, "tier": 2, "shards": 8}
			check(Rules.reason_v49(old).is_empty(), "Existing three-map active/pending envelope valid: " + map_id + state)
			var path := "user://old49-" + map_id + "-" + state + ".json"
			var original := serialized(old)
			write(path, original)
			var game := Game.new()
			var events := [0]
			game.changed.connect(func(): events[0] += 1)
			check(game.load_build(path) and game.snapshot() == expected(old) and game.successful_saves == 1 and events[0] == 1, "Existing49 migrates atomically without progress or reward changes")
			check(FileAccess.get_file_as_bytes(path + ".v49-backup.json") == original, "Exact original49 bytes backed up")
			check(game.migration_message.contains("银杏回廊 I") and game.migration_message.contains("不额外赠送"), "Migration notice opens only mapI without gifts")
			if state == "active":
				check(Maps.compile_normal(map_id, 3, old.journey.active_run.normal_ids, old.journey.active_run.special_ids).ok and Journey.complete(game.normal_journey(), 17).ok, "Old explicit unfinished profile remains replayable")
			else: check(game.normal_pending_rewards().pending_map_reward == old.journey.pending_map_reward, "Old pending reward remains exact")
			var disk := FileAccess.get_file_as_bytes(path)
			var reopened := Game.new()
			check(reopened.load_build(path) and reopened.snapshot() == expected(old) and reopened.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == disk, "Native50 reload performs no repeated migration")
			write(ROOT + "fixtures/v49-" + map_id + "-" + state + ".json", original)
	var native_path := "user://native49-exact.json"
	write(native_path, bytes)
	var native := Game.new()
	check(native.load_build(native_path) and FileAccess.get_file_as_bytes(native_path + ".v49-backup.json") == bytes, "Released native49 serializer preserved byte-for-byte")
	check(native.snapshot().items == source.items and native.snapshot().locations == source.locations and native.snapshot().talents == source.talents and native.snapshot().progress == source.progress and native.crafting_balance() == 0, "Original equipment, inventory, talents and XP unchanged; no currency gifted")

func validation_checks(source: Dictionary) -> void:
	var calls := [0]
	var permissive := func(_candidate: Dictionary) -> String: calls[0] += 1; return ""
	for mutation: String in ["fourth_key", "missing_key", "extra_key", "fourth_active", "fourth_pending", "fractional_revision", "bad_uid", "bad_binding", "bad_source", "bad_budget", "bad_claimed", "unknown_field"]:
		var bad := source.duplicate(true)
		match mutation:
			"fourth_key": bad.journey.best_tiers[MAP_ID] = 0
			"missing_key": bad.journey.best_tiers.erase("sunwell_terrace")
			"extra_key": bad.journey.best_tiers.unknown = 0
			"fourth_active": bad.journey.next_run_id = 2; bad.journey.active_run = {"run_id": 1, "map_id": MAP_ID, "tier": 1, "normal_ids": [], "special_ids": [], "fee_paid": 0}
			"fourth_pending": bad.journey.next_run_id = 2; bad.journey.pending_map_reward = {"run_id": 1, "map_id": MAP_ID, "tier": 1, "shards": 4}
			"fractional_revision": bad.revision = 0.5
			"bad_uid": bad.items[bad.items.keys()[0]].uid = "missing"
			"bad_binding": bad.bindings[0].keycode = KEY_C
			"bad_source": bad.talents.source_version = "3.30"
			"bad_budget": bad.talents.normal_points += 1
			"bad_claimed": bad.journey.claimed_gems = 1
			"unknown_field": bad.wallet = {"shards": 10}
		calls[0] = 0
		check(not Rules.reason_v49(bad, permissive).is_empty() and Rules.decode_v49(bad).is_empty() and Migration.migrate_v49(bad, permissive).is_empty() and calls[0] == 0, "Complete original49 legality precedes permissive callback: " + mutation)
		var path := "user://reject49-" + mutation + ".json"
		var bytes := serialized(bad)
		write(path, bytes)
		var store := Store.new()
		var memory := store.snapshot()
		check(not store.load_build(path) and store.snapshot() == memory and store.save_attempts == 0 and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path + ".v49-backup.json"), "Invalid49 source reaches no backup or publication: " + mutation)
		check(store.save_build(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "Rejected49 remains protected")
	var current := expected(source)
	check(Rules.decode_v49(current).is_empty() and Rules.decode(source).is_empty() and Migration.migrate_v49(current).is_empty(), "Exact49 and50 envelopes cannot be confused")
	for bad_tier: Variant in [true, -1, 4, 0.5, "0", null]:
		var bad := current.duplicate(true)
		bad.journey.best_tiers[MAP_ID] = bad_tier
		check(not Rules.reason(bad).is_empty() and Rules.decode(bad).is_empty(), "Current50 rejects malformed fourth-map tier " + str(bad_tier))
	for mutation: String in ["missing", "extra", "alias"]:
		var bad := current.duplicate(true)
		if mutation == "missing": bad.journey.best_tiers.erase(MAP_ID)
		elif mutation == "extra": bad.journey.best_tiers.unknown_map = 0
		else: bad.journey.best_tiers.erase(MAP_ID); bad.journey.best_tiers.Ginkgo_Arcade = 0
		check(not Rules.reason(bad).is_empty() and Rules.decode(bad).is_empty(), "Current50 requires exactly four canonical map keys: " + mutation)
	var float_tier := current.duplicate(true)
	float_tier.journey.best_tiers[MAP_ID] = 0.0
	check(not Rules.reason(float_tier).is_empty() and Rules.decode(float_tier) == current, "Only JSON decoding normalizes whole floating-point tiers")
	var restricted := func(_candidate: Dictionary) -> String: return "extra restriction"
	check(Migration.migrate_v49(source, restricted).is_empty(), "Optional callback may add restrictions")

func failure_checks(source: Dictionary, bytes: PackedByteArray) -> void:
	for failure: String in ["backup", "collision", "external", "atomic"]:
		var path := "user://failure50-" + failure + ".json"
		write(path, bytes)
		var store := Store.new()
		var memory := store.snapshot()
		var events := [0]
		store.changed.connect(func(): events[0] += 1)
		if failure == "backup": store._io = BackupFailIO.new()
		if failure == "collision": write(path + ".v49-backup.json", "retained backup".to_utf8_buffer())
		if failure == "external": store._io = ExternalIO.new()
		if failure == "atomic": check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Actual temp-file collision installed")
		check(not store.load_build(path) and store.snapshot() == memory and store.successful_saves == 0 and events[0] == 0, "Failed migration preserves live memory: " + failure)
		check(FileAccess.get_file_as_bytes(path) == ("external writer".to_utf8_buffer() if failure == "external" else bytes) and store.save_attempts == (1 if failure == "atomic" else 0), "Failure preserves original/external bytes and write ordering")
		if failure == "collision": check(FileAccess.get_file_as_string(path + ".v49-backup.json") == "retained backup", "Existing conflicting backup never overwritten")
		if failure in ["external", "atomic"]: check(FileAccess.get_file_as_bytes(path + ".v49-backup.json") == bytes, "Exact original backup survives failed commit")
		if failure == "atomic":
			check(DirAccess.remove_absolute(path + ".tmp") == OK and store.load_build(path) and store.snapshot() == expected(source) and events[0] == 1, "Matching-backup retry commits exactly once after fault removal")

func chain_checks(source: Dictionary) -> void:
	# One focused chain pass, rather than rerunning historical suites.
	var legacy_path := "res://tests/fixtures/v041_journey/v25-default.json"
	var bytes := FileAccess.get_file_as_bytes(legacy_path)
	var path := "user://history25.json"
	write(path, bytes)
	var store := Store.new()
	check(store.load_build(path) and store.snapshot().version == 50 and store.snapshot().journey == Journey.empty() and store.save_attempts == 1 and FileAccess.get_file_as_bytes(path + ".v25-backup.json") == bytes, "Full25→50 loader chain adds maps at their historical boundaries and writes once")
	check(not FileAccess.file_exists(path + ".v49-backup.json") and Store.Currency.total_quantity(store.snapshot().items).quantity == 0, "Full old chain creates no intermediate backup or currency")
	var frozen := source.duplicate(true)
	frozen.version = 48
	check(Rules.reason_v48(frozen).is_empty() and Cold.migrate_v48(frozen) == source, "Cold migration endpoint remains frozen49 without a fourth key")
	for version: int in range(30, 50):
		var old := source.duplicate(true)
		old.version = version
		# Refunded native49 route is also legal under30; only map vocabulary varies.
		check(Journey.reason_v49(old.journey).is_empty() and not Rules._decode(old, true, version, true).is_empty(), "Frozen schema%d still decodes exact three-map keys" % version)
		old.journey.best_tiers[MAP_ID] = 0
		check(Rules._decode(old, true, version, true).is_empty(), "Frozen schema%d rejects an injected fourth key" % version)
	for version: int in range(26, 30):
		var old := source.duplicate(true)
		old.version = version
		old.journey = Journey.empty_legacy()
		check(not Rules._decode(old, true, version, true).is_empty(), "Frozen%d keeps exact two-map keys" % version)
		old.journey.best_tiers.sunwell_terrace = 0
		check(Rules._decode(old, true, version, true).is_empty(), "Frozen%d rejects premature third map" % version)

func transaction_checks() -> void:
	var game := FaultGame.new()
	if not check(Fixture.prepare(game, PATH).ok, "Shared fixture migrates genuine49 into opened Normal50 profile"): return
	write(ROOT + "fixtures/v50-ginkgo-I-ready.json", serialized(game.snapshot()))
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	for map_id: String in Journey.MAP_IDS:
		for tier: int in range(1, 4):
			var compiled := Maps.compile_normal(map_id, tier, [], [])
			check(compiled.ok and compiled.profile.fee == [0, 4, 8][tier - 1] and compiled.profile.base_completion_reward == [4, 8, 12][tier - 1], "Real Normal profile compiles " + map_id + " tier" + str(tier))
	var one: Dictionary = Maps.compile_normal(MAP_ID, 1, [], []).profile
	var two: Dictionary = Maps.compile_normal(MAP_ID, 2, [], []).profile
	var three: Dictionary = Maps.compile_normal(MAP_ID, 3, [], []).profile
	check([one.wave, two.wave, three.wave] == [3, 6, 10] and Normal.tiers(MAP_ID, 0)[0].unlocked and not Normal.tiers(MAP_ID, 0)[1].unlocked and not Normal.tiers(MAP_ID, 1)[2].unlocked, "Ginkgo I initially open; II/III require its own preceding tier; waves3/6/10")
	var before := observed(game)
	check(not game.normal_start_map(two, game.revision(), PATH).ok and not game.normal_start_map(three, game.revision(), PATH).ok and observed(game) == before, "Locked new tiers do not deduct or allocate a run")
	game.fail_save = true
	check(not game.normal_start_map(one, game.revision(), PATH).ok and observed(game) == before and events[0] == 0, "Failed first admission preserves memory, original bytes and run serial")
	game.fail_save = false
	var opened := game.normal_start_map(one, game.revision(), PATH)
	check(opened.ok and opened.run_id == 1 and opened.cost == 0 and game.crafting_balance() == 0, "New tierI starts free through actual model")
	write(ROOT + "fixtures/v50-ginkgo-I-active.json", serialized(game.snapshot()))
	before = observed(game)
	game.fail_save = true
	check(not game.normal_complete_map(opened.run_id, game.revision(), PATH).ok and observed(game) == before, "Failed completion retains active run and no unlock")
	game.fail_save = false
	check(game.normal_complete_map(opened.run_id, game.revision(), PATH).ok and game.normal_journey().best_tiers[MAP_ID] == 1 and game.crafting_balance() == 0, "Completion unlocks only this map; reward remains pending")
	write(ROOT + "fixtures/v50-ginkgo-I-pending.json", serialized(game.snapshot()))
	before = observed(game)
	check(not game.normal_complete_map(opened.run_id, game.revision(), PATH).ok and not game.normal_start_map(two, game.revision(), PATH).ok and observed(game) == before, "Same run completes once and pending reward gates admission")
	game.fail_save = true
	check(not game.normal_claim_rewards(game.revision(), PATH).ok and observed(game) == before, "Failed claim preserves pending reward, inventory and original bytes")
	game.fail_save = false
	var claim := game.normal_claim_rewards(game.revision(), PATH)
	check(claim.ok and claim.claimed_shards == 4 and game.crafting_balance() == 4 and game.snapshot().crafting.keys() == ["revision"], "Claim creates real shard inventory with no second wallet")
	write(ROOT + "fixtures/v50-ginkgo-II-ready.json", serialized(game.snapshot()))
	before = observed(game)
	check(not game.normal_start_map(Maps.compile_normal("old_garden", 2, [], []).profile, game.revision(), PATH).ok and observed(game) == before, "Ginkgo progress never unlocks another map")
	game.fail_save = true
	check(not game.normal_start_map(two, game.revision(), PATH).ok and observed(game) == before, "Failed paid admission keeps exact fee and run serial")
	game.fail_save = false
	opened = game.normal_start_map(two, game.revision(), PATH)
	check(opened.ok and opened.cost == 4 and game.crafting_balance() == 0, "TierII deducts exactly four inventory shards")
	before = observed(game)
	check(not game.normal_start_map(two, game.revision(), PATH, opened.run_id).ok and observed(game) == before, "Underfunded retry retains old active run atomically")
	check(game.normal_complete_map(opened.run_id, game.revision(), PATH).ok and game.normal_claim_rewards(game.revision(), PATH).ok and game.crafting_balance() == 8, "TierII completion and claim earn exactly eight shards")
	write(ROOT + "fixtures/v50-ginkgo-III-ready.json", serialized(game.snapshot()))
	opened = game.normal_start_map(three, game.revision(), PATH)
	check(opened.ok and opened.cost == 8 and game.crafting_balance() == 0, "TierIII deducts exactly eight real shards")
	check(game.normal_complete_map(opened.run_id, game.revision(), PATH).ok and game.normal_claim_rewards(game.revision(), PATH).ok and game.crafting_balance() == 12 and game.normal_journey().best_tiers[MAP_ID] == 3, "TierIII completes and claims exactly twelve real shards")
	opened = game.normal_start_map(two, game.revision(), PATH)
	check(opened.ok and game.crafting_balance() == 8, "Replay tierII pays its fee")
	before = observed(game)
	game.fail_save = true
	check(not game.normal_start_map(two, game.revision(), PATH, opened.run_id).ok and observed(game) == before, "Failed funded retry preserves original run and fee")
	game.fail_save = false
	var retry := game.normal_start_map(two, game.revision(), PATH, opened.run_id)
	check(retry.ok and retry.run_id == opened.run_id + 1 and game.crafting_balance() == 4, "Funded retry atomically abandons old run and charges a new fee")
	before = observed(game)
	check(not game.normal_complete_map(opened.run_id, game.revision(), PATH).ok and observed(game) == before, "Replaced run cannot settle")
	game.fail_save = true
	check(not game.normal_abandon_map(retry.run_id, game.revision(), PATH).ok and observed(game) == before, "Failed abandonment preserves active run and disk")
	game.fail_save = false
	check(game.normal_abandon_map(retry.run_id, game.revision(), PATH).ok and game.crafting_balance() == 4 and game.normal_journey().pending_map_reward.is_empty(), "Abandonment gives no refund or completion award")
	# Retain owed milestones and all claim ordinals under genuine capacity pressure.
	var filled := game.snapshot()
	for uid: String in filled.locations.keys():
		if filled.locations[uid].kind == "bag": filled.locations.erase(uid); filled.items.erase(uid)
	while true:
		var uid := "item_%06d" % int(filled.next_item_serial)
		if not game._place_journey_reward(filled, Gems.create_instance(uid, "support:efficiency")): break
	filled.revision += 1
	check(game._commit(filled, PATH).ok, "Real full240-cell gem fixture passes canonical validation")
	opened = game.normal_start_map(one, game.revision(), PATH)
	check(opened.ok and game.normal_complete_map(opened.run_id, game.revision(), PATH).ok, "Full bag can complete free new map with pending reward")
	for index: int in range(60): game.add_normal_root_xp(0)
	check(game.save_build(PATH) == OK, "Milestones persist through ordinary final reward flush")
	before = observed(game)
	var event_count: int = events[0]
	check(not game.normal_claim_rewards(game.revision(), PATH).ok and observed(game) == before and events[0] == event_count and game.normal_pending_rewards().pending_gems == 2 and game.normal_pending_rewards().pending_flasks == 1, "Full bag preserves map award, milestone ordinals, UIDs, currency and signals")
	write(ROOT + "fixtures/v50-ginkgo-full-pending.json", serialized(game.snapshot()))
	var remove := ""
	for uid: String in game.snapshot().locations:
		if game.snapshot().locations[uid].kind == "bag": remove = uid; break
	check(game.discard_item(remove, game.revision(), PATH).ok, "Actual discard frees one reward cell")
	claim = game.normal_claim_rewards(game.revision(), PATH)
	check(claim.ok and claim.claimed_shards == 4 and claim.claimed_gems == 0 and game.normal_pending_rewards().pending_map_reward.is_empty() and game.normal_pending_rewards().pending_gems == 2, "One free cell claims map shards exactly once and retains milestone backlog")
	before = observed(game)
	check(not game.normal_claim_rewards(game.revision(), PATH).ok and observed(game) == before, "Repeated full-bag claim cannot duplicate map award")
	var disk := FileAccess.get_file_as_bytes(PATH)
	write(PATH, disk + " ".to_utf8_buffer())
	var memory := game.snapshot()
	check(not game.normal_start_map(one, game.revision(), PATH).ok and game.snapshot() == memory and FileAccess.get_file_as_bytes(PATH) == disk + " ".to_utf8_buffer(), "External Normal save bytes remain protected on new-map admission")

func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v083-save-") or not OS.get_user_data_dir().begins_with(isolation + "/"): quit(78); return
	var bytes := FileAccess.get_file_as_bytes(Fixture.NATIVE49)
	var source := Rules.decode_v49(JSON.parse_string(bytes.get_string_from_utf8()))
	if not check(not source.is_empty() and Rules.reason_v49(source).is_empty(), "Released native49 fixture is legal before migration"): quit(1); return
	migration_checks(source, bytes)
	validation_checks(source)
	failure_checks(source, bytes)
	chain_checks(source)
	transaction_checks()
	var report := {"checks": checks, "failures": failures, "failed_labels": labels, "migration": "49→50", "changed_fields": ["version", "journey.best_tiers.ginkgo_arcade"], "native49_source": Fixture.NATIVE49, "native49_sha256": FileAccess.get_sha256(Fixture.NATIVE49), "source_policy": Rules.SourceTree.CURRENT_SAVE_VERSION, "equipment_vocabulary": Rules.equipment_vocabulary_for_save_version(50), "fixture_helper": "res://tests/fixtures/v083/ginkgo_journey_fixture.gd"}
	write(ROOT + "save-report.json", serialized(report))
	print("Fourth map journey: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
