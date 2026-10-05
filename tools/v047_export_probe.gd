extends SceneTree
## Short final-PCK runtime evidence only. This does not run the historical
## source suite, a 600-second simulation, or Windows-native/visual acceptance.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const EXPECTED_CHECKS: int = 18
const GEM_ID: String = "support:ember_proliferation"
const ICON_PATH: String = "res://assets/ui/grimoire/ember_proliferation.png"
const FONT_CHARACTERS: String = "燃余烬扩散"
var arena: Node
var output: String
var results: Array[Dictionary] = []
var failures: int = 0
var report: Dictionary = {"ok": false, "status": "running", "probe": "v047_export_probe",
	"scope": "Same-PCK headless runtime; not Windows-native or visual review"}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String, evidence: Dictionary = {}) -> bool:
	results.append({"ok": value, "label": label, "evidence": evidence})
	if not value:
		failures += 1
		push_error("Packed v47 probe: " + label)
	return value

func close(a: float, b: float) -> bool:
	return absf(a - b) <= 0.000001 * maxf(1.0, absf(b))

func sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func target(offset: Vector2) -> Dictionary:
	# Use the actual admission path. Rewardless roots isolate status/death work
	# from the existing progression, loot, and save transactions.
	var enemy: Dictionary = arena._spawn_monster("brute", arena.player_pos + offset, "ordinary", "", [], false)
	if enemy.is_empty(): return enemy
	enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0
	enemy.shield = 0.0; enemy.max_shield = 0.0; enemy.armour = 0.0; enemy.evasion = 0.0
	enemy.speed = 0.0; enemy.attack_timer = 1000.0; enemy.resistances.fire = 0.0
	enemy.shield_recharge_rate = 0.0; enemy.shield_regen = 0.0
	return enemy

func status(enemy: Dictionary) -> Dictionary:
	return arena.burn_runtime.status_for("monster", int(enemy.id))

func hit(enemy: Dictionary, compiled: Dictionary) -> Dictionary:
	var frozen: Dictionary = arena.critical_runtime.freeze(compiled.snapshot)
	if not frozen.get("ok", false): return {}
	var before: int = arena.damage_trace.size()
	# Apply a real compiler packet through main to the source only. This avoids
	# accidentally treating two meteor AoE hits as evidence of propagation.
	arena._apply_damage_packet(enemy, compiled.packets.direct, frozen.snapshot, Color.ORANGE)
	return arena.damage_trace.back().duplicate(true) if arena.damage_trace.size() == before + 1 else {}

func advance(to_time: float) -> void:
	arena.elapsed = to_time
	arena._advance_monster_burns(to_time)

func last_burn(enemy: Dictionary) -> Dictionary:
	for index: int in range(arena.burn_trace.size() - 1, -1, -1):
		var row: Dictionary = arena.burn_trace[index]
		if row.target_kind == "monster" and int(row.target_id) == int(enemy.id):
			return row.duplicate(true)
	return {}

func write_report() -> bool:
	var file := FileAccess.open(output.path_join("packed-runtime-probe.json"), FileAccess.WRITE)
	if file == null:
		push_error("Packed v47 probe cannot write report: " + str(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true

func finish() -> void:
	report.ok = failures == 0 and results.size() == EXPECTED_CHECKS
	report.status = "complete" if report.ok else "failed"
	report.results = results
	report.checks = results.size()
	report.expected_checks = EXPECTED_CHECKS
	report.failures = failures
	var written: bool = write_report()
	var success: bool = bool(report.ok) and written
	print("Packed v47 ember proliferation probe: %s (%d/%d checks, %d failures)" % ["PASS" if success else "FAIL", results.size(), EXPECTED_CHECKS, failures])
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	quit(0 if success else 1)

func run() -> void:
	output = OS.get_environment("V047_PROBE_OUTPUT")
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(user_args.size()):
		if user_args[index].begins_with("--output-dir="):
			output = user_args[index].trim_prefix("--output-dir=")
		elif user_args[index] == "--output-dir" and index + 1 < user_args.size():
			output = user_args[index + 1]
	var command: PackedStringArray = OS.get_cmdline_args()
	var pack_index: int = command.find("--main-pack")
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if output.is_empty() or pack_index < 0 or pack_index + 1 >= command.size() or not isolated.begins_with("/tmp/godot-m1-"):
		push_error("Packed v47 probe requires --main-pack, V047_PROBE_OUTPUT (or -- --output-dir PATH), and isolated /tmp/godot-m1-* XDG_DATA_HOME")
		quit(78); return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Packed v47 probe cannot create output directory")
		quit(1); return
	# Leave an incomplete receipt if loading or an assertion interrupts the run.
	# The runner must also reject ERROR lines and a nonzero process exit.
	if not write_report(): quit(1); return
	report.command_line = Array(command)
	report.main_pack = command[pack_index + 1]
	report.engine = Engine.get_version_info().string
	report.platform = OS.get_name()
	report.probe_resource = get_script().resource_path
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await process_frame
	var model: RefCounted = arena.state
	report.version = str(ProjectSettings.get_setting("application/config/version"))
	report.schema = model.snapshot().version
	report.save_dir = str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	report.user_dir = OS.get_user_data_dir()
	report.bag = model.bag_layout()
	check(report.version == "0.47.0" and report.schema == 29 and report.save_dir == "godot-game-preview-v021" and report.bag == {"pages": 2, "columns": 12, "rows": 10}, "Packed version, schema29, original save identity, and 240 bag cells", {"version": report.version, "schema": report.schema, "save_dir": report.save_dir, "bag": report.bag})
	var metadata: Dictionary = Gems.definition(GEM_ID)
	var gifted: int = 0
	for item: Dictionary in model.snapshot().items.values():
		if item.definition_id == GEM_ID: gifted += 1
	check(metadata.get("definition_id", "") == GEM_ID and metadata.get("kind", "") == "support_gem" and metadata.get("name", "") == "余烬扩散辅助" and metadata.get("family", "") == "burning" and metadata.get("skills", []) == ["meteor", "tornado"] and Gems.minimum_save_version(GEM_ID) == 29 and gifted == 0, "Real new gem metadata is present with zero gifted instances", {"definition_id": metadata.get("definition_id", ""), "name": metadata.get("name", ""), "kind": metadata.get("kind", ""), "family": metadata.get("family", ""), "skills": metadata.get("skills", []), "gifted": gifted})
	var texture := load(ICON_PATH) as Texture2D
	check(texture != null and texture.get_width() > 0 and texture.get_height() > 0 and metadata.get("icon", "") == ICON_PATH and metadata.get("icon_texture") is Texture2D, "Imported ember PNG loads through the packed resource and gem metadata", {"resource": ICON_PATH, "width": texture.get_width() if texture != null else 0, "height": texture.get_height() if texture != null else 0})
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	var missing: String = ""
	if font != null:
		font.allow_system_fallback = false
		for index: int in FONT_CHARACTERS.length():
			if not font.has_char(FONT_CHARACTERS.unicode_at(index)): missing += FONT_CHARACTERS[index]
		# FontFile.data is the bundled raw font, not the imported cache filename.
		report.font_sha256 = sha256(font.data)
		report.font_raw_bytes = font.data.size()
	else:
		missing = FONT_CHARACTERS
	check(font != null and report.get("font_raw_bytes", 0) > 0 and missing.is_empty(), "Bundled font covers 燃余烬扩散 without system fallback; raw SHA256 recorded", {"actual_sha256": report.get("font_sha256", ""), "raw_bytes": report.get("font_raw_bytes", 0), "required": FONT_CHARACTERS, "missing": missing})
	var saved: bool = arena.save_build()
	var pristine: Dictionary = model.snapshot()
	var original_disk: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	var entry: Dictionary = {"ok": true}
	if arena.world_context().normal_town:
		entry = arena.leave_normal_town(arena.world_context().revision)
	arena.hud._process(0.0)
	for index: int in range(4):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	if not check(saved and not original_disk.is_empty() and entry.ok and arena.world_context().mode == "normal" and not arena.world_context().test_mode and not arena.hud.is_blocking() and Same._same_data(pristine, model.snapshot()) and original_disk == FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH), "Saved canonical baseline survives the actual normal-practice transition", {"entry": entry, "save_bytes": original_disk.size(), "world": arena.world_context()}):
		await finish(); return
	var saves_before: int = model.successful_saves
	arena.enemies.clear(); arena.projectiles.clear(); arena.monster_runtime.reset()
	arena.burn_runtime.reset(); arena.feedback_runtime.reset(); arena.leech_runtime.clear()
	arena.damage_trace.clear(); arena.burn_trace.clear(); arena._ember_deaths.clear()
	arena.elapsed = 0.0; arena.player_pos = arena.ARENA.get_center(); arena.spawn_timer = 1000.0
	var compiled: Dictionary = Compiler.compile_group("meteor", Combat.snapshot({"damage": 10.0, "crit_base_chance": 0.0, "crit_base_multiplier": 1.5}, []), ["ember_proliferation"])
	if not check(compiled.get("ok", false) and compiled.get("snapshot", {}).has("burn_proliferation") and compiled.get("burn_profile", {}).get("proliferation", {}).get("enabled", false) and close(compiled.get("burn_profile", {}).get("duration", -1.0), 3.0), "Real meteor compiler provides the ember packet, burn policy, and three-second duration", {"compiled": compiled}):
		await finish(); return
	var source: Dictionary = target(Vector2(80, 0))
	var recipient: Dictionary = target(Vector2(190, 0))
	var third: Dictionary = target(Vector2(300, 0))
	if not check(not source.is_empty() and not recipient.is_empty() and not third.is_empty() and not source.reward_eligible and not recipient.reward_eligible and not third.reward_eligible, "Source, receiver, and next neighbor use actual rewardless monster admission", {"source_id": source.get("id", 0), "recipient_id": recipient.get("id", 0), "third_id": third.get("id", 0)}):
		await finish(); return
	var direct: Dictionary = hit(source, compiled)
	var original: Dictionary = status(source)
	if not check(not direct.is_empty() and direct.skill_id == "meteor" and not original.is_empty() and original.provenance.get("ember_generation", -1) == 0 and close(original.provenance.get("ember_expiry", -1.0), 3.0) and status(recipient).is_empty() and status(third).is_empty() and close(recipient.health, 10000.0), "Only the real direct source hit seeds ember generation zero", {"settlement": direct, "status": original, "recipient_status": status(recipient), "third_status": status(third)}):
		await finish(); return
	arena.elapsed = 0.25
	arena._damage_enemy(source, 1000000.0, Color.WHITE)
	var inherited: Dictionary = status(recipient)
	if not check(source.health <= 0.0 and source.death_processed and status(source).is_empty() and not inherited.is_empty() and inherited.provenance.get("ember_generation", -1) == 1 and close(inherited.last_time, 0.25), "Actual source death at 0.25 seconds creates a generation-one receiver", {"source_health": source.health, "source_death_processed": source.death_processed, "receiver": inherited}):
		await finish(); return
	var dps: float = original.raw_dps
	check(dps > 0.0 and close(inherited.raw_dps, dps) and close(inherited.provenance.ember_expiry, 3.0) and close(inherited.remaining, 2.75) and close(recipient.health, 10000.0) and close(recipient.shield, 0.0) and status(third).is_empty(), "Transfer preserves DPS and absolute 3.0 deadline without instant damage or a duration reset", {"original": original, "inherited": inherited, "recipient_health": recipient.health})
	var rng_before: int = arena.rng.state
	var critical_before: Dictionary = arena.critical_runtime.checkpoint()
	var leech_before: Dictionary = arena.leech_runtime.snapshot()
	var tick_saves_before: int = model.successful_saves
	var tick_disk_before: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	recipient.resistances.fire = 0.5
	recipient.shield = dps * 0.5
	advance(0.75)
	var shield_record: Dictionary = last_burn(recipient)
	check(close(recipient.shield, dps * 0.25) and close(recipient.health, 10000.0) and close(shield_record.get("settlement", {}).get("shield_spent", -1.0), dps * 0.25) and close(shield_record.get("settlement", {}).get("health_lost", -1.0), 0.0), "Inherited burn uses receiver fire resistance and spends shield first", {"record": shield_record, "remaining_shield": recipient.shield, "remaining_health": recipient.health, "expected_spent": dps * 0.25})
	advance(1.75)
	var health_record: Dictionary = last_burn(recipient)
	check(close(recipient.shield, 0.0) and close(10000.0 - float(recipient.health), dps * 0.25) and close(health_record.get("settlement", {}).get("shield_spent", -1.0), dps * 0.25) and close(health_record.get("settlement", {}).get("health_lost", -1.0), dps * 0.25) and close(status(recipient).get("remaining", -1.0), 1.25), "The next real status settlement exhausts shield then reduces health", {"record": health_record, "remaining_shield": recipient.shield, "remaining_health": recipient.health, "expected_health_loss": dps * 0.25})
	check(arena.rng.state == rng_before and Same._same_data(arena.critical_runtime.checkpoint(), critical_before) and Same._same_data(arena.leech_runtime.snapshot(), leech_before) and model.successful_saves == tick_saves_before and tick_disk_before == FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH), "Nonlethal inherited status ticks consume no gameplay RNG, critical roll, leech admission, or save write", {"rng_before": str(rng_before), "rng_after": str(arena.rng.state), "critical_before": critical_before, "critical_after": arena.critical_runtime.checkpoint(), "leech_before": leech_before, "leech_after": arena.leech_runtime.snapshot(), "saves_before": tick_saves_before, "saves_after": model.successful_saves})
	check(not status(recipient).is_empty() and Same._same_data(pristine, model.snapshot()) and original_disk == FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH), "Live inherited status remains runtime-only and absent from canonical save state", {"live_status": status(recipient), "canonical_same": Same._same_data(pristine, model.snapshot()), "disk_bytes_same": original_disk == FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)})
	arena._damage_enemy(recipient, 1000000.0, Color.WHITE)
	check(recipient.health <= 0.0 and recipient.death_processed and status(recipient).is_empty() and status(third).is_empty() and close(third.health, 10000.0) and arena._ember_deaths.is_empty(), "Killing generation one cannot propagate to its nearby third target", {"recipient_health": recipient.health, "third_health": third.health, "third_status": status(third), "pending_transfers": arena._ember_deaths.size()})
	var kills_before: int = arena.kills
	var repeated_rng: int = arena.rng.state
	arena._finish_enemy_death(source)
	arena._finish_enemy_death(recipient)
	check(arena.kills == kills_before and arena.reward_kills == 0 and arena.rng.state == repeated_rng and arena._ember_deaths.is_empty(), "Duplicate real deaths cannot replay transfer, rewards, or legacy random draws", {"kills_before": kills_before, "kills_after": arena.kills, "reward_kills": arena.reward_kills})
	var restart_hit: Dictionary = hit(third, compiled)
	var live_before_restart: bool = not status(third).is_empty()
	arena.restart_run()
	check(not restart_hit.is_empty() and live_before_restart and arena.burn_runtime.is_empty() and arena._ember_deaths.is_empty(), "Actual restart clears a live ember status and pending propagation", {"had_live_status": live_before_restart, "remaining_statuses": arena.burn_statuses(), "pending_transfers": arena._ember_deaths.size()})
	var final_disk: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	# Strict types and recursive data equality deliberately ignore dictionary key
	# insertion order. Serialized Variant bytes would report false mutations.
	check(Same._same_data(pristine, model.snapshot()) and original_disk == final_disk and saves_before == model.successful_saves, "Canonical state, original save bytes, and post-entry save count remain unchanged", {"canonical_same": Same._same_data(pristine, model.snapshot()), "disk_bytes_same": original_disk == final_disk, "disk_sha256_before": sha256(original_disk), "disk_sha256_after": sha256(final_disk), "successful_saves_before": saves_before, "successful_saves_after": model.successful_saves})
	await finish()
