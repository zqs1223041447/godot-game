extends SceneTree
## Scene-level boss loot, active remote passives and persistence. Isolate user://.
const Model = preload("res://scripts/build_state.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
var arena: Node2D
var checks: int = 0
var failures: int = 0
var changes: int = 0
var finished: bool = false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_case(_test_v6_scene_migration, "literal v6 scene migration and first autosave")
	_case(_test_boss_rewards, "once-only original boss award and old milestone")
	_case(_test_demo_rewards, "all demonstration bosses remain rewardless")
	_case(_test_capacity, "jewel limit and return-space exhaustion")
	_case(_test_remote_combat, "remote passive reaches actual damage and save/restart")
	print("Special jewel integration: %d checks, %d failures" % [checks, failures])
	if is_instance_valid(arena): arena.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _case(test: Callable, name: String) -> void:
	finished = false
	_reset()
	test.call()
	_expect(finished, "Case reaches final assertion: " + name)

func _reset() -> void:
	if is_instance_valid(arena): arena.free()
	var model = Model.new()
	_expect(model.save_build() == OK, "Fresh isolated profile written")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.hud.close_panel()
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	arena.rng.seed = 90905
	changes = 0
	arena.state.changed.connect(func() -> void: changes += 1)

func _expect(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + name)

func _special_count() -> int:
	var count: int = 0
	for jewel: Dictionary in arena.state.jewels.values():
		if jewel.base == "branchfinder": count += 1
	return count

func _boss() -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster("rift_warden", arena.player_pos + Vector2(220, 0), "level_boss")
	enemy.spawn = 0.0
	return enemy

func _kill(enemy: Dictionary) -> void:
	arena._damage_enemy(enemy, 10000000.0, Color.WHITE)

func _test_v6_scene_migration() -> void:
	arena.free()
	var legacy: Dictionary = Model.new()._snapshot()
	legacy.version = 6
	legacy.erase("crafting")
	var text: String = JSON.stringify(legacy, "\t").replace("\n", "\r\n") + "\r\n"
	var original: PackedByteArray = PackedByteArray([0xef, 0xbb, 0xbf])
	original.append_array(text.to_utf8_buffer())
	var file: FileAccess = FileAccess.open("user://build_save.json", FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_expect(arena.state.migrated_from_v6 and arena.state.last_load_error.is_empty(), "Real scene recognizes literal v6 and does not protect a valid old profile as corrupt")
	_expect(arena.hud.is_blocking() and arena.hud._active_panel == "talents", "Migration opens the relevant tree panel")
	_expect(_special_count() == 0 and arena.state.jewels == legacy.jewels and arena.state.equipped == legacy.equipped, "Scene migration retains old items and grants no special jewel")
	_expect(arena.state.allocate_passive("ember_1_0"), "First ordinary build change goes through normal autosave signal")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json.v6-backup.json") == original, "First scene autosave preserves old BOM and CRLF bytes exactly")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://build_save.json"))
	_expect(saved is Dictionary and int(saved.version) == Model.SAVE_VERSION and saved.allocated_nodes.has("ember_1_0"), "Only after successful backup does scene autosave write the new allocation in current schema")
	finished = true

func _test_boss_rewards() -> void:
	_expect(_special_count() == 0 and arena.state.jewels.size() == 3, "Fresh profile does not get a free special jewel")
	arena.reward_kills = 19
	var before_id: int = arena.state.next_jewel_id
	var boss: Dictionary = _boss()
	_kill(boss)
	_expect(_special_count() == 1 and arena.state.jewels.size() == 5, "Boss at twentieth kill awards old random milestone plus one special jewel")
	_expect(arena.state.next_jewel_id == before_id + 2, "Both admitted items have unique consecutive identities")
	var special: Dictionary = arena.state.jewels["jewel_%06d" % (before_id + 1)]
	_expect(Jewels.validate_instance(special) and special.affixes.is_empty(), "Real boss creates exact fixed special instance")
	var before: Dictionary = arena.state._snapshot()
	_kill(boss)
	_expect(arena.state._snapshot() == before, "Repeated corpse damage cannot duplicate any reward")
	arena._flush_monster_spawns()
	_expect(arena.enemies.size() == 4, "Boss still creates original four terminal descendants")
	for child: Dictionary in arena.enemies.duplicate():
		child.spawn = 0.0
		_kill(child)
	_expect(arena.state._snapshot() == before and _special_count() == 1, "All boss descendants remain progression-rewardless")
	_expect(arena.reward_kills == 20 and arena.kills == 5, "Eligible counter distinguishes root from offspring")
	arena._flush_monster_spawns()
	var second: Dictionary = _boss()
	_kill(second)
	_expect(_special_count() == 2, "Later legitimate boss can yield another source for alternative coverage")
	finished = true

func _test_demo_rewards() -> void:
	for density: bool in [false, true]:
		if density: arena.start_density_demo()
		else: arena.start_monster_demo()
		var before: Dictionary = arena.state._snapshot()
		var found: bool = false
		for enemy: Dictionary in arena.enemies:
			if enemy.rarity == "boss":
				found = true
				enemy.spawn = 0.0
				_kill(enemy)
		_expect(found and arena.state._snapshot() == before and _special_count() == 0, "Demo boss gives no special, normal loot or XP; density=%s" % density)
	finished = true

func _test_capacity() -> void:
	while arena.state.jewels.size() < Model.MAX_JEWELS:
		if arena.state.award_special_jewel().is_empty(): break
	_expect(arena.state.jewels.size() == Model.MAX_JEWELS, "Fixture reaches actual 64-jewel limit")
	var jewels: Dictionary = arena.state.jewels.duplicate(true)
	var next_id: int = arena.state.next_jewel_id
	_kill(_boss())
	_expect(arena.state.jewels == jewels and arena.state.next_jewel_id == next_id, "Boss at jewel cap cannot overwrite instances or spend serial")
	_expect(not arena.state._validate_snapshot(arena.state._snapshot()).is_empty(), "Capacity rejection leaves a valid full profile")
	_reset()
	# Fill real owned-space with valid 1x1 original charms, then jewels.
	for unused: int in range(Model.MAX_EQUIPMENT):
		var id: String = "gear_%06d" % arena.state.next_equipment_id
		var item: Dictionary = {"id": id, "base_id": "wayglass_token", "rarity": "normal", "item_level": 1, "affixes": []}
		var candidates: Dictionary = arena.state.equipment_instances.duplicate(true)
		candidates[id] = item
		var inventory: Array = arena.state.inventory.duplicate()
		inventory.append(id)
		if not Model._owned_items_fit(inventory, arena.state.jewels.keys(), candidates): break
		_expect(Equipment.validate_instance(item), "Space filler is a genuine catalog instance")
		arena.state.equipment_instances[id] = item
		arena.state.inventory.append(id)
		arena.state.next_equipment_id += 1
		arena.state._sync_backpack()
	while arena.state.jewels.size() < Model.MAX_JEWELS:
		if arena.state.award_special_jewel().is_empty(): break
	_expect(arena.state.jewels.size() < Model.MAX_JEWELS, "Return-space fixture exhausts backpack before jewel limit")
	var before: Dictionary = arena.state._snapshot()
	var signals_before: int = changes
	_expect(arena.state.award_special_jewel().is_empty() and arena.state._snapshot() == before and changes == signals_before, "Full return-space award is atomic, silent and consumes no identity")
	jewels = arena.state.jewels.duplicate(true)
	next_id = arena.state.next_jewel_id
	_kill(_boss())
	_expect(arena.state.jewels == jewels and arena.state.next_jewel_id == next_id, "Actual boss respects exhausted return-space")
	_expect(not arena.state._validate_snapshot(arena.state._snapshot()).is_empty(), "Real failed pickup preserves valid ownership and layout")
	finished = true

func _path(target: String) -> Array[String]:
	var queue: Array[String] = [Passives.START_ID]
	var previous: Dictionary = {Passives.START_ID: ""}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == target: break
		for neighbor: String in Passives.get_neighbors(current):
			if not previous.has(neighbor):
				previous[neighbor] = current
				queue.append(neighbor)
	var path: Array[String] = []
	var cursor: String = target
	while cursor != Passives.START_ID:
		path.push_front(cursor)
		cursor = previous[cursor]
	return path

func _test_remote_combat() -> void:
	arena.state.level = 40
	arena.state.talent_points = Model.BASE_TALENT_POINTS + arena.state.level - 1
	var socket_id: String = "ember_3_0"
	for id: String in _path(socket_id):
		_expect(arena.state.allocate_passive(id), "Physical path reaches source socket: " + id)
	var jewel_id: String = arena.state.award_special_jewel()
	_expect(not jewel_id.is_empty() and arena.state.socket_jewel(socket_id, jewel_id), "Special item installs in genuinely connected socket")
	var analysis: Dictionary = arena.state.allocation_analysis()
	var target: String = ""
	for id: String in analysis.granted_by:
		if arena.state.allocated_nodes.has(id): continue
		var adjacent: bool = false
		for neighbor: String in Passives.get_neighbors(id):
			if analysis.connected.has(neighbor): adjacent = true
		if not adjacent and Passives.get_node_stats(id).has("damage"):
			target = id
			break
	_expect(not target.is_empty(), "Actual socket covers a damage node with no normal allocation route")
	if target.is_empty(): return
	var cast_before: Dictionary = arena.state.get_skill_cast("tornado")
	var total_before: float = Damage.resolve(cast_before.packets.parent, cast_before.snapshot.modifiers).total
	var points: int = arena.state.talent_points
	_expect(arena.state.allocate_passive(target), "Covered disconnected point can be allocated")
	_expect(arena.state.talent_points == points - 1 and arena.state.allocation_sources(target).has(socket_id), "Remote point spends one point and identifies real granting socket")
	var cast_after: Dictionary = arena.state.get_skill_cast("tornado")
	var total_after: float = Damage.resolve(cast_after.packets.parent, cast_after.snapshot.modifiers).total
	_expect(total_after > total_before and arena.get_stats() == arena.state.get_stats(), "Remote passive immediately changes compiled hit damage and live actor stats")
	var enemy: Dictionary = arena._spawn_monster("crawler", arena.player_pos + Vector2(110, 0))
	enemy.spawn = 0.0
	var expected: float = Damage.resolve(cast_after.packets.parent, cast_after.snapshot.modifiers, enemy.get("resistances", {})).total
	arena._apply_damage_packet(enemy, cast_after.packets.parent, cast_after.snapshot, Color.WHITE, 0.0)
	_expect(is_equal_approx(arena.damage_trace.back().total, expected), "Real damage executor uses the same remotely modified packet as preview")
	var before: Dictionary = arena.state._snapshot()
	var signals_before: int = changes
	_expect(not arena.state.remove_jewel_reason(socket_id).is_empty() and not arena.state.remove_jewel(socket_id), "Removing required source is refused with a reason")
	_expect(arena.state._snapshot() == before and changes == signals_before, "Blocked removal changes no stats, points, items or signals")
	_expect(arena.state.save_build("user://special-scene-roundtrip.json") == OK, "Remote build writes successfully")
	var loaded = Model.new()
	_expect(loaded.load_build("user://special-scene-roundtrip.json") and loaded._snapshot() == before, "Whole remote build reloads without false connectivity rejection")
	_expect(loaded.allocation_analysis().legal and loaded.get_stats() == arena.state.get_stats(), "Reload preserves eligibility and all actual stats")
	arena.restart_run()
	_expect(arena.state._snapshot() == before and arena.state.allocation_analysis().legal, "Run restart retains remote allocation and original jewel")
	_expect(arena.state.refund_passive(target) and arena.state.remove_jewel(socket_id), "Refunding dependent point permits source retrieval")
	arena.state.refund_talents()
	_expect(arena.state.allocated_nodes == [Passives.START_ID] and arena.state.jewel_inventory.has(jewel_id), "Full reset returns all points and keeps special item")
	finished = true
