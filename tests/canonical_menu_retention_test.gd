extends SceneTree

const ProbeGearRngSeed: int = 210044

var arena: Node2D
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m4-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	root.size = Vector2i(1280, 720)
	arena = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	await _frames(6)
	var state = arena.state
	var original_snapshot: Dictionary = state.snapshot()

	# The first K opens the real canonical panel; same-state K toggles must reuse its row controls.
	arena.hud.handle_menu_key(KEY_K, true, false)
	await _frames(6)
	var skills: Control = arena.hud._skill_support_panel as Control
	var rows: Control = skills._rows as Control
	var first_row: Node = rows.find_child("SkillGroupRow_00", true, false)
	var first_row_id: int = first_row.get_instance_id()
	var first_generation: int = int(rows._generation)
	var before_reopens: Dictionary = state.snapshot()
	check(arena.hud._active_panel == "skills" and arena.hud.is_blocking(), "K opens the blocking canonical skills window")
	for cycle: int in range(3):
		arena.hud.handle_menu_key(KEY_K, true, false)
		arena.hud.handle_menu_key(KEY_K, true, false)
		await _frames(2)
		var reopened_first: Node = rows.find_child("SkillGroupRow_00", true, false)
		check(reopened_first.get_instance_id() == first_row_id, "K toggle %d retains the first row Node ID" % (cycle + 1))
		check(int(rows._generation) == first_generation, "K toggle %d retains the row generation" % (cycle + 1))
		check(state.snapshot() == before_reopens, "K toggle %d leaves the model snapshot unchanged" % (cycle + 1))
	check(before_reopens == original_snapshot, "Repeated K opens never alter canonical ownership")

	# Reward one actual focus-support instance while K is open; the tray must show that UID.
	var support_uid: String = state.award_gem("support:focus")
	await _frames(2)
	check(not support_uid.is_empty(), "Actual support:focus reward allocates a new UID")
	check(not before_reopens.items.has(support_uid), "Reward UID was not present in the earlier model snapshot")
	check(state.item(support_uid).definition_id == "support:focus" and state.location(support_uid).kind == "bag",
		"Awarded focus support is owned in the shared bag")
	var awarded_button: Node = skills.find_child("BagGem_" + support_uid, true, false)
	check(awarded_button != null and awarded_button.is_visible_in_tree(), "K tray visibly contains the newly awarded UID")
	check(int(rows._generation) > first_generation, "Changed support snapshot advances the row generation")

	# Simulate a stale binding request so _report must force-render even though the view token is unchanged.
	var group_id: String = str(state.snapshot().skill_groups[0].id)
	var before_rejection: Dictionary = state.snapshot()
	var rejected_generation: int = int(rows._generation)
	var existing_code := 0
	for binding: Dictionary in before_rejection.bindings:
		if str(binding.group_id) == group_id:
			existing_code = int(binding.keycode)
			break
	var picker: OptionButton = rows._binding_controls[group_id] as OptionButton
	var unused_code: int = KEY_F9 if state.group_for_key(KEY_F9).is_empty() else KEY_F10
	var request_index: int = picker.get_item_index(unused_code)
	rows._revision = state.revision() - 1
	rows._on_binding_selected(request_index, group_id, rejected_generation)
	await _frames(1)
	picker = rows._binding_controls[group_id] as OptionButton
	check(int(rows._generation) > rejected_generation, "Rejected _report rebuilds controls with a newer generation")
	check(rows._binding_requests.is_empty(), "Rejected _report clears binding request latches")
	check(state.snapshot() == before_rejection, "Rejected stale binding leaves the model unchanged")
	check(state.group_for_key(unused_code).is_empty(), "Rejected key remains unbound")
	check(picker.get_item_id(picker.selected) == existing_code, "Rejected picker restores the authoritative key choice")

	# A real inventory craft confirmation is cancelled after I is hidden; its item stays owned.
	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(6)
	var inventory: Control = arena.hud._inventory_panel as Control
	var gear_rng := RandomNumberGenerator.new()
	gear_rng.seed = ProbeGearRngSeed
	var gear_uid: String = state.award_equipment(gear_rng, 30, "rare")
	await _frames(2)
	check(not gear_uid.is_empty(), "Craft-cancel fixture creates one real rare item instance")
	inventory._select_item(gear_uid)
	var gear: Dictionary = state.item(gear_uid)
	inventory._request_craft("salvage", gear_uid, gear.payload)
	var before_cancel: Dictionary = state.snapshot()
	check(not inventory._pending_craft.is_empty() and inventory._craft_dialog.visible,
		"Inventory opens its real salvage confirmation without consuming the item")
	arena.hud.handle_menu_key(KEY_K, true, false)
	await _frames(2)
	inventory._craft_dialog.canceled.emit()
	await _frames(2)
	check(state.snapshot() == before_cancel and not state.item(gear_uid).is_empty(),
		"Cancelling a hidden I confirmation preserves exact canonical item and save state")
	check(inventory._pending_craft.is_empty() and not inventory._craft_dialog.visible,
		"Hidden I cancellation clears pending craft state")

	# Closing the menu restores actual cast admission; runtime mana/CD match its cached recipe.
	arena.hud.handle_menu_key(KEY_K, true, false)
	await _frames(2)
	check(not arena.hud.is_blocking(), "Second K toggle closes the blocking window")
	var cast_group_id := "group_000002"
	var compiled: Dictionary = state.get_group_cast(cast_group_id)
	check(bool(compiled.get("ok", false)) and str(compiled.skill_id) == "frost", "The default second row has its real frost recipe")
	var compile_count_before: int = int(state.cache_diagnostics().skill_compiles)
	arena.mana = float(arena._stats.max_mana)
	var mana_before: float = float(arena.mana)
	var projectile_start: int = arena.projectiles.size()
	var accepted: bool = arena.cast_group(cast_group_id)
	var projectile_delta: int = arena.projectiles.size() - projectile_start
	var mana_matches: bool = is_equal_approx(float(arena.mana), mana_before - float(compiled.mana))
	var cooldown_matches: bool = is_equal_approx(arena.group_cooldown_remaining(cast_group_id), float(compiled.cooldown))
	check(accepted, "Actual cast_group succeeds after the skills menu closes")
	check(mana_matches and cooldown_matches, "Accepted cast charges the compiled mana and cooldown")
	check(projectile_delta == int(compiled.initial_count), "Cast emits the recipe's dynamic initial projectile count")
	if projectile_delta > 0:
		var first_projectile: Dictionary = arena.projectiles[projectile_start]
		check(is_equal_approx(float(first_projectile.slow), float(compiled.recipe.slow))
			and is_equal_approx(Vector2(first_projectile.velocity).length(), float(compiled.recipe.speed)),
			"Actual projectile uses the current compiled speed and chill recipe")
	var frost_slot: int = state.skill_slots.find("frost")
	arena.hud._update_live()
	var button: Button = arena.hud._skill_buttons[frost_slot] as Button
	var expected_cooldown_text: String = "%.1fs" % arena.group_cooldown_remaining(cast_group_id)
	check(button.text.contains(expected_cooldown_text) and is_equal_approx(float(arena.hud._bars.mana.value), float(arena.mana)),
		"Live HUD reflects changed mana and cooldown values")
	check(int(state.cache_diagnostics().skill_compiles) == compile_count_before,
		"Menu reopen, actual cast, and live refresh reuse the cached recipe")

	print("Canonical menu retention: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _frames(count: int) -> void:
	for unused: int in range(count):
		await process_frame


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
