extends SceneTree
## Run this resource from the final PCK with --main-pack, never as release proof
## from a source checkout. No migration, acquisition, or long simulation sweep.
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Renderer = preload("res://scripts/visuals/combat_feedback_renderer.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const EXPECTED_CHECKS: int = 16
const FONT_CHARACTERS: String = "燃暴击!-.<0123456789 "
var arena: Node
var output: String
var results: Array[Dictionary] = []
var failures: int = 0
var report: Dictionary = {"ok":false, "status":"running", "probe":"v046_export_probe",
	"scope":"Same-PCK headless runtime; not Windows-native or visual review"}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String, evidence: Dictionary = {}) -> bool:
	results.append({"ok":value, "label":label, "evidence":evidence})
	if not value:
		failures += 1
		push_error("Packed v46 probe: " + label)
	return value

func close(a: float, b: float) -> bool:
	return absf(a - b) <= 0.000001 * maxf(1.0, absf(b))

func sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func receipt(kind: String, target_id: int) -> Dictionary:
	for entry: Dictionary in arena.damage_feedback():
		if entry.target_kind == "monster" and entry.target_id == target_id and entry.kind == kind:
			return entry
	return {}

func spent(record: Dictionary) -> float:
	return float(record.get("shield_spent", -1.0)) + float(record.get("health_lost", -1.0))

func matches(row: Dictionary, records: Array, count: int) -> bool:
	if row.is_empty(): return false
	var shield: float = 0.0
	var life: float = 0.0
	for record: Dictionary in records:
		shield += float(record.get("shield_spent", -1.0))
		life += float(record.get("health_lost", -1.0))
	return close(row.amount, shield + life) and close(row.shield_spent, shield) \
		and close(row.health_lost, life) and int(row.hit_count) == count

func target(offset: Vector2) -> Dictionary:
	# Actual admitted monsters, with rewards explicitly disabled so their deaths
	# cannot introduce unrelated XP, loot, or save mutations into this probe.
	var enemy: Dictionary = arena._spawn_monster("brute", arena.player_pos + offset, "ordinary", "", [], false)
	if enemy.is_empty(): return enemy
	enemy.spawn = 0.0; enemy.health = 10000.0; enemy.max_health = 10000.0
	enemy.shield = 0.0; enemy.max_shield = 0.0; enemy.armour = 0.0; enemy.evasion = 0.0
	enemy.speed = 0.0; enemy.attack_timer = 1000.0; enemy.resistances = {}
	enemy.shield_recharge_rate = 0.0; enemy.shield_regen = 0.0
	return enemy

func hit(enemy: Dictionary, compiled: Dictionary, role: String = "direct") -> Dictionary:
	var frozen: Dictionary = arena.critical_runtime.freeze(compiled.snapshot)
	if not frozen.get("ok", false):
		push_error("Packed v46 probe: real critical runtime rejected compiler fixture")
		return {}
	var before: int = arena.damage_trace.size()
	arena._apply_damage_packet(enemy, compiled.packets[role], frozen.snapshot, Color.ORANGE)
	return arena.damage_trace.back().duplicate(true) if arena.damage_trace.size() == before + 1 else {}

func write_report() -> bool:
	var file := FileAccess.open(output.path_join("packed-runtime-probe.json"), FileAccess.WRITE)
	if file == null:
		push_error("Packed v46 probe: cannot write report: " + str(FileAccess.get_open_error()))
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
	print("Packed v46 combat feedback probe: %s (%d/%d checks, %d failures)" % ["PASS" if success else "FAIL", results.size(), EXPECTED_CHECKS, failures])
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	quit(0 if success else 1)

func run() -> void:
	output = OS.get_environment("V046_PACK_QA")
	var expected_font: String = OS.get_environment("V046_PACK_FONT_SHA256").to_lower()
	var hex := RegEx.new()
	hex.compile("^[0-9a-f]{64}$")
	if output.is_empty() or hex.search(expected_font) == null or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):
		push_error("Packed v46 probe requires V046_PACK_QA, a 64-hex raw-font SHA256, and isolated /tmp/godot-m1-* XDG_DATA_HOME")
		quit(78); return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Packed v46 probe cannot create output directory")
		quit(1); return
	# An interrupted run must leave an explicitly incomplete artifact, never an
	# older passing report. The runner must also reject any ERROR in the log.
	if not write_report(): quit(1); return
	report.command_line = Array(OS.get_cmdline_args())
	report.engine = Engine.get_version_info().string
	report.platform = OS.get_name()
	report.probe_resource = get_script().resource_path
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await process_frame
	var model: RefCounted = arena.state
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	font.allow_system_fallback = false
	report.version = str(ProjectSettings.get_setting("application/config/version"))
	report.schema = model.snapshot().version
	report.save_dir = str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	report.user_dir = OS.get_user_data_dir()
	report.bag = model.bag_layout()
	report.font_sha256 = sha256(font.data)
	check(report.version == "0.46.0" and report.schema == 28 and report.save_dir == "godot-game-preview-v021" and report.bag == {"pages":2,"columns":12,"rows":10}, "Packed version, save identity, schema, and bag dimensions", {"version":report.version,"schema":report.schema,"save_dir":report.save_dir,"bag":report.bag})
	var missing: String = ""
	for index: int in FONT_CHARACTERS.length():
		if not font.has_char(FONT_CHARACTERS.unicode_at(index)): missing += FONT_CHARACTERS[index]
	check(report.font_sha256 == expected_font and missing.is_empty(), "Bundled raw font hash and feedback glyphs", {"actual_sha256":report.font_sha256,"expected_sha256":expected_font,"required":FONT_CHARACTERS,"missing":missing})
	var saved: bool = arena.save_build()
	var pristine: Dictionary = model.snapshot()
	var pristine_bytes: PackedByteArray = var_to_bytes(pristine)
	var original_disk: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	var entry: Dictionary = {"ok":true}
	if arena.world_context().normal_town:
		entry = arena.leave_normal_town(arena.world_context().revision)
	arena.hud._process(0.0)
	for index: int in range(4):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	if not check(saved and not original_disk.is_empty() and entry.ok and arena.world_context().mode == "normal" and not arena.world_context().test_mode and not arena.hud.is_blocking(), "Pristine live model saved and normal practice entered through actual transition", {"entry":entry,"save_bytes":original_disk.size(),"world":arena.world_context()}):
		await finish(); return
	var saves_before: int = model.successful_saves
	arena.enemies.clear(); arena.monster_runtime.reset(); arena.burn_runtime.reset(); arena.feedback_runtime.reset()
	arena.damage_trace.clear(); arena.burn_trace.clear()
	arena.player_pos = arena.ARENA.get_center(); arena.mana = 1000.0; arena.spawn_timer = 1000.0
	# Typed compiler inputs only: 10 base damage, zero/certain critical chance,
	# 2x critical multiplier; ignite is a real support. Basic's 1000 base damage
	# supplies the overkill fixture without constructing a synthetic packet.
	var plain: Dictionary = Compiler.compile_group("meteor", Combat.snapshot({"damage":10.0,"crit_base_chance":0.0,"crit_base_multiplier":2.0}, []), [])
	var critical: Dictionary = Compiler.compile_group("meteor", Combat.snapshot({"damage":10.0,"crit_base_chance":1.0,"crit_base_multiplier":2.0}, []), [])
	var ignite: Dictionary = Compiler.compile_group("meteor", Combat.snapshot({"damage":10.0,"crit_base_chance":1.0,"crit_base_multiplier":2.0}, []), ["ignite"])
	var lethal: Dictionary = Compiler.compile_basic(Combat.snapshot({"damage":1000.0,"crit_base_chance":0.0}, []))
	if not check(plain.get("ok", false) and critical.get("ok", false) and ignite.get("ok", false) and lethal.get("ok", false) and ignite.has("burn_profile"), "Real compiler accepts four documented fixtures", {"ordinary":plain,"critical":critical,"critical_ignite":ignite,"lethal_basic":lethal}):
		await finish(); return
	var enemy: Dictionary = target(Vector2(100, 0))
	if enemy.is_empty(): check(false, "Actual monster fixture admission"); await finish(); return
	enemy.shield = 3.0
	var first: Dictionary = hit(enemy, plain)
	var second: Dictionary = hit(enemy, critical)
	var third: Dictionary = hit(enemy, plain)
	if not check(not first.is_empty() and not second.is_empty() and not third.is_empty() and arena.damage_feedback().is_empty(), "Three actual settlements remain pending before the aggregation window", {"settlements":[first,second,third],"visible":arena.damage_feedback()}):
		await finish(); return
	var step: Dictionary = arena.feedback_runtime.advance(0.2)
	var ordinary_row: Dictionary = receipt("hit", enemy.id)
	var critical_row: Dictionary = receipt("critical", enemy.id)
	check(step.ok and arena.damage_feedback().size() == 2 and not ordinary_row.is_empty() and not critical_row.is_empty() and ordinary_row.id != critical_row.id, "At 0.2 seconds ordinary and critical kinds have independent visible receipts", {"rows":arena.damage_feedback()})
	check(matches(ordinary_row, [first, third], 2), "Ordinary receipt aggregates actual shield and life loss and two hits", {"row":ordinary_row,"settlements":[first,third]})
	check(matches(critical_row, [second], 1) and second.get("critical", {}).get("critical", false) and str(Renderer.presentation(critical_row).get("text", "")).ends_with("!"), "Guaranteed critical receipt contains only actual critical spend and its marker", {"row":critical_row,"settlement":second,"presentation":Renderer.presentation(critical_row)})
	var before_copy: PackedByteArray = var_to_bytes(arena.damage_feedback())
	var detached: Array = arena.damage_feedback()
	if not detached.is_empty():
		detached[0].amount = -999.0; detached[0].kind = "altered"; detached[0].position = Vector2(-999, -999)
	detached.clear()
	check(var_to_bytes(arena.damage_feedback()) == before_copy, "Main feedback accessor returns detached rows and array")
	step = arena.feedback_runtime.advance(0.75)
	check(step.ok and arena.damage_feedback().is_empty() and close(ordinary_row.get("lifetime", -1.0), 0.75) and close(critical_row.get("lifetime", -1.0), 0.75), "Visible receipts expire at the 0.75-second lifetime")
	var trace_before: int = arena.damage_trace.size()
	var accepted: bool = arena._execute_compiled(ignite)
	var ignition: Dictionary = arena.damage_trace.back().duplicate(true) if arena.damage_trace.size() == trace_before + 1 else {}
	if not check(accepted and not ignition.is_empty() and ignition.get("critical", {}).get("critical", false) and arena.burn_statuses().size() == 1, "Actual compiled critical-ignite cast attaches real burning", {"accepted":accepted,"settlement":ignition,"statuses":arena.burn_statuses()}):
		await finish(); return
	var rng_before: int = arena.rng.state
	var crit_before: Dictionary = arena.critical_runtime.checkpoint()
	var advance_ignition: Dictionary = arena.feedback_runtime.advance(0.2)
	var burn_health_before: float = enemy.health
	var burn_shield_before: float = enemy.shield
	arena.elapsed += 0.5
	arena._advance_monster_burns(arena.elapsed)
	var burn_record: Dictionary = arena.burn_trace.back().duplicate(true) if not arena.burn_trace.is_empty() else {}
	var advance_burn: Dictionary = arena.feedback_runtime.advance(0.2)
	var burn_row: Dictionary = receipt("burn", enemy.id)
	var burn_settlement: Dictionary = burn_record.get("settlement", {})
	var burn_text: String = str(Renderer.presentation(burn_row).get("text", ""))
	var burn_actual: float = burn_health_before - float(enemy.health) + burn_shield_before - float(enemy.shield)
	check(advance_ignition.ok and advance_burn.ok and arena.damage_feedback().size() == 2 and matches(receipt("critical", enemy.id), [ignition], 1) and matches(burn_row, [burn_settlement], 0) and spent(burn_settlement) > 0.0 and close(spent(burn_settlement), burn_actual) and burn_text.begins_with("燃 ") and not burn_text.contains("!"), "Real burn settlement is separate actual spend with zero hit count and no critical marker", {"record":burn_record,"actual_resource_loss":burn_actual,"rows":arena.damage_feedback(),"burn_text":burn_text})
	check(arena.rng.state == rng_before and arena.critical_runtime.checkpoint() == crit_before, "Burn and feedback-only advance consume neither gameplay nor critical RNG", {"gameplay_before":str(rng_before),"gameplay_after":str(arena.rng.state),"critical_before":crit_before,"critical_after":arena.critical_runtime.checkpoint()})
	var victim: Dictionary = target(Vector2(-100, 0))
	if victim.is_empty(): check(false, "Actual overkill target admission"); await finish(); return
	victim.shield = 2.0; victim.health = 3.0
	var lethal_record: Dictionary = hit(victim, lethal, "projectile")
	var lethal_row: Dictionary = receipt("hit", victim.id)
	check(not lethal_record.is_empty() and close(lethal_record.get("total", -1.0), 1000.0) and victim.health <= 0.0 and matches(lethal_row, [lethal_record], 1) and close(lethal_row.get("amount", -1.0), 5.0) and close(lethal_row.get("shield_spent", -1.0), 2.0) and close(lethal_row.get("health_lost", -1.0), 3.0) and close(lethal_row.get("age", -1.0), 0.0), "Lethal 1000 damage flushes immediately as 2 shield plus 3 life, excluding overkill", {"settlement":lethal_record,"row":lethal_row,"remaining_health":victim.health})
	var pending: Dictionary = hit(enemy, plain)
	var visible_before_restart: int = arena.damage_feedback().size()
	arena.restart_run()
	step = arena.feedback_runtime.advance(0.2)
	check(not pending.is_empty() and visible_before_restart > 0 and step.ok and arena.damage_feedback().is_empty(), "Actual restart clears both visible and pending feedback", {"visible_before_restart":visible_before_restart,"pending_settlement":pending,"after":arena.damage_feedback()})
	var final_disk: PackedByteArray = FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(Same._same_data(pristine, model.snapshot()) and pristine_bytes == var_to_bytes(model.snapshot()) and original_disk == final_disk and saves_before == model.successful_saves, "Canonical model, exact save bytes, and save count remain unchanged by feedback scenarios", {"canonical_same":Same._same_data(pristine, model.snapshot()),"snapshot_bytes_same":pristine_bytes == var_to_bytes(model.snapshot()),"disk_bytes_same":original_disk == final_disk,"disk_sha256_before":sha256(original_disk),"disk_sha256_after":sha256(final_disk),"successful_saves_before":saves_before,"successful_saves_after":model.successful_saves})
	await finish()
