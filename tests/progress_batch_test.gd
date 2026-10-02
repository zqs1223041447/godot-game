extends SceneTree
## Independent real-cast/tick regressions; run only with disposable XDG roots.
const Fixture = preload("res://tests/fixtures/progress_batch_fixture.gd")
const Model = preload("res://scripts/build_state.gd")
var checks: int = 0
var failures: int = 0
var arena: Node2D
var suite_finished: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_case(_combat_differential, "real public AoE/tick kills, rewards, capacity and exact bytes")
	_case(_immediate_menu_edits, "outside-transaction menu persistence")
	_case(_immediate_stats, "every signal updates stats and clamps vitals immediately")
	_case(_empty_and_rejected, "empty/rejected/early-return public calls")
	_case(_nested_transactions, "nested public calls and outermost boundary")
	_case(_autosave_boundary, "15-second autosave coincides with combat changes")
	_case(_forced_boundaries, "manual save, death and normal exit flush inside batch")
	_case(_reentrant_saves, "save callback mutation persists latest state")
	_case(_reentrant_hud, "HUD refresh and failure notification callbacks remain safe")
	_case(_failed_save_retry, "denied save retained without 60-Hz retry storm")
	_case(_future_guard, "future-version bytes and absolute alias remain protected")
	_case(_legacy_backup, "v6 byte-exact backup, alias and conflict preservation")
	_dispose()
	print("Progress batching: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _case(test: Callable, label: String) -> void:
	suite_finished = false
	test.call()
	_expect(suite_finished, "Case reached final assertion: " + label)

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _dispose() -> void:
	if is_instance_valid(arena):
		arena.free()
	arena = null

func _new(batching: bool = true, initial: Dictionary = {}) -> void:
	_dispose()
	arena = Fixture.create(self, batching, initial)
	_expect(is_instance_valid(arena), "Disposable real arena fixture is available")

func _counts(refreshes: int, attempts: int, successes: int, label: String) -> void:
	var actual: Dictionary = Fixture.counts(arena)
	_expect(actual.hud_refreshes == refreshes and actual.save_attempts == attempts and actual.save_successes == successes, label + " counters: " + str(actual))
	_expect(actual.save_attempts == actual.spy_attempts and actual.save_successes == actual.spy_successes, label + " agrees with independent model-save spy")

func _combat_differential() -> void:
	for scenario: String in ["roots_cast", "mixed_cast", "roots_tick", "mixed_tick", "full_backpack_cast"]:
		var reference: Dictionary = {}
		var reference_counts: Dictionary = {}
		var initial: Dictionary = Fixture.full_backpack() if scenario.begins_with("full") else Model.new()._snapshot()
		_expect(not Model.new()._validate_snapshot(initial).is_empty(), scenario + " starts with fully valid save data")
		for batching: bool in [false, true]:
			_new(batching, initial)
			Fixture.prepare_combat(arena, scenario)
			var starting_ids: Array = []
			var total_xp: int = 0
			for enemy: Dictionary in arena.enemies:
				starting_ids.append(enemy.id)
				total_xp += int(enemy.xp_reward)
			_expect(starting_ids.size() == 100, scenario + " starts with 100 real catalog roots")
			_expect(Fixture.execute(arena, scenario), scenario + " public transaction accepted")
			_expect(arena.kills == 100 and arena.reward_kills == 100, scenario + " actually kills and rewards all 100 roots")
			if scenario.contains("tick"):
				_expect(int(arena.event_counts.get("hit", 0)) == 100, scenario + " records 100 genuine projectile contacts")
			var expected_level: int = int(initial.level)
			var expected_xp: int = int(initial.xp) + total_xp
			while expected_xp >= 12 + expected_level * 8:
				expected_xp -= 12 + expected_level * 8
				expected_level += 1
			_expect(arena.state.level == expected_level and arena.state.xp == expected_xp and arena.state.talent_points == initial.talent_points + expected_level - initial.level, scenario + " preserves every XP/level/talent reward")
			_expect(arena.pickups.size() == 25, scenario + " retains all four-kill supplies")
			_expect(Fixture.saved_matches(arena), scenario + " exact file bytes are latest complete schema snapshot")
			_expect(not arena._progress_save_dirty and arena._progress_transaction_depth == 0, scenario + " returns with clean persistence and balanced transaction")
			var counts: Dictionary = Fixture.counts(arena)
			if batching:
				_counts(1, 1, 1, scenario + " batched")
				_expect(counts.signals == reference_counts.signals, scenario + " suppresses no model signal")
				var current: Dictionary = Fixture.final_snapshot(arena)
				_expect(current.arena.has_all(["kills", "reward_kills", "_stats", "enemies", "projectiles", "pickups", "damage_trace", "combat_trace", "elapsed", "health", "mana", "shield", "cooldowns", "total_damage"]), "Complete-state comparator includes actual inherited arena gameplay properties")
				_expect(current == reference, scenario + " exact complete final gameplay/model/RNG/IDs/capacity/cue state and saved-byte equivalence")
				if current != reference:
					for key: String in current:
						if current[key] != reference[key]:
							print("Differential mismatch category: ", scenario, " / ", key)
			else:
				_counts(counts.signals, counts.signals, counts.signals, scenario + " historical per-signal")
				_expect(counts.signals >= 100, scenario + " retains individual XP and reward signals")
				reference_counts = counts
				reference = Fixture.final_snapshot(arena)
			if scenario.begins_with("full"):
				_expect(arena.state.equipment_instances == initial.equipment_instances and arena.state.jewels == initial.jewels and arena.state.next_equipment_id == initial.next_equipment_id and arena.state.next_jewel_id == initial.next_jewel_id, "Full backpack retains every item/jewel and consumes no rejected reward identity")
			print("Progress differential %s %s: %s" % [scenario, "batched" if batching else "historical", JSON.stringify(counts)])
	suite_finished = true

func _immediate_menu_edits() -> void:
	_new()
	_expect(arena.state.equip("swift_blade"), "Menu equipment edit succeeds")
	_counts(1, 1, 1, "Equipment saves before return")
	_expect(Fixture.saved_matches(arena), "Equipped item immediately present on disk")
	_expect(arena.state.allocate_passive("ember_1_0"), "Menu passive allocation succeeds")
	_counts(2, 2, 2, "Passive saves before return")
	_expect(Fixture.saved_matches(arena), "Passive immediately present on disk")
	_expect(arena.state.set_skill_supports("bolt", ["focus"]), "Menu support edit succeeds")
	_counts(3, 3, 3, "Support saves before return")
	_expect(Fixture.saved_matches(arena), "Supports immediately present on disk")
	_expect(not arena.state.equip("swift_blade") and not arena.state.set_skill_supports("nova", ["volley"]), "Rejected menu changes remain rejected")
	_counts(3, 3, 3, "Rejected menu edits add no persistence work")
	suite_finished = true

func _immediate_stats() -> void:
	_new()
	var observed: Dictionary = {"signals": 0, "fresh": true, "unflushed": true}
	arena.state.changed.connect(func():
		observed.signals += 1
		var stats: Dictionary = arena.state.get_stats()
		observed.fresh = observed.fresh and arena.get_stats() == stats and arena.health <= stats.max_health and arena.mana <= stats.max_mana and arena.shield <= stats.max_shield
		observed.unflushed = observed.unflushed and arena.progress_hud_refresh_count == 0 and arena.state.save_attempts == 0)
	arena._begin_progress_transaction()
	for item: String in ["vitality_armor", "storm_charm", "swift_blade"]:
		arena.health = 100000.0
		arena.mana = 100000.0
		arena.shield = 100000.0
		_expect(arena.state.equip(item), "Fixture equip emits its normal individual signal")
	_expect(observed.signals == 3 and observed.fresh, "Every synchronous signal observer sees refreshed stats and clamped health/mana/shield")
	_expect(observed.unflushed, "HUD/disk waits while live stats remain current")
	arena._end_progress_transaction()
	_counts(1, 1, 1, "Three live-stat changes flush once")
	_expect(Fixture.saved_matches(arena), "Batch saves final equipped model")
	suite_finished = true

func _empty_and_rejected() -> void:
	_new()
	_expect(not arena.cast_skill(-1) and not arena.cast_skill(100), "Out-of-range casts reject")
	arena.hud.open_panel("pause")
	_expect(not arena.cast_skill(2), "Paused cast rejects")
	arena.hud.close_panel()
	arena.mana = 0.0
	_expect(not arena.cast_skill(2), "Insufficient-mana cast rejects")
	arena.mana = float(arena.get_stats().max_mana)
	_expect(arena.cast_skill(2), "No-target nova is a valid zero-progress cast")
	_expect(not arena.cast_skill(2), "Cooldown cast rejects")
	arena.tick(Fixture.STEP)
	_counts(0, 0, 0, "Zero model changes produce no save or refresh")
	_expect(arena._progress_transaction_depth == 0, "All early-return cast paths close transactions")
	arena.alive = false
	_expect(not arena.cast_skill(0), "Dead-player cast rejects")
	arena.tick(Fixture.STEP)
	_expect(arena._progress_transaction_depth == 0, "Tick death return closes transaction")
	arena.alive = true
	_expect(arena.state.equip("swift_blade"), "Menu edit after early returns remains responsive")
	_counts(1, 1, 1, "Early return does not leak batching into menu actions")
	suite_finished = true

func _nested_transactions() -> void:
	_new()
	Fixture.prepare_combat(arena, "roots_cast", 4)
	arena._begin_progress_transaction()
	arena._begin_progress_transaction()
	_expect(arena.cast_skill(2), "Public damaging cast nested inside outer transaction succeeds")
	_expect(not arena.cast_skill(2), "Nested rejected call closes its own transaction")
	arena.tick(Fixture.STEP)
	_counts(0, 0, 0, "Nested cast and tick do not flush enclosing transaction")
	arena._end_progress_transaction()
	_counts(0, 0, 0, "First enclosing boundary still defers")
	arena._end_progress_transaction()
	_counts(1, 1, 1, "Outermost boundary flushes once")
	_expect(arena._progress_transaction_depth == 0 and Fixture.saved_matches(arena), "Nested transaction balance and final persisted state")
	suite_finished = true

func _autosave_boundary() -> void:
	_new()
	Fixture.prepare_combat(arena, "roots_tick")
	arena._autosave_timer = 15.0 - Fixture.STEP * 0.5
	arena.tick(Fixture.STEP)
	_expect(arena.kills == 100, "Autosave boundary includes all 100 tick kills")
	_counts(1, 1, 1, "Autosave and transaction end share one completed save")
	_expect(arena._autosave_timer == 0.0 and Fixture.saved_matches(arena), "Existing autosave interval retained with current bytes")
	Fixture.reset_counts(arena)
	arena._autosave_timer = 15.0 - Fixture.STEP * 0.5
	arena.tick(Fixture.STEP)
	_counts(0, 1, 1, "Unchanged 15-second autosave retains historical explicit attempt")
	suite_finished = true

func _forced_boundaries() -> void:
	for boundary: String in ["manual", "death", "exit"]:
		_new()
		arena._begin_progress_transaction()
		arena.state.add_xp(3)
		_counts(0, 0, 0, boundary + " starts with pending progress")
		match boundary:
			"manual":
				_expect(arena.save_build(), "Explicit manual save returns success before outer end")
			"death":
				arena.invulnerable = 0.0
				arena.hit_player(1000000.0)
				_expect(not arena.alive, "Real hit_player enters death path")
			"exit":
				arena._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
				_expect(arena.quit_requests == 1, "Normal OS close calls overridable quit hook without terminating test runner")
		_counts(1, 1, 1, boundary + " forces pending HUD and save immediately")
		_expect(Fixture.saved_matches(arena), boundary + " final data is already persisted")
		arena._end_progress_transaction()
		_counts(1, 1, 1, boundary + " outer exit adds no duplicate save")
	suite_finished = true

func _reentrant_saves() -> void:
	_new()
	arena.state.after_save = func(): arena.state.add_xp(7)
	Fixture.prepare_combat(arena, "roots_cast", 1)
	_expect(arena.cast_skill(2), "Reentrant mutation fixture casts through actual gameplay")
	_counts(2, 2, 2, "Post-write model mutation requires one fresh bounded save")
	_expect(arena.state.xp == 10 and Fixture.saved_matches(arena), "Reentrant XP appears in exact latest saved bytes")
	_expect(not arena._progress_save_dirty and not arena._progress_hud_dirty, "One-shot reentry leaves no lost dirty flags")
	Fixture.reset_counts(arena)
	arena.state.after_save = func():
		arena.state.equip("swift_blade")
		arena.save_build()
	_expect(arena.save_build(), "Explicit save reentry drains after in-flight model writer returns")
	_counts(1, 2, 2, "Reentrant explicit save avoids recursive writer and keeps new mutation")
	_expect(Fixture.saved_matches(arena), "Reentrant explicit call leaves latest complete file")
	suite_finished = true

func _failed_save_retry() -> void:
	_new()
	var before: PackedByteArray = FileAccess.get_file_as_bytes(Fixture.SAVE_PATH)
	arena.state.deny_saves = true
	Fixture.prepare_combat(arena, "roots_cast", 2)
	_expect(arena.cast_skill(2), "Save denial does not reject successful combat")
	_counts(1, 1, 0, "Denied burst attempts once")
	_expect(arena._progress_save_dirty and FileAccess.get_file_as_bytes(Fixture.SAVE_PATH) == before, "Failure retains pending state and untouched old bytes")
	for frame: int in range(120):
		arena.tick(Fixture.STEP)
	_expect(not arena.cast_skill(-1), "Rejected cast while failed save pending")
	_counts(1, 1, 0, "120 empty ticks and rejected cast never retry pending failure")
	_expect(not arena.save_build(), "Explicit failed-save retry accurately returns false")
	_counts(1, 2, 0, "Manual attempt retries once")
	arena._autosave_timer = 15.0 - Fixture.STEP * 0.5
	arena.tick(Fixture.STEP)
	_counts(1, 3, 0, "Existing autosave retries once")
	arena.state.deny_saves = false
	Fixture.prepare_combat(arena, "roots_cast", 1)
	# prepare_combat resets only counters; clear old corpses first through normal tick.
	arena.cooldowns.nova = 0.0
	_expect(arena.cast_skill(2), "Actual changed transaction retries once save target recovers")
	_counts(1, 1, 1, "Next real progress change retries latest pending data")
	_expect(not arena._progress_save_dirty and Fixture.saved_matches(arena), "Recovery persists all accumulated XP and rewards")
	# Also exercise a real atomic-write failure, not just the save spy's error code.
	Fixture.reset_counts(arena)
	var temporary: String = ProjectSettings.globalize_path(Fixture.SAVE_PATH) + ".tmp"
	_expect(DirAccess.make_dir_absolute(temporary) == OK, "Disposable directory blocks atomic temporary-file creation")
	arena.state.add_xp(1)
	_counts(1, 1, 0, "Actual filesystem refusal is observable")
	_expect(arena._progress_save_dirty, "Actual write failure preserves pending state")
	_expect(DirAccess.remove_absolute(temporary) == OK and arena.save_build(), "Removing fixture obstruction permits explicit recovery")
	_expect(Fixture.saved_matches(arena), "Recovered actual write stores complete latest model")
	suite_finished = true

func _reentrant_hud() -> void:
	_new()
	Fixture.install_hud_spy(arena)
	arena.hud.after_refresh = func(): arena.state.add_xp(7)
	arena.state.add_xp(3)
	_counts(2, 1, 1, "HUD refresh mutation joins the first save and schedules one final HUD refresh")
	_expect(arena.hud.refresh_calls == 2 and Fixture.saved_matches(arena) and arena.state.xp == 10, "Independent HUD spy and exact file confirm reentrant refresh correctness")
	Fixture.reset_counts(arena)
	arena.hud.refresh_calls = 0
	arena.state.deny_saves = true
	arena.hud.after_notify = func():
		arena.state.add_xp(1)
		arena.save_build()
	_expect(not arena.save_build(), "Failure notification can request a save without recursively reentering writer")
	_counts(0, 1, 0, "Reentrant failed-save notification performs only one disk attempt")
	_expect(arena._progress_save_dirty and arena._progress_hud_dirty, "Failure-notification mutation retains latest pending model/HUD")
	arena.tick(Fixture.STEP)
	_counts(1, 1, 0, "Next empty tick finishes pending HUD without retrying failed save")
	arena.state.deny_saves = false
	_expect(arena.save_build() and Fixture.saved_matches(arena), "Explicit recovery saves mutation made during failure notification")
	suite_finished = true

func _future_guard() -> void:
	_dispose()
	var future: Dictionary = Model.new()._snapshot()
	future.version = 99
	var bytes: PackedByteArray = (JSON.stringify(future, " ") + "\r\n").to_utf8_buffer()
	_expect(Fixture.write_bytes(Fixture.SAVE_PATH, bytes), "Write disposable future-version source")
	arena = Fixture.create_from_existing(self, true)
	_expect(not arena.state.save_block_reason().is_empty(), "Future source enters protected state")
	Fixture.prepare_combat(arena, "roots_cast", 2)
	_expect(arena.cast_skill(2), "Protected persistence does not suppress model progress")
	_counts(1, 1, 0, "Protected source blocks batched write")
	_expect(not arena.save_build(), "Explicit save also honors future guard")
	var alias: String = ProjectSettings.globalize_path(Fixture.SAVE_PATH)
	_expect(arena.state.save_build(alias) == ERR_INVALID_DATA, "Absolute alias cannot bypass future-version guard")
	_expect(FileAccess.get_file_as_bytes(Fixture.SAVE_PATH) == bytes, "Future source bytes stay exact after mutation and all save routes")
	_expect(arena.state.save_build("user://progress_batch_manual_copy.json") == OK and not arena.state.save_block_reason().is_empty(), "Saving separate valid copy does not consume protected original guard")
	var valid: Dictionary = Model.new()._snapshot()
	_expect(Fixture.write_bytes(Fixture.SAVE_PATH, JSON.stringify(valid).to_utf8_buffer()), "External-restoration fixture replaces protected file")
	_expect(arena.state.load_build() and arena.state.save_block_reason().is_empty() and Fixture.saved_matches(arena), "Successful restoration unlocks path and persists immediately")
	suite_finished = true

func _legacy_backup() -> void:
	_dispose()
	var legacy: Dictionary = Model.new()._snapshot()
	legacy.version = 6
	legacy.erase("crafting")
	var original: PackedByteArray = ("\ufeff" + JSON.stringify(legacy, "\t").replace("\n", "\r\n") + "\r\n").to_utf8_buffer()
	var backup: String = Fixture.SAVE_PATH + ".v6-backup.json"
	DirAccess.remove_absolute(backup)
	_expect(Fixture.write_bytes(Fixture.SAVE_PATH, original), "Write v6 source with UTF-8 BOM and CRLF")
	arena = Fixture.create_from_existing(self, true)
	_expect(arena.state.migrated_from_v6 and not FileAccess.file_exists(backup), "Load migration is deferred until first actual write")
	Fixture.prepare_combat(arena, "roots_cast", 10)
	_expect(arena.cast_skill(2), "Migrated model participates in real combat transaction")
	_counts(1, 1, 1, "Legacy upgrade is one model save invocation")
	_expect(FileAccess.get_file_as_bytes(backup) == original and Fixture.saved_matches(arena), "One model save also writes distinct byte-exact legacy backup before schema7 output")
	var backup_bytes: PackedByteArray = FileAccess.get_file_as_bytes(backup)
	arena.state.add_xp(1)
	_expect(FileAccess.get_file_as_bytes(backup) == backup_bytes, "Later saves preserve original backup exactly")
	_dispose()
	DirAccess.remove_absolute(backup)
	_expect(Fixture.write_bytes(Fixture.SAVE_PATH, original), "Restore legacy fixture for absolute alias")
	arena = Fixture.create_from_existing(self, true)
	var absolute: String = ProjectSettings.globalize_path(Fixture.SAVE_PATH)
	_expect(arena.state.save_build(absolute) == OK and FileAccess.get_file_as_bytes(backup) == original, "Absolute alias of original source still requires exact legacy backup")
	_dispose()
	_expect(Fixture.write_bytes(Fixture.SAVE_PATH, original), "Restore legacy fixture for conflicting backup")
	var conflict: PackedByteArray = "existing distinct backup must survive\n".to_utf8_buffer()
	_expect(Fixture.write_bytes(backup, conflict), "Prepare conflicting backup bytes")
	arena = Fixture.create_from_existing(self, true)
	arena.state.add_xp(3)
	_counts(1, 1, 0, "Conflicting legacy backup blocks queued autosave")
	_expect(FileAccess.get_file_as_bytes(Fixture.SAVE_PATH) == original and FileAccess.get_file_as_bytes(backup) == conflict and arena._progress_save_dirty, "Backup conflict leaves both files exact and new model progress pending")
	DirAccess.remove_absolute(backup)
	_expect(arena.save_build() and FileAccess.get_file_as_bytes(backup) == original and Fixture.saved_matches(arena), "Resolved backup conflict retries preserving source and latest progress")
	suite_finished = true
