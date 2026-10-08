extends SceneTree
## Bounded actual Main/HUD/death-ledger integration. Fixtures only fill bag
## capacity or inject write errors; map admission, rewards and completion run live.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const PATH := "user://build_save.json"

class FaultModel extends Model:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path, bytes)

class ObservedMain extends "res://scripts/main.gd":
	var boss_awards: Array[Dictionary] = []
	func _award_kill_equipment(enemy: Dictionary) -> void:
		if enemy.get("rarity", "") != "boss":
			super._award_kill_equipment(enemy)
			return
		var before: Dictionary = state.snapshot()
		var uid: String = "gear_%06d" % int(before.next_item_serial)
		var oracle := RandomNumberGenerator.new()
		oracle.state = rng.state
		var pool: String = str(enemy.get("equipment_pool", ""))
		if pool == "defense": pool = Gear.CURRENT_DEFENSE_POOL_ID
		var item_level: int = clampi(wave * 2 - 1, 1, 30)
		var generated: Dictionary = Gear.generate_loot_profile(oracle, uid, item_level, "rare", Build.LOOT_PROFILE_ID) if pool.is_empty() else Gear.generate_for_pool(oracle, uid, item_level, "rare", pool)
		super._award_kill_equipment(enemy)
		boss_awards.append({"uid": uid, "before": before, "expected": Build.Items.wrap_equipment(generated),
			"item": state.item(uid), "location": state.location(uid), "rng": str(rng.state), "expected_rng": str(oracle.state),
			"pool": pool, "item_level": item_level})

var arena: Node2D
var model: FaultModel
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var awards: Array[Dictionary] = []
var group := ""
var filler_uids: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	evidence.append({"case": group, "ok": ok, "label": label})
	if not ok: failures.append(group + ": " + label); push_error(group + ": " + label)
	return ok
func accepted(result: Dictionary, label: String) -> bool:
	return check(bool(result.get("ok", false)), label + ": " + str(result.get("reason", "")))
func disk() -> PackedByteArray: return FileAccess.get_file_as_bytes(PATH)
func observe() -> Array:
	return [model.snapshot(), disk(), arena.rng.state, model.successful_saves, arena.reward_kills, arena._map_run.snapshot()]
func pause() -> void:
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	for unused: int in range(4): arena.hud.close_panel()
func dispose() -> void:
	if is_instance_valid(arena): arena.queue_free(); await process_frame
	arena = null; model = null
func fresh(label: String, test_profile: bool = false) -> bool:
	group = label
	await dispose()
	for path: String in [PATH, "user://town_test_build_save.json"]:
		if FileAccess.file_exists(path):
			if not check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only isolated suite save"): return false
	arena = load("res://scenes/main.tscn").instantiate()
	arena.set_script(ObservedMain)
	model = FaultModel.new(); arena.state = model
	root.add_child(arena); pause(); await process_frame
	if not check(arena.world_context().normal_town and arena.save_build(), "Actual Main opens and saves formal town"): return false
	arena.rng.seed = 550155
	if test_profile:
		if not accepted(arena.enter_town_test(arena.world_context().revision), "Enter existing independent test town"): return false
		model = FaultModel.new()
		if not check(model.load_build(arena.TOWN_TEST_BUILD_PATH), "Open independent test save"): return false
		arena._replace_build(model, arena.TOWN_TEST_BUILD_PATH)
	else:
		if not accepted(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision), "Select actual free tier-I map"): return false
	if not accepted(arena.start_map(arena.map_draft().revision), "Actual map admission"): return false
	pause(); filler_uids.clear()
	return check(arena.enemies.size() == 25 and arena._map_run.boss_id > 0 and arena.world_context().mode == "map", "Actual map registers 24 ordinary roots and one boss")
func boss() -> Dictionary:
	for enemy: Dictionary in arena.enemies:
		if int(enemy.id) == arena._map_run.boss_id: return enemy
	return {}
func kill(enemy: Dictionary) -> void:
	enemy.spawn = 0.0
	arena._begin_progress_transaction()
	arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 10000.0, Color.WHITE)
	arena._end_progress_transaction()
func fill_bag(existing_pending: bool = false) -> String:
	var candidate: Dictionary = model.snapshot()
	var occupied: Dictionary = {}
	var metadata: Dictionary = Model.Items.metadata_for_items(candidate.items)
	for uid: String in candidate.locations:
		var location: Dictionary = candidate.locations[uid]
		if location.kind != "bag": continue
		for y: int in range(location.y, location.y + int(metadata[uid].size[1])):
			for x: int in range(location.x, location.x + int(metadata[uid].size[0])):
				occupied[Vector3i(location.page, x, y)] = true
	for page: int in range(Locations.CURRENT_BAG_PAGES):
		for y: int in range(Locations.CURRENT_BAG_ROWS):
			for x: int in range(Locations.CURRENT_BAG_COLUMNS):
				if occupied.has(Vector3i(page, x, y)): continue
				var uid: String = "item_%06d" % int(candidate.next_item_serial)
				candidate.next_item_serial += 1
				candidate.items[uid] = Gems.create_instance(uid, "support:efficiency")
				candidate.locations[uid] = {"kind": "bag", "page": page, "x": x, "y": y}
				filler_uids.append(uid)
	var pending := ""
	if existing_pending:
		pending = "item_%06d" % int(candidate.next_item_serial)
		candidate.next_item_serial += 1
		candidate.items[pending] = Gems.create_instance(pending, "support:efficiency")
		candidate.locations[pending] = {"kind": "recovery", "index": candidate.items.size() - 1}
	candidate.revision += 1
	check(model._commit(candidate, arena.build_save_path).ok, "Capacity-only fixture preserves all real items and passes canonical commit")
	check(occupied.size() + filler_uids.size() == Locations.CURRENT_BAG_PAGES * Locations.CURRENT_BAG_COLUMNS * Locations.CURRENT_BAG_ROWS, "Both real bag pages are completely full")
	return pending
func verify_award(kind: String) -> Dictionary:
	if not check(arena.boss_awards.size() == 1, "Registered boss invokes one original equipment decision"): return {}
	var receipt: Dictionary = arena.boss_awards[0]
	check(receipt.item == receipt.expected and not receipt.item.is_empty(), "Exact first original pool roll, UID, level and rare affixes retained")
	check(receipt.rng == receipt.expected_rng, "No reroll or alternative loot selection consumes RNG")
	check(receipt.location.get("kind") == kind, "Unique boss instance enters " + kind)
	check(model.snapshot().version == 55 and Model.Rules.reason(model.snapshot()).is_empty(), "Unchanged schema55 validates complete build")
	check(model.normal_journey().normal_root_kills == 1 and arena.reward_kills == 1 and arena._map_run.boss_defeated, "Actual once-only formal death records one kill")
	var changed_uids: Array[String] = []
	for uid: String in receipt.before.items:
		if model.item(uid) != receipt.before.items[uid] or model.location(uid) != receipt.before.locations[uid]: changed_uids.append(uid)
	check(changed_uids.is_empty(), "Every existing item and authoritative location preserved; differing UIDs: " + str(changed_uids))
	awards.append({"case": group, "uid": receipt.uid, "item": receipt.item, "location": receipt.location, "pool": receipt.pool, "item_level": receipt.item_level})
	return receipt
func repeated_death(enemy: Dictionary) -> void:
	var before := observe()
	var decisions: int = arena.boss_awards.size()
	for unused: int in range(3): arena._finish_enemy_death(enemy, false)
	check(observe() == before and arena.boss_awards.size() == decisions, "Repeated same dead dictionary cannot duplicate reward/save/RNG")
	var copy: Dictionary = enemy.duplicate(true)
	copy.death_processed = false
	arena._finish_enemy_death(copy, false)
	check(observe() == before and arena.boss_awards.size() == decisions, "Root ledger also rejects reconstructed same identity")
func reload_exact(label: String) -> Model:
	var restored := Model.new()
	check(restored.load_build(arena.build_save_path) and restored.snapshot() == model.snapshot(), label)
	return restored
func normal_case() -> void:
	if not await fresh("normal bag"): return
	var target := boss(); kill(target)
	var receipt := verify_award("bag")
	if receipt.is_empty(): return
	check(model.snapshot().next_item_serial == receipt.before.next_item_serial + 2, "Original normal bag gear plus unchanged special-jewel reward allocate one serial each")
	check(model.pending_items().is_empty(), "Normal bag admission adds no recovery")
	repeated_death(target); reload_exact("Normal rare gear and existing rewards survive exact canonical reload")
func full_case(existing_pending: bool, fail_save: bool) -> void:
	if not await fresh("full bag / pending=%s / write fault=%s" % [existing_pending, fail_save]): return
	var pending := fill_bag(existing_pending)
	var target := boss()
	var before_disk := disk()
	var before_state := model.snapshot()
	var saves: int = model.successful_saves
	model.fail_writes = fail_save
	kill(target)
	var receipt := verify_award("recovery")
	if receipt.is_empty(): return
	check(model.snapshot().next_item_serial == receipt.before.next_item_serial + 1, "Full bag allocates only boss gear; special jewel follows original refusal rule")
	check(model.pending_items() == ([pending, receipt.uid] if existing_pending else [receipt.uid]), "Append preserves original pending queue and one new UID")
	if fail_save:
		check(disk() == before_disk and model.successful_saves == saves and arena._progress_save_dirty, "Failed batch write keeps exact prior disk and complete new memory dirty")
		var old := Model.new()
		check(old.load_build(PATH) and old.snapshot() == before_state, "Reload of failed write sees complete prior canonical snapshot")
		var expected := model.snapshot()
		repeated_death(target)
		check(not arena.save_build() and model.snapshot() == expected and disk() == before_disk, "Explicit failed retry neither rolls back part of reward nor half-writes")
		model.fail_writes = false
		check(arena.save_build() and model.snapshot() == expected and not arena._progress_save_dirty, "Retry saves exact retained UID/affixes without reminting")
	else:
		check(model.successful_saves == saves + 1 and disk() != before_disk, "Death reward batch makes one successful complete save")
		repeated_death(target)
	reload_exact("Full-bag pending gear survives exact canonical reload")
	if existing_pending:
		var prior: Dictionary = model.snapshot()
		await dispose()
		arena = load("res://scenes/main.tscn").instantiate(); arena.set_script(ObservedMain)
		model = FaultModel.new(); arena.state = model
		root.add_child(arena); pause(); await process_frame
		check(arena.world_context().normal_town and model.normal_journey().active_run.is_empty(), "Actual Main reload uses existing safe active-map abandonment")
		check(model.snapshot().items == prior.items and model.snapshot().locations == prior.locations and model.snapshot().next_item_serial == prior.next_item_serial and model.normal_journey().normal_root_kills == prior.journey.normal_root_kills, "Actual game reload preserves complete gear/pending inventory and issues no additional rewards")
		check(model.normal_journey().best_tiers.old_garden == 0 and model.crafting_balance() == 0 and model.normal_journey().pending_map_reward.is_empty(), "Reload of unfinished map adds no unlock, fee refund or completion receipt")
		repeated_death(target)
	arena.hud.open_panel("inventory"); await process_frame; await process_frame
	var panel: Control = arena.hud._inventory_panel
	panel.refresh()
	check(panel._pending.visible and panel._pending.get_child(1).get_child_count() == model.pending_items().size(), "Original pending UI lists every old/new item")
	var before := observe()
	panel._pending.get_child(1).get_child(model.pending_items().find(receipt.uid)).pressed.emit()
	check(observe() == before, "Actual pending button refuses full bag without item/save/RNG mutation")
	# Free a contiguous rectangle using canonical discard, preserving all real items.
	for uid: String in filler_uids:
		var location: Dictionary = model.location(uid)
		if location.page == 1 and location.x >= 10 and location.y >= 7:
			accepted(model.discard_item(uid, model.revision(), PATH), "Canonical discard frees fixture cell")
	check(not model.first_bag_position(receipt.uid).is_empty(), "Original placement planner finds contiguous gear space")
	panel.refresh()
	before = observe(); model.fail_writes = true
	panel._pending.get_child(1).get_child(model.pending_items().find(receipt.uid)).pressed.emit()
	check(observe() == before, "Failed original UI move commit preserves memory/disk/serials and pending gear")
	model.fail_writes = false
	panel._pending.get_child(1).get_child(model.pending_items().find(receipt.uid)).pressed.emit()
	await process_frame; panel.refresh()
	check(model.location(receipt.uid).kind == "bag" and model.item(receipt.uid) == receipt.expected, "Same actual pending button returns same UID and all original affixes")
	check(model.pending_items() == ([pending] if existing_pending else []), "Take-back leaves existing pending item intact")
	reload_exact("Retrieved original gear survives exact reload")
	repeated_death(target)
	if existing_pending: return
	while arena.hud.is_blocking(): arena.hud.close_panel()
	# Finish this real map to check the unchanged unlock/receipt authority.
	arena._begin_progress_transaction()
	for unused: int in range(8):
		for enemy: Dictionary in arena.enemies.duplicate():
			if float(enemy.health) > 0.0:
				enemy.spawn = 0.0; arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 10000.0, Color.WHITE)
		arena._flush_monster_spawns()
	arena._check_map_complete(); arena._end_progress_transaction()
	check(arena.world_context().mode == "map_complete" and model.normal_journey().best_tiers.old_garden == 1 and model.normal_journey().pending_map_reward.get("shards") == 4, "Actual finite map still unlocks tier-I and creates original four-shard receipt")
	check(arena.reward_kills == 25 and model.normal_journey().normal_root_kills == 25 and arena.boss_awards.size() == 1, "Complete actual roster rewards exactly 25 roots and one boss decision")
	check(model.crafting_balance() == 0, "Recovery creates no currency source or automatic settlement credit")
	accepted(arena.return_to_town(arena.world_context().revision), "Original completed-map return succeeds")
	for uid: String in filler_uids:
		var location: Dictionary = model.location(uid)
		if location.get("kind") == "bag" and location.page == 1 and location.x in [8, 9] and location.y >= 7:
			accepted(model.discard_item(uid, model.revision(), PATH), "Canonical organizing frees settlement space after ordinary drops")
	accepted(arena.claim_normal_rewards(arena.world_context().revision), "Original settlement claim succeeds after organizing")
	check(model.crafting_balance() == 4 and model.normal_journey().pending_map_reward.is_empty(), "Existing one-time settlement credits exactly four physical shards")
	accepted(arena.craft_normal_map("old_garden", 2, [], [], arena.map_draft().revision), "Original completion unlocks tier-II draft")
	var fee: int = int(arena._map_draft_profile.fee)
	accepted(arena.start_map(arena.map_draft().revision), "Original paid tier-II entry succeeds")
	check(fee > 0 and model.crafting_balance() == 4 - fee, "Existing map fee is still debited exactly once")
func pending_with_room_case() -> void:
	if not await fresh("existing pending / room in bag"): return
	var pending := fill_bag(true)
	for uid: String in filler_uids:
		var location: Dictionary = model.location(uid)
		if location.page == 1 and location.x >= 10 and location.y >= 7:
			accepted(model.discard_item(uid, model.revision(), PATH), "Canonical organizing creates room while old pending remains")
	var target := boss(); kill(target)
	var receipt := verify_award("bag")
	if receipt.is_empty(): return
	check(model.pending_items() == [pending] and model.snapshot().next_item_serial == receipt.before.next_item_serial + 1, "Existing pending does not prevent boss bag placement or duplicate unrelated rewards")
	repeated_death(target); reload_exact("Boss bag gear coexists with old pending after exact reload")
func isolation_case() -> void:
	if not await fresh("test profile isolation", true): return
	fill_bag()
	var formal_disk := disk()
	var serial: int = model.snapshot().next_item_serial
	var target := boss(); kill(target)
	check(model.pending_items().is_empty() and model.snapshot().next_item_serial == serial and arena.boss_awards[0].item.is_empty(), "Test boss full bag keeps original refusal; no formal recovery")
	check(disk() == formal_disk, "Test death never writes formal save")
	if not await fresh("ordinary and demo isolation"): return
	fill_bag()
	var ordinary: Dictionary = {}
	for enemy: Dictionary in arena.enemies:
		if enemy.id != arena._map_run.boss_id: ordinary = enemy; break
	# Exercise the shared ordinary award even if this root's rarity isn't rare.
	var before := observe()
	arena._award_kill_equipment(ordinary)
	check(observe() == before and model.pending_items().is_empty(), "Non-boss full-bag gear path retains original no-award/RNG rollback")
	before = observe(); arena.demo_mode = true
	kill(boss())
	check(model.snapshot() == before[0] and disk() == before[1] and arena.reward_kills == 0 and arena.boss_awards.is_empty(), "Demo boss death does not enter formal reward path")
func guards_case() -> void:
	if not await fresh("model guards and limits"): return
	var random := RandomNumberGenerator.new(); random.seed = 5501
	var before := observe(); var random_before: int = random.state
	check(model.award_normal_boss_equipment(random, 1, "current", arena._normal_run_id + 1).is_empty() and observe() == before and random.state == random_before, "Mismatched persisted run rejected before generating loot")
	check(model.award_normal_boss_equipment(random, 1, "unknown_pool", arena._normal_run_id).is_empty() and observe() == before and random.state == random_before, "Unknown registry pool rejected without mutation")
	var original := model.snapshot()
	for limit: String in ["next_item_serial", "revision"]:
		var candidate: Dictionary = original.duplicate(true); candidate[limit] = Model.Rules.MAX_SERIAL
		check(Model.Rules.reason(candidate).is_empty(), "Exhausted " + limit + " fixture remains legal schema55")
		model._accept_memory(candidate); before = observe(); random_before = random.state
		check(model.award_normal_boss_equipment(random, 1, "current", arena._normal_run_id).is_empty() and observe() == before and random.state == random_before, "Exhausted " + limit + " prevents reward and consumes no RNG")
	model._accept_memory(original)
	var candidate: Dictionary = original.duplicate(true)
	while candidate.items.size() < Model.Rules.V17_MAX_ITEMS:
		var uid: String = "item_%06d" % int(candidate.next_item_serial)
		candidate.next_item_serial += 1
		candidate.items[uid] = Gems.create_instance(uid, "support:efficiency")
		candidate.locations[uid] = {"kind": "recovery", "index": candidate.items.size() - 1}
	check(Model.Rules.reason(candidate).is_empty(), "Reward item-cap fixture passes unchanged canonical rules")
	model._accept_memory(candidate); before = observe(); random_before = random.state
	check(model.award_normal_boss_equipment(random, 1, "current", arena._normal_run_id).is_empty() and observe() == before and random.state == random_before, "Original item cap remains mandatory and failed admission restores RNG")
	model._accept_memory(original)
	accepted(model.normal_abandon_map(arena._normal_run_id, model.revision(), PATH), "Original active-run abandonment")
	before = observe(); random_before = random.state
	check(model.award_normal_boss_equipment(random, 1, "current", arena._normal_run_id).is_empty() and observe() == before and random.state == random_before, "Absent active map cannot mint recovery gear")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-formal-boss-recovery."): quit(78); return
	await normal_case()
	await full_case(false, false)
	await full_case(true, true)
	await pending_with_room_case()
	await isolation_case()
	await guards_case()
	check(checks > 100 and awards.size() == 4, "All bounded scenarios actually executed")
	await dispose()
	var hashes: Dictionary = {}
	for source: String in ["scripts/main.gd", "scripts/canonical_game_state.gd", "scripts/save/canonical_build_rules.gd", "scripts/save/canonical_build_store.gd", "scripts/items/item_location_rules.gd", "scripts/items/equipment_catalog.gd", "scripts/ui/canonical_inventory_panel.gd", "tests/formal_boss_equipment_recovery_test.gd"]:
		hashes[source] = FileAccess.get_sha256("res://" + source)
	var report := {"checks": checks, "failures": failures.size(), "failed_labels": failures, "evidence": evidence, "awards": awards, "source_sha256": hashes, "display": DisplayServer.get_name(), "schema": Model.Rules.VERSION}
	var target := OS.get_environment("FORMAL_BOSS_RECOVERY_REPORT")
	if not target.is_empty():
		var output := FileAccess.open(target, FileAccess.WRITE); output.store_string(JSON.stringify(report, "\t") + "\n"); output.close()
	print("FORMAL_BOSS_EQUIPMENT_RECOVERY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
