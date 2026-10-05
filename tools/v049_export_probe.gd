extends SceneTree
## Short final-PCK evidence through the real main scene and CanonicalGameState.
## No historical suite, 600s simulation, GUI, or Windows-native claim is made.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Targeted = preload("res://scripts/items/targeted_reforge_rules.gd")
const Same = preload("res://scripts/items/crafting_transaction_planner.gd")
const EXPECTED_CHECKS: int = 18
const FONT_SHA256: String = "c43797ccb46c17240acd21ffca909282d45c0cd8586afb945144013ac0de3ca4"
const FONT_BYTES: int = 415088
const FONT_MAPPED_CODEPOINTS: int = 1069
const FONT_CHARACTERS: String = "定向重铸暴击生命偷取魔力伤害保持稀有度替换全部词缀保证至少一条底材物品等级不保证高阶或更强结果可能相同或更差碎片仍会消耗"
const TARGETS: Dictionary = {
	"targeted_reforge_critical": ["global_critical_chance", "global_critical_multiplier"],
	"targeted_reforge_life_leech": ["attack_life_leech"],
	"targeted_reforge_mana_leech": ["attack_mana_leech"],
	"targeted_reforge_damage": ["runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread",
		"attack_added_physical", "attack_added_fire", "spell_added_cold", "spell_added_lightning", "whetstone_edge", "tempered_edge"],
}
const OLD_OPERATIONS: Array[String] = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
const EXPECTED_AFFIX_IDS: Array[String] = [
	"rootwell", "deepwell", "lanternveil", "runesong", "prismedge", "farweave", "coalglow", "rimeecho",
	"sparkthread", "wellturn", "trailstep", "beatlink", "attack_added_physical", "attack_added_fire",
	"spell_added_cold", "spell_added_lightning", "emberward", "whetstone_edge", "tempered_edge",
	"nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "nine_slot_suffix_endurance",
	"nine_slot_suffix_mana_flow", "nine_slot_suffix_stride", "nine_slot_suffix_skill_row",
	"attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier",
]
var arena: Node
var model: RefCounted
var output: String
var save_path: String
var results: Array[Dictionary] = []
var failures: int = 0
var finished: bool = false
var report: Dictionary = {"ok": false, "status": "running", "probe": "v049_export_probe",
	"scope": "Same-PCK headless targeted crafting transactions, root UI wiring, and actual equipped compiler consumer; not visual or Windows-native acceptance"}


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String, evidence: Dictionary = {}) -> bool:
	results.append({"ok": value, "label": label, "evidence": evidence})
	if not value:
		failures += 1
		push_error("Packed v49 probe: " + label)
	return value


func sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func json_data(value: Variant) -> Variant:
	# JSON converts all numeric values to floats. Normalize only at this boundary;
	# in-memory and reloaded models are compared with strict recursive types.
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func close(a: float, b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= 0.000001 * maxf(1.0, absf(b))


func write_report() -> bool:
	var file := FileAccess.open(output.path_join("packed-runtime-probe.json"), FileAccess.WRITE)
	if file == null:
		push_error("Packed v49 probe cannot write report: " + str(FileAccess.get_open_error()))
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
	push_error("Packed v49 probe timed out or stopped after a runtime error")
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
	print("Packed v49 targeted reforge probe: %s (%d/%d checks, %d failures)" % ["PASS" if success else "FAIL", results.size(), EXPECTED_CHECKS, failures])
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	quit(0 if success else 1)


func roll(id: String) -> Dictionary:
	return {"id": id, "tier": 1, "value": Gear.affix_definition(id).tiers[0].min}


func source(operation: String) -> Dictionary:
	# Same original catalog fixture as the focused transaction test. Every UID
	# comes from this actual model's next serial, including the real shard stacks.
	var bow: bool = operation == "targeted_reforge_damage"
	var affixes: Array = [roll("deepwell"), roll("wellturn")] if bow else \
		[roll("nine_slot_prefix_vitality"), roll("nine_slot_suffix_endurance")]
	if bow:
		affixes.append(roll("whetstone_edge"))
		affixes.append(roll("coalglow"))
	return {"id": "gear_%06d" % int(model.snapshot().next_item_serial),
		"base_id": "ashwood_bow" if bow else "nine_slot_etched_ring",
		"rarity": "rare" if bow else "magic", "item_level": 30, "affixes": affixes}


func entry(entries: Array, operation: String) -> Dictionary:
	for value: Dictionary in entries:
		if value.get("operation", "") == operation: return value
	return {}


func target_valid(instance: Dictionary, operation: String) -> bool:
	if not Gear.validate_instance_for_version(instance, 27): return false
	for affix: Dictionary in instance.affixes:
		if TARGETS[operation].has(affix.id): return true
	return false


func transact(operation: String, original: Dictionary) -> Dictionary:
	var before: Dictionary = model.snapshot()
	var disk: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	var saves: int = model.successful_saves
	var attempts: int = model.save_attempts
	var balance: int = model.crafting_balance()
	var cost: int = 40 if original.rarity == "rare" else 16
	var quote: Dictionary = model.crafting_quote(operation, original.id, save_path)
	var issued_clean: bool = Same._same_data(before, model.snapshot()) and disk == FileAccess.get_file_as_bytes(save_path) and model.save_attempts == attempts
	if not quote.get("ok", false):
		check(false, "Actual paid target quote: " + operation, {"quote": quote})
		return {}
	var result: Dictionary = model.execute_crafting(quote.handle, original)
	var crafted: Dictionary = model.item(original.id).get("payload", {})
	var after: Dictionary = model.snapshot()
	var identity: bool = not crafted.is_empty()
	for field: String in ["id", "base_id", "rarity", "item_level"]:
		identity = identity and crafted.get(field) == original[field]
	var ok: bool = issued_clean and result.get("ok", false) and result.get("operation", "") == operation \
		and quote.get("cost", {}) == {Craft.MATERIAL_ID: cost} and result.get("cost", {}) == quote.cost \
		and quote.get("rules_version", "") == "original-targeted-reforge-v1-affix27" \
		and not quote.has("instance") and not quote.has("candidate") and not quote.get("consumes_item", true) \
		and identity and target_valid(crafted, operation) and Same._same_data(model.location(original.id), before.locations[original.id]) \
		and model.crafting_balance() == balance - cost and after.revision == before.revision + 1 \
		and after.crafting.revision == before.crafting.revision + 1 and after.next_item_serial == before.next_item_serial \
		and model.successful_saves == saves + 1 and model.save_attempts == attempts + 1
	check(ok, "Actual %s %d-shard transaction preserves UID, slot, rarity and guarantees existing target family" % [operation, cost],
		{"quote": quote, "result": result, "crafted": crafted, "balance_before": balance, "balance_after": model.crafting_balance(),
		"successful_saves_before": saves, "successful_saves_after": model.successful_saves, "quote_was_read_only": issued_clean})
	return {"handle": quote.handle, "source": original.duplicate(true), "crafted": crafted, "ok": ok}


func run() -> void:
	output = OS.get_environment("V049_PROBE_OUTPUT")
	# Godot consumes --main-pack before exposing OS args. Never search args for
	# it: require the runner's exact path and the actual empty packed res root.
	var pack_path: String = OS.get_environment("V049_MAIN_PACK")
	var isolated: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if output.is_empty() or pack_path.is_empty() or not FileAccess.file_exists(pack_path) \
		or not ProjectSettings.globalize_path("res://").is_empty() or not isolated.begins_with("/tmp/godot-m1-"):
		push_error("Packed v49 probe requires the loaded V049_MAIN_PACK, V049_PROBE_OUTPUT, and isolated /tmp/godot-m1-* XDG_DATA_HOME")
		quit(78); return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Packed v49 probe cannot create output directory")
		quit(1); return
	# Keep a running receipt if loading fails. Accept only final complete status,
	# exact count, process exit zero, and a log without ERROR lines.
	if not write_report(): quit(1); return
	create_timer(45.0).timeout.connect(watchdog)
	report.command_line = Array(OS.get_cmdline_args())
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
	arena.set_process(false); arena.set_physics_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await process_frame
	model = arena.state
	save_path = arena.build_save_path
	report.version = str(ProjectSettings.get_setting("application/config/version"))
	report.schema = model.snapshot().version
	report.save_dir = str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	report.user_dir = OS.get_user_data_dir()
	report.bag = model.bag_layout()
	check(model is Model and report.version == "0.49.0" and report.schema == 30 and report.save_dir == "godot-game-preview-v021"
		and report.bag == {"pages": 2, "columns": 12, "rows": 10} and save_path == arena.NORMAL_BUILD_PATH,
		"Packed v0.49 uses actual CanonicalGameState, unchanged schema30, v021 save identity and 240 cells",
		{"version": report.version, "schema": report.schema, "save_dir": report.save_dir, "bag": report.bag, "save_path": save_path})
	var font := load("res://assets/fonts/arena_sans.otf") as FontFile
	var missing: String = ""
	if font != null:
		font.allow_system_fallback = false
		for index: int in FONT_CHARACTERS.length():
			if not font.has_char(FONT_CHARACTERS.unicode_at(index)) and not missing.contains(FONT_CHARACTERS[index]): missing += FONT_CHARACTERS[index]
		report.font_sha256 = sha256(font.data)
		report.font_raw_bytes = font.data.size()
		report.font_mapped_codepoints = font.get_supported_chars().length()
	else: missing = FONT_CHARACTERS
	# The final coverage scan confirmed these unchanged v048 font bytes cover
	# all v049 text. Exact raw SHA preserves every baseline glyph as well.
	check(font != null and report.get("font_sha256", "") == FONT_SHA256
		and report.get("font_raw_bytes", 0) == FONT_BYTES
		and report.get("font_mapped_codepoints", 0) == FONT_MAPPED_CODEPOINTS and missing.is_empty(),
		"Exact unchanged 1069-codepoint bundled font covers targeted text without system fallback",
		{"expected_sha256": FONT_SHA256, "sha256": report.get("font_sha256", ""), "bytes": report.get("font_raw_bytes", 0),
		"mapped_codepoints": report.get("font_mapped_codepoints", 0), "targeted_text": FONT_CHARACTERS, "missing": missing})
	var rules_ok: bool = Targeted.operation_ids() == TARGETS.keys() and Targeted.COSTS == {"magic": 16, "rare": 40}
	for operation: String in TARGETS:
		rules_ok = rules_ok and Targeted.TARGETS[operation].families == TARGETS[operation]
	var expected_operations: Array = OLD_OPERATIONS.duplicate()
	expected_operations.append_array(TARGETS.keys())
	check(rules_ok and Craft.operation_ids() == expected_operations and Craft.TARGETED_RULES_VERSION == "original-targeted-reforge-v1-affix27",
		"Actual packed helper and crafting entry expose four explicit targets alongside the six original operations",
		{"operations": Craft.operation_ids(), "costs": Targeted.COSTS, "rules_version": Craft.TARGETED_RULES_VERSION})
	var sources: Dictionary = {}
	var admitted: bool = model.crafting_balance() == 0
	for operation: String in TARGETS:
		var original: Dictionary = source(operation)
		var accepted: bool = Gear.validate_instance(original) and model._admit_reward_item(Items.wrap_equipment(original))
		admitted = admitted and accepted
		sources[operation] = original
	var stacks: Array[String] = []
	for quantity: int in [1, 94]:
		var uid: String = "item_%06d" % int(model.snapshot().next_item_serial)
		var accepted: bool = model._admit_reward_item(Items.calibration_shard(uid, quantity))
		admitted = admitted and accepted
		stacks.append(uid)
	var saved: bool = arena.save_build()
	var baseline: Dictionary = model.snapshot()
	var original_disk: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	if not check(admitted and saved and model.crafting_balance() == 95 and not original_disk.is_empty()
		and Same._same_data(json_data(baseline), JSON.parse_string(original_disk.get_string_from_utf8())),
		"Catalog-valid original fixtures and two actual shard UIDs use legitimate canonical serials and save coherently",
		{"sources": sources, "shard_uids": stacks, "balance": model.crafting_balance(), "next_item_serial": baseline.next_item_serial}):
		await finish(); return
	var attempts: int = model.save_attempts
	var saves: int = model.successful_saves
	var rng: int = arena.rng.state
	var metadata_ok: bool = true
	var metadata: Dictionary = {}
	for operation: String in TARGETS:
		var operations: Array = model.crafting_operations(sources[operation].id, save_path)
		var selected: Dictionary = entry(operations, operation)
		var cost: int = 40 if operation == "targeted_reforge_damage" else 16
		metadata_ok = metadata_ok and operations.size() == 10 and selected.get("available", false) \
			and selected.get("targeted", false) and selected.get("target_id", "") == operation.trim_prefix("targeted_reforge_") \
			and not str(selected.get("target_label", "")).is_empty() and selected.get("cost", {}) == {Craft.MATERIAL_ID: cost}
		metadata[operation] = selected
	check(metadata_ok and model._craft_quotes.is_empty() and model.save_attempts == attempts
		and Same._same_data(baseline, model.snapshot()) and original_disk == FileAccess.get_file_as_bytes(save_path),
		"Actual model metadata advertises all four compatible targets at current magic16 and rare40 prices without mutation", {"metadata": metadata})
	for unused: int in range(4):
		if arena.hud.is_blocking(): arena.hud.close_panel()
	arena.hud.open_panel("inventory")
	await process_frame
	var panel: Control = arena.hud._inventory_panel
	panel._select_item(sources.targeted_reforge_life_leech.id)
	var controls: Control = panel._craft_controls
	var ui_targets: Array = []
	for index: int in range(controls._target_select.item_count):
		ui_targets.append(controls._target_select.get_item_metadata(index))
	check(panel.model == model and controls._target_row.visible and ui_targets == TARGETS.keys()
		and not controls._target_button.disabled and controls._target_button.text.contains("16")
		and model._craft_quotes.is_empty() and Same._same_data(baseline, model.snapshot())
		and original_disk == FileAccess.get_file_as_bytes(save_path),
		"Real root inventory integrates the four-target row and model price; opening it issues no quote or payment",
		{"targets": ui_targets, "button": controls._target_button.text, "selected_uid": panel._selected_uid})
	arena.hud.close_panel()
	var cancellation_ok: bool = true
	var canceled: Array[Dictionary] = []
	for operation: String in TARGETS:
		var quote: Dictionary = model.crafting_quote(operation, sources[operation].id, save_path)
		cancellation_ok = cancellation_ok and quote.get("ok", false)
		if not quote.get("ok", false):
			canceled.append({"operation": operation, "quote": quote})
			continue
		model.cancel_crafting_quote(quote.handle)
		var rejected: Dictionary = model.execute_crafting(quote.handle, sources[operation])
		cancellation_ok = cancellation_ok and not rejected.get("ok", true) and rejected.get("code", "") == "unknown_quote"
		canceled.append({"operation": operation, "rejected": rejected})
	check(cancellation_ok and model._craft_quotes.is_empty() and Same._same_data(baseline, model.snapshot())
		and original_disk == FileAccess.get_file_as_bytes(save_path) and model.save_attempts == attempts and model.successful_saves == saves,
		"Issuing and canceling every target preserves raw disk, strict snapshot and save counts; canceled handles cannot execute", {"canceled": canceled})
	var transactions: Array[Dictionary] = []
	for operation: String in TARGETS:
		var transaction: Dictionary = transact(operation, sources[operation])
		if transaction.is_empty() or not transaction.get("ok", false):
			await finish(); return
		transactions.append(transaction)
	var crafted_state: Dictionary = model.snapshot()
	var expected: Dictionary = baseline.duplicate(true)
	for transaction: Dictionary in transactions:
		expected.items[transaction.source.id] = Items.wrap_equipment(transaction.crafted)
	expected.items.erase(stacks[0]); expected.locations.erase(stacks[0])
	expected.items[stacks[1]].payload.quantity = 7
	expected.revision += 4; expected.crafting.revision += 4
	check(model.crafting_balance() == 7 and model.item(stacks[0]).is_empty() and model.location(stacks[0]).is_empty()
		and model.item(stacks[1]).payload.quantity == 7 and Same._same_data(model.location(stacks[1]), baseline.locations[stacks[1]])
		and Same._same_data(expected, crafted_state) and model.successful_saves == saves + 4 and model.save_attempts == attempts + 4,
		"Exactly 88 real bag shards paid across UIDs; only four payloads, shard debit and revisions changed",
		{"remaining_shard_uid": stacks[1], "remaining": model.crafting_balance(), "total_paid": 88,
		"strict_expected_state": Same._same_data(expected, crafted_state), "successful_saves": model.successful_saves})
	var crafted_disk: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	var replay_ok: bool = true
	for transaction: Dictionary in transactions:
		var replay: Dictionary = model.execute_crafting(transaction.handle, transaction.source)
		replay_ok = replay_ok and not replay.get("ok", true) and replay.get("code", "") == "unknown_quote"
	check(replay_ok and Same._same_data(crafted_state, model.snapshot()) and crafted_disk == FileAccess.get_file_as_bytes(save_path)
		and model.successful_saves == saves + 4 and model.save_attempts == attempts + 4,
		"All four committed quote handles reject replay with strict state and raw save bytes unchanged")
	var affix_ids: Array[String] = Gear.all_affix_ids()
	var expected_ids: Array[String] = EXPECTED_AFFIX_IDS.duplicate()
	affix_ids.sort(); expected_ids.sort()
	check(Gear.CURRENT_VOCABULARY == 27 and Gear.CANONICAL_LOOT_PROFILE_ID == "canonical_v27"
		and Gear.all_base_ids().size() == 14 and affix_ids == expected_ids
		and crafted_state.version == 30 and crafted_state.crafting.keys() == ["revision"]
		and crafted_state.talents.source_version == "3.29.1" and Same._same_data(crafted_state.talents, baseline.talents)
		and arena.rng.state == rng,
		"Original 14 bases, 30 affix families, v27 vocabulary and source3.29.1 talents remain unchanged; no target ledger or gameplay RNG use",
		{"catalog_vocabulary": Gear.CURRENT_VOCABULARY, "affix_ids": affix_ids, "source_version": crafted_state.talents.source_version,
		"crafting": crafted_state.crafting, "rng_before": str(rng), "rng_after": str(arena.rng.state)})
	var life_uid: String = sources.targeted_reforge_life_leech.id
	var life_item: Dictionary = model.item(life_uid).payload
	var fraction: float = 0.0
	for affix: Dictionary in life_item.affixes:
		if affix.id == "attack_life_leech": fraction += float(affix.value) / 10000.0
	var equipped: Dictionary = model.move_item(life_uid, {"kind": "equipment", "slot_id": "ring_1"}, model.revision(), save_path)
	if not check(equipped.get("ok", false) and model.location(life_uid) == {"kind": "equipment", "slot_id": "ring_1"}
		and Same._same_data(life_item, model.item(life_uid).payload) and fraction > 0.0 and model.crafting_balance() == 7,
		"Actual canonical transfer equips the paid life-leech result in ring_1 with its same UID and rolled basis points",
		{"transfer": equipped, "uid": life_uid, "life_fraction": fraction}):
		await finish(); return
	var equipped_state: Dictionary = model.snapshot()
	var equipped_disk: PackedByteArray = FileAccess.get_file_as_bytes(save_path)
	var consumer_attempts: int = model.save_attempts
	var consumer_saves: int = model.successful_saves
	var cast: Dictionary = model.get_basic_cast()
	check(cast.get("ok", false) and cast.has("leech") and close(float(cast.get("leech", {}).get("health", {}).get("attack_fraction", -1.0)), fraction)
		and Same._same_data(equipped_state, model.snapshot()) and equipped_disk == FileAccess.get_file_as_bytes(save_path)
		and model.save_attempts == consumer_attempts,
		"Real equipped basic-attack compiler consumes the crafted life-leech fraction without a save or state mutation",
		{"expected_fraction": fraction, "compiled_leech": cast.get("leech", {})})
	var restored := Model.new()
	var loaded: bool = restored.load_build(save_path)
	check(loaded and Same._same_data(equipped_state, restored.snapshot())
		and Same._same_data(json_data(equipped_state), JSON.parse_string(equipped_disk.get_string_from_utf8()))
		and equipped_disk == FileAccess.get_file_as_bytes(save_path) and restored.save_attempts == 0 and restored.successful_saves == 0,
		"Exact equipped schema30 state equals actual saved JSON and fresh-model reload through strict recursive comparison",
		{"loaded": loaded, "disk_sha256": sha256(equipped_disk), "bytes": equipped_disk.size(), "schema": restored.snapshot().version})
	var restored_cast: Dictionary = restored.get_basic_cast()
	var restored_replay: Dictionary = restored.execute_crafting(transactions[1].handle, transactions[1].source)
	check(restored_cast.get("ok", false) and restored_cast.has("leech")
		and close(float(restored_cast.get("leech", {}).get("health", {}).get("attack_fraction", -1.0)), fraction)
		and Same._same_data(cast, restored_cast) and not restored_replay.get("ok", true) and restored_replay.get("code", "") == "unknown_quote"
		and Same._same_data(equipped_state, restored.snapshot()) and Same._same_data(equipped_state, model.snapshot())
		and equipped_disk == FileAccess.get_file_as_bytes(save_path) and restored.save_attempts == 0
		and model.save_attempts == consumer_attempts and model.successful_saves == consumer_saves and arena.rng.state == rng,
		"Reload retains the complete real compiled consumer, rejects old authority, and causes no further mutation, save or gameplay RNG use",
		{"compiled_leech": restored_cast.get("leech", {}), "old_handle_rejected": restored_replay, "balance": restored.crafting_balance()})
	await finish()
