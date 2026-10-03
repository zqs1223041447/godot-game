extends SceneTree
## Deterministic combat + UI integration checks; user:// is isolated by validate.sh.

const Model = preload("res://scripts/build_state.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Grid = preload("res://scripts/item_grid_view.gd")

var failures: int = 0
var checks: int = 0
var arena: Node


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	_expect(ProjectSettings.get_setting("application/config/name") == "godot游戏仓", "Project title")
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_expect(packed != null, "Main scene loads")
	if packed == null:
		_finish()
		return
	arena = packed.instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_expect(arena is Node2D and arena.alive, "Playable arena initializes")
	_expect(arena.hud.get_node_or_null("HUDRoot") != null, "HUD root exists")
	_expect(arena.enemies.size() == 3, "Initial enemy encounter")
	_expect(arena.state.skill_slots.size() == 5, "Five populated skill slots")
	_expect(arena.health == arena.get_stats().max_health, "Life initializes full")
	_expect(arena.mana == arena.get_stats().max_mana, "Mana initializes full")
	_expect(arena.shield == arena.get_stats().max_shield, "Energy shield initializes full")

	arena.invulnerable = 0.0
	arena.shield = 10.0
	var hp: float = arena.health
	arena.hit_player(15.0)
	_expect(arena.shield == 0.0 and arena.health == hp - 5.0, "Shield absorbs damage before life")
	arena.hit_player(15.0)
	_expect(arena.health == hp - 5.0, "Brief hit immunity prevents stacked contact damage")
	arena.enemies.clear()
	arena.auto_fire = false
	arena.spawn_timer = 9999.0
	arena.shield = 0.0
	arena.mana = 0.0
	arena.tick(1.0)
	_expect(arena.mana > 0.0 and arena.shield == 0.0, "Mana regenerates while shield waits after damage")
	arena.damage_delay = 0.0
	arena.tick(1.0)
	_expect(arena.shield > 0.0, "Shield regenerates after delay")

	var original: Vector2 = arena.player_pos
	Input.action_press("move_right")
	arena.tick(0.1)
	Input.action_release("move_right")
	_expect(arena.player_pos.x > original.x, "Movement uses build move speed")
	arena.player_pos = arena.ARENA.end - Vector2.ONE
	Input.action_press("move_right")
	Input.action_press("move_down")
	arena.tick(1.0)
	Input.action_release("move_right")
	Input.action_release("move_down")
	_expect(arena.player_pos.x <= arena.ARENA.end.x - arena.PLAYER_RADIUS and arena.player_pos.y <= arena.ARENA.end.y - arena.PLAYER_RADIUS, "Arena boundaries clamp player")
	arena.player_pos = Vector2(640, 335)
	var enemy: Dictionary = arena._spawn_enemy(Vector2(840, 335), 0)
	enemy.spawn = 0.0
	var enemy_x: float = enemy.pos.x
	arena._update_enemies(0.1)
	_expect(enemy.pos.x < enemy_x, "Enemy actively approaches player")
	arena.auto_fire = true
	arena.attack_timer = 0.0
	arena._update_auto_attack()
	_expect(arena.projectiles.size() > 0, "Auto attack launches real projectile")
	for i: int in range(30):
		arena._update_projectiles(0.02)
	_expect(float(enemy.health) < float(enemy.max_health), "Projectile collision damages enemy")

	arena.enemies.clear()
	arena.projectiles.clear()
	arena.mana = float(arena.get_stats().max_mana)
	_expect(arena.cast_skill(0), "Slot 1 launches ability")
	_expect(arena.projectiles.size() == 3, "Arcane ability fires three piercing projectiles")
	_expect(not arena.cast_skill(0), "Cooldown prevents ability spam")
	arena.mana = 0.0
	_expect(not arena.cast_skill(1), "Insufficient mana prevents cast")
	arena.mana = float(arena.get_stats().max_mana)
	_expect(arena.cast_skill(1), "Frost ability casts")
	_expect(arena.projectiles.back().slow == 3.0, "Frost projectiles carry slow effect")
	var nova_target: Dictionary = arena._spawn_enemy(arena.player_pos + Vector2(70, 0), 0)
	nova_target.spawn = 0.0
	var kills_before: int = arena.kills
	_expect(arena.cast_skill(2), "Nova casts")
	_expect(arena.kills > kills_before, "Nova damages nearby enemies and awards kills")
	var dash_start: Vector2 = arena.player_pos
	_expect(arena.cast_skill(3), "Dash casts")
	_expect(arena.player_pos.distance_to(dash_start) > 100.0 and arena.invulnerable > 0.0, "Dash moves player and grants immunity")
	arena.shield = 0.0
	arena.mana = 100.0
	_expect(arena.cast_skill(4) and arena.shield > 0.0, "Ward restores shield")

	arena.state.slot_skill(0, "meteor")
	arena.mana = 100.0
	var meteor_target: Dictionary = arena._spawn_enemy(arena.player_pos + Vector2(100, 0), 0)
	meteor_target.spawn = 0.0
	_expect(arena.cast_skill(0) and meteor_target.health <= 0.0, "Slotted meteor affects combat")
	arena.state.slot_skill(0, "chain")
	arena.mana = 100.0
	var chain_target: Dictionary = arena._spawn_enemy(arena.player_pos + Vector2(100, 0), 0)
	chain_target.spawn = 0.0
	_expect(arena.cast_skill(0) and chain_target.health <= 0.0, "Chain lightning affects combat")

	_check_jewel_drops()
	arena.hud.open_panel("inventory")
	_expect(arena.hud.is_blocking(), "Inventory pauses combat")
	var time_before: float = arena.elapsed
	arena._process(1.0)
	_expect(arena.elapsed == time_before, "Paused menu freezes combat clock")
	_expect(not arena.cast_skill(1), "Menus block ability casts")
	var inventory_panel: Control = arena.hud.find_child("InventoryPanel", true, false) as Control
	_expect(inventory_panel != null, "Grid inventory panel exists")
	if inventory_panel:
		inventory_panel.select_item("item:swift_blade")
	var equip_button: Button = arena.hud.find_child("EquipSelectedButton", true, false) as Button
	_expect(equip_button != null, "Grid-selected equipment action exists")
	if equip_button:
		equip_button.pressed.emit()
	_expect(arena.state.equipped.weapon == "swift_blade", "Selected grid item equips through UI")
	_expect(arena.get_stats().attack_speed > 1.7, "Equipment changes live derived stats")
	await process_frame
	await _check_inventory_ui(inventory_panel)
	await _check_passive_ui()

	arena.hud.open_panel("skills")
	var skill_button: Button = arena.hud.find_child("SelectSkill_bolt", true, false) as Button
	_expect(skill_button != null, "Skill library action exists")
	if skill_button:
		skill_button.pressed.emit()
	_expect(arena.state.skill_slots[0] == "bolt", "Skill UI changes target hotbar slot")
	await process_frame
	arena.hud.close_panel()
	_expect(not arena.hud.is_blocking(), "Closing menu resumes gameplay")
	arena.invulnerable = 0.0
	arena.shield = 0.0
	arena.hit_player(9999.0)
	_expect(not arena.alive and arena.hud.is_blocking(), "Death shows blocking retry screen")
	var old_level: int = arena.state.level
	var old_jewels: Dictionary = arena.state.jewels.duplicate(true)
	arena.restart_run()
	_expect(arena.alive and arena.kills == 0 and arena.state.level == old_level, "Restart resets run and retains build")
	_expect(arena.health == arena.get_stats().max_health and not arena.hud.is_blocking(), "Restart restores vitals and closes overlay")
	_expect(arena.state.jewels == old_jewels, "Restart preserves all collected jewels")
	_expect(arena.save_build(), "Build persists successfully")

	var preset := ConfigFile.new()
	_expect(preset.load("res://export_presets.cfg") == OK, "Export preset parses")
	_expect(preset.get_value("preset.0", "platform", "") == "Windows Desktop", "Windows export target")
	_expect(preset.get_value("preset.0.options", "binary_format/architecture", "") == "x86_64", "64-bit export architecture")
	arena.free()
	_finish()


func _check_jewel_drops() -> void:
	arena.kills = 18
	arena.reward_kills = 18
	var before: int = arena.state.jewels.size()
	var target: Dictionary = arena._spawn_enemy(arena.player_pos + Vector2(40, 0), 0)
	arena._damage_enemy(target, 9999.0, Color.WHITE)
	_expect(arena.kills == 19 and arena.state.jewels.size() == before, "Ordinary kill does not award milestone jewel")
	target = arena._spawn_enemy(arena.player_pos + Vector2(40, 0), 0)
	arena._damage_enemy(target, 9999.0, Color.WHITE)
	_expect(arena.kills == 20 and arena.state.jewels.size() == before + 1, "Twentieth kill awards exactly one jewel")
	arena._damage_enemy(target, 9999.0, Color.WHITE)
	_expect(arena.kills == 20 and arena.state.jewels.size() == before + 1, "Repeated damage to dead target cannot duplicate milestone drop")
	for i: int in range(Model.MAX_JEWELS):
		if arena.state.jewels.size() >= Model.MAX_JEWELS:
			break
		arena.state.award_jewel(arena.rng)
	_expect(arena.state.jewels.size() == Model.MAX_JEWELS, "Drop capacity fixture fills to limit")
	var owned: Dictionary = arena.state.jewels.duplicate(true)
	var loose: Array = arena.state.jewel_inventory.duplicate()
	arena.kills = 39
	arena.reward_kills = 39
	target = arena._spawn_enemy(arena.player_pos + Vector2(40, 0), 0)
	arena._damage_enemy(target, 9999.0, Color.WHITE)
	_expect(arena.kills == 40 and arena.state.jewels == owned and arena.state.jewel_inventory == loose, "Full-capacity milestone preserves existing jewels without duplication")
	arena.enemies.clear()


func _check_inventory_ui(panel: Control) -> void:
	if panel == null:
		return
	var grid: Control = panel.find_child("InventoryGrid", true, false) as Control
	_expect(grid != null, "Grid canvas exists")
	if grid == null:
		return
	var loose_jewel: String = "jewel:" + arena.state.jewel_inventory[0]
	var item_box: Rect2 = grid.item_rect(loose_jewel)
	_expect(item_box.size == Vector2.ONE * Grid.CELL, "Jewel renders in a single cell")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = item_box.get_center()
	grid._gui_input(click)
	_expect(panel.selected_item_key == loose_jewel, "Grid mouse click selects actual item")
	var name_label: Label = panel.find_child("ItemNameLabel", true, false) as Label
	var stats_label: Label = panel.find_child("ItemStatsLabel", true, false) as Label
	_expect(name_label != null and not name_label.text.is_empty() and stats_label != null and not stats_label.text.is_empty(), "Grid inspector displays item identity and affixes")
	var free_cell := Vector2i(-1, -1)
	for y: int in range(Model.BACKPACK_ROWS - 1, -1, -1):
		for x: int in range(Model.BACKPACK_COLUMNS - 1, -1, -1):
			var cell := Vector2i(x, y)
			if arena.state.can_place_in_backpack(loose_jewel, cell) and arena.state.backpack_positions[loose_jewel] != cell:
				free_cell = cell
				break
		if free_cell.x >= 0:
			break
	var payload: Dictionary = {"type": "inventory_item", "key": loose_jewel, "grab_offset": Vector2i.ZERO}
	var target: Vector2 = Vector2(free_cell) * Grid.CELL + Vector2.ONE * (Grid.INSET + Grid.CELL / 2.0)
	_expect(free_cell.x >= 0 and grid._can_drop_data(target, payload), "Grid previews valid empty drop")
	grid._drop_data(target, payload)
	_expect(arena.state.backpack_positions[loose_jewel] == free_cell, "Grid drop moves item into exact requested cell")
	var before: Dictionary = arena.state._snapshot()
	_expect(not grid._can_drop_data(Vector2(-20, -20), payload), "Grid previews out-of-bounds drop as invalid")
	grid._drop_data(Vector2(-20, -20), payload)
	_expect(arena.state._snapshot() == before, "Rejected UI drop leaves all positions and stats unchanged")
	var overlap: Vector2 = grid.item_rect("item:vitality_armor").position + Vector2.ONE * 10.0
	_expect(not grid._can_drop_data(overlap, payload), "Grid rejects overlapping multi-cell equipment")
	grid._drop_data(overlap, payload)
	_expect(arena.state._snapshot() == before, "Overlap drop cannot destroy either item")
	for malformed: Variant in [null, "item", {}, {"type": "inventory_item"}, {"type": "other", "key": loose_jewel}, {"type": "inventory_item", "key": loose_jewel, "grab_offset": "wrong"}]:
		_expect(not grid._can_drop_data(target, malformed), "Unrecognized drag payload rejected")
	var weapon: Control = panel.find_child("EquipSlot_weapon", true, false) as Control
	_expect(weapon != null, "Weapon slot drop target exists")
	if weapon:
		_expect(not weapon._can_drop_data(Vector2.ZERO, payload), "Equipment slot rejects jewel drag")
		var wrong_slot: Dictionary = {"type": "inventory_item", "key": "item:storm_charm", "grab_offset": Vector2i.ZERO}
		_expect(not weapon._can_drop_data(Vector2.ZERO, wrong_slot), "Weapon slot rejects wrong equipment type")
		var weapon_payload: Dictionary = {"type": "inventory_item", "key": "item:ember_wand", "grab_offset": Vector2i.ZERO}
		_expect(weapon._can_drop_data(Vector2.ZERO, weapon_payload), "Weapon slot accepts matching backpack equipment")
		weapon._drop_data(Vector2.ZERO, weapon_payload)
		_expect(arena.state.equipped.weapon == "ember_wand" and arena.state.backpack_positions.has("item:swift_blade"), "Equipment drag atomically swaps occupied slot")
	panel.select_item("item:swift_blade")
	var equip: Button = panel.find_child("EquipSelectedButton", true, false) as Button
	equip.pressed.emit()
	var unequip: Button = panel.find_child("UnequipSelectedButton", true, false) as Button
	_expect(unequip.visible and panel.selected_item_key == "item:swift_blade", "Selected equipped item exposes unequip action")
	unequip.pressed.emit()
	_expect(not arena.state.equipped.has("weapon") and arena.state.backpack_positions.has("item:swift_blade"), "Unequip UI returns item to grid")
	equip.pressed.emit()
	_expect(arena.state.equipped.weapon == "swift_blade", "Repeated equip after unequip restores weapon")
	var sort: Button = panel.find_child("AutoSortBackpackButton", true, false) as Button
	_expect(sort != null, "Grid sort action exists")
	if sort:
		sort.pressed.emit()
		before = arena.state._snapshot()
		sort.pressed.emit()
		_expect(arena.state._snapshot() == before, "Repeated UI sort is stable")
	var selected: String = panel.selected_item_key
	arena.hud.open_panel("skills")
	arena.hud.open_panel("inventory")
	await process_frame
	_expect(arena.hud.find_child("InventoryPanel", true, false) == panel and panel.selected_item_key == selected, "Inventory tab reuse preserves inspector selection")
	panel.select_item(loose_jewel)
	var open_passives: Button = panel.find_child("OpenPassivesButton", true, false) as Button
	_expect(open_passives != null and open_passives.visible, "Selected jewel provides passive-tree navigation")
	if open_passives:
		open_passives.pressed.emit()
	_expect(arena.hud._active_panel == "talents" and arena.hud.is_blocking(), "Jewel navigation opens tree while keeping combat paused")
	# Inventory navigation prepares a replacement without changing the build.
	var tree_panel: Control = arena.hud.find_child("PassiveTreePanel", true, false) as Control
	_expect(tree_panel != null, "Inventory navigation creates passive inspector")
	if tree_panel == null:
		return
	tree_panel.select_node(Passives.START_ID)
	for id: String in ["ember_1_0", "ember_2_0", "ember_3_0"]:
		_expect(arena.state.allocate_passive(id), "Prepare allocated inventory-navigation socket")
	var occupied_jewel: String = arena.state.jewel_inventory[0]
	_expect(arena.state.socket_jewel("ember_3_0", occupied_jewel), "Prepare occupied socket for inventory replacement navigation")
	var rare_id: String = "jewel_000003"
	_expect(arena.state.jewel_inventory.has(rare_id) and arena.state.jewels[rare_id].rarity == "rare", "Navigation fixture selects an unsocketed rare jewel")
	arena.hud.open_panel("inventory")
	panel.select_item("jewel:" + rare_id)
	before = arena.state._snapshot()
	open_passives.pressed.emit()
	_expect(arena.hud._active_panel == "talents" and arena.hud.is_blocking(), "Rare jewel navigation opens passive panel")
	_expect(tree_panel.selected_node_id == "ember_3_0", "Navigation chooses first allocated socket from non-socket selection")
	_expect(tree_panel.selected_jewel_id == rare_id, "Navigation preserves inventory-selected rare jewel for replacement")
	_expect(arena.state._snapshot() == before and arena.state.socketed_jewels.get("ember_3_0") == occupied_jewel, "Navigation does not automatically socket, replace, or otherwise mutate build")
	arena.state.refund_talents()
	tree_panel.select_node(Passives.START_ID)


func _check_passive_ui() -> void:
	arena.hud.open_panel("talents")
	await process_frame
	var panel: Control = arena.hud.find_child("PassiveTreePanel", true, false) as Control
	_expect(panel != null, "Passive tree panel exists")
	if panel == null:
		return
	var view: Control = panel.tree_view
	_expect(view != null and view.name == "TreeViewport", "Interactive graph canvas exists")
	_expect(panel.find_child("NodeInspector", true, false) != null and panel.find_child("JewelInventory", true, false) != null, "Node details and jewel inventory are present")
	_expect(arena.hud.is_blocking(), "Passive tree pauses combat")
	var time_before: float = arena.elapsed
	arena._process(1.0)
	_expect(arena.elapsed == time_before and not arena.cast_skill(1), "Tree blocks combat simulation and casts")
	panel.select_node("ember_6_0")
	var allocate: Button = panel.find_child("AllocateButton", true, false) as Button
	var refund: Button = panel.find_child("RefundButton", true, false) as Button
	_expect(allocate != null and refund != null, "Graph allocation and refund controls exist")
	_expect(allocate.disabled and not panel.allocate_selected(), "Inspector refuses distant node allocation")
	view.center_origin()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.node_screen_position("ember_1_0")
	view._gui_input(click)
	_expect(panel.selected_node_id == "ember_1_0", "Canvas mouse selection updates inspector")
	var before: Dictionary = arena.get_stats().duplicate()
	var points: int = arena.state.talent_points
	_expect(not allocate.disabled, "Adjacent unallocated node enables allocation")
	allocate.pressed.emit()
	_expect(arena.state.allocated_nodes.has("ember_1_0") and arena.state.talent_points == points - 1, "Inspector button allocates selected graph node")
	_expect(arena.get_stats().damage > before.damage, "Passive allocation changes live combat damage")
	_expect(allocate.disabled and not panel.allocate_selected(), "Repeated allocation click cannot spend extra point")
	panel.select_node("ember_2_0")
	_expect(panel.allocate_selected(), "Inspector expands connected path")
	panel.select_node("ember_1_0")
	_expect(refund.disabled and not panel.refund_selected(), "Inspector blocks disconnecting bridge refund")
	panel.select_node("ember_3_0")
	_expect(panel.allocate_selected(), "Inspector allocates reached jewel socket")
	var first: String = arena.state.jewel_inventory[0]
	var second: String = arena.state.jewel_inventory[1]
	panel.select_jewel(first)
	var insert: Button = panel.find_child("InsertJewelButton", true, false) as Button
	var remove: Button = panel.find_child("RemoveJewelButton", true, false) as Button
	_expect(insert != null and remove != null and not insert.disabled, "Allocated socket exposes insert/remove controls")
	var socket_stats: Dictionary = arena.get_stats().duplicate()
	insert.pressed.emit()
	_expect(arena.state.socketed_jewels.get("ember_3_0") == first and arena.get_stats() != socket_stats, "Jewel UI insertion applies stats to arena")
	panel.select_jewel(second)
	_expect(panel.insert_selected_jewel(), "Jewel UI replacement succeeds")
	_expect(arena.state.jewel_inventory.has(first) and arena.state.socketed_jewels.get("ember_3_0") == second, "Jewel UI replacement returns old jewel")
	remove.pressed.emit()
	_expect(not arena.state.socketed_jewels.has("ember_3_0") and arena.get_stats() == socket_stats, "Jewel UI removal reverses jewel bonuses")
	_expect(not panel.remove_selected_jewel(), "Repeated UI removal is safe")
	panel.select_jewel(first)
	_expect(panel.insert_selected_jewel() and panel.refund_selected(), "Refunding selected socket returns its jewel")
	_expect(arena.state.jewel_inventory.has(first), "Refund UI preserves inserted jewel")
	panel.select_node("ember_2_0")
	_expect(panel.refund_selected(), "UI refunds leaf path node")
	panel.select_node("ember_1_0")
	_expect(panel.refund_selected() and arena.get_stats() == before, "UI returns original stats after path refunds")
	for id: String in ["ember_1_0", "ember_2_0", "ember_3_0"]:
		panel.select_node(id)
		_expect(panel.allocate_selected(), "Prepare UI reset path")
	panel.select_jewel(first)
	_expect(panel.insert_selected_jewel(), "Prepare socketed jewel for UI reset")
	var reset: Button = panel.find_child("ResetPassivesButton", true, false) as Button
	_expect(reset != null and not reset.disabled, "Full passive reset button enables")
	if reset:
		reset.pressed.emit()
	_expect(arena.state.allocated_nodes == [Passives.START_ID] and arena.state.jewel_inventory.has(first) and arena.get_stats() == before, "Reset button safely refunds graph and returns jewel")
	var reset_snapshot: Dictionary = arena.state._snapshot()
	if reset:
		reset.pressed.emit()
	_expect(arena.state._snapshot() == reset_snapshot, "Repeated UI reset cannot duplicate points or jewels")
	panel.select_jewel(first)
	var discard: Button = panel.find_child("DiscardJewelButton", true, false) as Button
	_expect(discard != null, "Jewel discard action exists")
	if discard:
		discard.pressed.emit()
		_expect(arena.state.jewels.has(first), "First discard click only requests confirmation")
		arena.hud.close_panel()
		arena.hud.open_panel("talents")
		discard.pressed.emit()
		_expect(arena.state.jewels.has(first), "Closing panel cancels pending discard confirmation")
		panel.select_jewel(second)
		discard.pressed.emit()
		_expect(arena.state.jewels.has(second), "Changing selection clears old discard approval")
		panel.select_jewel(first)
	view.set_zoom(0.55)
	var anchor := Vector2(190, 130)
	var anchor_world: Vector2 = view.screen_to_world(anchor)
	view.set_zoom(0.8, anchor)
	_expect(view.screen_to_world(anchor).is_equal_approx(anchor_world), "Zoom remains anchored under pointer")
	view.set_zoom(100.0)
	_expect(view.zoom <= 1.8, "Zoom-in respects upper bound")
	view.set_zoom(0.001)
	_expect(view.zoom >= 0.15, "Zoom-out respects lower bound")
	view.center_origin()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = view.size * 0.5
	var prior_zoom: float = view.zoom
	view._gui_input(wheel)
	_expect(view.zoom > prior_zoom, "Mouse wheel zooms graph")
	view.center_origin()
	var pan_before: Vector2 = view.pan
	click.button_index = MOUSE_BUTTON_MIDDLE
	click.position = view.size * 0.5
	view._gui_input(click)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(37, -21)
	view._gui_input(motion)
	click.pressed = false
	view._gui_input(click)
	_expect(view.pan == pan_before + motion.relative, "Middle-mouse drag pans graph")
	var saved_pan: Vector2 = view.pan
	var saved_zoom: float = view.zoom
	var saved_selection: String = panel.selected_node_id
	arena.state.add_xp(1)
	_expect(panel.selected_node_id == saved_selection and view.pan == saved_pan and view.zoom == saved_zoom, "Live stat refresh retains camera and selection")
	view.set_search_query("珠宝孔")
	_expect(view.get_search_match_count() >= 12, "Search finds every jewel socket")
	view.set_search_query("")
	click.pressed = true
	view._gui_input(click)
	arena.hud.open_panel("skills")
	arena.hud.open_panel("talents")
	await process_frame
	var reopened: Control = arena.hud.find_child("PassiveTreePanel", true, false) as Control
	_expect(reopened == panel and view.pan == saved_pan and view.zoom == saved_zoom, "Switching tabs preserves the same graph instance and camera")
	view._gui_input(motion)
	_expect(view.pan == saved_pan, "Interrupted drag stops after tab switch")
	view.fit_tree()
	_expect(view.zoom >= 0.15 and view.zoom <= 1.8, "Fit-tree camera remains valid")
	view.center_origin()
	_expect(view.pan == Vector2.ZERO and is_equal_approx(view.zoom, 0.34), "Center control restores origin view")
	for i: int in range(3):
		arena.hud.close_panel()
		_expect(not arena.hud.is_blocking(), "Repeated close resumes gameplay")
		arena.hud.open_panel("talents")
		_expect(arena.hud.is_blocking(), "Repeated open pauses gameplay")


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _finish() -> void:
	print("Combat/UI integration: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
