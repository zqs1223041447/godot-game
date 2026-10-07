extends SceneTree
## Bounded receipt integration: actual Main methods and canonical transactions.
## Main omits combat/_ready; a real TownServicePanel runs in the SceneTree.
## Its actual button signal and deferred refresh are checked; no native GUI claim.
## Only the capacity fixture synthesizes bag occupancy, using current catalog/rules.
const Main = preload("res://scripts/main.gd")
const TownPanel = preload("res://scripts/ui/town_service_panel.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const PATH := "user://build_save.json"
const COUNTS := ["claimed_shards", "claimed_gems", "claimed_flasks"]
const SOURCES := ["tests/reward_claim_feedback_test.gd", "scripts/main.gd", "scripts/canonical_game_state.gd", "scripts/save/canonical_build_store.gd", "scripts/save/canonical_build_rules.gd", "scripts/world/normal_journey_state.gd", "scripts/items/gem_catalog.gd", "scripts/items/item_location_rules.gd", "scripts/ui/town_service_panel.gd"]

class ReceiptMain extends Main:
	var last_response: Dictionary = {}
	func claim_normal_rewards(expected_revision: Variant) -> Dictionary:
		last_response = super.claim_normal_rewards(expected_revision)
		return last_response

class FaultModel extends Model:
	var fail_save := false
	var claim_calls := 0
	var last_claim: Dictionary = {}
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
	func normal_claim_rewards(expected_revision: Variant, path: String, include_map: bool = true) -> Dictionary:
		claim_calls += 1
		last_claim = super.normal_claim_rewards(expected_revision, path, include_map)
		return last_claim

var arena: Node
var panel: PanelContainer
var feedback_messages: Array[String] = []
var checks := 0
var failures := 0
var model_changes := 0
var world_changes := 0
var evidence: Array[Dictionary] = []
var receipts: Array[Dictionary] = []
var group := ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	evidence.append({"ok": value, "label": label})
	if not value:
		failures += 1
		push_error(label)
	return value

func accepted(result: Dictionary, label: String) -> bool:
	return check(result.get("ok") is bool and result.get("ok", false), label + ": " + str(result.get("reason", "")))

func observe() -> Dictionary:
	var snapshot: Dictionary = arena.state.snapshot()
	return {"snapshot": var_to_bytes(snapshot), "revision": arena.state.revision(),
		"serials": [snapshot.next_item_serial, snapshot.journey.next_run_id, snapshot.journey.claimed_gems, snapshot.journey.claimed_flasks],
		"balance": arena.state.crafting_balance(), "disk": FileAccess.get_file_as_bytes(PATH),
		"world": arena.world_context(), "rng": arena.rng.state,
		"successful_saves": arena.state.successful_saves, "model_changes": model_changes, "world_changes": world_changes}

func install(model: FaultModel) -> void:
	if is_instance_valid(panel): panel.free()
	if is_instance_valid(arena): arena.free()
	arena = ReceiptMain.new()
	arena.state = model
	arena.rng.seed = 102102
	model.changed.connect(func() -> void: model_changes += 1)
	arena.world_context_changed.connect(func() -> void: world_changes += 1)
	panel = TownPanel.new()
	root.add_child(panel)
	panel.setup(arena)
	panel.feedback.connect(func(message: String) -> void: feedback_messages.append(message))
	arena.world_context_changed.connect(panel.refresh_world)

func pending_fixture() -> bool:
	install(FaultModel.new())
	if not check(arena.state.save_build(PATH) == OK, "Fresh isolated canonical profile saved"): return false
	var compiled: Dictionary = Maps.compile_normal("old_garden", 1, [], [])
	if not accepted(compiled, "Compile current free tier-I map"): return false
	var entered: Dictionary = arena.state.normal_start_map(compiled.profile, arena.state.revision(), PATH)
	if not accepted(entered, "Actual model entry issues persisted run"): return false
	if not check(entered.has("run_id"), "Entry includes run ID"): return false
	var completed: Dictionary = arena.state.normal_complete_map(entered.run_id, arena.state.revision(), PATH)
	if not accepted(completed, "Actual model completion creates pending map receipt"): return false
	var before_revision: int = arena.state.revision()
	for index: int in range(60): arena.state.add_normal_root_xp(0)
	if not check(arena.state.revision() == before_revision + 60, "Sixty real reward-batch calls advance one revision each"): return false
	if not check(arena.state.save_build(PATH) == OK, "Milestone batch persisted"): return false
	var pending: Dictionary = arena.state.normal_pending_rewards()
	return check(pending.pending_map_reward.get("shards") == 4 and pending.pending_gems == 2 and pending.pending_flasks == 1 and arena.state.crafting_balance() == 0,
		"Fixture owes four map shards, two milestone gems and one milestone flask; nothing credited")

func record(label: String, result: Dictionary, before_world: Dictionary, model_called: bool) -> void:
	receipts.append({"case": label, "main_result": result.duplicate(true),
		"model_result": arena.state.last_claim.duplicate(true) if model_called else {},
		"model_called": model_called, "world_before": before_world,
		"fresh_world_context": arena.world_context(), "model_pending": arena.state.normal_pending_rewards(),
		"balance": arena.state.crafting_balance(), "model_revision": arena.state.revision(),
		"status_text": panel._reward_status.text, "feedback": feedback_messages.back() if not feedback_messages.is_empty() else "",
		"rng_state": str(arena.rng.state), "disk_sha256": FileAccess.get_sha256(PATH)})

func press_claim(label: String) -> Dictionary:
	var feedback_count := feedback_messages.size()
	arena.last_response = {}
	# Emitting directly also exercises a rapid/replayed event after the button hides.
	panel._claim.pressed.emit()
	var result: Dictionary = arena.last_response.duplicate(true)
	var immediate: String = panel._reward_status.text
	check(feedback_messages.size() == feedback_count + 1 and feedback_messages.back() == immediate, label + ": one feedback signal matches visible claim status")
	check(panel._reward_status.visible, label + ": result remains visible even when claim button hides")
	await process_frame
	check(panel._reward_status.text == immediate and feedback_messages.size() == feedback_count + 1, label + ": deferred frame preserves result without duplicate feedback")
	return result

func reject_main(expected_revision: int, expected_code: String, label: String, write_attempts: int = 0, expected_pending: String = "") -> void:
	var before := observe()
	var attempts: int = arena.state.save_attempts
	var calls: int = arena.state.claim_calls
	var result: Dictionary = arena.claim_normal_rewards(expected_revision) if expected_code == "stale_world" else await press_claim(label)
	check(result.get("ok") is bool and not result.get("ok", true), label + ": Main rejects")
	check(result.get("code") == expected_code and not str(result.get("reason", "")).is_empty(), label + ": exact error code and useful reason")
	for key: String in COUNTS: check(not result.has(key), label + ": no false " + key + " credit")
	check(not result.has("world"), label + ": failure does not reuse a successful world receipt")
	check(observe() == before, label + ": exact full snapshot, serials, balance, disk, RNG, world and notifications unchanged")
	check(arena.state.save_attempts == attempts + write_attempts, label + ": expected persistence attempts only")
	var model_called: bool = arena.state.claim_calls != calls
	check(model_called == (expected_code != "stale_world"), label + ": stale world is rejected before model claim")
	if model_called:
		var model_result: Dictionary = arena.state.last_claim
		check(model_result.get("ok") is bool and not model_result.get("ok", true) and model_result.get("error_code") == expected_code, label + ": Main preserves actual model failure")
		for key: String in COUNTS: check(not model_result.has(key), label + ": model adds no " + key + " credit")
	if expected_code != "stale_world":
		var expected_text := str(result.get("reason", "")) + ("\n" + expected_pending if not expected_pending.is_empty() else "")
		check(panel._reward_status.text == expected_text and not panel._reward_status.text.contains("已领取"), label + ": failure shows reason and fresh pending quantities without credit")
	record(label, result, before.world, model_called)

func claim(expected: Array, label: String, expected_text: String) -> bool:
	var before := observe()
	var result: Dictionary = await press_claim(label)
	record(label, result, before.world, true)
	if not accepted(result, label): return false
	check(panel._reward_status.text == expected_text, label + ": exact credited quantities and current pending categories in live panel")
	if not check(result.has_all(COUNTS) and result.get("world") is Dictionary, label + ": complete Main receipt"): return false
	var model_result: Dictionary = arena.state.last_claim
	if not accepted(model_result, label + " actual model receipt"): return false
	if not check(model_result.has_all(COUNTS), label + ": complete model receipt"): return false
	for index: int in range(COUNTS.size()):
		var key: String = COUNTS[index]
		check(result[key] is int and result[key] == expected[index] and result[key] == model_result[key], label + ": exact authoritative " + key)
	check(result.world == arena.world_context(), label + ": success includes fresh post-commit world")
	check(arena.state.revision() == int(before.revision) + 1 and int(result.world.revision) == int(before.world.revision) + 1, label + ": one model/world revision")
	check(arena.state.successful_saves == int(before.successful_saves) + 1 and model_changes == int(before.model_changes) + 1 and world_changes == int(before.world_changes) + 1, label + ": one committed save and each notification")
	check(arena.rng.state == before.rng and arena.state.crafting_balance() == int(before.balance) + int(expected[0]), label + ": exact shard delta without RNG use")
	var reloaded := FaultModel.new()
	if not check(reloaded.load_build(PATH), label + ": committed file reloads"): return false
	check(reloaded.snapshot() == arena.state.snapshot(), label + ": persisted state exactly matches receipt owner")
	return true

func reload_pending(label: String) -> bool:
	var before := observe()
	var expected: Dictionary = arena.state.snapshot()
	var pending: Dictionary = arena.state.normal_pending_rewards()
	var reloaded := FaultModel.new()
	if not check(reloaded.load_build(PATH), label + ": actual load succeeds"): return false
	check(reloaded.snapshot() == expected and reloaded.normal_pending_rewards() == pending, label + ": full state and every pending category preserved")
	install(reloaded)
	var recovery: Dictionary = arena._recover_normal_active()
	if not accepted(recovery, label + " actual Main recovery"): return false
	check(arena.state.snapshot() == expected and arena.state.normal_pending_rewards() == pending and FileAccess.get_file_as_bytes(PATH) == before.disk,
		label + ": recovery leaves settled pending rewards and exact disk bytes intact")
	check(arena.world_context().can_claim_normal_rewards, label + ": recovered town exposes pending claim")
	return true

func full_group() -> void:
	if not pending_fixture(): return
	var before := observe()
	var attempts: int = arena.state.save_attempts
	var pending: Dictionary = arena.state.normal_pending_rewards()
	pending.pending_map_reward.shards = 999
	pending.pending_gems = 999
	pending.pending_flasks = 999
	var context: Dictionary = arena.world_context()
	context.pending_map_reward.shards = 888
	context.pending_gems = 888
	check(observe() == before and arena.state.save_attempts == attempts, "Detached pending/world reads cannot mutate snapshot, revisions, disk, saves, RNG or notifications")
	var old_model_revision: int = arena.state.revision()
	var old_world_revision: int = arena.world_context().revision
	var old_items: Dictionary = arena.state.snapshot().items
	if not await claim([4, 2, 1], "full_claim", "已领取：校准碎片 ×4 · 宝石 ×2 · 药剂 ×1"): return
	var definitions: Array = []
	for uid: String in arena.state.snapshot().items:
		if not old_items.has(uid): definitions.append(arena.state.item(uid).definition_id)
	check(definitions.size() == 4 and definitions.has(Model.Journey.gem_definition(1)) and definitions.has(Model.Journey.gem_definition(2)) and definitions.has(Model.Journey.flask_definition(1)), "Exact frozen milestone ordinals materialize alongside one currency stack")
	var world: Dictionary = arena.world_context()
	check(world.pending_map_reward.is_empty() and world.pending_gems == 0 and world.pending_flasks == 0 and not world.can_claim_normal_rewards, "Full claim leaves no pending categories")
	await reject_main(old_world_revision, "stale_world", "duplicate_world_receipt")
	await reject_main(int(arena.world_context().revision), "no_pending_reward", "fresh_repeat_after_full_claim")
	before = observe()
	attempts = arena.state.save_attempts
	var stale: Dictionary = arena.state.normal_claim_rewards(old_model_revision, PATH)
	check(not stale.get("ok", true) and stale.get("error_code") == "stale_revision", "Actual model rejects duplicate stale revision")
	for key: String in COUNTS: check(not stale.has(key), "Stale model result has no " + key)
	check(observe() == before and arena.state.save_attempts == attempts, "Stale model claim preserves full snapshot, serials, disk, balance, RNG and notifications")

func fill_bag() -> bool:
	# Synthetic occupancy only; no rewards, journey state or balances are fabricated.
	# Build one current catalog item and clone its valid envelope. One final _commit
	# validates all cells, avoiding a full metadata sort for each inserted gem.
	var candidate: Dictionary = arena.state.snapshot()
	for uid: String in candidate.locations.keys():
		if candidate.locations[uid].kind == "bag":
			candidate.locations.erase(uid)
			candidate.items.erase(uid)
	var template: Dictionary = Gems.create_instance("item_%06d" % int(candidate.next_item_serial), "support:efficiency")
	if not check(not template.is_empty() and Gems.definition("support:efficiency").get("size") == [1, 1], "Current catalog supplies a real one-cell occupancy gem"): return false
	for page: int in range(Locations.CURRENT_BAG_PAGES):
		for y: int in range(Locations.CURRENT_BAG_ROWS):
			for x: int in range(Locations.CURRENT_BAG_COLUMNS):
				var uid := "item_%06d" % int(candidate.next_item_serial)
				var wrapped: Dictionary = template.duplicate(true)
				wrapped.uid = uid
				candidate.items[uid] = wrapped
				candidate.locations[uid] = {"kind": "bag", "page": page, "x": x, "y": y}
				candidate.next_item_serial += 1
	candidate.revision += 1
	var result: Dictionary = arena.state._commit(candidate, PATH)
	return accepted(result, "Synthetic full occupancy passes current canonical schema and item validation")

func discard_cell(x: int, y: int) -> bool:
	var snapshot: Dictionary = arena.state.snapshot()
	for uid: String in snapshot.locations:
		var location: Dictionary = snapshot.locations[uid]
		if location == {"kind": "bag", "page": 0, "x": x, "y": y}:
			var result: Dictionary = arena.state.discard_item(uid, arena.state.revision(), PATH)
			return accepted(result, "Real discard frees bag cell %d,%d" % [x, y])
	return check(false, "Expected occupied fixture cell exists")

func capacity_group() -> void:
	if not pending_fixture() or not fill_bag(): return
	await reject_main(int(arena.world_context().revision), "bag_full", "nothing_fits", 0, "待领：校准碎片 ×4 · 宝石 ×2 · 药剂 ×1")
	if not reload_pending("full_bag_reload"): return
	if not discard_cell(0, 0): return
	var old_revision: int = arena.world_context().revision
	if not await claim([4, 0, 0], "partial_map_only", "已领取：校准碎片 ×4\n待领：宝石 ×2 · 药剂 ×1"): return
	var pending: Dictionary = arena.state.normal_pending_rewards()
	check(pending.pending_map_reward.is_empty() and pending.pending_gems == 2 and pending.pending_flasks == 1, "Partial claim credits only map shards and retains every unplaced gem/flask")
	await reject_main(old_revision, "stale_world", "duplicate_partial_receipt")
	await reject_main(int(arena.world_context().revision), "bag_full", "fresh_repeat_still_full", 0, "待领：宝石 ×2 · 药剂 ×1")
	if not reload_pending("partial_claim_reload"): return
	# Two 1x1 holes allow the gems but cannot fit the current 1x2 flask.
	if not discard_cell(1, 0) or not discard_cell(2, 0): return
	if not await claim([0, 2, 0], "partial_gems_only", "已领取：宝石 ×2\n待领：药剂 ×1"): return
	pending = arena.state.normal_pending_rewards()
	check(pending.pending_gems == 0 and pending.pending_flasks == 1, "Gems clear their own backlog while flask remains pending")
	if not discard_cell(3, 0) or not discard_cell(3, 1): return
	if not await claim([0, 0, 1], "remaining_flask", "已领取：药剂 ×1"): return
	check(not arena.world_context().can_claim_normal_rewards, "Capacity recovery exhausts owed rewards exactly once")
	await reject_main(int(arena.world_context().revision), "no_pending_reward", "fresh_repeat_after_capacity_recovery")

func persistence_group() -> void:
	if not pending_fixture(): return
	arena.state.fail_save = true
	await reject_main(int(arena.world_context().revision), "save_failed", "persistence_fault", 1, "待领：校准碎片 ×4 · 宝石 ×2 · 药剂 ×1")
	if not reload_pending("failed_claim_reload"): return
	if not await claim([4, 2, 1], "recovered_claim", "已领取：校准碎片 ×4 · 宝石 ×2 · 药剂 ×1"): return
	await reject_main(int(arena.world_context().revision), "no_pending_reward", "fresh_repeat_after_save_recovery")

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v102-"):
		push_error("This write test requires a fresh /tmp/godot-m1-v102-* XDG_DATA_HOME")
		quit(78)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="): group = argument.trim_prefix("--group=")
	if group not in ["full", "capacity", "persistence"] or FileAccess.file_exists(PATH):
		push_error("Choose --group=full|capacity|persistence with a fresh isolated userdata directory")
		quit(78)
		return
	var started := Time.get_ticks_msec()
	match group:
		"full": await full_group()
		"capacity": await capacity_group()
		"persistence": await persistence_group()
	var hashes: Dictionary = {}
	for path: String in SOURCES: hashes[path] = FileAccess.get_sha256("res://" + path)
	var report := {"group": group, "checks": checks, "failures": failures, "duration_ms": Time.get_ticks_msec() - started,
		"engine": Engine.get_version_info().string, "source_hashes": hashes,
		"scope": "Actual Main + canonical persistence + live TownServicePanel button/deferred feedback; no native GUI or combat simulation", "assertions": evidence, "receipts": receipts}
	var output_path := OS.get_environment("V102_REWARD_REPORT")
	if not output_path.is_empty():
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		if output == null:
			check(false, "Evidence report path is writable")
		else:
			output.store_string(JSON.stringify(report, "\t"))
			output.close()
	if is_instance_valid(panel): panel.free()
	if is_instance_valid(arena): arena.free()
	print("Reward claim feedback [%s]: %d checks, %d failures" % [group, checks, failures])
	quit(1 if failures else 0)
