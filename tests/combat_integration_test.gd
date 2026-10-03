extends SceneTree
## Scene-level checks. Always run under isolated XDG directories (tools/validate.sh).
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")

var checks: int = 0
var failures: int = 0
var arena: Node
var migration_changes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Establish a known build inside the validation runner's disposable save root.
	var fresh = Model.new()
	_expect(fresh.save_build() == OK, "Fresh isolated integration fixture saves")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_test_explosion_application()
	_test_live_defense()
	_test_tornado_cast()
	_test_equipment_snapshot()
	_test_cancellation()
	_test_combat_panel()
	_test_schema_two_migration()
	print("Combat integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.0001, "%s (actual %.6f, expected %.6f)" % [label, value, expected])


func _reset() -> void:
	arena.restart_run()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.spawn_timer = 9999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT


func _enemy(position: Vector2) -> Dictionary:
	var enemy: Dictionary = arena._spawn_enemy(position, 0)
	enemy.spawn = 0.0
	enemy.radius = 0.0
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	return enemy


func _carrier(snapshot: Dictionary, origin: Vector2, lifetime: float = 1.0, payload: Dictionary = {}) -> Dictionary:
	var packet: Dictionary = Damage.packet({"fire": 100.0}, ["hit", "projectile"], "tornado") if payload.is_empty() else payload
	return arena.projectile_runtime.make_projectile(origin, Vector2.RIGHT,
		{"speed": 100.0, "range": 1000.0, "lifetime": lifetime, "radius": 0.0, "pierce": -1, "role": "child"},
		packet, snapshot, arena.projectile_runtime.new_cast(), Color.WHITE)


func _test_explosion_application() -> void:
	_reset()
	var target: Dictionary = _enemy(Vector2(600, 300))
	target.resistances = {"fire": 0.5}
	# Duplicate world references must still cause only one application per effect.
	arena.enemies.append(target)
	var snapshot: Dictionary = Recipes.snapshot({"damage": 100.0, "global_increased": 0.2,
		"projectile_increased": 0.5, "elemental_increased": 0.3}, ["explode_on_flight_end"])
	arena.projectiles.append(_carrier(snapshot, Vector2(500, 300)))
	arena._update_projectiles(1.0)
	_near(target.health, 10000.0 - 67.5, "Explosion damages a target once, with component mitigation")
	_expect(arena.damage_trace.size() == 1 and arena.event_counts.get("hit", 0) == 0, "Expiry endpoint excludes direct arrow hit")
	_expect(arena.event_counts.get("explosion", 0) == 1 and arena.event_counts.get("split", 0) == 0 and arena.event_counts.get("return_started", 0) == 0, "Explosion does not enter projectile behavior hooks")
	if not arena.damage_trace.is_empty():
		var record: Dictionary = arena.damage_trace[0]
		_expect(record.tags.has("explosion") and not record.tags.has("projectile"), "Applied explosion has scoped delivery tags")
		_expect(not str(record.effect_id).is_empty() and record.target_id == target.id, "Applied explosion records effect and target identity")
		_near(record.components.fire, 67.5, "Damage trace records final elemental component")
	_near(arena.total_damage, 67.5, "Damage accounting counts actual application once")
	arena._update_projectiles(3.0)
	_near(target.health, 10000.0 - 67.5, "Explosion cannot apply again on later updates")
	arena.projectiles.append(_carrier(snapshot, Vector2(500, 300)))
	arena._update_projectiles(1.0)
	_near(target.health, 10000.0 - 135.0, "A separate explosion can independently hit the same target")
	_expect(arena.damage_trace.size() == 2 and arena.damage_trace[0].effect_id != arena.damage_trace[1].effect_id, "Separate explosions use separate effect identities")


func _test_live_defense() -> void:
	_reset()
	var target: Dictionary = _enemy(Vector2(600, 300))
	target.resistances = {"fire": 0.0}
	var snapshot: Dictionary = Recipes.snapshot({"damage": 100.0}, [])
	arena.projectiles.append(_carrier(snapshot, Vector2(500, 300), 2.0))
	arena._update_projectiles(0.5)
	_near(target.health, 10000.0, "Projectile has not reached target before defense change")
	target.resistances.fire = 0.75
	arena._update_projectiles(0.6)
	_near(target.health, 9975.0, "Hit reads current resistance, not cast-time resistance")
	target.resistances.fire = 0.0
	arena._update_projectiles(0.2)
	_near(target.health, 9975.0, "Defense change does not retroactively alter a hit or repeat it")
	_expect(arena.damage_trace.size() == 1, "Sustained contact keeps one damage application per leg")


func _test_tornado_cast() -> void:
	_reset()
	arena.equip_tornado_example()
	arena.mana = 100.0
	var cost: float = Data.SKILLS.tornado.mana
	_expect(arena.cast_skill(0), "Tornado can be cast through the real skill slot")
	_near(arena.mana, 100.0 - cost, "Successful tornado charges mana exactly once")
	_near(arena.cooldowns.tornado, Data.SKILLS.tornado.cooldown, "Successful tornado starts its cooldown")
	_expect(arena.projectiles.size() == 5 and arena.total_shots == 5, "Equipped count bonus emits and counts five mothers")
	var cast_ids: Dictionary = {}
	for shot: Dictionary in arena.projectiles:
		cast_ids[shot.cast_id] = true
	_expect(cast_ids.size() == 1, "All tornado mothers share a single cast identity")
	_expect(not arena.cast_skill(0), "Cooldown blocks repeated tornado cast")
	_near(arena.mana, 100.0 - cost, "Rejected cooldown cast does not charge mana")
	_expect(arena.projectiles.size() == 5 and arena.total_shots == 5, "Rejected cooldown cast adds no shots")
	arena._update_projectiles(0.5)
	_expect(arena.projectiles.size() == 15 and arena.event_counts.get("split", 0) == 5, "Real scene integrates five splits into fifteen children")
	_expect(arena.event_counts.get("explosion", 0) == 0, "Mother consumption emits no explosion in scene")
	_reset()
	arena.mana = 100.0
	var snapshot: Dictionary = arena.state.get_combat_snapshot()
	for index: int in range(arena.MAX_PROJECTILES):
		arena.projectiles.append(_carrier(snapshot, Vector2(500, 300)))
	_expect(not arena.cast_skill(0), "Capacity rejects full tornado volley")
	_near(arena.mana, 100.0, "Capacity failure refunds mana")
	_near(arena.cooldowns.tornado, 0.0, "Capacity failure refunds cooldown")
	_expect(arena.total_shots == 0 and arena.projectiles.size() == arena.MAX_PROJECTILES, "Capacity failure preserves existing carriers and shot accounting")


func _test_equipment_snapshot() -> void:
	_reset()
	arena.equip_tornado_example()
	arena.mana = 100.0
	var original: Dictionary = arena.state.get_skill_cast("tornado").snapshot
	_expect(arena.cast_skill(0), "Snapshot scenario starts equipped tornado")
	arena.state.equip("swift_blade")
	arena.state.equip("guardian_robe")
	arena.state.equip("azure_charm")
	_expect(arena.state.get_combat_snapshot().effects.is_empty(), "Equipment change removes current return and explosion grants")
	arena._update_projectiles(0.5)
	var preserved: bool = arena.projectiles.size() == 15
	var expected_damage: float = Damage.resolve(Recipes.tornado_packet(original, "child"), original.modifiers).total
	for child: Dictionary in arena.projectiles:
		preserved = preserved and child.snapshot == original and absf(float(child.damage) - expected_damage) < 0.0001
	_expect(preserved, "Children inherit cast-time numbers and effects after mid-flight equipment change")
	arena._update_projectiles(2.0)
	_expect(arena.projectiles.is_empty(), "Original children finish their own lifetime")
	_expect(arena.event_counts.get("return_started", 0) == 15 and arena.event_counts.get("explosion", 0) == 15, "Original cast retains all returns and explosions despite unequipping")
	arena.cooldowns.tornado = 0.0
	arena.mana = 100.0
	_expect(arena.cast_skill(0) and arena.projectiles.size() == 3, "Later cast uses changed count and equipment")
	arena._update_projectiles(3.0)
	_expect(arena.event_counts.get("return_started", 0) == 15 and arena.event_counts.get("explosion", 0) == 15, "Later unequipped cast grants no extra returns or explosions")
	_expect(arena.event_counts.get("split", 0) == 8, "Both casts preserve their own parent counts")


func _test_cancellation() -> void:
	_reset()
	var snapshot: Dictionary = Recipes.snapshot({"damage": 100.0}, ["return_on_range", "explode_on_flight_end"])
	var target: Dictionary = _enemy(Vector2(600, 300))
	var dying: Dictionary = _carrier(snapshot, Vector2(500, 300))
	arena.projectiles.append(dying)
	arena.invulnerable = 0.0
	arena.shield = 0.0
	arena.health = 1.0
	arena.hit_player(2.0)
	_expect(not arena.alive and arena.projectiles.is_empty(), "Player death cancels active projectiles")
	_expect(not dying.active and dying.end_reason == "owner_death", "Death cancellation has explicit cause")
	_expect(arena.event_counts.get("explosion", 0) == 0 and arena.damage_trace.is_empty(), "Death cancellation emits no damaging effects")
	_near(target.health, 10000.0, "Death does not damage nearby targets")
	arena.hud.close_panel()
	_expect(arena.hud.is_blocking(), "Death screen cannot be dismissed into combat")
	_reset()
	var reset_shot: Dictionary = _carrier(snapshot, Vector2(500, 300))
	arena.projectiles.append(reset_shot)
	arena.restart_run()
	_expect(arena.alive and arena.projectiles.is_empty() and not reset_shot.active and reset_shot.end_reason == "run_reset", "Restart cancels old carriers and starts clean run")
	_expect(arena.event_counts.is_empty() and arena.damage_trace.is_empty() and arena.combat_trace.is_empty(), "Restart clears traces without synthetic explosions")
	_expect(not arena.hud.is_blocking(), "Restart closes death panel")


func _press(name: String) -> void:
	var button: Button = arena.hud.find_child(name, true, false) as Button
	_expect(button != null, "Combat control exists: " + name)
	if button != null:
		button.pressed.emit()


func _test_combat_panel() -> void:
	_reset()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F6
	key.pressed = true
	arena._unhandled_key_input(key)
	_expect(arena.hud.is_blocking() and arena.hud._active_panel == "combat", "F6 opens the combat inspector")
	var before: float = arena.elapsed
	arena._process(0.5)
	_near(arena.elapsed, before, "Combat inspector pauses simulation")
	_expect(not arena.cast_skill(0), "Inspector blocks skill casts")
	_press("EquipTornadoExample")
	_expect(arena.state.skill_slots[0] == "tornado" and arena.combat_preview().count == 5, "Example button equips skill and count bonus")
	_expect(arena.state.get_combat_snapshot().effects.size() == 2, "Example button equips both effect grants")
	_press("ToggleReturnEffect")
	_expect(not arena.state.get_combat_snapshot().effects.has("return_on_range"), "Return toggle unequips grant")
	_press("ToggleReturnEffect")
	_expect(arena.state.get_combat_snapshot().effects.has("return_on_range"), "Return toggle re-equips grant")
	_press("ToggleExplosionEffect")
	_expect(not arena.state.get_combat_snapshot().effects.has("explode_on_flight_end"), "Explosion toggle unequips grant")
	_press("ToggleExplosionEffect")
	_expect(arena.state.get_combat_snapshot().effects.has("explode_on_flight_end"), "Explosion toggle re-equips grant")
	_press("ToggleProjectileCount")
	_expect(arena.combat_preview().count == 3, "Count toggle removes extra mothers")
	_press("ToggleProjectileCount")
	_expect(arena.combat_preview().count == 5, "Count toggle restores extra mothers")
	var loaded = Model.new()
	_expect(loaded.load_build() and loaded.get_combat_snapshot() == arena.state.get_combat_snapshot(), "Inspector changes persist and reload accurately")
	key.physical_keycode = KEY_ESCAPE
	arena._unhandled_key_input(key)
	_expect(not arena.hud.is_blocking(), "Escape closes inspector")
	arena._process(1.0 / 30.0)
	_expect(arena.elapsed > before, "Combat resumes after inspector closes")


func _migration_changed() -> void:
	migration_changes += 1


func _write_fixture(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Migration fixture opens: " + path)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _test_schema_two_migration() -> void:
	var path: String = "user://combat_schema2_fixture.json"
	var backup: String = path + ".v2-backup.json"
	var conflict_path: String = "user://combat_schema2_conflict.json"
	var conflict_backup: String = conflict_path + ".v2-backup.json"
	var fixture_paths: Array[String] = [path, backup, conflict_path, conflict_backup]
	for fixture_path: String in fixture_paths:
		if FileAccess.file_exists(fixture_path):
			DirAccess.remove_absolute(fixture_path)
	var old = Model.new()
	old.inventory.assign(["ember_wand", "swift_blade", "guardian_robe", "vitality_armor", "azure_charm", "storm_charm"])
	old.equipped = {"weapon": "swift_blade", "armor": "vitality_armor", "charm": "storm_charm"}
	old.skill_slots.assign(["meteor", "chain", "nova", "dash", "ward"])
	old.add_xp(85)
	_expect(old.allocate_passive("ember_1_0") and old.allocate_passive("ember_2_0") and old.allocate_passive("ember_3_0"), "Legacy fixture retains a connected nontrivial passive path")
	_expect(old.socket_jewel("ember_3_0", "jewel_000001"), "Legacy fixture includes a socketed jewel")
	old._sync_backpack()
	_expect(old.move_in_backpack("item:ember_wand", Vector2i(10, 5)), "Legacy fixture includes a custom non-packed inventory position")
	var legacy: Dictionary = old._snapshot()
	legacy.version = 2
	legacy.erase("crafting")
	legacy.erase("equipment_instances")
	legacy.erase("next_equipment_id")
	legacy.erase("skill_supports")
	_expect(legacy.inventory.size() == 6 and not old._validate_snapshot(legacy).is_empty(), "True schema2 original-six inventory and exact corresponding layout validate")
	var original_text: String = "\n" + JSON.stringify(legacy, "  ", true, true) + "\n"
	if not _write_fixture(path, original_text):
		return
	var loaded = Model.new()
	loaded.changed.connect(_migration_changed)
	migration_changes = 0
	_expect(loaded.load_build(path), "Schema2 legacy build loads and migrates")
	_expect(migration_changes == 1 and loaded.migrated_from_v2 and not loaded.migrated_from_v1, "Migration emits one change with correct source-version flag")
	_expect(FileAccess.get_file_as_string(path) == original_text and not FileAccess.file_exists(backup), "Load leaves original bytes untouched until same-path save")
	_expect(loaded.inventory.size() == 9 and loaded.inventory.slice(0, 6) == legacy.inventory, "Migration preserves original inventory order and adds exactly three items")
	for id: String in Data.COMBAT_STARTER_ITEMS:
		_expect(loaded.inventory.count(id) == 1, "Mechanic equipment granted exactly once: " + id)
	var migrated: Dictionary = loaded._snapshot()
	for field: String in ["equipped", "skill_slots", "level", "xp", "talent_points", "allocated_nodes", "jewels", "jewel_inventory", "socketed_jewels", "next_jewel_id"]:
		_expect(migrated[field] == legacy[field], "Schema2 migration preserves " + field)
	var positions_preserved: bool = true
	for key: String in legacy.backpack_positions:
		positions_preserved = positions_preserved and migrated.backpack_positions.get(key) == legacy.backpack_positions[key]
	_expect(positions_preserved, "Migration preserves all old backpack positions when new gear fits")
	_expect(not loaded._validate_snapshot(migrated).is_empty(), "Migrated layout includes valid non-overlapping new gear positions")
	_expect(loaded.load_build(path) and loaded.inventory.size() == 9 and migration_changes == 2, "Repeated legacy loading neither duplicates grants nor emits extra changes")
	_expect(loaded.save_build(path) == OK, "First same-path migrated save succeeds")
	_expect(FileAccess.file_exists(backup) and FileAccess.get_file_as_string(backup) == original_text, "Migration backup preserves original schema2 bytes exactly")
	_expect(loaded.migration_backup_path == backup, "Migration records the actual backup destination")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(saved is Dictionary and int(saved.version) == Model.SAVE_VERSION, "Migrated primary save writes current schema")
	_expect(migration_changes == 2, "Saving migration does not emit redundant build changes")
	var reloaded = Model.new()
	_expect(reloaded.load_build(path) and reloaded._snapshot() == loaded._snapshot(), "Schema3 migrated build round-trips every field")
	_expect(not reloaded.migrated_from_v1 and not reloaded.migrated_from_v2 and reloaded.inventory.size() == 9, "Schema3 reload does not rerun migration or add items")
	_expect(reloaded.save_build(path) == OK and FileAccess.get_file_as_string(backup) == original_text, "Later schema3 saves preserve the original migration backup")
	var conflicting_text: String = "Previously preserved unrelated legacy backup\n"
	if _write_fixture(conflict_path, original_text) and _write_fixture(conflict_backup, conflicting_text):
		var conflict = Model.new()
		_expect(conflict.load_build(conflict_path), "Legacy data loads even when a backup conflict exists")
		var before: Dictionary = conflict._snapshot()
		_expect(conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS, "Conflicting legacy backup blocks migrated overwrite")
		_expect(FileAccess.get_file_as_string(conflict_path) == original_text, "Backup conflict preserves original primary bytes")
		_expect(FileAccess.get_file_as_string(conflict_backup) == conflicting_text, "Backup conflict never overwrites existing backup bytes")
		_expect(conflict._snapshot() == before, "Rejected migration save preserves in-memory build")
	for fixture_path: String in fixture_paths:
		if FileAccess.file_exists(fixture_path):
			DirAccess.remove_absolute(fixture_path)
