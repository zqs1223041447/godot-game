extends RefCounted
## Disposable real arena fixtures shared by progress regressions and CPU benchmark.
## Damage is overridden to 100,000 only in the spy's live stats; saved builds retain
## valid schema7 data. Enemies retain catalog HP/shields/XP, reward and lineage rules.
const Model = preload("res://scripts/build_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const ProjectileRuntimeScript = preload("res://scripts/combat/projectile_runtime.gd")
const MonsterRuntimeScript = preload("res://scripts/monsters/monster_runtime.gd")
const SAVE_PATH: String = "user://build_save.json"
const STEP: float = 1.0 / 60.0

class SpyBuild extends "res://scripts/build_state.gd":
	var save_attempts: int = 0
	var save_successes: int = 0
	var change_count: int = 0
	var deny_saves: bool = false
	var after_save: Callable
	var fixture_damage: float = 100000.0

	func _init() -> void:
		changed.connect(_count_change)

	func _count_change() -> void:
		change_count += 1

	func get_stats() -> Dictionary:
		var result: Dictionary = super.get_stats()
		result.damage = fixture_damage
		return result

	func save_build(path: String = "user://build_save.json") -> Error:
		save_attempts += 1
		var result: Error = ERR_CANT_CREATE if deny_saves else super.save_build(path)
		if result == OK:
			save_successes += 1
		# Reentry deliberately happens AFTER the actual write, exposing stale-save bugs.
		var callback: Callable = after_save
		after_save = Callable()
		if callback.is_valid():
			callback.call()
		return result

class ExitSpyArena extends "res://scripts/main.gd":
	var quit_requests: int = 0

	func _quit_game() -> void:
		quit_requests += 1

class SpyHud extends "res://scripts/game_hud.gd":
	var refresh_calls: int = 0
	var after_refresh: Callable
	var after_notify: Callable

	func refresh_build() -> void:
		refresh_calls += 1
		super.refresh_build()
		var callback: Callable = after_refresh
		after_refresh = Callable()
		if callback.is_valid():
			callback.call()

	func notify(message: String) -> void:
		super.notify(message)
		var callback: Callable = after_notify
		after_notify = Callable()
		if callback.is_valid():
			callback.call()

static func install_hud_spy(arena: Node2D) -> void:
	arena.hud.free()
	arena.hud = SpyHud.new()
	arena.add_child(arena.hud)
	arena.hud.setup(arena)
	arena.hud.set_process(false)
	arena.hud.refresh_calls = 0

static func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true

static func create(tree: SceneTree, batching: bool, initial: Dictionary = {}) -> Node2D:
	var snapshot: Dictionary = Model.new()._snapshot() if initial.is_empty() else initial
	if not write_bytes(SAVE_PATH, JSON.stringify(snapshot, "\t", true, true).to_utf8_buffer()):
		return null
	return create_from_existing(tree, batching)

static func create_from_existing(tree: SceneTree, batching: bool) -> Node2D:
	var arena: Node2D = load("res://scenes/main.tscn").instantiate()
	arena.set_script(ExitSpyArena)
	arena.state = SpyBuild.new()
	arena.use_progress_batching = batching
	tree.root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.restart_run()
	arena.hud.close_panel()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime = MonsterRuntimeScript.new()
	arena.projectile_runtime = ProjectileRuntimeScript.new()
	arena.spawn_timer = 99999.0
	arena.invulnerable = 100.0
	arena.rng.seed = 9021007
	arena._autosave_timer = 0.0
	arena.rings.clear()
	reset_counts(arena)
	return arena

static func reset_counts(arena: Node2D) -> void:
	arena.state.save_attempts = 0
	arena.state.save_successes = 0
	arena.state.change_count = 0
	arena.progress_hud_refresh_count = 0
	arena.progress_save_attempt_count = 0
	arena.progress_save_success_count = 0

static func prepare_combat(arena: Node2D, scenario: String, count: int = 100) -> void:
	var tick_scenario: bool = scenario.contains("tick")
	for index: int in range(count):
		var template: String = "crawler"
		if scenario.contains("mixed"):
			template = "rift_warden" if index == count - 1 else "brood_host" if index == count - 2 else "splitter" if index >= count - 10 else "crawler"
		var position: Vector2 = arena.player_pos + Vector2.RIGHT.rotated(TAU * index / maxi(1, count)) * (65.0 + (index % 5) * 12.0)
		if tick_scenario:
			position = arena.ARENA.position + Vector2(140 + (index % 10) * 145, 65 + int(index / 10) * 52)
		var enemy: Dictionary = arena._spawn_monster(template, position, "level_boss" if template == "rift_warden" else "ordinary")
		enemy.spawn = 0.0
		if tick_scenario:
			var origin: Vector2 = position - Vector2(float(enemy.radius) + 14.0, 0.0)
			var snapshot: Dictionary = arena.state.get_combat_snapshot()
			arena.projectiles.append(arena.projectile_runtime.make_projectile(origin, Vector2.RIGHT,
				{"speed": 1800.0, "range": 500.0, "lifetime": 1.0, "radius": 5.5, "pierce": 0},
				Damage.packet({"physical": 100000.0}, ["hit", "projectile"], "basic"), snapshot,
				arena.projectile_runtime.new_cast(), Color.WHITE))
	# Setup cues deliberately excluded from measured region, without bypassing gameplay.
	arena.rings.clear()
	reset_counts(arena)

static func execute(arena: Node2D, scenario: String) -> bool:
	if scenario.contains("tick"):
		arena.tick(STEP)
		return true
	return arena.cast_skill(arena.state.skill_slots.find("nova"))

static func counts(arena: Node2D) -> Dictionary:
	return {"signals": arena.state.change_count, "hud_refreshes": arena.progress_hud_refresh_count,
		"save_attempts": arena.progress_save_attempt_count, "save_successes": arena.progress_save_success_count,
		"spy_attempts": arena.state.save_attempts, "spy_successes": arena.state.save_successes}

static func _script_values(value: Object, ignored: Array[String] = []) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in value.get_property_list():
		var key: String = property.name
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) or ignored.has(key):
			continue
		var item: Variant = value.get(key)
		if item is Object or item is Callable or item is Signal:
			continue
		result[key] = item.duplicate(true) if item is Dictionary or item is Array else item
	return result

static func final_snapshot(arena: Node2D) -> Dictionary:
	# Every scalar/container arena script property, full model schema, runtime IDs,
	# ledgers, lineage queues, presentation cues and both RNG seed/state are compared.
	# Persistence diagnostics/dirty state are bookkeeping, not gameplay observables.
	var ignored: Array[String] = ["use_progress_batching", "progress_hud_refresh_count", "progress_save_attempt_count", "progress_save_success_count", "quit_requests"]
	for property: Dictionary in arena.get_property_list():
		if str(property.name).begins_with("_progress_"):
			ignored.append(str(property.name))
	return {"arena": _script_values(arena, ignored), "model": arena.state._snapshot(),
		"rng_seed": arena.rng.seed, "rng_state": arena.rng.state,
		"monsters": _script_values(arena.monster_runtime), "projectiles": _script_values(arena.projectile_runtime),
		"visual_cues": _script_values(arena.visual_cues), "saved_bytes": FileAccess.get_file_as_bytes(SAVE_PATH)}

static func saved_matches(arena: Node2D) -> bool:
	return FileAccess.get_file_as_string(SAVE_PATH) == JSON.stringify(arena.state._snapshot(), "\t", true, true)

static func full_backpack() -> Dictionary:
	var model := Model.new()
	var random := RandomNumberGenerator.new()
	random.seed = 104
	while model.jewels.size() < Model.MAX_JEWELS:
		if model.award_jewel(random).is_empty():
			break
	# Add size-one generated charms until total-owned reservation reaches capacity.
	for serial: int in range(2):
		var id: String = "gear_%06d" % model.next_equipment_id
		model.equipment_instances[id] = {"id": id, "base_id": "wayglass_token", "rarity": "normal", "item_level": 1, "affixes": []}
		model.inventory.append(id)
		model.next_equipment_id += 1
	model._sync_backpack()
	return model._snapshot()
