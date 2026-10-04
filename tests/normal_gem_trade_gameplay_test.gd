extends SceneTree
## Actual main routing and two real camp/boss completions; no fabricated currency.
## This is a headless integration test, not native GUI verification.
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const TARGET := "skill:shade_bolt"
const SOURCES := ["tests/normal_gem_trade_gameplay_test.gd", "scripts/main.gd", "scripts/canonical_game_state.gd", "scripts/save/canonical_build_store.gd", "scripts/items/gem_trade_rules.gd", "scripts/items/gem_catalog.gd", "scripts/town/town_catalog.gd", "scripts/combat/skill_compiler.gd", "scripts/game_hud.gd", "scripts/ui/town_service_panel.gd", "scripts/ui/canonical_inventory_panel.gd"]
var arena: Node
var checks := 0
var failures := 0
var evidence: Array[Dictionary] = []
var changes := 0
var source_hashes: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	evidence.append({"ok": value, "label": label})
	if not value:
		failures += 1
		push_error(label)

func disk(path: String) -> Dictionary:
	return {"exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

func runtime() -> Dictionary:
	return {"rng": arena.rng.state, "critical": arena.critical_runtime.checkpoint(),
		"flasks": arena.flask_runtime.snapshot(), "cooldowns": arena.cooldowns.duplicate(true),
		"group_cooldowns": arena.group_cooldowns.snapshot(), "health": arena.health, "mana": arena.mana,
		"shield": arena.shield, "player_pos": arena.player_pos, "alive": arena.alive,
		"monsters": arena.EncounterAdmission._snapshot(arena.monster_runtime),
		"camps": arena._map_camps.checkpoint(), "map_run": arena._map_run.snapshot(),
		"enemies": arena.enemies.duplicate(true), "projectiles": arena.projectiles.duplicate(true),
		"particles": arena.particles.duplicate(true), "rings": arena.rings.duplicate(true),
		"pickups": arena.pickups.duplicate(true), "floating_text": arena.floating_text.duplicate(true),
		"projectile_ids": [arena.projectile_runtime.next_projectile_id, arena.projectile_runtime.next_cast_id]}

func observe() -> Dictionary:
	return {"model_id": arena.state.get_instance_id(), "build": arena.state.snapshot(),
		"world": arena.world_context(), "runtime": runtime(),
		"normal_disk": disk(arena.NORMAL_BUILD_PATH), "test_disk": disk(arena.TOWN_TEST_BUILD_PATH),
		"saves": [arena.state.save_attempts, arena.state.successful_saves, arena.progress_save_attempt_count,
			arena.progress_save_success_count, arena.progress_hud_refresh_count]}

func reject(call: Callable, label: String) -> void:
	var before := observe()
	var result: Dictionary = call.call()
	check(not result.get("ok", false), label + ": rejected")
	check(observe() == before, label + ": full build/runtime/world and both disk files unchanged")

func all_unavailable(rows: Array) -> bool:
	for row: Dictionary in rows:
		if row.available or str(row.reason).is_empty(): return false
	return not rows.is_empty()

func kill_all() -> void:
	for enemy: Dictionary in arena.enemies.duplicate():
		if float(enemy.health) > 0.0:
			enemy.spawn = 0.0
			arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 1000.0, Color.WHITE)
	arena._flush_monster_spawns()

func complete_map() -> void:
	var geometry: Dictionary = arena.world_geometry().landmarks
	for camp: Dictionary in geometry.camps:
		arena.player_pos = camp.trigger_center
		arena._update_map_spawning(0.0)
	check(arena.enemies.size() == 24, "All three real old-garden camps admit 24 ordinary roots")
	arena._begin_progress_transaction()
	kill_all()
	check(arena.world_context().boss_phase == "ready", "Original camp deaths unlock real boss gate")
	arena.player_pos = geometry.boss.trigger_center
	arena._update_map_spawning(0.0)
	check(arena.world_context().boss_phase == "active" and arena._map_run.boss_id > 0, "Real boss is admitted through its gate")
	kill_all()
	check(arena.enemies.size() == 4 and arena.world_context().mode == "map", "Boss descendants prevent premature reward")
	kill_all()
	arena._check_map_complete()
	arena._end_progress_transaction()
	check(arena.world_context().mode == "map_complete" and arena.world_context().pending_map_reward.shards == 4, "Real root/boss/descendant completion creates four-shard receipt")

func trade(operation: String, target: String, expected_delta: int) -> Dictionary:
	var before := observe()
	var balance: int = arena.state.crafting_balance()
	var revision: int = arena.state.revision()
	var notifications := changes
	var quote: Dictionary = arena.normal_gem_trade_quote(operation, target, revision)
	check(quote.get("ok", false), "Main issues " + operation + " quote")
	check(observe() == before, "Quoting " + operation + " leaves full authoritative state and both files unchanged")
	if not quote.get("ok", false): return {}
	var result: Dictionary = arena.execute_normal_gem_trade(quote.handle, target)
	check(result.ok and arena.state.crafting_balance() == balance + expected_delta, operation + " applies exact shard delta " + str(expected_delta))
	check(arena.state.revision() == revision + 1 and changes == notifications + 1, operation + " publishes exactly one revision and changed signal")
	check(arena.state.save_attempts == before.saves[0] + 1 and arena.state.successful_saves == before.saves[1] + 1 and arena.progress_save_attempt_count == before.saves[2], operation + " persists exactly once with no main autosave duplication")
	check(runtime() == before.runtime, operation + " preserves loot/combat RNG, charges, active flask recovery, cooldown debts and other run state")
	check(disk(arena.TOWN_TEST_BUILD_PATH) == before.test_disk, operation + " leaves test disk byte-identical")
	var loaded := Model.new()
	check(loaded.load_build(arena.NORMAL_BUILD_PATH) and loaded.snapshot() == arena.state.snapshot(), operation + " reloads exact committed build")
	reject(func() -> Dictionary: return arena.execute_normal_gem_trade(quote.handle, target), operation + " duplicate confirmation")
	return result

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	for source: String in SOURCES: source_hashes[source] = FileAccess.get_sha256("res://" + source)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	check(arena.save_build() and arena.world_context().normal_town and arena.state.crafting_balance() == 0, "Fresh real main starts in formal town with zero shards")
	var stock: Array = arena.town_stock("skill_merchant")
	check(stock.size() == Gems.definitions().size() and stock.size() == 26, "Formal stock is derived from all 26 current catalog definitions")
	for row: Dictionary in stock:
		check(row.paid and row.id == row.definition_id and row.cost is int and row.cost == (8 if row.kind == "skill_gem" else 4) and not row.preview.is_empty(), "Formal stock has exact identity, preview and typed active/support price: " + row.id)
	reject(func() -> Dictionary: return arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision()), "Zero-shard paid purchase")
	reject(func() -> Dictionary: return arena.town_buy(TARGET, arena.state.revision()), "Free town supplier in formal profile")
	# Make the independent test file real and prove free test gems cannot fund normal play.
	check(arena.enter_town_test(arena.world_context().revision).ok, "Explicit test profile entry remains available")
	var normal_disk := disk(arena.NORMAL_BUILD_PATH)
	stock = arena.town_stock("skill_merchant")
	check(stock.size() == 26 and stock[0].price_label == "测试免费" and stock[0].available and not stock[0].get("paid", false), "Existing free test stock remains free and available")
	var supply: Dictionary = arena.town_buy(TARGET, arena.state.revision())
	check(supply.ok and disk(arena.NORMAL_BUILD_PATH) == normal_disk, "Test free gem is delivered without modifying normal disk")
	var test_uid: String = str(supply.get("uid", ""))
	check(not test_uid.is_empty() and arena.state.item(test_uid).definition_id == TARGET, "Test supply reports the owned free gem UID")
	check(all_unavailable(arena.normal_gem_offers()), "Paid offers are disabled in test town")
	reject(func() -> Dictionary: return arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision()), "Paid buy in test town")
	reject(func() -> Dictionary: return arena.normal_gem_trade_quote("recycle", test_uid, arena.state.revision()), "Free test gem recycle in test town")
	reject(func() -> Dictionary: return arena.state.gem_trade_quote("recycle", test_uid, arena.state.revision(), arena.NORMAL_BUILD_PATH), "Test model cannot redirect free gem recycle into normal save")
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.state.item(test_uid).is_empty(), "Returning to formal profile has no test-owned gem")
	reject(func() -> Dictionary: return arena.normal_gem_trade_quote("recycle", test_uid, arena.state.revision()), "Foreign test UID in formal town")
	# Earn all eight shards through current camp mechanics, including both real bosses.
	for cycle: int in range(2):
		check(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok, "Free tier-I actual map begins: " + str(cycle + 1))
		check(all_unavailable(arena.normal_gem_offers()) and all_unavailable(arena.town_stock("skill_merchant")), "Paid merchant disabled in actual map")
		reject(func() -> Dictionary: return arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision()), "Paid buy while in map")
		complete_map()
		check(all_unavailable(arena.normal_gem_offers()), "Paid offers remain disabled on map-complete screen")
		reject(func() -> Dictionary: return arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision()), "Paid buy before completed-map return")
		check(arena.return_to_town(arena.world_context().revision).ok, "Actual completed map returns to formal town")
		var claim: Dictionary = arena.claim_normal_rewards(arena.world_context().revision)
		check(claim.ok and claim.claimed_shards == 4 and arena.state.crafting_balance() == 4 * (cycle + 1), "Actual completion claim adds exactly four physical bag shards")
	check(arena.state.normal_journey().normal_root_kills == 50, "Two real maps count 50 roots/bosses and exclude descendants")
	# The scene binds quotes to both world context and current model identity.
	var quote: Dictionary = arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision())
	var round_trip_quote: Dictionary = arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision())
	check(quote.ok and round_trip_quote.ok and arena.leave_normal_town(arena.world_context().revision).ok, "Funded quotes captured before practice transition")
	check(all_unavailable(arena.normal_gem_offers()) and all_unavailable(arena.town_stock("skill_merchant")), "Paid stock disabled in practice arena")
	reject(func() -> Dictionary: return arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision()), "Paid buy in practice arena")
	reject(func() -> Dictionary: return arena.execute_normal_gem_trade(quote.handle, TARGET), "Captured town quote after leaving for practice")
	check(arena.enter_normal_town(arena.world_context().revision).ok, "Practice returns to formal town")
	reject(func() -> Dictionary: return arena.execute_normal_gem_trade(round_trip_quote.handle, TARGET), "Unconsumed captured town quote cannot revive on return")
	quote = arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision())
	round_trip_quote = arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision())
	var old_model: RefCounted = arena.state
	check(quote.ok and round_trip_quote.ok and arena.enter_town_test(arena.world_context().revision).ok and arena.state != old_model, "Funded quotes captured before actual profile replacement")
	reject(func() -> Dictionary: return arena.execute_normal_gem_trade(quote.handle, TARGET), "Captured quote after model replacement")
	var retired_before: Dictionary = old_model.snapshot()
	reject(func() -> Dictionary: return old_model.execute_gem_trade(quote.handle, TARGET), "Retired formal model cannot use delayed quote")
	check(old_model.snapshot() == retired_before, "Rejected delayed quote leaves retired model snapshot unchanged")
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.state != old_model, "Normal file reloads into new live model")
	reject(func() -> Dictionary: return arena.execute_normal_gem_trade(round_trip_quote.handle, TARGET), "Unconsumed old-model quote cannot revive after profile round trip")
	quote = arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision())
	var world_revision: int = arena.world_context().revision
	check(quote.ok and arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision).ok and arena.world_context().revision == world_revision, "Map draft emits context change without changing world revision")
	reject(func() -> Dictionary: return arena.execute_normal_gem_trade(quote.handle, TARGET), "World-context signal invalidates quote even when world revision is unchanged")
	quote = arena.normal_gem_trade_quote("buy", TARGET, arena.state.revision())
	check(quote.ok, "Explicit cancel starts with valid funded quote")
	var cancel_before := observe()
	arena.cancel_normal_gem_trade_quote(quote.handle)
	check(observe() == cancel_before, "Cancel changes no build/runtime/world or disk file")
	reject(func() -> Dictionary: return arena.execute_normal_gem_trade(quote.handle, TARGET), "Cancelled quote cannot execute")
	# Non-empty runtime sentinels detect charge/refill or cooldown-reset regressions.
	# Direct runtime setup is intentional because town correctly blocks flask/cast input.
	arena.health = 10.0
	arena.mana = 10.0
	var flask_slots: Array = arena.state.flask_slots()
	for slot: Dictionary in flask_slots:
		if slot.uid.is_empty(): continue
		var maximum: float = arena.get_stats().max_health if slot.resource == "health" else arena.get_stats().max_mana
		check(arena.flask_runtime.use(slot.uid, 10.0, maximum, arena.get_stats()).ok, "Runtime sentinel consumes owned flask: " + slot.slot_id)
	var sentinel_group: Dictionary = arena.state.skill_group("group_000001")
	check(arena.group_cooldowns.begin("group_000001", sentinel_group.main_uid, 3.25), "Runtime sentinel creates non-empty stable group cooldown debt")
	arena.cooldowns["dash"] = 2.5
	arena.state.changed.connect(func() -> void: changes += 1)
	var bought := trade("buy", TARGET, -8)
	if bought.is_empty():
		await finish()
		return
	var bought_uid: String = bought.uid
	check(not bought_uid.is_empty() and arena.state.item(bought_uid) == Gems.create_instance(bought_uid, TARGET) and arena.state.location(bought_uid).kind == "bag", "Bought UID is a real level-1 quality-0 gem in bag")
	var other_gems: Dictionary = {}
	for uid: String in arena.state.snapshot().items:
		if uid != bought_uid and Gems.validate_instance(arena.state.item(uid)): other_gems[uid] = arena.state.item(uid)
	check(not other_gems.is_empty(), "Selected-UID recycle has other owned gems to preserve")
	check(arena.state.move_item(bought_uid, {"kind":"skill_main", "group_id":"group_000009"}, arena.state.revision(), arena.NORMAL_BUILD_PATH).ok, "Bought exact UID equips into actual skill group")
	check(not arena.normal_gem_recycle_info(bought_uid).available, "Equipped bought gem has disabled recycle metadata")
	reject(func() -> Dictionary: return arena.normal_gem_trade_quote("recycle", bought_uid, arena.state.revision()), "Equipped bought UID cannot recycle")
	check(arena.leave_normal_town(arena.world_context().revision).ok, "Bought gem can enter actual practice combat")
	while arena.hud.is_blocking(): arena.hud.close_panel()
	arena.mana = arena.get_stats().max_mana
	var compiled: Dictionary = arena.state.get_group_cast("group_000009")
	check(compiled.ok and compiled.main_uid == bought_uid and compiled.skill_id == "shade_bolt", "Actual compiler resolves bought UID and catalog recipe")
	var projectiles_before: int = arena.projectiles.size()
	var mana_before: float = arena.mana
	check(arena.cast_group("group_000009"), "Real main accepts cast from bought/equipped gem")
	check(arena.projectiles.size() == projectiles_before + int(compiled.initial_count) and is_equal_approx(arena.mana, mana_before - float(compiled.mana)) and is_equal_approx(arena.group_cooldown_remaining("group_000009"), float(compiled.cooldown)), "Accepted cast emits exact compiled count and pays compiled mana/cooldown")
	for shot: Dictionary in arena.projectiles.slice(projectiles_before):
		check(shot.skill_id == "shade_bolt" and shot.payload == compiled.packets.projectile and is_equal_approx(shot.speed, float(compiled.recipe.speed)) and shot.pierce == compiled.recipe.pierce, "Actual projectile consumes bought gem's compiled packet and recipe")
	check(arena.enter_normal_town(arena.world_context().revision).ok, "Actual cast returns to formal town")
	check(arena.state.move_item(bought_uid, arena.state.first_bag_position(bought_uid), arena.state.revision(), arena.NORMAL_BUILD_PATH).ok, "Exact bought gem unequips back into bag")
	check(arena.normal_gem_recycle_info(bought_uid).available and arena.normal_gem_recycle_info(bought_uid).credit == 1, "Bag selected UID exposes exact one-shard recycle")
	var recycled := trade("recycle", bought_uid, 1)
	check(recycled.get("ok", false) and arena.state.item(bought_uid).is_empty() and arena.state.location(bought_uid).is_empty(), "Recycle removes only exact selected bought UID")
	for uid: String in other_gems: check(arena.state.item(uid) == other_gems[uid], "Recycle preserves every other owned gem UID: " + uid)
	reject(func() -> Dictionary: return arena.normal_gem_trade_quote("recycle", bought_uid, arena.state.revision()), "Deleted selected UID cannot recycle twice")
	await finish()

func finish() -> void:
	var after_hashes: Dictionary = {}
	for source: String in SOURCES: after_hashes[source] = FileAccess.get_sha256("res://" + source)
	check(after_hashes == source_hashes, "All captured test/main/model/catalog/UI source hashes remained stable during run")
	var output := OS.get_environment("V044_GEM_GAMEPLAY_PROOF")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks": checks, "failures": failures, "user_dir": OS.get_user_data_dir(), "source_sha256": source_hashes, "source_sha256_after": after_hashes, "coverage": "Headless actual-main integration; two camp/boss/descendant map completions; no native GUI verification", "normal_disk_sha256": FileAccess.get_sha256(arena.NORMAL_BUILD_PATH), "test_disk_sha256": FileAccess.get_sha256(arena.TOWN_TEST_BUILD_PATH), "evidence": evidence}, "\t"))
			file.close()
		else:
			check(false, "Proof output could not be written")
	print("Normal gem trade gameplay: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
