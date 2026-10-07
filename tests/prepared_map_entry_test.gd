extends SceneTree
## Isolated v115 entry transactions against real Main and the real save writer.
## Reuses v114's earned tier-I reward; never replays combat or grants currency.
const Session = preload("res://scripts/studies/modular_study_session.gd")
const PreparedEntry = preload("res://scripts/world/prepared_map_entry.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const FIXTURE := "/tmp/godot-m1-v114-closure/data/godot-game-preview-v021/build_save.json"
const SAVE := "user://build_save.json"

class FaultModel extends Model:
	var fail_save := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)

var arena: Node2D
var checks := 0
var failures := 0
var fixture_bytes := PackedByteArray()
var failed_labels: Array[String] = []
var cancelling_session: RefCounted
var callback_entry: RefCounted
var callback_geometry: RefCounted
var callback_count := 0
var callback_retained := false
var callback_duplicate: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		failed_labels.append(label)
		printerr("PREPARED_ENTRY_FAIL: " + label)
	return value


func accepted(result: Dictionary, label: String) -> bool:
	return check(bool(result.get("ok", false)), label + ": " + str(result.get("reason", result.get("error", ""))))


func pause() -> void:
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	for unused: int in range(4):
		arena.hud.close_panel()


func fresh(tier: int = 1) -> bool:
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
		arena = null
	var save := FileAccess.open(SAVE, FileAccess.WRITE)
	if not check(save != null, "Isolated save accepts the untouched earned fixture"):
		return false
	save.store_buffer(fixture_bytes)
	save.close()
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	pause()
	await process_frame
	pause()
	var model := FaultModel.new()
	if not accepted({"ok": model.load_build(SAVE)}, "Real FaultModel reloads the copied canonical envelope"):
		return false
	arena._replace_build(model, SAVE)
	arena.rng.seed = 8611507
	if not check(arena.world_context().normal_town and model.normal_journey().best_tiers.old_garden == 1 \
		and model.normal_journey().normal_root_kills == 25 and model.crafting_balance() == 4 \
		and model.normal_journey().active_run.is_empty() and model.normal_journey().pending_map_reward.is_empty(),
		"Fixture supplies exactly four previously earned shards and only tier-II unlock"):
		return false
	return accepted(arena.craft_normal_map("old_garden", tier, [], [], arena.map_draft().revision),
		"Fresh lawful old_garden tier %d draft" % tier)


func authority() -> Dictionary:
	# Object identity is separate from detached bytes. A different geometry with
	# equal metadata is still an observable, forbidden failed-entry mutation.
	return {"model_id": arena.state.get_instance_id(), "model": var_to_bytes(arena.state.snapshot()),
		"disk": FileAccess.get_file_as_bytes(SAVE), "geometry_id": arena._geometry.get_instance_id(),
		"geometry": var_to_bytes(arena._geometry.snapshot()), "world": var_to_bytes(arena.world_context()),
		"draft": var_to_bytes([arena.map_draft(), arena._map_draft_profile]),
		"runtime": var_to_bytes([Encounter._snapshot(arena.monster_runtime), arena.monster_runtime.templates,
			arena.monster_runtime.validation_errors]), "run": var_to_bytes(arena._map_run.snapshot()),
		"actors": var_to_bytes(arena.enemies), "records": var_to_bytes(arena.map_spawn_records()),
		"rng": var_to_bytes([arena.rng.seed, arena.rng.state]),
		"main": var_to_bytes([arena.run_revision, arena._normal_run_id, arena.ARENA, arena.player_pos,
			arena.get_node("WorldCamera").position, arena.elapsed, arena.health, arena.mana, arena.shield,
			arena.alive, arena.kills, arena.reward_kills, arena.player_facing, arena.projectiles,
			arena.projectile_runtime.next_cast_id, arena.projectile_runtime.next_projectile_id,
			arena.cooldowns, arena.attack_timer, arena._simulation_accumulator, arena._camp_landmarks,
			arena.map_mechanism_state()])}


func unchanged(before: Dictionary, label: String) -> void:
	var after := authority()
	for key: String in before:
		check(before[key] == after[key], label + " preserves " + key)


func released(geometry: RefCounted, label: String) -> void:
	check(geometry != null and not geometry._study_active and not geometry._space.is_valid() \
		and geometry._bodies.is_empty() and geometry._shapes.is_empty() and geometry._polygons.is_empty() \
		and geometry._body_contours.is_empty() and geometry._native_probes.is_empty() \
		and geometry._query_circle == null and not geometry.physics_ready(), label)


func launch_prepare(session: RefCounted, ticket: Dictionary) -> void:
	ticket.result = await session.prepare_entry(arena)
	ticket.done = true


func finish_prepare(ticket: Dictionary) -> Dictionary:
	# The contract waits two physics frames. This budget detects a lost coroutine
	# while keeping a failing focused test bounded, without ticking Main combat.
	for unused: int in range(12):
		if ticket.done:
			return ticket.result
		await physics_frame
	check(false, "Preparation settles within twelve physics frames")
	return {"ok": false, "reason": "Preparation did not settle"}


func test_wait_cancel_and_concurrency() -> void:
	if not await fresh(): return
	var session := Session.new()
	var before := authority()
	var ticket := {"done": false, "result": {}}
	launch_prepare(session, ticket)
	var entry: RefCounted = session._entry
	var candidate: RefCounted = entry.geometry_ref()
	check(not ticket.done and entry.phase() == "preparing" and candidate._space.is_valid(),
		"Preparing owns a detached native space before the first physics await")
	check(not candidate.is_clear(Layout.layout("old_garden", View.exploration_arena()).landmarks.entry, 15.0),
		"Pre-readiness native queries fail closed")
	unchanged(before, "Waiting for native synchronization")
	var duplicate: Dictionary = await session.prepare_entry(arena)
	check(not duplicate.ok and session._entry == entry, "Concurrent prepare rejects without replacing the original owner")
	check(not session.enter(arena).ok and entry.phase() == "preparing", "Entry before readiness cannot start or consume preparation")
	await physics_frame
	unchanged(before, "First physics frame")
	session.cancel_entry()
	check(entry.phase() == "cancelled" and entry.geometry_ref() == null, "Mid-await cancel invalidates the handle immediately")
	released(candidate, "Mid-await cancel releases every native resource immediately")
	var result := await finish_prepare(ticket)
	check(not result.ok and not session.enter(arena).ok, "Cancelled coroutine settles as failure and cannot enter")
	unchanged(before, "Cancellation and rejected concurrent calls")
	var retry: Dictionary = await session.prepare_entry(arena)
	if accepted(retry, "Same session may prepare again after cancellation settles"):
		var retry_geometry: RefCounted = retry.entry.geometry_ref()
		session.cancel_entry()
		released(retry_geometry, "Ready cancellation also releases all native ownership")
	unchanged(before, "Cancelled ready retry")


func test_stale_await(kind: String) -> void:
	if not await fresh(): return
	var session := Session.new()
	var ticket := {"done": false, "result": {}}
	launch_prepare(session, ticket)
	var entry: RefCounted = session._entry
	var candidate: RefCounted = entry.geometry_ref()
	match kind:
		"draft":
			accepted(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision), "Concurrent fresh draft")
		"world":
			arena._world_revision += 1
		"model_revision":
			var next: Dictionary = arena.state.snapshot()
			next.revision += 1
			accepted(arena.state._commit(next, SAVE), "Concurrent no-content model revision commits normally")
		"model_identity":
			var replacement := FaultModel.new()
			check(replacement.load_build(SAVE), "Replacement model loads the exact same revision")
			check(replacement.revision() == arena.state.revision(), "Model swap changes identity without changing revision")
			arena._replace_build(replacement, SAVE)
		"rng":
			arena.rng.randi()
		"runtime":
			arena.monster_runtime.next_id += 1
		"runtime_templates":
			# Native preparation must not bless a different source roster just
			# because its live identity cursor and lineage checkpoint are equal.
			arena.monster_runtime.templates = arena.monster_runtime.templates.duplicate(true)
			arena.monster_runtime.templates.erase("crawler")
	var after_external_change := authority()
	var result := await finish_prepare(ticket)
	check(not result.ok, "Async preparation rejects stale " + kind + " token")
	check(entry.phase() == "cancelled" and entry.geometry_ref() == null, "Stale " + kind + " cancels its owner")
	released(candidate, "Stale " + kind + " releases native resources")
	unchanged(after_external_change, "Rejected stale " + kind)
	# Cleanup even when the stale assertion failed; keep the failed test visible.
	session.cancel_entry()


func test_native_failure(kind: String) -> void:
	if not await fresh(): return
	var session := Session.new()
	var before := authority()
	var ticket := {"done": false, "result": {}}
	launch_prepare(session, ticket)
	var entry: RefCounted = session._entry
	var candidate: RefCounted = entry.geometry_ref()
	if kind == "readiness":
		# Keep the actual space/bodies alive, but make one synchronization probe
		# impossible. Elapsed frames alone must not qualify this candidate.
		candidate._native_probes[0] = Vector2(10000000, 10000000)
	else:
		candidate._release_native()
	var result := await finish_prepare(ticket)
	check(not result.ok and entry.phase() == "cancelled", "Native " + kind + " failure rejects preparation")
	released(candidate, "Native " + kind + " failure leaves no RID, shape or query resource")
	unchanged(before, "Native " + kind + " failure")


func test_ready_revalidation(kind: String) -> void:
	if not await fresh(): return
	var session := Session.new()
	var prepared: Dictionary = await session.prepare_entry(arena)
	if not accepted(prepared, "Prepare ready revalidation case " + kind): return
	var entry: RefCounted = prepared.entry
	var candidate: RefCounted = entry.geometry_ref()
	if kind == "draft":
		accepted(arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision), "Change ready draft")
	elif kind == "route":
		var blocker: Vector2 = Session.layout(View.exploration_arena()).solid_probes[0]
		check(not candidate.is_clear(blocker, 36.0), "Tampered route endpoint is blocked in the actual native space")
		entry._landmarks.route_segments[0].to = blocker
	elif kind == "landmark":
		entry._landmarks.outposts[0].id = "forged_outpost"
	elif kind == "native_resource":
		candidate._release_native()
	var before := authority()
	var result: Dictionary = session.enter(arena)
	check(not result.ok, "Main independently rejects ready " + kind + " tampering")
	check(entry.phase() == "cancelled" and entry.geometry_ref() == null, "Failed ready " + kind + " consumes and cancels owner")
	released(candidate, "Failed ready " + kind + " frees remaining native resources")
	unchanged(before, "Rejected ready " + kind)


func test_fake_and_locked() -> void:
	if not await fresh(): return
	var before := authority()
	var fake := {"validated": true, "ready": true, "geometry": arena._geometry,
		"landmarks": Layout.layout("old_garden", View.exploration_arena()).landmarks}
	check(not arena.start_map_prepared(arena.map_draft().revision, fake).ok,
		"Caller-supplied validated Dictionary cannot authorize prepared entry")
	check(not arena.craft_normal_map("old_garden", 3, [], [], arena.map_draft().revision).ok,
		"Lawful tier-I fixture cannot unlock tier III through the study adapter")
	unchanged(before, "Fake validated owner and locked tier III")


func test_save_failure() -> void:
	if not await fresh(2): return
	var session := Session.new()
	var prepared: Dictionary = await session.prepare_entry(arena)
	if not accepted(prepared, "Paid tier-II preparation before writer failure"): return
	var entry: RefCounted = prepared.entry
	var candidate: RefCounted = entry.geometry_ref()
	var before := authority()
	arena.state.fail_save = true
	var result: Dictionary = session.enter(arena)
	check(not result.ok and str(result.get("code", "")) == "save_failed", "Real canonical write failure rejects prepared paid entry")
	check(entry.phase() == "cancelled" and entry.geometry_ref() == null, "Failed canonical write consumes prepared owner")
	released(candidate, "Failed write releases detached native resources")
	unchanged(before, "Failed real save")
	check(arena.state.crafting_balance() == 4, "Failed save preserves all four earned shards")
	check(not session.enter(arena).ok, "Failed-save entry cannot be replayed")
	unchanged(before, "Replay of failed-save entry")
	arena.state.fail_save = false


func test_insufficient_funds() -> void:
	if not await fresh(2): return
	# Spend exactly the lawful four-shard balance through the unchanged public
	# entry, then abandon normally. No fabricated currency or completion state.
	if not accepted(arena.start_map(arena.map_draft().revision), "Ordinary paid entry consumes the earned four shards"): return
	if not accepted(arena.return_to_town(arena.world_context().revision), "Ordinary town return abandons without refund"): return
	pause()
	check(arena.state.crafting_balance() == 0, "Real paid entry exhausts the lawful fixture balance")
	if not accepted(arena.craft_normal_map("old_garden", 2, [], [], arena.map_draft().revision), "Unlocked but unaffordable tier-II draft"): return
	var session := Session.new()
	var before := authority()
	var prepared: Dictionary = await session.prepare_entry(arena)
	if prepared.ok:
		var entry: RefCounted = prepared.entry
		var candidate: RefCounted = entry.geometry_ref()
		check(not session.enter(arena).ok, "Prepared geometry cannot bypass actual insufficient-funds admission")
		check(entry.phase() == "cancelled", "Insufficient-funds admission cancels the prepared owner")
		released(candidate, "Insufficient-funds rejection releases native resources")
	else:
		check(not session.enter(arena).ok, "Unaffordable preparation cannot enter")
		if session._entry != null:
			check(session._entry.phase() == "cancelled" and session._entry.geometry_ref() == null,
				"Early affordability rejection leaves no prepared resources")
	unchanged(before, "Insufficient-funds entry")


func cancel_during_saved_signal() -> void:
	callback_count += 1
	cancelling_session.cancel_entry()
	callback_duplicate = cancelling_session.enter(arena)
	callback_retained = callback_entry.phase() == "in_use" \
		and callback_entry.geometry_ref() == callback_geometry and callback_geometry.physics_ready()


func test_success(tier: int, reentrant_cancel: bool = false) -> void:
	if not await fresh(tier): return
	var original_plan: Dictionary = arena._prepare_camp_run(arena._map_draft_profile, int(arena.state.normal_journey().next_run_id))
	if not accepted(original_plan, "Unchanged default planner provides independent old_garden reference"): return
	var original_landmarks: Dictionary = original_plan.landmarks.duplicate(true)
	var original_records: Array = original_plan.spawn_records.duplicate(true)
	var original_roots: Array = original_plan.roots.duplicate(true)
	# Main adds these existing combat profile fields for either entry path.
	for enemy: Dictionary in original_roots:
		arena._apply_source_actor_profile(enemy)
	var before := authority()
	var before_next_id: int = arena.monster_runtime.next_id
	var before_journey: Dictionary = arena.state.normal_journey()
	var before_revision: int = arena.state.revision()
	var before_rng: int = arena.rng.state
	var cost: int = arena.map_draft().cost
	var session := Session.new()
	var prepared: Dictionary = await session.prepare_entry(arena)
	if not accepted(prepared, "Prepare lawful tier %d without admitting roots" % tier): return
	var entry: RefCounted = prepared.entry
	var candidate: RefCounted = entry.geometry_ref()
	check(entry is PreparedEntry and entry.phase() == "ready" and candidate.physics_ready(), "Ready entry owns queryable actual native geometry")
	unchanged(before, "Completed detached preparation")
	var supplied: Dictionary = entry.landmarks()
	var wanted: Dictionary = original_landmarks.duplicate(true)
	# The default planner fills root_ids only in its own detached plan. Compare
	# the adapter against the original, unadmitted authored landmark contract.
	wanted = Layout.layout("old_garden", View.exploration_arena()).landmarks
	supplied.erase("route_segments")
	wanted.erase("route_segments")
	check(var_to_bytes(supplied) == var_to_bytes(wanted), "Preparation changes route segments only, preserving every other authored landmark")
	var copy: Dictionary = entry.landmarks()
	copy.route_segments.clear()
	check(not entry.landmarks().route_segments.is_empty(), "Landmark reads are detached from prepared authority")
	var original_geometry: RefCounted = arena._geometry
	var duplicate: Dictionary = await session.prepare_entry(arena)
	check(not duplicate.ok and session._entry == entry, "Second preparation cannot overwrite a ready entry")
	if reentrant_cancel:
		cancelling_session = session
		callback_entry = entry
		callback_geometry = candidate
		callback_count = 0
		callback_retained = false
		callback_duplicate = {}
		arena.state.changed.connect(cancel_during_saved_signal)
	var result: Dictionary = session.enter(arena)
	if reentrant_cancel:
		arena.state.changed.disconnect(cancel_during_saved_signal)
		check(callback_count == 1 and callback_retained and not callback_duplicate.get("ok", true),
			"Synchronous save callback cannot cancel or enter an in-use geometry transaction")
		cancelling_session = null
		callback_entry = null
		callback_geometry = null
	if not accepted(result, "Real prepared tier %d transaction commits" % tier):
		session.cancel_entry()
		return
	check(entry.phase() == "transferred" and entry.geometry_ref() == null, "Successful entry transfers and relinquishes the one-use handle")
	check(arena._geometry == candidate and arena._geometry != original_geometry and candidate.physics_ready(),
		"Main installs the identical prepared geometry instance without rebuilding its native space")
	check(arena.enemies.size() == 25 and arena.map_spawn_records() == original_records \
		and var_to_bytes(arena.enemies) == var_to_bytes(original_roots),
		"All 25 actual roots retain default planner fields plus the ordinary Main source profile")
	check(arena.monster_runtime.next_id == before_next_id + 25 and arena.monster_runtime.queue.is_empty(), "Success allocates exactly 25 root IDs once")
	check(arena.rng.state == before_rng, "Successful detached entry consumes no gameplay RNG")
	check(arena.state.crafting_balance() == 4 - cost and arena.state.revision() == before_revision + 1 \
		and arena.state.normal_journey().next_run_id == before_journey.next_run_id + 1 \
		and arena.state.normal_journey().active_run.fee_paid == cost,
		"One successful entry advances one saved run and pays its exact fee once")
	var reloaded := Model.new()
	check(reloaded.load_build(SAVE) and reloaded.snapshot() == arena.state.snapshot(), "Actual saved envelope equals the committed canonical model")
	var committed := authority()
	check(not session.enter(arena).ok and not arena.start_map_prepared(arena.map_draft().revision, entry).ok,
		"Duplicate entry through either API cannot spend again or allocate roots")
	session.cancel_entry()
	entry.cancel()
	check(candidate.physics_ready() and arena._geometry == candidate, "Late cancellation cannot release transferred Main geometry")
	unchanged(committed, "Duplicate entry and late cancellation")
	if not accepted(arena.return_to_town(arena.world_context().revision), "Normal town return releases admitted study geometry"): return
	released(candidate, "Town releases the transferred native space, bodies, shapes and query circle")
	check(arena.world_context().normal_town and arena.enemies.is_empty() and arena.map_spawn_records().is_empty() \
		and arena.state.crafting_balance() == 4 - cost, "Town clears the admitted roster and keeps the fee paid once")


func test_ordinary_retry() -> void:
	if not await fresh(1): return
	var session := Session.new()
	var prepared: Dictionary = await session.prepare_entry(arena)
	if not accepted(prepared, "Prepare the ordinary-retry study fixture"): return
	var candidate: RefCounted = prepared.entry.geometry_ref()
	if not accepted(session.enter(arena), "Admit native study before ordinary retry"): return
	var expected: Dictionary = arena._prepare_camp_run(arena._map_run.profile, int(arena.state.normal_journey().next_run_id))
	if not accepted(expected, "Prepare unchanged ordinary retry reference"): return
	for enemy: Dictionary in expected.roots:
		arena._apply_source_actor_profile(enemy)
	var before := authority()
	arena.state.fail_save = true
	check(not arena.retry_normal_map(arena.world_context().revision).ok, "Failed ordinary retry keeps the current native study")
	unchanged(before, "Failed ordinary retry")
	check(arena._geometry == candidate and candidate.physics_ready(), "Failed retry preserves native instance and resources")
	arena.state.fail_save = false
	var previous_run: int = arena._normal_run_id
	var previous_revision: int = arena.run_revision
	arena.restart_run()
	check(arena._normal_run_id == previous_run + 1 and arena.run_revision == previous_revision + 1,
		"Ordinary restart button path commits exactly one new normal run")
	check(arena._geometry != candidate and arena._geometry.snapshot().id == "old_garden" \
		and arena._geometry.snapshot().encounter_mode == "exploration", "Ordinary restart adopts ordinary collision, not native study walls")
	released(candidate, "Ordinary restart releases the former native space, bodies, shapes and query circle")
	check(arena._camp_landmarks == expected.landmarks and arena.map_spawn_records() == expected.spawn_records \
		and var_to_bytes(arena.enemies) == var_to_bytes(expected.roots), "Ordinary restart adopts matching original routes and roots")
	check(arena.retained_actors._hero_presentation.is_empty(), "Ordinary restart clears the study-only hero presentation")
	check(arena.state.crafting_balance() == 4, "Free tier-I retry preserves previously earned currency")
	check(arena.return_to_town(arena.world_context().revision).ok, "Ordinary retry returns through the existing town path")


func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or ProjectSettings.globalize_path(SAVE) == FIXTURE:
		printerr("PREPARED_ENTRY_BLOCKED: use an isolated /tmp/godot-m1-* XDG_DATA_HOME")
		quit(78)
		return
	var fixture_path := OS.get_environment("PREPARED_ENTRY_FIXTURE")
	if fixture_path.is_empty(): fixture_path = FIXTURE
	if not FileAccess.file_exists(fixture_path):
		printerr("PREPARED_ENTRY_BLOCKED: missing earned v114 fixture: " + fixture_path)
		quit(78)
		return
	fixture_bytes = FileAccess.get_file_as_bytes(fixture_path)
	if not check(not fixture_bytes.is_empty(), "Earned fixture is nonempty"):
		quit(1)
		return
	var success_only := "--success-only" in OS.get_cmdline_user_args()
	if not success_only:
		await test_wait_cancel_and_concurrency()
		for kind: String in ["draft", "world", "model_revision", "model_identity", "rng", "runtime", "runtime_templates"]:
			await test_stale_await(kind)
		for kind: String in ["readiness", "resource"]:
			await test_native_failure(kind)
		for kind: String in ["draft", "route", "landmark", "native_resource"]:
			await test_ready_revalidation(kind)
		await test_fake_and_locked()
		await test_save_failure()
		await test_insufficient_funds()
	await test_success(1)
	await test_success(2, true)
	await test_ordinary_retry()
	check(FileAccess.get_file_as_bytes(fixture_path) == fixture_bytes, "Original earned fixture remains byte-for-byte untouched")
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	print("PREPARED_ENTRY_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "failed_labels": failed_labels,
		"fixture": fixture_path, "scope": "success and ordinary retry only" if success_only else "complete focused entry test", "method": "Fresh isolated real Main; native preparation, authoritative admission and actual save transactions; no combat replay"}))
	quit(1 if failures else 0)
