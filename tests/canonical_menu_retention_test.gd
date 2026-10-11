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
	# Main now starts in formal town, where casting is intentionally forbidden.
	# Enter real practice before testing menu pause/resume; do not bypass world admission.
	check(arena.world_context().normal_town, "Fresh canonical Main starts in formal town")
	check(not arena.cast_group("group_000002"), "Town correctly rejects combat casting")
	var entered: Dictionary = arena.leave_normal_town(arena.world_context().revision)
	check(bool(entered.get("ok", false)) and arena.world_context().mode == "normal",
		"Existing town exit enters actual normal practice for the menu regression")
	if not bool(entered.get("ok", false)):
		arena.queue_free()
		await process_frame
		quit(1)
		return
	await _frames(3)
	var state = arena.state
	var original_snapshot: Dictionary = state.snapshot()

	# Open the two docks together: the skill editor and bag share the model's real item instances.
	arena.hud.handle_menu_key(KEY_K, true, false)
	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(6)
	var skills: Control = arena.hud._skill_support_panel as Control
	var rows: Control = skills._rows as Control
	var inventory: Control = arena.hud._inventory_panel as Control
	var grid: Control = inventory._grid as Control
	var left_scroll: ScrollContainer = arena.hud._dock_scrolls.left as ScrollContainer
	var left_content: VBoxContainer = arena.hud._dock_bodies.left as VBoxContainer
	var first_row: Node = rows.find_child("SkillGroupRow_00", true, false)
	var first_row_id: int = first_row.get_instance_id()
	var first_generation: int = int(rows._generation)
	var before_reopens: Dictionary = state.snapshot()
	check(arena.hud._active_panel == "skills" and arena.hud.is_blocking(), "K opens the left skills dock")
	check(arena.hud._menu_routes.snapshot().right_inventory and inventory.is_visible_in_tree(), "I opens the shared bag beside skills")
	check(not arena.cast_group("group_000002"), "Open docks block actual combat casting in practice")
	check(skills.find_child("SharedBagGemTray", true, false) == null, "Skills do not build a duplicate bag tray")
	check(left_content.size.y >= left_scroll.size.y - 1.0 and rows.size.y > 500.0,
		"Left dock VBox fills its scroll viewport and the skill list receives the remaining height")
	print("Dock fill skills: viewport=%.1f content=%.1f panel=%.1f rows=%.1f"
		% [left_scroll.size.y, left_content.size.y, skills.size.y, rows.size.y])
	for cycle: int in range(3):
		arena.hud.handle_menu_key(KEY_K, true, false)
		arena.hud.handle_menu_key(KEY_K, true, false)
		await _frames(2)
		var reopened_first: Node = rows.find_child("SkillGroupRow_00", true, false)
		check(reopened_first.get_instance_id() == first_row_id, "K toggle %d retains the first row Node ID" % (cycle + 1))
		check(int(rows._generation) == first_generation, "K toggle %d retains the row generation" % (cycle + 1))
		check(state.snapshot() == before_reopens, "K toggle %d leaves the model snapshot unchanged" % (cycle + 1))
		check(arena.hud.is_blocking() and inventory.is_visible_in_tree(), "K toggle %d leaves I open and the battle paused" % (cycle + 1))
	check(before_reopens == original_snapshot, "Repeated K opens never alter canonical ownership")

	# Reward one actual focus-support instance while both docks are open; only the shared grid shows it.
	var support_uid: String = state.award_gem("support:focus")
	await _frames(2)
	check(not support_uid.is_empty(), "Actual support:focus reward allocates a new UID")
	check(not before_reopens.items.has(support_uid), "Reward UID was not present in the earlier model snapshot")
	check(state.item(support_uid).definition_id == "support:focus" and state.location(support_uid).kind == "bag",
		"Awarded focus support is owned in the shared bag")
	check(grid.item_rect(support_uid).has_area(), "Shared right-hand grid visibly contains the awarded UID")
	check(skills.find_child("BagGem_" + support_uid, true, false) == null, "Awarded UID is not copied into a skill-side tray")
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

	# A real inventory craft confirmation remains blocking while either dock is open.
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
	await _frames(3)
	check(arena.hud.is_blocking() and inventory.is_visible_in_tree(), "Closing K preserves the open I dock and pause")
	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(3)
	check(not arena.hud.is_blocking(), "Closing the last dock resumes the world")
	inventory._craft_dialog.canceled.emit()
	await _frames(2)
	check(state.snapshot() == before_cancel and not state.item(gear_uid).is_empty(),
		"Cancelling a hidden I confirmation preserves exact canonical item and save state")
	check(inventory._pending_craft.is_empty() and not inventory._craft_dialog.visible,
		"Hidden I cancellation clears pending craft state")

	# Closing both docks restores actual cast admission; runtime mana/CD match its cached recipe.
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

	# Instantiate all canonical views, close them, then deliver one batched model update while hidden.
	var pre_level_xp: int = maxi(0, 12 + int(state.level) * 8 - 5 - int(state.xp))
	if pre_level_xp > 0:
		state.add_xp(pre_level_xp)
	check(int(state.level) == 1 and int(state.xp) == 15, "Fresh fixture is seeded five XP below its first level threshold")
	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(5)
	inventory = arena.hud._inventory_panel as Control
	grid = inventory._grid as Control
	var inventory_generation: int = int(inventory.refresh_generation)
	arena.hud.handle_menu_key(KEY_K, true, false)
	await _frames(5)
	skills = arena.hud._skill_support_panel as Control
	rows = skills._rows as Control
	var skill_generation: int = int(rows._generation)
	# CharacterStats was removed from the bag header; C is the current character route.
	arena.hud.handle_menu_key(KEY_C, true, false)
	await _frames(5)
	var character: Control = arena.hud._character_panel as Control
	var character_generation: int = int(character.refresh_generation)
	var character_body: VBoxContainer = character.find_child("CharacterSheetBody", true, false) as VBoxContainer
	var strength_value: Label = character.find_child("Value_strength", true, false) as Label
	check(character.size.y >= left_scroll.size.y - 1.0 and character_body.size.y >= character.size.y,
		"Character scroll and its content occupy the left dock's available height")
	check(strength_value.is_visible_in_tree() and strength_value.get_global_rect().has_area() and not strength_value.text.is_empty(),
		"Character sheet displays a real derived stat value in the viewport")
	check(character.find_child("CharacterStat_crit_chance", true, false) == null
		and character.find_child("CharacterStat_crit_multiplier", true, false) == null,
		"Unimplemented critical stats are omitted instead of shown as zero")
	print("Dock fill character: viewport=%.1f content=%.1f panel=%.1f strength_rect=%s strength=%s"
		% [left_scroll.size.y, character_body.size.y, character.size.y,
			str(strength_value.get_global_rect()), strength_value.text])
	arena.hud.open_panel("talents")
	await _frames(8)
	var passive: Control = arena.hud._passive_panel as Control
	var passive_generation: int = int(passive.refresh_generation)
	check(passive.is_visible_in_tree() and not arena.hud._dock_roots.left.is_visible_in_tree()
		and not arena.hud._dock_roots.right.is_visible_in_tree(), "T overlays and hides both retained docks")
	arena.hud.handle_menu_key(KEY_T, true, false)
	await _frames(5)
	check(character.is_visible_in_tree() and inventory.is_visible_in_tree(), "Leaving T restores the character and bag docks")
	arena.hud.handle_menu_key(KEY_K, true, false)
	await _frames(3)
	check(skills.is_visible_in_tree() and not character.is_visible_in_tree(), "K swaps the left dock back to the retained skill view")
	arena.hud.handle_menu_key(KEY_T, true, false)
	await _frames(5)
	arena.hud.handle_menu_key(KEY_T, true, false)
	await _frames(3)
	arena.hud.handle_menu_key(KEY_K, true, false)
	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(5)
	check(not inventory.is_visible_in_tree() and not skills.is_visible_in_tree()
		and not character.is_visible_in_tree() and not passive.is_visible_in_tree(), "I/K/T and character switching leave every view hidden")
	check(int(inventory.refresh_generation) == inventory_generation and int(rows._generation) == skill_generation
		and int(character.refresh_generation) == character_generation and int(passive.refresh_generation) == passive_generation,
		"Closing docks and overlays alone does not rebuild canonical views")

	var before_hidden_change: Dictionary = state.snapshot()
	var hidden_rng := RandomNumberGenerator.new()
	hidden_rng.seed = ProbeGearRngSeed + 1
	arena._begin_progress_transaction()
	var awarded_hidden_support: String = state.award_gem("support:focus")
	var awarded_hidden_gear: String = state.award_equipment(hidden_rng, 30, "rare")
	var level_before_hidden_xp: int = int(state.level)
	var reached_new_level: bool = state.add_xp(5)
	arena._end_progress_transaction()
	await _frames(3)
	check(not awarded_hidden_support.is_empty() and not awarded_hidden_gear.is_empty(), "Hidden update grants real support and equipment instances")
	check(reached_new_level and int(state.level) == level_before_hidden_xp + 1 and int(state.xp) == 0,
		"Five XP while hidden crosses the saved level threshold")
	check(int(inventory.refresh_generation) == inventory_generation and int(rows._generation) == skill_generation
		and int(character.refresh_generation) == character_generation and int(passive.refresh_generation) == passive_generation,
		"Model signals mark hidden views dirty without rebuilding controls")
	check(state.item(awarded_hidden_support).definition_id == "support:focus"
		and state.location(awarded_hidden_support).kind == "bag" and not state.item(awarded_hidden_gear).is_empty(),
		"Hidden updates preserve real UIDs and canonical bag locations")
	check(before_hidden_change.revision < state.revision(), "Batched hidden rewards and XP advance model revision")

	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(5)
	check(int(inventory.refresh_generation) == inventory_generation + 1
		and grid.bag_page() == int(state.location(awarded_hidden_support).page)
		and grid.item_rect(awarded_hidden_support).has_area(), "Reopening I refreshes once and displays the new support UID")
	var hidden_gear_page: int = int(state.location(awarded_hidden_gear).page)
	if grid.bag_page() != hidden_gear_page:
		inventory._turn_page(hidden_gear_page - grid.bag_page())
	check(grid.bag_page() == hidden_gear_page and grid.item_rect(awarded_hidden_gear).has_area(),
		"The same shared bag displays the new gear UID on its model-assigned page")
	arena.hud.handle_menu_key(KEY_K, true, false)
	await _frames(5)
	check(int(rows._generation) == skill_generation + 1 and int(rows._revision) == state.revision(),
		"Reopening K refreshes the current skill snapshot once")
	arena.hud.handle_menu_key(KEY_C, true, false)
	await _frames(5)
	var progress_label: Label = character.find_child("CharacterProgress", true, false) as Label
	check(int(character.refresh_generation) == character_generation + 1
		and progress_label.text.contains("Lv.%d" % int(state.level)),
		"C reopens a current derived sheet with the new level")
	arena.hud.open_panel("talents")
	await _frames(8)
	var passive_summary: Label = passive.find_child("SourceTreeSummary", true, false) as Label
	check(int(passive.refresh_generation) == passive_generation + 1
		and passive_summary.text.contains("可用 %d" % int(state.talent_points)),
		"Reopening T refreshes the passive point budget once")
	check(arena.hud._menu_routes.snapshot().overlay == "talents"
		and arena.hud._menu_routes.snapshot().left == "character"
		and arena.hud._menu_routes.snapshot().right_inventory, "Talents overlays the active character and bag docks")
	arena.hud.handle_menu_key(KEY_ESCAPE, true, false)
	await _frames(3)
	check(arena.hud._menu_routes.snapshot().overlay.is_empty()
		and character.is_visible_in_tree() and inventory.is_visible_in_tree(), "Escape first closes T and restores both docks")
	arena.hud.handle_menu_key(KEY_ESCAPE, true, false)
	await _frames(3)
	check(arena.hud._menu_routes.snapshot().left.is_empty()
		and arena.hud._menu_routes.snapshot().right_inventory and not character.is_visible_in_tree()
		and inventory.is_visible_in_tree() and arena.hud.is_blocking(), "Escape next closes the most recently opened left dock")
	arena.hud.handle_menu_key(KEY_ESCAPE, true, false)
	await _frames(3)
	check(not arena.hud._menu_routes.snapshot().right_inventory and not arena.hud.is_blocking(),
		"Escape closes the last dock and resumes the battle")
	arena.hud.handle_menu_key(KEY_ESCAPE, true, false)
	await _frames(3)
	check(arena.hud._menu_routes.snapshot().overlay == "pause" and arena.hud.is_blocking(),
		"Escape with no open dock enters pause")
	arena.hud.handle_menu_key(KEY_ESCAPE, true, false)
	await _frames(3)
	check(arena.hud._menu_routes.snapshot().overlay.is_empty() and not arena.hud.is_blocking(),
		"Escape closes pause back to the live world")

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
