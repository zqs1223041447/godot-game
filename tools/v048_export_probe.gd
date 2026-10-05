extends SceneTree
## Short same-PCK evidence only: one real camp plus a rewardless attack fixture.
## Natural 36-root/boss/reward completion is covered by the source main70 test.
## This probe does not claim Windows-native, visual, full-suite, or 600s coverage.
const Catalog = preload("res://scripts/world/map_catalog.gd")
const Normal = preload("res://scripts/world/normal_map_catalog.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const EXPECTED_CHECKS: int = 20
const FONT_SHA256: String = "c43797ccb46c17240acd21ffca909282d45c0cd8586afb945144013ac0de3ca4"
const FONT_MAPPED_CODEPOINTS: int = 1069
const FONT_CHARACTERS: String = "晴泉台地西北东阶据点脉双响霜纹雷回锁定"
var arena: Node
var output: String
var results: Array[Dictionary] = []
var failures: int = 0
var finished: bool = false
var report: Dictionary = {"ok": false, "status": "running", "probe": "v048_export_probe",
	"scope": "Same-PCK headless runtime; one natural camp and a rewardless map_boss attack fixture; not natural boss unlock, Windows-native, or visual acceptance",
	"natural_completion_source_test": "tests/sunwell_gameplay_test.gd (separate source main70 evidence)"}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String, evidence: Dictionary = {}) -> bool:
	results.append({"ok": value, "label": label, "evidence": evidence})
	if not value:
		failures += 1
		push_error("Packed v48 probe: " + label)
	return value

func close(a: float, b: float) -> bool:
	return is_finite(a) and absf(a - b) <= 0.000001 * maxf(1.0, absf(b))

func sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func json_data(value: Variant) -> Variant:
	# Normalize both sides at a JSON boundary, then compare recursively and
	# strictly. JSON numbers are floats; key insertion order is not content.
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func write_report() -> bool:
	var file := FileAccess.open(output.path_join("packed-runtime-probe.json"), FileAccess.WRITE)
	if file == null:
		push_error("Packed v48 probe cannot write report: " + str(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	return true

func watchdog() -> void:
	if finished: return
	report.ok = false; report.status = "aborted"
	report.error = "Probe did not complete within 45 seconds; reject this run"
	report.results = results; report.checks = results.size(); report.failures = failures + 1
	write_report()
	push_error("Packed v48 probe timed out or stopped after a runtime error")
	quit(1)

func finish() -> void:
	finished = true
	if results.size() != EXPECTED_CHECKS:
		failures += 1
		report.error = "Incomplete check count; reject this run"
	report.ok = failures == 0 and results.size() == EXPECTED_CHECKS
	report.status = "complete" if report.ok else "failed"
	report.results = results; report.checks = results.size()
	report.expected_checks = EXPECTED_CHECKS; report.failures = failures
	var written: bool = write_report()
	var success: bool = bool(report.ok) and written
	print("Packed v48 Sunwell probe: %s (%d/%d checks, %d failures)" % ["PASS" if success else "FAIL", results.size(), EXPECTED_CHECKS, failures])
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	quit(0 if success else 1)

func run() -> void:
	output = OS.get_environment("V048_PROBE_OUTPUT")
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(user_args.size()):
		if user_args[index].begins_with("--output-dir="):
			output = user_args[index].trim_prefix("--output-dir=")
		elif user_args[index] == "--output-dir" and index + 1 < user_args.size():
			output = user_args[index + 1]
	var command: PackedStringArray = OS.get_cmdline_args()
	var pack_index: int = command.find("--main-pack")
	# Godot consumes --main-pack before exposing OS.get_cmdline_args(). The
	# runner supplies the exact PCK path; an empty res root proves packed mode.
	var pack_path: String = command[pack_index + 1] if pack_index >= 0 and pack_index + 1 < command.size() else OS.get_environment("V048_MAIN_PACK")
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if output.is_empty() or pack_path.is_empty() or not FileAccess.file_exists(pack_path) or not ProjectSettings.globalize_path("res://").is_empty() or not isolated.begins_with("/tmp/godot-m1-"):
		push_error("Packed v48 probe requires a loaded --main-pack, V048_MAIN_PACK path, V048_PROBE_OUTPUT, and isolated /tmp/godot-m1-* XDG_DATA_HOME")
		quit(78); return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Packed v48 probe cannot create output directory")
		quit(1); return
	# The runner must require completion, exact check count, exit zero, and no
	# ERROR lines. This receipt remains running if loading/assertion interrupts.
	if not write_report(): quit(1); return
	create_timer(45.0).timeout.connect(watchdog)
	report.command_line = Array(command)
	report.main_pack = pack_path
	report.main_pack_sha256 = sha256(FileAccess.get_file_as_bytes(pack_path))
	report.engine = Engine.get_version_info().string
	report.platform = OS.get_name()
	report.probe_resource = get_script().resource_path
	report.probe_sha256 = sha256(FileAccess.get_file_as_bytes(get_script().resource_path))
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		report.error = "Packed main scene could not load"
		await finish(); return
	arena = scene.instantiate()
	root.add_child(arena)
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await process_frame
	var model: RefCounted = arena.state
	report.version = str(ProjectSettings.get_setting("application/config/version"))
	report.actual_source_version = report.version
	report.schema = model.snapshot().version
	report.save_dir = str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	report.user_dir = OS.get_user_data_dir()
	report.bag = model.bag_layout()
	check(report.version == "0.48.0" and report.schema == 30 and report.save_dir == "godot-game-preview-v021" and report.bag == {"pages": 2, "columns": 12, "rows": 10}, "Packed version 0.48.0, schema30, original v021 save identity, and 240 bag cells", {"version": report.version, "schema": report.schema, "save_dir": report.save_dir, "bag": report.bag})
	var tiers: Array[Dictionary] = Normal.tiers("sunwell_terrace", 0)
	var tier_contract: bool = tiers.size() == 3
	for index: int in range(tiers.size()):
		tier_contract = tier_contract and tiers[index].wave == [3, 6, 10][index] and tiers[index].cost == [0, 4, 8][index] and tiers[index].unlocked == (index == 0)
	check(Catalog.MAPS.keys() == ["old_garden", "broken_ruins", "sunwell_terrace"] and Catalog.MAPS.sunwell_terrace.name == "晴泉台地" and Catalog.MAPS.sunwell_terrace.ordinary_target == 36 and Catalog.MAPS.sunwell_terrace.boss_attack_id == "sunwell_echo" and tier_contract, "Third map catalog and normal tiers use waves 3/6/10, fees 0/4/8, and initial tier locks", {"map_ids": Catalog.MAPS.keys(), "tiers": tiers})
	var town: Dictionary = arena.world_context()
	var saved: bool = arena.save_build()
	var town_state: Dictionary = model.snapshot()
	var town_disk: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	var draft_before: Dictionary = arena.map_draft()
	var locked: Dictionary = arena.craft_normal_map("sunwell_terrace", 2, [], [], draft_before.revision)
	check(saved and town.normal_town and not town.test_mode and model.normal_journey().best_tiers.sunwell_terrace == 0 and not locked.get("ok", true) and locked.get("code", "") == "tier_locked" and Same._same_data(draft_before, arena.map_draft()) and Same._same_data(town_state, model.snapshot()) and town_disk == FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH), "Actual normal town refuses locked Sunwell II without draft, state, or disk mutation", {"town": town, "rejected": locked})
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	var missing: String = ""
	if font != null:
		font.allow_system_fallback = false
		for index: int in FONT_CHARACTERS.length():
			if not font.has_char(FONT_CHARACTERS.unicode_at(index)): missing += FONT_CHARACTERS[index]
		report.font_sha256 = sha256(font.data)
		report.font_raw_bytes = font.data.size()
		report.font_mapped_codepoints = font.get_supported_chars().length()
	else: missing = FONT_CHARACTERS
	check(font != null and report.get("font_sha256", "") == FONT_SHA256 and report.get("font_raw_bytes", 0) == 415088 and report.get("font_mapped_codepoints", 0) == FONT_MAPPED_CODEPOINTS and missing.is_empty(), "Exact 1069-codepoint bundled font and new map glyphs load without system fallback", {"actual_sha256": report.get("font_sha256", ""), "expected_sha256": FONT_SHA256, "raw_bytes": report.get("font_raw_bytes", 0), "mapped_codepoints": report.get("font_mapped_codepoints", 0), "required": FONT_CHARACTERS, "missing": missing})
	var craft: Dictionary = arena.craft_normal_map("sunwell_terrace", 1, [], [], arena.map_draft().revision)
	var start: Dictionary = arena.start_map(arena.map_draft().revision) if craft.get("ok", false) else {"ok": false, "reason": "craft failed"}
	arena.hud._process(0.0)
	for index: int in range(4):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	if not check(craft.get("ok", false) and start.get("ok", false) and arena.world_context().mode == "map" and not arena.world_context().test_mode and arena.world_context().map_id == "sunwell_terrace" and arena.world_context().map_tier == 1 and arena.world_context().fee_paid == 0 and not arena.hud.is_blocking(), "Actual craft_normal_map Sunwell I and start_map enter the real normal map", {"craft": craft, "start": start, "world": arena.world_context()}):
		await finish(); return
	# Entry is an expected save transaction. All runtime purity comparisons
	# deliberately start here, after entry, never against the earlier town bytes.
	var baseline: Dictionary = model.snapshot()
	var disk: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	var saves: int = model.successful_saves
	var attempts: int = model.save_attempts
	var rng: int = arena.rng.state
	var critical: Dictionary = arena.critical_runtime.checkpoint()
	var leech: Dictionary = arena.leech_runtime.snapshot()
	var parsed_disk: Variant = JSON.parse_string(disk.get_string_from_utf8())
	check(not disk.is_empty() and not model.normal_journey().active_run.is_empty() and Same._same_data(json_data(baseline), parsed_disk), "Post-entry canonical baseline equals saved JSON through strict recursive comparison", {"save_bytes": disk.size(), "disk_sha256": sha256(disk), "successful_saves": saves, "save_attempts": attempts, "active_run": model.normal_journey().active_run})
	var geometry: Dictionary = arena.world_geometry()
	var marks: Dictionary = geometry.get("landmarks", {})
	var basins: Array[Dictionary] = []
	var solid: bool = geometry.get("id", "") == "sunwell_terrace" and geometry.get("obstacle_style", "") == "spring_basin" and geometry.get("walls", []).size() == 4
	for index: int in range(geometry.get("walls", []).size()):
		var wall: Rect2 = geometry.walls[index]
		var from: Vector2 = wall.get_center() - Vector2(wall.size.x * 0.5 + 40.0, 0.0)
		var to: Vector2 = wall.get_center() + Vector2(wall.size.x * 0.5 + 40.0, 0.0)
		var sweep: Dictionary = arena._geometry.sweep(from, to, arena.PLAYER_RADIUS)
		var moved: Vector2 = arena._geometry.move(from, to, arena.PLAYER_RADIUS)
		var blocked: bool = not arena._geometry.is_clear(wall.get_center(), 0.0) and sweep.hit and sweep.wall == index and not arena._geometry.visible(from, to) and moved.distance_to(to) > 1.0 and arena._geometry.is_clear(moved, arena.PLAYER_RADIUS)
		solid = solid and blocked
		basins.append({"index": index, "wall": wall, "blocked": blocked, "sweep": sweep, "moved": moved})
	check(solid, "All four physical spring basins block real movement, sweep, and visibility", {"basins": basins})
	var dormant: bool = marks.get("camps", []).size() == 3
	for camp: Dictionary in marks.get("camps", []): dormant = dormant and camp.root_count == 12
	check(dormant and arena.enemies.is_empty() and arena.world_context().ordinary_target == 36 and arena.world_context().boss_phase == "sealed" and arena._map_run.snapshot().admitted == 0, "Three dormant camps expose 36 targets with zero initial monsters and sealed boss", {"landmarks": marks, "run": arena._map_run.snapshot()})
	if marks.get("camps", []).size() != 3:
		await finish(); return
	var selected: Dictionary = marks.camps[0]
	arena.player_pos = selected.trigger_center
	arena._update_map_spawning(0.0)
	var births: bool = arena.enemies.size() == 12
	var ids: Array = []
	for enemy: Dictionary in arena.enemies:
		ids.append(enemy.id)
		births = births and close(enemy.spawn, 0.6) and arena._geometry.is_clear(enemy.pos, enemy.radius) and enemy.root_id == enemy.id and enemy.reward_eligible
	check(births and arena._map_run.snapshot().admitted == 12, "Actual single camp trigger admits twelve roots with 0.6s birth protection and clear geometry", {"camp": selected.id, "ids": ids, "run": arena._map_run.snapshot()})
	arena._update_map_spawning(0.0)
	var ids_after: Array = []
	for enemy: Dictionary in arena.enemies: ids_after.append(enemy.id)
	check(Same._same_data(ids, ids_after) and arena._map_run.snapshot().admitted == 12 and arena.rng.state == rng, "Repeated actual trigger neither duplicates roots nor consumes gameplay RNG", {"ids_before": ids, "ids_after": ids_after, "rng_before": str(rng), "rng_after": str(arena.rng.state)})
	# Keep real camp roots alive but inert and remote: no reward/death shortcuts.
	for index: int in range(arena.enemies.size()):
		var enemy: Dictionary = arena.enemies[index]
		enemy.speed = 0.0; enemy.attack_timer = 1000.0; enemy.knockback = Vector2.ZERO
		enemy.pos = arena.ARENA.position + Vector2(60.0 + 60.0 * (index % 6), 45.0 + 90.0 * (index / 6))
	var boss: Dictionary = arena._spawn_monster("rift_warden", marks.boss.center, "map_boss", "", [], false)
	if not check(not boss.is_empty() and boss.get("map_boss_attack_id", "") == "sunwell_echo" and not boss.get("reward_eligible", true) and arena._map_run.boss_id == 0 and arena.world_context().boss_phase == "sealed", "Rewardless map_boss attack fixture uses real admission; natural boss remains sealed", {"fixture_id": boss.get("id", 0), "reward_eligible": boss.get("reward_eligible", true), "registered_boss_id": arena._map_run.boss_id, "natural_boss_phase": arena.world_context().boss_phase}):
		await finish(); return
	boss.spawn = 0.0; boss.speed = 0.0; boss.knockback = Vector2.ZERO; boss.attack_timer = 0.0
	# Overlap the stationary boss body during the second warning to expose any
	# accidental extra contact hit independently of the later pulse immunity.
	var fixed: Vector2 = boss.pos
	arena.player_pos = fixed
	var original_stats: Dictionary = arena._stats.duplicate(true)
	var original_health: float = arena.health
	var original_shield: float = arena.shield
	arena._stats.max_health = 10000.0; arena._stats.max_shield = 5000.0
	arena._stats.life_regen = 0.0; arena._stats.shield_recharge_rate = 0.0
	arena._stats.armour = 0.0; arena._stats.evasion = 0.0
	arena.health = 10000.0; arena.shield = 7.0; arena.invulnerable = 0.0
	arena._player_evasion_entropy = 99.0
	arena.telegraphs.reset(); arena.telegraph_trace.clear(); arena.incoming_damage_trace.clear()
	arena._start_enemy_telegraphs()
	var attack: Dictionary = arena.telegraphs.state_for(boss.id)
	if not check(not attack.is_empty() and attack.center == fixed and attack.phase == "windup" and attack.pulse_index == 0 and attack.pulse_count == 2 and close(attack.elapsed, 0.0) and close(attack.profile.radius, 85.0) and close(attack.profile.windup_seconds, 0.8) and close(attack.profile.damage_multiplier, 0.65) and arena.rng.state == rng, "Real boss start freezes the point and two 0.8s, radius85, 0.65D pulses without RNG", {"attack": attack, "locked_point": fixed}):
		await finish(); return
	var expected: Dictionary = Defense.incoming_source_hit(attack.packet.base, arena._stats, arena.shield, arena.health, "player")
	# Northward dodge stays clear of the dormant north camp's southern trigger.
	arena.player_pos = fixed + Vector2(0.0, -150.0)
	arena.tick(0.79)
	var early: Dictionary = arena.telegraphs.state_for(boss.id)
	check(arena.telegraph_trace.is_empty() and arena.incoming_damage_trace.is_empty() and early.get("pulse_index", -1) == 0 and close(early.get("elapsed", -1.0), 0.79) and close(arena.health, 10000.0) and close(arena.shield, 7.0), "No pulse occurs before 0.8s and getter reports current first-warning elapsed", {"state": early, "elapsed": arena.elapsed})
	arena.tick(0.01)
	var second: Dictionary = arena.telegraphs.state_for(boss.id)
	var first_event: Dictionary = arena.telegraph_trace[0] if arena.telegraph_trace.size() == 1 else {}
	check(first_event.get("inside", true) == false and first_event.get("applied", true) == false and first_event.get("pulse_index", -1) == 0 and close(first_event.get("attack_age", -1.0), 0.8) and first_event.get("center") == fixed and close(first_event.get("radius", -1.0), 85.0) and second.get("phase", "") == "windup" and second.get("pulse_index", -1) == 1 and second.get("center") == fixed and close(second.get("elapsed", -1.0), 0.0), "Walking outside avoids first pulse at 0.8s; second full warning retains the locked circle", {"event": first_event, "second_warning": second})
	arena.player_pos = fixed
	arena.tick(0.4)
	var midway: Dictionary = arena.telegraphs.state_for(boss.id)
	check(arena.telegraph_trace.size() == 1 and arena.incoming_damage_trace.is_empty() and close(arena.health, 10000.0) and close(arena.shield, 7.0) and midway.get("pulse_index", -1) == 1 and close(midway.get("elapsed", -1.0), 0.4) and arena.player_pos.distance_to(boss.pos) < arena.PLAYER_RADIUS + float(boss.radius) and close(boss.attack_timer, 0.0), "Returning into boss contact during second warning causes no contact damage; getter age is 0.4s", {"state": midway, "incoming_count": arena.incoming_damage_trace.size(), "player": arena.player_pos, "boss": boss.pos})
	arena.tick(0.4)
	var second_event: Dictionary = arena.telegraph_trace[1] if arena.telegraph_trace.size() == 2 else {}
	var settlement: Dictionary = arena.incoming_damage_trace[0] if arena.incoming_damage_trace.size() == 1 else {}
	check(expected.get("ok", false) and second_event.get("applied", false) and second_event.get("inside", false) and second_event.get("pulse_index", -1) == 1 and close(second_event.get("attack_age", -1.0), 1.6) and second_event.get("center") == fixed and close(second_event.get("radius", -1.0), 85.0) and settlement.get("source_id", -1) == boss.id and close(settlement.get("shield_spent", -1.0), 7.0) and float(settlement.get("health_lost", 0.0)) > 0.0 and close(arena.shield, float(expected.get("remaining_shield", -1.0))) and close(arena.health, float(expected.get("remaining_health", -1.0))), "Second pulse at 1.6s settles one real packet through shield then health at the original point", {"event": second_event, "settlement": settlement, "expected": expected, "health": arena.health, "shield": arena.shield})
	var recovering: Dictionary = arena.telegraphs.state_for(boss.id)
	check(recovering.get("phase", "") == "recovery" and recovering.get("pulse_index", -1) == 1 and recovering.get("center") == fixed and close(recovering.get("elapsed", -1.0), 0.8) and close(arena.invulnerable, 0.32) and arena.incoming_damage_trace.size() == 1, "Recovery follows second pulse with current getter age and only one incoming damage settlement", {"state": recovering, "invulnerable": arena.invulnerable, "incoming_count": arena.incoming_damage_trace.size()})
	boss.attack_timer = 1000.0
	var health_after: float = arena.health
	var shield_after: float = arena.shield
	arena.tick(1.9)
	check(arena.telegraphs.state_for(boss.id).is_empty() and arena.telegraph_trace.size() == 2 and arena.incoming_damage_trace.size() == 1 and close(arena.health, health_after) and close(arena.shield, shield_after), "After complete 1.9s recovery the fixture has no active sequence or extra damage", {"elapsed": arena.elapsed, "state": arena.telegraphs.state_for(boss.id), "pulse_count": arena.telegraph_trace.size(), "incoming_count": arena.incoming_damage_trace.size()})
	arena._stats = original_stats; arena.health = original_health; arena.shield = original_shield
	check(arena._map_run.boss_id == 0 and not arena._map_run.ready_for_boss() and arena.world_context().boss_phase == "sealed" and arena._map_run.snapshot().admitted == 12 and arena.enemies.size() == 13 and arena._map_run.snapshot().ordinary_kills == 0 and arena.kills == 0 and arena.reward_kills == 0 and model.normal_journey().best_tiers.sunwell_terrace == 0 and Same._same_data(arena._stats, original_stats), "Attack fixture never claims natural boss unlock, extra camps, kills, rewards, or progression; player fixture stats restored", {"run": arena._map_run.snapshot(), "enemy_count": arena.enemies.size(), "reward_kills": arena.reward_kills, "best_tier": model.normal_journey().best_tiers.sunwell_terrace})
	var final_disk: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(Same._same_data(baseline, model.snapshot()) and Same._same_data(parsed_disk, JSON.parse_string(final_disk.get_string_from_utf8())) and disk == final_disk and model.successful_saves == saves and model.save_attempts == attempts and arena.rng.state == rng and Same._same_data(critical, arena.critical_runtime.checkpoint()) and Same._same_data(leech, arena.leech_runtime.snapshot()), "Post-entry runtime consumes no unexpected RNG, critical roll, leech, canonical mutation, or save write", {"canonical_same": Same._same_data(baseline, model.snapshot()), "disk_bytes_same": disk == final_disk, "disk_sha256_before": sha256(disk), "disk_sha256_after": sha256(final_disk), "saves_before": saves, "saves_after": model.successful_saves, "attempts_before": attempts, "attempts_after": model.save_attempts, "rng_before": str(rng), "rng_after": str(arena.rng.state)})
	await finish()
