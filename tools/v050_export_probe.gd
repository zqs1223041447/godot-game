extends SceneTree
## Short same-PCK behavior receipt. The one external input is the frozen clock
## fixture; every production scene, font, compiler and runtime loads from res://.
## No frame-budget, historical-suite, full-GUI, 600s or Windows-native claim.
const Model = preload("res://scripts/canonical_game_state.gd")
const Burn = preload("res://scripts/combat/burn_runtime.gd")
const Clock = preload("res://scripts/combat/ember_event_clock.gd")
const Projectiles = preload("res://scripts/combat/projectile_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const EXPECTED_CHECKS: int = 20
const FONT_SHA256: String = "c43797ccb46c17240acd21ffca909282d45c0cd8586afb945144013ac0de3ca4"
const FONT_BYTES: int = 415088
const FONT_MAPPED_CODEPOINTS: int = 1069
const FONT_CHARACTERS: String = "燃烧余烬扩散辅助宝石伤害持续时间投射物目标生命魔力护盾"
const FIXTURE_SHA256: String = "0da998461697075884fb6390691b8d51e7954a53488b5170860bb7c3200e2f23"
const FIXTURE_BYTES: int = 25708
const RAW_TIMES: Array[float] = [0.0, 0.008498710574771513, 0.008495442978210952, 0.008485886630782776]
var arena: Node
var model: RefCounted
var output: String
var save_path: String
var results: Array[Dictionary] = []
var failures: int = 0
var finished: bool = false
var report: Dictionary = {"ok": false, "status": "running", "probe": "v050_export_probe",
	"scope": "Short same-PCK real-main ember clock, public burn snapshots, same-time cleanup/transfer and schema30 persistence; no performance or visual acceptance claim"}


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String, evidence: Dictionary = {}) -> bool:
	results.append({"ok": value, "label": label, "evidence": evidence})
	if not value:
		failures += 1
		push_error("Packed v50 probe: " + label)
	return value


func sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func same_data(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right): return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key: Variant in left:
			if not right.has(key) or not same_data(left[key], right[key]): return false
		return true
	if left is Array:
		if left.size() != right.size(): return false
		for index: int in range(left.size()):
			if not same_data(left[index], right[index]): return false
		return true
	return left == right


func json_data(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func write_report() -> bool:
	var file: FileAccess = FileAccess.open(output.path_join("packed-runtime-probe.json"), FileAccess.WRITE)
	if file == null:
		push_error("Packed v50 probe cannot write report: " + str(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	return true


func watchdog() -> void:
	if finished: return
	report.ok = false
	report.status = "aborted"
	report.error = "Probe did not complete within 45 seconds; reject this run"
	report.results = results
	report.checks = results.size()
	report.failures = failures + 1
	write_report()
	push_error("Packed v50 probe timed out or stopped after a runtime error")
	quit(1)


func finish() -> void:
	finished = true
	if results.size() != EXPECTED_CHECKS:
		failures += 1
		report.error = "Incomplete check count; reject this run"
	report.ok = failures == 0 and results.size() == EXPECTED_CHECKS
	report.status = "complete" if report.ok else "failed"
	report.results = results
	report.checks = results.size()
	report.expected_checks = EXPECTED_CHECKS
	report.failures = failures
	var written: bool = write_report()
	var success: bool = bool(report.ok) and written
	print("Packed v50 burn behavior probe: %s (%d/%d checks, %d failures)" % ["PASS" if success else "FAIL", results.size(), EXPECTED_CHECKS, failures])
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	quit(0 if success else 1)


func origin(at: float, duration: float) -> Dictionary:
	return {"ember_generation": 0, "ember_expiry": at + duration, "skill_id": "meteor", "cast_id": 1}


func resource_receipt() -> Dictionary:
	return {"health": arena.health, "mana": arena.mana, "shield": arena.shield,
		"kills": arena.kills, "reward_kills": arena.reward_kills, "pickups": arena.pickups.duplicate(true),
		"state": model.snapshot(), "save_attempts": model.save_attempts, "successful_saves": model.successful_saves,
		"main_save_attempts": arena.progress_save_attempt_count, "main_save_successes": arena.progress_save_success_count,
		"disk": FileAccess.get_file_as_bytes(save_path)}


func quiet_receipt() -> Dictionary:
	var receipt: Dictionary = resource_receipt()
	receipt.rng = arena.rng.state
	receipt.critical = arena.critical_runtime.checkpoint()
	receipt.total_damage = arena.total_damage
	receipt.events = arena.event_counts.duplicate(true)
	receipt.combat_trace = arena.combat_trace.duplicate(true)
	receipt.damage_trace = arena.damage_trace.duplicate(true)
	receipt.burn_trace = arena.burn_trace.duplicate(true)
	return receipt


func run_clock_case(fixture: Dictionary, start: float, cast: Dictionary) -> Dictionary:
	arena._world_mode = "normal"
	arena._geometry.configure("old_garden", arena.ARENA)
	arena.enemies.assign(fixture.actors.duplicate(true))
	arena.player_pos = fixture.player_pos
	arena.projectiles.assign(fixture.shots.duplicate(true))
	arena.projectile_runtime = Projectiles.new()
	arena.monster_runtime.reset()
	arena.burn_runtime.reset()
	arena.critical_runtime.reset(508)
	arena.combat_trace.clear()
	arena.damage_trace.clear()
	arena.burn_trace.clear()
	arena.event_counts.clear()
	var critical: Dictionary = arena.critical_runtime.freeze(cast.snapshot)
	if not critical.get("ok", false): return {"ok": false, "error": "Real critical freeze failed"}
	for shot: Dictionary in arena.projectiles:
		shot.payload = cast.packets.parent.duplicate(true)
		shot.snapshot = critical.snapshot.duplicate(true)
	var raw_shots: Array[Dictionary] = []
	raw_shots.assign(arena.projectiles.duplicate(true))
	var expected: Array[Dictionary] = Projectiles.new().advance(raw_shots, float(fixture.step), arena.enemies,
		arena.player_pos, arena.MAX_PROJECTILES, func(_shot: Dictionary, _id: int) -> bool: return true)
	var expected_bytes: PackedByteArray = var_to_bytes(expected)
	var plan: Dictionary = Clock.offsets(expected)
	if not plan.get("ok", false) or expected.size() != 4:
		return {"ok": false, "error": "Frozen carriers did not yield four valid current-runtime events", "plan": plan}
	var times: Array[float] = []
	var ids: Array[int] = []
	var sequences: Array[int] = []
	var all_hits: bool = true
	for event: Dictionary in expected:
		times.append(float(event.time))
		ids.append(int(event.target_id))
		sequences.append(int(event.sequence))
		all_hits = all_hits and event.type == "hit"
	arena.elapsed = start + float(fixture.step)
	arena._burn_step_start = start
	arena._burn_step_active = true
	arena.rng.seed = 50123
	var before: Dictionary = resource_receipt()
	var critical_before: Dictionary = arena.critical_runtime.checkpoint()
	var expected_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	expected_rng.seed = arena.rng.seed
	expected_rng.state = arena.rng.state
	# Four existing hit settlements each consume one text-position and eight
	# particle draws. Nonlethal burn integration itself consumes no reward RNG.
	for unused_hit: int in range(4):
		expected_rng.randf_range(-8, 8)
		for unused_particle: int in range(4):
			expected_rng.randf()
			expected_rng.randf_range(40, 130)
	arena._update_projectiles(float(fixture.step))
	var trace_exact: bool = arena.combat_trace.size() == expected.size()
	if trace_exact:
		for index: int in range(expected.size()):
			var brief: Dictionary = expected[index].duplicate(true)
			brief.erase("snapshot")
			brief.erase("payload")
			trace_exact = trace_exact and var_to_bytes(brief) == var_to_bytes(arena.combat_trace[index])
	var statuses: Array[Dictionary] = arena.burn_runtime.statuses()
	var clock_exact: bool = statuses.size() == 3
	var clocks: Array[float] = []
	for status: Dictionary in statuses:
		clocks.append(float(status.last_time))
		clock_exact = clock_exact and float(status.last_time) == start + float(plan.offsets.back())
		clock_exact = clock_exact and status.provenance.get("ember_generation", -1) == 0
	var living: bool = true
	for enemy: Dictionary in arena.enemies: living = living and float(enemy.health) > 0.0
	return {"ok": true, "start": start, "raw_times": times, "target_ids": ids, "sequences": sequences,
		"expected_original": all_hits and times == RAW_TIMES and ids == [20, 20, 30, 39] and sequences == [2, 1, 3, 4]
			and var_to_bytes(expected) == expected_bytes,
		"dispatch_exact": trace_exact and clock_exact and living and arena.event_counts == {"hit": 4}
			and arena.damage_trace.size() == 4 and arena.kills == 0,
		"burn_count": statuses.size(), "burn_clocks": clocks, "adapted_offsets": plan.offsets,
		"guards_clear": arena._ember_projectile_clock.is_empty() and not arena._ember_advancing
			and not arena._ember_defer_deaths and not arena._ember_flushing and arena._ember_deaths.is_empty(),
		"resources_unchanged": same_data(before, resource_receipt()),
		"rng_exact": arena.rng.state == expected_rng.state and same_data(critical_before, arena.critical_runtime.checkpoint()),
		"actual_rng": str(arena.rng.state), "expected_rng": str(expected_rng.state)}


func run() -> void:
	output = OS.get_environment("V050_PROBE_OUTPUT")
	var pack_path: String = OS.get_environment("V050_MAIN_PACK")
	var fixture_path: String = OS.get_environment("V050_CLOCK_FIXTURE")
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	var xdg_safe: bool = isolated.begins_with("/tmp/godot-m1-")
	for variable: String in ["XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var value: String = OS.get_environment(variable)
		xdg_safe = xdg_safe and (value.is_empty() or value.simplify_path().begins_with("/tmp/godot-m1-"))
	if not output.is_absolute_path() or not pack_path.is_absolute_path() or not FileAccess.file_exists(pack_path) \
		or not fixture_path.is_absolute_path() or not fixture_path.simplify_path().ends_with("/docs/qa/v050-density/minimal-clock.bin") \
		or not FileAccess.file_exists(fixture_path) or not ProjectSettings.globalize_path("res://").is_empty() or not xdg_safe:
		push_error("Packed v50 probe requires absolute V050_MAIN_PACK, V050_PROBE_OUTPUT, frozen V050_CLOCK_FIXTURE at docs/qa/v050-density/minimal-clock.bin, empty packed res root, and isolated /tmp/godot-m1-* XDG paths")
		quit(78)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Packed v50 probe cannot create output directory")
		quit(1)
		return
	# A running/partial receipt is never acceptable. Require complete, 20/20,
	# process exit zero and no ERROR lines in the runner's captured engine log.
	if not write_report(): quit(1); return
	create_timer(45.0).timeout.connect(watchdog)
	report.command_line = Array(OS.get_cmdline_args())
	report.main_pack = pack_path
	report.main_pack_sha256 = sha256(FileAccess.get_file_as_bytes(pack_path))
	report.engine = Engine.get_version_info().string
	report.platform = OS.get_name()
	report.probe_resource = get_script().resource_path
	report.probe_sha256 = sha256(FileAccess.get_file_as_bytes(get_script().resource_path))
	report.clock_fixture = fixture_path
	var fixture_bytes: PackedByteArray = FileAccess.get_file_as_bytes(fixture_path)
	report.clock_fixture_sha256 = sha256(fixture_bytes)
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		report.error = "Packed main scene could not load"
		await finish()
		return
	arena = scene.instantiate()
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await process_frame
	model = arena.state
	save_path = arena.build_save_path
	report.version = str(ProjectSettings.get_setting("application/config/version"))
	report.schema = model.snapshot().version
	report.save_dir = str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	report.user_dir = OS.get_user_data_dir()
	report.bag = model.bag_layout()
	check(model is Model and report.version == "0.50.0" and report.schema == 30
		and report.save_dir == "godot-game-preview-v021" and report.bag == {"pages": 2, "columns": 12, "rows": 10}
		and save_path == arena.NORMAL_BUILD_PATH and str(report.user_dir).begins_with(isolated + "/")
		and arena.get_script().resource_path == "res://scripts/main.gd"
		and model.get_script().resource_path == "res://scripts/canonical_game_state.gd"
		and arena.burn_runtime.get_script().resource_path == "res://scripts/combat/burn_runtime.gd",
		"Packed v0.50 actual main/model/runtime retain schema30, v021 save identity and 240 cells",
		{"version": report.version, "schema": report.schema, "save_dir": report.save_dir, "bag": report.bag, "save_path": save_path})
	var font: FontFile = load("res://assets/fonts/arena_sans.otf") as FontFile
	var missing: String = ""
	if font != null:
		font.allow_system_fallback = false
		for index: int in range(FONT_CHARACTERS.length()):
			if not font.has_char(FONT_CHARACTERS.unicode_at(index)) and not missing.contains(FONT_CHARACTERS[index]): missing += FONT_CHARACTERS[index]
		report.font_sha256 = sha256(font.data)
		report.font_raw_bytes = font.data.size()
		report.font_mapped_codepoints = font.get_supported_chars().length()
	else: missing = FONT_CHARACTERS
	check(font != null and report.get("font_sha256", "") == FONT_SHA256 and report.get("font_raw_bytes", 0) == FONT_BYTES
		and report.get("font_mapped_codepoints", 0) == FONT_MAPPED_CODEPOINTS and missing.is_empty(),
		"Exact unchanged raw 415088-byte, 1069-codepoint bundled font covers burn text without system fallback",
		{"sha256": report.get("font_sha256", ""), "bytes": report.get("font_raw_bytes", 0),
			"mapped_codepoints": report.get("font_mapped_codepoints", 0), "missing": missing})
	var baseline: Dictionary = model.snapshot()
	var attempts_before: int = model.save_attempts
	var saves_before: int = model.successful_saves
	var saved: bool = arena.save_build()
	var original_disk: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	if not check(saved and not original_disk.is_empty() and same_data(baseline, model.snapshot())
		and baseline.talents.source_version == "3.29.1" and model.save_attempts == attempts_before + 1
		and model.successful_saves == saves_before + 1
		and same_data(json_data(baseline), JSON.parse_string(original_disk.get_string_from_utf8())),
		"One real-main save preserves current schema30/source3.29.1 profile and writes coherent JSON",
		{"source_version": baseline.talents.source_version, "disk_sha256": sha256(original_disk), "bytes": original_disk.size()}):
		await finish(); return
	var fixture_value: Variant = bytes_to_var(fixture_bytes)
	var fixture_valid: bool = fixture_value is Dictionary and fixture_bytes.size() == FIXTURE_BYTES \
		and report.clock_fixture_sha256 == FIXTURE_SHA256
	if fixture_valid:
		fixture_valid = fixture_value.get("actors") is Array and fixture_value.actors.size() == 3 \
			and fixture_value.get("shots") is Array and fixture_value.shots.size() == 4 \
			and fixture_value.get("player_pos") is Vector2 and float(fixture_value.get("step", 0.0)) == 1.0 / 60.0
	if not check(fixture_valid, "External frozen fixture is the exact original three-actor/four-carrier input",
		{"sha256": report.clock_fixture_sha256, "bytes": fixture_bytes.size(), "expected_sha256": FIXTURE_SHA256}):
		await finish(); return
	var fixture: Dictionary = fixture_value
	var chain: Array[Dictionary] = [{"time": RAW_TIMES[1]}, {"time": RAW_TIMES[2]}, {"time": RAW_TIMES[3]}]
	var chain_bytes: PackedByteArray = var_to_bytes(chain)
	var plan: Dictionary = Clock.offsets(chain)
	check(is_equal_approx(RAW_TIMES[1], RAW_TIMES[2]) and is_equal_approx(RAW_TIMES[2], RAW_TIMES[3])
		and not is_equal_approx(RAW_TIMES[1], RAW_TIMES[3]) and plan.ok
		and plan.offsets == [RAW_TIMES[1], RAW_TIMES[1], RAW_TIMES[1]] and var_to_bytes(chain) == chain_bytes,
		"Actual packed clock accepts adjacent ties whose maximum/end pair is not tied, preserving raw offsets",
		{"raw_times": RAW_TIMES, "neighbor_tie": true, "max_pair_tie": false, "plan": plan})
	var rejected_all: bool = true
	for invalid: Variant in [null, {}, [{}], [{"time": true}], [{"time": NAN}], [{"time": INF}], [{"time": -0.001}], [{"time": 0.01}, {"time": 0.009}]]:
		var rejected: Dictionary = Clock.offsets(invalid)
		rejected_all = rejected_all and not rejected.ok and rejected.offsets.is_empty()
	check(rejected_all and Clock.offsets([{"time": 0.0}]).offsets == [0.0]
		and Clock.offsets([{"time": 0.00001}, {"time": 0.2}]).offsets == [0.00001, 0.2],
		"Genuine reverse/malformed clocks reject without partial output; each batch starts fresh")
	var burn: RefCounted = Burn.new()
	var admitted: bool = burn.monster_ids_at_time(0.0).is_empty()
	admitted = burn.apply("monster", 10, 0, 1.0, 0.3, 0.1, origin(0.1, 0.3)).ok and admitted
	admitted = burn.apply("monster", 2, 0, 1.0, 0.3, 0.1).ok and admitted
	admitted = burn.apply("player", 0, 2, 1.0, 3.0, 1.0).ok and admitted
	var public_states: Array[Dictionary] = burn.statuses()
	check(admitted and public_states.size() == 3 and public_states[0].target_id == 2 and public_states[1].target_id == 10
		and public_states[2].target_kind == "player" and burn.monster_ids_at_time(0.1) == [2, 10],
		"Public status snapshots sort monster IDs numerically 2,10; later player clock is independent")
	var original_states: PackedByteArray = var_to_bytes(burn.statuses())
	public_states[1].provenance.ember_generation = 1
	public_states[0].raw_dps = 999.0
	public_states.clear()
	var public_single: Dictionary = burn.status_for("monster", 10)
	public_single.provenance.ember_expiry = 999.0
	var public_ids: Array[int] = burn.monster_ids_at_time(0.1)
	public_ids.clear()
	check(var_to_bytes(burn.statuses()) == original_states and burn.monster_ids_at_time(0.1) == [2, 10],
		"Public statuses/status_for deep-copy nested provenance and returned numeric IDs are detached")
	var zero: Dictionary = burn.advance_target("monster", 2, 0.1)
	var reverse: Dictionary = burn.advance_target("monster", 2, 0.09)
	check(zero.ok and zero.segments.is_empty() and not reverse.ok and reverse.segments.is_empty()
		and var_to_bytes(burn.statuses()) == original_states,
		"Exact zero-width advancement is bit-exact; actual BurnRuntime rejects genuine reversal atomically")
	var proof: bool = burn.monster_ids_at_time(false).is_empty() and burn.monster_ids_at_time(INF).is_empty()
	proof = proof and burn.monster_ids_at_time(0.2).is_empty()
	var advanced: Dictionary = burn.advance_target("monster", 2, 0.2)
	proof = proof and advanced.ok and not advanced.segments.is_empty() and burn.monster_ids_at_time(0.2).is_empty()
	var replaced: Dictionary = burn.apply("monster", 10, 0, 2.0, 0.3, 0.2)
	proof = proof and replaced.ok and burn.monster_ids_at_time(0.2) == [2, 10]
	var extra: Dictionary = burn.apply("monster", 7, 0, 1.0, 0.3, 0.1)
	proof = proof and extra.ok and burn.monster_ids_at_time(0.2).is_empty()
	var removed: Dictionary = burn.remove("monster", 7)
	proof = proof and removed.ok and removed.removed and burn.monster_ids_at_time(0.2) == [2, 10]
	check(proof, "Same-time IDs inspect fresh clocks after advancement, replacement, insertion and removal; invalid/positive-width proof fails")
	var cast: Dictionary = Compiler.compile_group("tornado", model.get_combat_snapshot(), ["ember_proliferation"])
	if not check(cast.get("ok", false) and cast.get("snapshot", {}).has("burn_proliferation")
		and cast.snapshot.has("burn_policy") and cast.get("packets", {}).has("parent")
		and cast.packets.parent.skill_id == "tornado" and same_data(baseline, model.snapshot()),
		"Actual packed current-profile compiler supplies ember tornado payload and snapshot without canonical mutation"):
		await finish(); return
	var initial: Dictionary = run_clock_case(fixture, 0.0, cast)
	var long_clock: Dictionary = run_clock_case(fixture, 1000000.0, cast)
	check(initial.get("ok", false) and long_clock.get("ok", false)
		and initial.get("expected_original", false) and long_clock.get("expected_original", false),
		"Real packed projectile runtime retains frozen four-event raw times, target order and sequences", {"initial": initial, "long_clock": long_clock})
	check(initial.get("dispatch_exact", false), "Actual main at zero uptime dispatches four nonlethal hits and three generation-zero burns with exact raw trace and adapted clock", initial)
	check(long_clock.get("dispatch_exact", false), "Actual main at long uptime retains the same four-hit order and three causal burn clocks", long_clock)
	check(initial.get("guards_clear", false) and long_clock.get("guards_clear", false),
		"Both real projectile batches clear the event-clock cache and all ember advancement/death guards")
	check(initial.get("resources_unchanged", false) and long_clock.get("resources_unchanged", false)
		and initial.get("rng_exact", false) and long_clock.get("rng_exact", false),
		"Nonlethal dispatch preserves player resources/rewards/save and exactly the existing cosmetic RNG draws; critical RNG does not advance")
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.monster_runtime.reset()
	arena.burn_runtime.reset()
	arena._burn_step_active = false
	arena.elapsed = 0.2
	var living: Dictionary = arena.monster_runtime.create_root("brute", 6, arena.ARENA.get_center(), "ordinary", "", [], true)
	var dead: Dictionary = arena.monster_runtime.create_root("brute", 6, arena.ARENA.get_center() + Vector2(40, 0), "ordinary", "", [], true)
	if living.is_empty() or dead.is_empty():
		report.error = "Actual catalog cleanup actors could not be created"
		await finish(); return
	living.spawn = 0.0
	dead.spawn = 0.0
	arena.enemies.assign([living, dead])
	var cleanup_admitted: bool = arena.burn_runtime.apply("monster", living.id, 0, 1.0, 3.0, 0.2, origin(0.2, 3.0)).ok
	cleanup_admitted = arena.burn_runtime.apply("monster", dead.id, 0, 1.0, 3.0, 0.2, origin(0.2, 3.0)).ok and cleanup_admitted
	cleanup_admitted = arena.burn_runtime.apply("monster", 99, 0, 1.0, 3.0, 0.2, origin(0.2, 3.0)).ok and cleanup_admitted
	dead.health = 0.0
	var live_before: Dictionary = arena.burn_runtime.status_for("monster", living.id)
	var body_before: PackedByteArray = var_to_bytes(living)
	var quiet_before: Dictionary = quiet_receipt()
	arena._advance_proliferating_burns(0.2)
	check(cleanup_admitted and arena.burn_runtime.statuses().size() == 1
		and arena.burn_runtime.status_for("monster", dead.id).is_empty() and arena.burn_runtime.status_for("monster", 99).is_empty()
		and var_to_bytes(arena.burn_runtime.status_for("monster", living.id)) == var_to_bytes(live_before)
		and var_to_bytes(living) == body_before,
		"Actual main same-time path removes dead/missing bodies and preserves live status/body bit-for-bit")
	check(same_data(quiet_before, quiet_receipt()) and not arena._ember_advancing and not arena._ember_defer_deaths and not arena._ember_flushing,
		"Same-time cleanup emits no damage/hit/reward, consumes no RNG, changes no resources/save and releases guards")
	var stronger: Dictionary = live_before.duplicate(true)
	stronger.raw_dps = 5.0
	arena._ember_deaths.append({"id": 99, "origin": living.pos + Vector2(10, 0), "at": 0.2, "status": stronger})
	arena._advance_proliferating_burns(0.2)
	var received: Dictionary = arena.burn_runtime.status_for("monster", living.id)
	var transferred: bool = arena._ember_deaths.is_empty() and not received.is_empty()
	if transferred:
		transferred = received.raw_dps == 5.0 and received.provenance.ember_generation == 1 \
			and received.provenance.ember_expiry == live_before.provenance.ember_expiry and received.last_time == 0.2
		var spent: Dictionary = received.duplicate(true)
		spent.raw_dps = 9.0
		arena._ember_deaths.append({"id": 99, "origin": living.pos + Vector2(10, 0), "at": 0.2, "status": spent})
		arena._advance_proliferating_burns(0.2)
		transferred = transferred and var_to_bytes(arena.burn_runtime.status_for("monster", living.id)) == var_to_bytes(received)
	check(transferred and arena._ember_deaths.is_empty() and var_to_bytes(living) == body_before
		and same_data(quiet_before, quiet_receipt()) and not arena._ember_advancing and not arena._ember_defer_deaths and not arena._ember_flushing,
		"Queued same-time transfer retains expiry, applies one hop only, causes no instant damage/resource/reward/RNG/save change and clears guards",
		{"received": received, "original_expiry": live_before.get("provenance", {}).get("ember_expiry", -1.0)})
	var restored: RefCounted = Model.new()
	var loaded: bool = restored.load_build(save_path)
	check(loaded and same_data(baseline, model.snapshot()) and same_data(baseline, restored.snapshot())
		and restored.snapshot().version == 30 and restored.snapshot().talents.source_version == "3.29.1"
		and original_disk == FileAccess.get_file_as_bytes(save_path) and model.save_attempts == attempts_before + 1
		and model.successful_saves == saves_before + 1 and restored.save_attempts == 0 and restored.successful_saves == 0
		and FileAccess.get_file_as_bytes(fixture_path) == fixture_bytes and var_to_bytes(fixture) == fixture_bytes,
		"One fresh-model reload exactly restores unchanged schema30/source profile; no combat save or frozen-fixture mutation",
		{"loaded": loaded, "disk_sha256": sha256(original_disk), "model_save_attempts": model.save_attempts, "model_successful_saves": model.successful_saves})
	await finish()
