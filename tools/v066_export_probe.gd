extends SceneTree
## Bounded external probe of the exact Windows PCK through Linux Godot.
## A source invocation validates parsing only and exits78 before runtime work.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const Ambush = preload("res://scripts/combat/ambush_support_rules.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const OLD_SHA256 = "8fb6643092d1aa4b2cca1a9a2458327700340bda6b6fa43d573cb82d90b1cd72"
const ORIGINAL_PNG_SHA256 = "41002fc3ed5977230d475e6a428a02f87bca46393eaf15601f9b60987c71ea00"
var arena: Node
var output := ""
var rows: Array[Dictionary] = []
var failures := 0
var completed := false
var evidence: Dictionary = {}
var started_msec := 0


func _initialize() -> void:
	call_deferred("run")


func sha(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func near(actual: float, expected: float) -> bool:
	return is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-9)


func same_json(left: Variant, right: Variant) -> bool:
	return Same._same_data(JSON.parse_string(JSON.stringify(left)), JSON.parse_string(JSON.stringify(right)))


func save_report() -> bool:
	if output.is_empty(): return false
	var report := {
		"ok": completed and failures == 0, "completed": completed,
		"checks": rows.size(), "failures": failures, "results": rows,
		"source_commit": OS.get_environment("V066_SOURCE"),
		"pck_sha256": evidence.get("pck_sha256", ""),
		"schema": 42, "source_policy": 41, "gear_vocabulary": 39, "evidence": evidence,
		"scope": "Bounded Linux same-Windows-PCK Ambush migration, paid ownership and Main consumers; not a source-suite rerun, performance or Windows hardware claim",
		"asset_boundary": "Original PNG SHA is checked by source manifest and imported-cache provenance in verify_windows_pack; this probe checks the actual PCK Texture2D dimensions and mipmaps, not unexported source PNG bytes"
	}
	var file := FileAccess.open(output.path_join("packed-runtime-probe.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write packed-runtime-probe.json")
		return false
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	return true


func check(ok: bool, label: String) -> bool:
	if failures > 0: return false
	if Time.get_ticks_msec() - started_msec >= 30000:
		ok = false
		label = "Packed Ambush probe exceeded30seconds: " + label
	rows.append({"ok": ok, "label": label})
	if not ok:
		failures += 1
		push_error(label)
		save_report()
		quit(1)
	return ok


func require(ok: bool, label: String) -> bool:
	if not ok: return check(false, label)
	return failures == 0


func transaction(result: Dictionary, label: String) -> bool:
	return require(bool(result.get("ok", false)), label + ": " + str(result.get("reason", result.get("error", ""))))


func prepare_recovery(model: RefCounted) -> bool:
	var pending: Array = model.pending_items()
	for uid: String in pending:
		var destination: Dictionary = model.first_bag_position(uid)
		if not require(not destination.is_empty(), "Original recovery UID has lawful bag space: " + uid): return false
		if not transaction(model.move_item(uid, destination, model.revision(), arena.build_save_path), "Recover original UID " + uid): return false
	evidence.recovered_items = pending.size()
	return check(model.pending_items().is_empty() and model.crafting_balance() == 73, "Real recovery transactions expose the original73shards without grants")


func group_for(model: RefCounted, skill: String) -> String:
	for row: Dictionary in model.snapshot().skill_groups:
		if model.skill_group(row.id).skill_id == skill: return row.id
	return ""


func owned_uid(model: RefCounted, definition_id: String) -> String:
	var saved: Dictionary = model.snapshot()
	for uid: String in saved.items:
		if saved.items[uid].definition_id == definition_id: return uid
	return ""


func buy_ambush(model: RefCounted) -> String:
	var before: int = model.crafting_balance()
	var quote: Dictionary = arena.normal_gem_trade_quote("buy", "support:ambush", model.revision())
	if not transaction(quote, "Actual Ambush purchase quote"): return ""
	if not require(quote.cost == {"calibration_shard": 4}, "Actual quote costs exactly4shards"): return ""
	var purchased: Dictionary = arena.execute_normal_gem_trade(quote.handle, "support:ambush")
	if not transaction(purchased, "Actual normal-town Ambush purchase"): return ""
	var uid: String = str(purchased.get("uid", ""))
	if not require(not uid.is_empty() and model.crafting_balance() == before - 4, "Paid purchase produces a UID and debits exactly4shards"): return ""
	var saved: Dictionary = model.snapshot()
	if not require(saved.items.get(uid, {}).get("definition_id") == "support:ambush" and saved.locations.get(uid, {}).get("kind") == "bag", "Purchased UID is a real owned bag support"): return ""
	return uid


func move_to_bag(model: RefCounted, uid: String) -> bool:
	var destination: Dictionary = model.first_bag_position(uid)
	if not require(not destination.is_empty(), "Removed support has lawful bag space: " + uid): return false
	return transaction(model.move_item(uid, destination, model.revision(), arena.build_save_path), "Remove real support " + uid)


func clean_combat() -> bool:
	# Bounded fixture cleanup only. No build edits, free gems or modified maxima.
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.trap_runtime.reset()
	arena.trap_trace.clear()
	arena.damage_trace.clear()
	arena.telegraphs.reset()
	arena.burn_runtime.reset()
	arena.shock_runtime.reset()
	arena.leech_runtime.clear()
	arena.group_cooldowns.reset()
	arena.cooldowns.clear()
	arena.auto_fire = false
	arena.spawn_timer = 10000.0
	arena._autosave_timer = 0.0
	arena._simulation_accumulator = 0.0
	arena.elapsed = 0.0
	arena._burn_step_active = false
	arena._burn_incoming_time = -1.0
	arena._stats = arena.state.get_stats()
	arena.health = float(arena._stats.max_health)
	arena.mana = float(arena._stats.max_mana)
	arena.shield = float(arena._stats.max_shield)
	arena.alive = true
	arena.player_pos = arena.ARENA.get_center()
	arena.critical_runtime.reset(66066)
	arena.hud._process(0.0)
	for unused: int in range(3): arena.hud.close_panel()
	return require(not arena.hud.is_blocking(), "Actual alive fixture has no blocking menu")


func target() -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("crawler", arena.player_pos + Vector2(50, 0), "ordinary", "normal", [], false)
	if not require(not enemy.is_empty(), "Real catalog root is admitted"): return {}
	# Explicit durable enemy fixture; actual Main performs all hit settlement.
	enemy.spawn = 0.0
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	enemy.shield = 0.0
	enemy.max_shield = 0.0
	enemy.armour = 0.0
	enemy.evasion = 0.0
	enemy.radius = 10.0
	enemy.resistances = {}
	enemy.speed = 0.0
	enemy.attack_timer = 1000.0
	enemy.knockback = Vector2.ZERO
	return enemy


func observation() -> PackedByteArray:
	return var_to_bytes([arena.mana, arena.cooldowns, arena.group_cooldowns.snapshot(),
		arena.projectile_runtime.next_cast_id, arena.projectile_runtime.next_projectile_id,
		arena.critical_runtime.checkpoint(), arena.rng.state, arena.trap_runtime._entries,
		arena.trap_runtime._next_id, arena.trap_runtime._clock, arena.trap_trace,
		arena.projectiles, arena.damage_trace, arena.state.snapshot(), arena.state.successful_saves,
		FileAccess.get_file_as_bytes(arena.build_save_path)])


func run() -> void:
	output = OS.get_environment("V066_PACK_QA")
	var fixture := OS.get_environment("V066_OLD_SAVE")
	var pack := OS.get_environment("V066_MAIN_PACK")
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if output.is_empty() or fixture.is_empty() or pack.is_empty() or OS.get_environment("V066_SOURCE").is_empty() or OS.get_environment("V066_PACK_FONT_SHA256").length() != 64 \
		or not ProjectSettings.globalize_path("res://").is_empty() or not pack.is_absolute_path() or not FileAccess.file_exists(pack) \
		or not isolated.begins_with("/tmp/godot-m1-v066-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		print("V066_PACK_GUARD: expected a loaded PCK, complete V066 environment and isolated user data; no runtime checks executed")
		quit(78)
		return
	started_msec = Time.get_ticks_msec()
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create V066_PACK_QA directory")
		quit(1)
		return
	create_timer(30.0).timeout.connect(func() -> void: check(false, "Packed Ambush probe stalled"))
	evidence.pck_sha256 = sha(FileAccess.get_file_as_bytes(pack))
	evidence.resource_root = ProjectSettings.globalize_path("res://")
	var original := FileAccess.get_file_as_bytes(fixture)
	var expected: Variant = JSON.parse_string(original.get_string_from_utf8())
	if not check(sha(original) == OLD_SHA256 and expected is Dictionary and expected.get("version") == 41 and expected.get("progress", {}).get("level") == 37 and expected.get("talents", {}).get("allocated", []).has("10661"), "Exact frozen-v65 schema41/level37/IR fixture is used"): return
	evidence.old_save_sha256 = sha(original)
	var file := FileAccess.open("user://build_save.json", FileAccess.WRITE)
	if not require(file != null, "Open isolated original-save destination"): return
	file.store_buffer(original)
	file.close()
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not require(scene != null, "Load actual packed main scene"): return
	arena = scene.instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	arena.hud.close_panel()
	var model: RefCounted = arena.state
	if not check(str(ProjectSettings.get_setting("application/config/version")) == "0.66.0" and model.snapshot().version == 42 and Source.CURRENT_SAVE_VERSION == 41 and Gear.CURRENT_VOCABULARY == 39, "Packed version0.66/schema42 retains source41 and gear39"): return
	expected.version = 42
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path + ".v41-backup.json") == original and same_json(model.snapshot(), expected), "Migration changes only schema across equal JSON boundaries and backs up41original bytes"): return
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	if not require(font != null, "Load actual packaged font"): return
	font.allow_system_fallback = false
	var glyphs_ok := true
	var required_text: String = Ambush.SUPPORTS.ambush.name + Ambush.SUPPORTS.ambush.description + "布防伏击符印暴击固定爆发范围消失卸下退款"
	for character: String in required_text.split(""):
		if character.strip_edges().is_empty(): continue
		glyphs_ok = glyphs_ok and font.has_char(character.unicode_at(0))
	if not check(sha(font.data) == OS.get_environment("V066_PACK_FONT_SHA256") and glyphs_ok, "Actual original font SHA and all Ambush rule glyphs match without system fallback"): return
	evidence.font_sha256 = sha(font.data)
	var texture := load("res://assets/ui/grimoire/ambush.png") as Texture2D
	if not require(texture != null, "Load actual imported Ambush PCK texture"): return
	var pixels: Image = texture.get_image()
	if not check(texture.get_width() > 0 and texture.get_height() > 0 and texture.get_width() <= 512 and texture.get_height() <= 512 and pixels != null and pixels.has_mipmaps(), "Actual imported PCK Texture2D is at most512pixels with real mipmaps"): return
	evidence.texture = {"width": texture.get_width(), "height": texture.get_height(), "mipmaps": pixels.has_mipmaps(), "original_png_sha256_expected": ORIGINAL_PNG_SHA256, "original_png_proof": "External source manifest plus imported-cache provenance; source PNG is not redundantly exported"}
	if not prepare_recovery(model): return
	var offer: Dictionary = {}
	for row: Dictionary in arena.normal_gem_offers():
		if row.definition_id == "support:ambush": offer = row
	if not check(arena.world_context().normal_town and not arena.world_context().test_mode and not offer.is_empty() and offer.get("available", false) and offer.get("cost") == 4, "Actual normal town offers Ambush at4original shards"): return
	var nova_uid: String = buy_ambush(model)
	if nova_uid.is_empty(): return
	var meteor_uid: String = buy_ambush(model)
	if meteor_uid.is_empty(): return
	if not check(nova_uid != meteor_uid and model.crafting_balance() == 65 and model.snapshot().items.size() == expected.items.size() + 2, "Two distinct paid support UIDs cost8shards with no active-gem purchase or grants"): return
	var nova_group: String = group_for(model, "nova")
	var meteor_group: String = group_for(model, "meteor")
	var fire_uid: String = owned_uid(model, "support:fire_focus")
	if not require(not nova_group.is_empty() and not meteor_group.is_empty() and not fire_uid.is_empty(), "Original Nova, meteor and FireFocus ownership exists"): return
	for entry: Dictionary in [{"uid":nova_uid,"group":nova_group,"index":0}, {"uid":meteor_uid,"group":meteor_group,"index":0}, {"uid":fire_uid,"group":meteor_group,"index":1}]:
		if not transaction(model.move_item(entry.uid, {"kind":"skill_support", "group_id":entry.group, "index":entry.index}, model.revision(), arena.build_save_path), "Slot actual owned support " + str(entry.uid)): return
	if not check(model.skill_group(nova_group).support_ids == ["ambush"] and model.skill_group(meteor_group).support_ids.has("ambush") and model.skill_group(meteor_group).support_ids.has("fire_focus"), "Bought UIDs slot into the existing Nova and meteor groups with the owned FireFocus"): return
	var nova: Dictionary = model.get_group_cast(nova_group)
	var meteor: Dictionary = model.get_group_cast(meteor_group)
	for compiled: Dictionary in [nova, meteor]:
		if not require(bool(compiled.get("ok", false)), "Actual equipped group compiles"): return
		var links: Array = compiled.support_ids.duplicate()
		links.erase("ambush")
		var baseline: Dictionary = Compiler.compile_group(compiled.skill_id, model.get_combat_snapshot(), links)
		if not require(bool(baseline.get("ok", false)), "Matching ordinary group compiles"): return
		if not require(Ambush.profile_error(compiled.get("trap_profile")).is_empty() and near(compiled.mana, baseline.mana * 1.25) and near(compiled.cooldown, baseline.cooldown) and near(Damage.resolve(compiled.packets.direct, compiled.snapshot.modifiers).total, Damage.resolve(baseline.packets.direct, baseline.snapshot.modifiers).total * 0.85) and compiled.packets.direct.tags == ["hit", "spell", "area"] and Preview.trap_lines(compiled).size() == 3, "Packed compiler retains exact policy, .85hit/1.25mana, cooldown and original tags"): return
	if not check(nova.initial_count == 0 and meteor.initial_count == 0, "Both real area groups expose the exact trap profile and preview with no projectile delivery"): return
	evidence.compiled = {"nova": nova, "meteor": meteor}
	if not transaction(arena.leave_normal_town(arena.world_context().revision), "Enter actual normal practice"): return
	if not clean_combat(): return
	if not check(arena.world_context().mode == "normal" and not arena.world_context().test_mode, "Real normal-town exit starts the actual practice consumer"): return
	var enemy: Dictionary = target()
	if enemy.is_empty(): return
	var mana_before: float = arena.mana
	var cast_id: int = arena.projectile_runtime.next_cast_id
	var saved: Dictionary = model.snapshot()
	var save_count: int = model.successful_saves
	if not require(arena.cast_group(nova_group), "Actual Nova trap placement admitted"): return
	var statuses: Array = arena.trap_statuses()
	if not check(near(mana_before - arena.mana, nova.mana) and near(arena.group_cooldown_remaining(nova_group), nova.cooldown) and arena.damage_trace.is_empty() and arena.projectiles.is_empty() and statuses.size() == 1 and statuses[0].position == arena.player_pos and not statuses[0].armed, "Nova placement pays once, starts original cooldown, stays at feet and has no instant hit"): return
	if not check(arena.critical_runtime.draws == 1 and arena.critical_runtime.events == 1 and cast_id > 0 and arena.projectile_runtime.next_cast_id == cast_id + 1 and same_json(model.snapshot(), saved) and model.successful_saves == save_count, "Placement freezes one critical draw and cast identity without persistent combat state"): return
	var nova_roll: Dictionary = arena.trap_runtime._entries[0].snapshot.get("critical_roll", {}).duplicate(true)
	statuses[0].position = Vector2.ZERO
	statuses[0].remaining_seconds = 999.0
	arena.elapsed = 0.349
	arena._update_traps()
	if not check(arena.damage_trace.is_empty() and arena.trap_statuses().size() == 1 and arena.trap_statuses()[0].position == arena.player_pos and not arena.trap_statuses()[0].armed, "Detached status cannot mutate a carrier and a pre-.35observation cannot trigger it"): return
	arena.elapsed = 0.35
	arena._update_traps()
	if not require(arena.damage_trace.size() == 1, "Exact .35arming settles one real hit"): return
	var record: Dictionary = arena.damage_trace[0]
	var expected_damage: float = Damage.resolve(nova.packets.direct, nova.snapshot.modifiers, {}, float(nova_roll.get("multiplier", 1.0))).total
	if not check(arena.trap_statuses().is_empty() and near(10000.0 - float(enemy.health), expected_damage) and record.phase == "trap" and record.cast_id == cast_id and record.skill_id == "nova" and record.tags == ["hit", "spell", "area"] and record.get("critical", {}) == nova_roll and near(enemy.slow, 0.6), "Exact .35trigger preserves frozen damage, original tags/slow and nonzero trap provenance"): return
	arena._update_traps()
	if not check(arena.damage_trace.size() == 1 and arena.critical_runtime.draws == 1 and arena.critical_runtime.events == 1 and arena.trap_trace.size() == 2 and arena.trap_trace[1].event == "triggered", "Consumed trap triggers once and never rerolls critical at detonation"): return
	evidence.nova_hit = record.duplicate(true)
	var hit_count: int = arena.damage_trace.size()
	if not require(arena.cast_group(meteor_group), "Actual meteor trap placement admitted"): return
	if not check(arena.damage_trace.size() == hit_count and arena.trap_statuses().size() == 1 and arena.trap_statuses()[0].position == arena.player_pos and arena.critical_runtime.draws == 2 and arena.critical_runtime.events == 2, "Actual meteor also places at feet with no immediate hit and one placement roll"): return
	var frozen: PackedByteArray = var_to_bytes(arena.trap_runtime._entries)
	var meteor_entry: Dictionary = arena.trap_runtime._entries[0].duplicate(true)
	var points_before: int = model.talent_points
	if not transaction(model.refund_passive("10661", model.revision(), arena.build_save_path), "Refund the original owned IronReflexes leaf"): return
	if not check(model.talent_points == points_before + 1 and not model.snapshot().talents.allocated.has("10661") and var_to_bytes(arena.trap_runtime._entries) == frozen, "Real source refund leaves the placed carrier and caster snapshot unchanged"): return
	if not move_to_bag(model, meteor_uid) or not move_to_bag(model, fire_uid): return
	var future_meteor: Dictionary = model.get_group_cast(meteor_group)
	if not require(bool(future_meteor.get("ok", false)), "Unlinked meteor compiles for future casts"): return
	if not check(not future_meteor.has("trap_profile") and not future_meteor.support_ids.has("fire_focus") and var_to_bytes(arena.trap_runtime._entries) == frozen and future_meteor.snapshot.modifiers != meteor_entry.snapshot.modifiers, "Removing the actual Ambush and FireFocus gems changes future casts while preserving frozen offense"): return
	enemy.resistances.fire = 0.5
	enemy.shield = 10.0
	var pools_before: float = float(enemy.health) + float(enemy.shield)
	var meteor_roll: Dictionary = meteor_entry.snapshot.get("critical_roll", {})
	expected_damage = Damage.resolve(meteor_entry.packet, meteor_entry.snapshot.modifiers, enemy.resistances, float(meteor_roll.get("multiplier", 1.0))).total
	arena.elapsed = float(meteor_entry.armed_at)
	arena._update_traps()
	if not require(arena.damage_trace.size() == hit_count + 1, "Frozen meteor settles one real hit after gem removal"): return
	record = arena.damage_trace.back()
	if not check(arena.trap_statuses().is_empty() and near(pools_before - float(enemy.health) - float(enemy.shield), expected_damage) and near(record.shield_spent, minf(10.0, expected_damage)) and record.phase == "trap" and record.cast_id == meteor_entry.cast_id and record.tags == ["hit", "spell", "area"] and record.get("critical", {}) == meteor_roll and arena.critical_runtime.draws == 2, "Trigger uses current enemy fire resistance/shield with frozen pre-refund and pre-removal caster damage"): return
	evidence.meteor_hit = record.duplicate(true)
	arena.group_cooldowns.reset()
	arena.mana = float(arena._stats.max_mana)
	hit_count = arena.damage_trace.size()
	if not require(arena.cast_group(meteor_group), "Actual unlinked meteor cast admitted"): return
	if not check(arena.damage_trace.size() == hit_count + 1 and arena.trap_statuses().is_empty() and arena.damage_trace.back().phase == "direct", "Future unlinked meteor retains its original immediate area hit"): return
	if not clean_combat(): return
	if not require(arena.cast_group(nova_group), "Actual active trap for save/reload admitted"): return
	saved = model.snapshot()
	if not require(model.save_build(arena.build_save_path) == OK, "Save the actual equipped42build"): return
	var loaded := Model.new()
	if not require(loaded.load_build(arena.build_save_path), "Reload the actual saved42build"): return
	if not check(same_json(loaded.snapshot(), saved) and loaded.snapshot().version == 42 and loaded.get_group_cast(nova_group) == model.get_group_cast(nova_group) and model.Rules.reason(loaded.snapshot()).is_empty() and arena.trap_statuses().size() == 1, "Save/reload preserves complete legal42build and equipped cast while the battle trap stays runtime-only"): return
	arena._replace_build(loaded, arena.build_save_path)
	model = loaded
	if not check(arena.trap_statuses().is_empty() and arena.trap_runtime.is_empty() and same_json(model.snapshot(), saved), "Actual profile replacement restores the saved build with no battle trap"): return
	if not clean_combat(): return
	if not require(arena.cast_group(nova_group), "Real first trap admits before capacity fixture"): return
	# Two bounded pure-runtime placements fill the shared pool. Source tests own
	# the exhaustive multi-group matrix; no extra groups/items are fabricated.
	var separate_critical := Critical.new()
	separate_critical.reset(6666)
	var frozen_meteor: Dictionary = separate_critical.freeze(meteor.snapshot)
	if not transaction(frozen_meteor, "Pure-runtime frozen meteor snapshot"): return
	for serial: int in [1001, 1002]:
		if not transaction(arena.trap_runtime.place(arena.elapsed, arena.player_pos, meteor, frozen_meteor.snapshot, serial), "Pure-runtime shared-pool placement"): return
	if not check(arena.trap_statuses().size() == 3 and arena.trap_statuses()[0].skill_id == "nova" and arena.trap_statuses()[1].skill_id == "meteor" and not arena.trap_runtime.can_place(arena.elapsed, arena.player_pos, nova).ok, "Pure-runtime minimum cross-skill fixture confirms one shared3trap capacity"): return
	arena.group_cooldowns.reset()
	var before: PackedByteArray = observation()
	if not check(not arena.cast_group(nova_group) and observation() == before, "Actual fourth placement rejects before mana, cooldown, critical RNG, cast IDs, runtime or save changes"): return
	enemy = target()
	if enemy.is_empty(): return
	mana_before = arena.mana
	var rng_before: int = arena.rng.state
	var crit_before: Dictionary = arena.critical_runtime.checkpoint()
	var disk_before: PackedByteArray = FileAccess.get_file_as_bytes(arena.build_save_path)
	arena.elapsed = 12.0
	arena._update_traps()
	if not check(arena.trap_runtime.is_empty() and arena.damage_trace.is_empty() and near(enemy.health, 10000.0) and near(arena.mana, mana_before) and arena.rng.state == rng_before and arena.critical_runtime.checkpoint() == crit_before and FileAccess.get_file_as_bytes(arena.build_save_path) == disk_before, "Exact12second expiry wins over an eligible enemy and causes no explosion, payment, RNG or save write"): return
	if not require(arena.cast_group(nova_group), "Real post-expiry placement admitted"): return
	if not require(arena.trap_statuses().size() == 1, "Cancellation fixture really has an active trap"): return
	if not transaction(arena.enter_normal_town(arena.world_context().revision), "Return through the actual normal-town API"): return
	if not check(arena.world_context().normal_town and arena.trap_runtime.is_empty() and arena.trap_statuses().is_empty(), "Actual return-to-town cancels an existing combat trap"): return
	if not check(FileAccess.get_file_as_bytes(arena.build_save_path + ".v41-backup.json") == original and model.crafting_balance() == 65, "Original41backup bytes survive purchases, casts, refund, removal, save/reload and town return"): return
	evidence.final_shards = model.crafting_balance()
	evidence.groups = {"nova": nova_group, "meteor": meteor_group}
	evidence.purchased_uids = [nova_uid, meteor_uid]
	evidence.elapsed_msec = Time.get_ticks_msec() - started_msec
	completed = true
	if not save_report():
		quit(1)
		return
	print("Packed v66 Ambush probe: %d checks, %d failures" % [rows.size(), failures])
	arena.queue_free()
	await process_frame
	quit(0)
