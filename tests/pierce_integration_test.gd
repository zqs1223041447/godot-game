extends SceneTree
## Execute only with disposable XDG roots and PIERCE_QA_ROOT=$XDG_DATA_HOME.
## Actual BuildState -> unified compiler -> main.cast_skill -> scene settlement.
const Model = preload("res://scripts/build_state.gd")
const Registry = preload("res://scripts/combat/support_registry.gd")
const Data = preload("res://scripts/game_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const FRESH: String = "user://pierce_fresh.json"
const V9: String = "res://tests/fixtures/pierce_v9_build.json"

class CountingState extends "res://scripts/build_state.gd":
	var compile_calls: int = 0
	func get_skill_cast(skill_id: String) -> Dictionary:
		compile_calls += 1
		return super.get_skill_cast(skill_id)

var arena: Node
var checks: int = 0
var failures: int = 0
var completed: bool = false
var changes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _prove_isolation():
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--probe-only"):
		quit(0)
		return
	var fresh = Model.new()
	_expect(fresh.save_build() == OK and fresh.save_build(FRESH) == OK, "Fresh fixtures write only after isolation proof")
	_start_scene()
	for test: Callable in [_state_transactions, _real_casts, _admission, _serial_budgets,
		_phase_ledger, _return_budgets, _frozen_flights, _literal_migration, _version_fences]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	completed = false
	await _scene_migration()
	_expect(completed, "Real v9 startup/autosave case completed without a script exception")
	arena.queue_free()
	await process_frame
	print("Pierce integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _prove_isolation() -> bool:
	var expected: String = OS.get_environment("PIERCE_QA_ROOT").simplify_path()
	var actual: String = ProjectSettings.globalize_path("user://").simplify_path()
	var safe: bool = expected.begins_with("/tmp/godot-pierce-acceptance-") \
		and expected == OS.get_environment("XDG_DATA_HOME").simplify_path() \
		and actual.begins_with(expected + "/") and actual == OS.get_user_data_dir().simplify_path()
	_expect(safe, "Disposable Linux userdata path must match explicit XDG_DATA_HOME and PIERCE_QA_ROOT")
	if not safe:
		return false
	print("ISOLATION PROVED: user://=" + actual)
	var fresh: bool = not FileAccess.file_exists("user://build_save.json")
	_expect(fresh, "Refuse an existing default build, even within the claimed QA directory")
	return fresh


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _near(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.0001, "%s (actual %.7f, expected %.7f)" % [message, actual, expected])


func _changed() -> void:
	changes += 1


func _write(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Isolated fixture opens: " + path)
	if file != null:
		file.store_buffer(bytes)
		file.close()


func _start_scene() -> void:
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = CountingState.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false


func _prepare(skill: String, links: Array) -> void:
	_expect(arena.state.load_build(FRESH), "Fresh build reload keeps live state signal wiring")
	arena.restart_run()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 614100
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	arena.state.slot_skill(0, skill)
	if not links.is_empty():
		_expect(arena.state.set_skill_supports(skill, links), "Real support transaction accepts fixture: " + skill + str(links))
	arena.mana = 100.0
	arena.cooldowns[skill] = 0.0


func _cast() -> bool:
	arena.state.compile_calls = 0
	var accepted: bool = arena.cast_skill(0)
	_expect(arena.state.compile_calls == 1, "Actual main cast compiles once for admission/payment/emission")
	return accepted


func _target(x: float) -> Dictionary:
	var target: Dictionary = arena._spawn_monster("crawler", Vector2(x, 300), "ordinary", "normal", [])
	target.spawn = 0.0
	target.radius = 0.0
	target.health = 100000.0
	target.max_health = 100000.0
	target.shield = 0.0
	target.resistances = {}
	target.speed = 0.0
	return target


func _center() -> Dictionary:
	return arena.projectiles[arena.projectiles.size() / 2]


func _hits(projectile_id: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in arena.combat_trace:
		if event.type == "hit" and (projectile_id == 0 or int(event.projectile_id) == projectile_id):
			result.append(event)
	return result


func _coefficient(skill: String) -> float:
	return 1.6 if skill == "bolt" else 0.85


func _state_transactions() -> void:
	var state = Model.new()
	state.changed.connect(_changed)
	_expect(Registry.get_definition("pierce").name == "贯穿辅助", "Unified registry exposes stable pierce identity")
	for skill: String in ["bolt", "frost"]:
		_expect(Registry.supports_for_skill(skill).has("pierce"), "Unified eligibility includes " + skill)
		changes = 0
		_expect(state.add_skill_support(skill, "pierce") and changes == 1, "Add pierce emits one validated change")
		var before: Dictionary = state._snapshot()
		var signals: int = changes
		_expect(not state.add_skill_support(skill, "pierce") and state._snapshot() == before and changes == signals, "Duplicate add is atomic and silent")
		_expect(state.set_skill_supports(skill, ["pierce", "focus"]) and state.get_skill_supports(skill) == ["focus", "pierce"], "Set canonicalizes both real support identities")
		before = state._snapshot()
		signals = changes
		for links: Array in [["volley", "focus", "pierce"], ["pierce", "pierce"], ["pierce", "unknown"], ["pierce", null]]:
			_expect(not state.set_skill_supports(skill, links) and state._snapshot() == before and changes == signals, "Invalid support set has no partial mutation: " + str(links))
		var cast: Dictionary = state.get_skill_cast(skill)
		_expect(cast.ok and cast.recipe.pierce == (3 if skill == "bolt" else 4), "State cast uses integrated extension recipe")
		_expect(not Compiler.compile_skill(skill, cast.snapshot, ["pierce"]).ok, "Compiled state snapshot cannot apply supports twice")
		cast.recipe.pierce = 99
		cast.snapshot.modifiers.clear()
		var ids: Array[String] = state.get_skill_supports(skill)
		ids.clear()
		_expect(state.get_skill_cast(skill).recipe.pierce == (3 if skill == "bolt" else 4) and state.get_skill_supports(skill) == ["focus", "pierce"], "Returned cast and support list cannot mutate build state")
		_expect(state.remove_skill_support(skill, "pierce") and state.get_skill_supports(skill) == ["focus"], "Remove targets pierce without removing legacy support")
		_expect(not state.remove_skill_support(skill, "pierce"), "Repeated removal rejects an absent identity")
	for skill: String in ["tornado", "nova", "dash", "ward", "meteor", "chain", "basic", "unknown"]:
		var before: Dictionary = state._snapshot()
		var signals: int = changes
		_expect(not Registry.compatibility_reason(skill, ["pierce"]).is_empty() and not state.add_skill_support(skill, "pierce"), "Pierce rejects ineligible skill: " + skill)
		_expect(state._snapshot() == before and changes == signals, "Rejected eligibility preserves whole build: " + skill)
	completed = true


func _real_casts() -> void:
	for skill: String in ["bolt", "frost"]:
		for links: Array in [[], ["pierce"], ["pierce", "volley"], ["volley", "pierce"], ["pierce", "focus"], ["focus", "pierce"]]:
			_prepare(skill, links)
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			var factor: float = (0.85 if links.has("pierce") else 1.0) * (0.8 if links.has("volley") else 1.0) * (1.25 if links.has("focus") else 1.0)
			var mana_factor: float = (1.2 if links.has("pierce") else 1.0) * (1.3 if links.has("volley") else 1.0) * (1.2 if links.has("focus") else 1.0)
			var count: int = (3 if skill == "bolt" else 5) + (2 if links.has("volley") else 0)
			var target: Dictionary = _target(620)
			_expect(cast.ok and _cast(), "Actual supported scene cast accepts: " + skill + str(links))
			_near(arena.mana, 100.0 - (7.0 if skill == "bolt" else 16.0) * mana_factor, "Actual mana charge includes each factor once")
			_near(arena.cooldowns[skill], 0.8 if skill == "bolt" else 4.0, "Support leaves actual cooldown unchanged")
			_expect(arena.projectiles.size() == count and arena.total_shots == count, "Actual emitted count respects old volley and pierce adds no initial shots")
			var modifiers: Dictionary = {}
			for modifier: Dictionary in cast.snapshot.modifiers:
				if str(modifier.get("id", "")).begins_with("support:"):
					modifiers[modifier.id] = int(modifiers.get(modifier.id, 0)) + 1
			_expect(modifiers.size() == links.size(), "Compiled snapshot has exactly the requested distinct support modifiers")
			for support: String in links:
				_expect(modifiers.get("support:" + support) == 1, "Support damage modifier occurs once: " + support)
			for shot: Dictionary in arena.projectiles:
				_expect(shot.pierce == (1 if skill == "bolt" else 2) + (2 if links.has("pierce") else 0), "Actual carrier receives finite compiled pierce")
				_near(shot.damage, 18.0 * _coefficient(skill) * factor, "Carrier resolved damage applies each more/less factor once")
				_near(shot.payload.base.get("lightning" if skill == "bolt" else "cold", 0.0), 18.0 * _coefficient(skill), "Raw packet is not pre-multiplied by support less")
			_near(Damage.resolve(cast.packets.secondary, cast.snapshot.modifiers).total, 18.0 * 0.9, "Integrated support modifiers do not reduce independent secondary packet")
			var unrelated: Dictionary = Damage.packet({"lightning": 100.0}, ["hit", "projectile", "attack"], "basic")
			_near(Damage.resolve(unrelated, cast.snapshot.modifiers).total, 100.0, "Integrated skill-scoped support cannot leak into basic projectile attack")
			arena._update_projectiles(0.3)
			_expect(arena.damage_trace.size() == 1, "Narrow center target receives exactly one real hit")
			_near(100000.0 - float(target.health), 18.0 * _coefficient(skill) * factor, "Actual health loss matches independent damage algebra")
	completed = true


func _admission() -> void:
	for skill: String in ["bolt", "frost"]:
		for links: Array in [["pierce"], ["volley", "pierce"], ["focus", "pierce"]]:
			_prepare(skill, links)
			var cast: Dictionary = arena.state.get_skill_cast(skill)
			arena.mana = float(cast.mana) - 0.001
			var insufficient: float = arena.mana
			var next_cast: int = arena.projectile_runtime.next_cast_id
			_expect(not _cast() and arena.projectiles.is_empty(), "Fraction below effective mana rejects before emission")
			_near(arena.mana, insufficient, "Insufficient-mana rejection makes no payment")
			_expect(arena.cooldowns[skill] == 0.0 and arena.total_shots == 0 and arena.projectile_runtime.next_cast_id == next_cast, "Rejected cast consumes no cooldown, count or cast ID")
			arena.mana = float(cast.mana)
			_expect(_cast(), "Exact effective mana admits actual cast")
			_near(arena.mana, 0.0, "Exact-cost cast pays exactly all available mana")
			_prepare(skill, links)
			_expect(_cast(), "Capacity fixture begins with actual emitted carriers")
			var prototype: Dictionary = arena.projectiles[0].duplicate(true)
			arena.projectiles.clear()
			for index: int in range(arena.MAX_PROJECTILES - int(cast.initial_count) + 1):
				arena.projectiles.append(prototype.duplicate(true))
			var before: Array = arena.projectiles.duplicate(true)
			arena.mana = 100.0
			arena.cooldowns[skill] = 0.0
			var shot_count: int = arena.total_shots
			next_cast = arena.projectile_runtime.next_cast_id
			_expect(not _cast() and arena.projectiles == before, "One missing slot rejects the whole actual volley without partial emission")
			_expect(arena.mana == 100.0 and arena.cooldowns[skill] == 0.0 and arena.total_shots == shot_count and arena.projectile_runtime.next_cast_id == next_cast, "Capacity refusal preserves mana, cooldown, count and cast ID")
			arena.projectiles.pop_back()
			_expect(_cast() and arena.projectiles.size() == arena.MAX_PROJECTILES, "Exactly enough free slots admits the entire volley")
			arena.cooldowns[skill] = 0.0
			arena.mana = 100.0
			before = arena.projectiles.duplicate(true)
			_expect(not _cast() and arena.projectiles == before and arena.mana == 100.0 and arena.cooldowns[skill] == 0.0, "Completely full capacity also refuses without payment")
		_prepare(skill, ["pierce"])
		arena.state.skill_supports[skill] = ["pierce", "focus", "volley"] # Deliberately corrupt only this fixture.
		_expect(not _cast() and arena.mana == 100.0 and arena.cooldowns[skill] == 0.0 and arena.projectiles.is_empty(), "Runtime three-slot corruption fails before payment")
	completed = true


func _serial_budgets() -> void:
	for skill: String in ["bolt", "frost"]:
		for links: Array in [[], ["pierce"]]:
			for indexed: bool in [false, true]:
				_prepare(skill, links)
				arena.projectile_runtime.use_spatial_index = indexed
				var targets: Array[Dictionary] = []
				for index: int in range(6):
					targets.append(_target(580.0 + index * 70.0))
				_expect(_cast(), "Serial target fixture enters through actual main.cast_skill")
				var center: Dictionary = _center()
				arena._update_projectiles(0.15)
				arena._update_projectiles(0.85)
				var hits: Array[Dictionary] = _hits(int(center.id))
				var capacity: int = (2 if skill == "bolt" else 3) + (2 if links.has("pierce") else 0)
				_expect(hits.size() == capacity and arena.damage_trace.size() == capacity, "%s total single-carrier targets are %d, indexed=%s" % [skill, capacity, indexed])
				_expect(center.end_reason == "hit_consumed" and center.pierce == 0, "Final permitted target consumes the finite carrier")
				for index: int in range(targets.size()):
					var expected: float = 18.0 * _coefficient(skill) * (0.85 if links.has("pierce") else 1.0) if index < capacity else 0.0
					_near(100000.0 - float(targets[index].health), expected, "Ordered target health confirms exact capacity and no repeat hit")
					if index < hits.size():
						_expect(int(hits[index].target_id) == int(targets[index].id), "Contact ordering follows swept geometry")
	arena.projectile_runtime.use_spatial_index = true
	completed = true


func _phase_ledger() -> void:
	for skill: String in ["bolt", "frost"]:
		_prepare(skill, ["pierce"])
		var target: Dictionary = _target(580)
		_expect(_cast(), "Ledger fixture casts actual supported volley")
		var center: Dictionary = _center()
		arena._update_projectiles(0.15)
		var budget: int = int(center.pierce)
		var health: float = float(target.health)
		target.pos = Vector2(center.pos) + Vector2(20, 0) # Same identity re-enters the next sweep.
		arena._update_projectiles(0.1)
		_expect(_hits(int(center.id)).size() == 1 and center.pierce == budget and target.health == health, "Same-phase target identity cannot spend pierce or take damage twice")
	completed = true


func _return_budgets() -> void:
	for skill: String in ["bolt", "frost"]:
		_prepare(skill, ["pierce"])
		_expect(arena.state.equip("return_mantle"), "Real equipment grants return")
		var original: Dictionary = _target(1100)
		_expect(_cast(), "Return fixture casts actual supported volley")
		var center: Dictionary = _center()
		arena._update_projectiles(650.0 / float(center.speed))
		var remaining: int = 2 if skill == "bolt" else 3
		_expect(center.state == "returning" and center.pierce == remaining, "Return begins with outbound-spent budget, never a replenished budget")
		_near(center.age, 650.0 / float(center.speed), "Return keeps original age")
		_near(center.lifetime, 1.7, "Return keeps original lifetime ceiling")
		var added: Array[Dictionary] = [_target(1130), _target(1060), _target(1030), _target(1000)]
		arena._update_projectiles(0.45)
		var hits: Array[Dictionary] = _hits(int(center.id))
		var capacity: int = 4 if skill == "bolt" else 5
		_expect(hits.size() == capacity and center.end_reason == "hit_consumed", "Outbound plus return share exactly four/five hits")
		_expect(hits[0].phase == "outbound" and hits[1].phase == "returning" and int(hits[2].target_id) == int(original.id), "Original target can be hit again only on the returning phase")
		var ledger: Dictionary = {}
		for hit: Dictionary in hits:
			var key: String = "%s:%d" % [hit.phase, hit.target_id]
			_expect(not ledger.has(key), "Per-phase target ledger has no duplicate")
			ledger[key] = true
		_near(100000.0 - float(original.health), 2.0 * 18.0 * _coefficient(skill) * 0.85, "Actual original-target health contains one hit per phase")
		_near(float(added[3].health), 100000.0, "Target beyond shared return budget remains untouched")
		if skill == "bolt":
			_near(float(added[2].health), 100000.0, "Bolt return cannot borrow frost's extra hit")
	completed = true


func _frozen_flights() -> void:
	for skill: String in ["bolt", "frost"]:
		_prepare(skill, ["focus", "pierce"])
		for id: String in ["prism_bow", "return_mantle", "detonation_charm"]:
			_expect(arena.state.equip(id), "Freeze fixture equips through actual API: " + id)
		var target: Dictionary = _target(1100)
		_expect(_cast(), "Frozen fixture casts through real admission")
		var center: Dictionary = _center()
		var frozen: Dictionary = center.snapshot.duplicate(true)
		var raw_packet: Dictionary = center.payload.duplicate(true)
		arena._update_projectiles(0.2)
		_expect(arena.state.remove_skill_support(skill, "pierce") and arena.state.remove_skill_support(skill, "focus") and arena.state.add_skill_support(skill, "volley"), "Actual support transactions reconfigure future casts while old cast flies")
		for slot: String in Model.EQUIPMENT_SLOTS:
			_expect(arena.state.unequip(slot), "Actual unequip removes old offensive/effect source: " + slot)
		_expect(arena.state.slot_skill(1, skill), "Actual slot swap does not recompile existing carriers")
		for shot: Dictionary in arena.projectiles:
			_expect(shot.snapshot == frozen and shot.payload == raw_packet and shot.pierce == (3 if skill == "bolt" else 4), "In-flight packet, support/equipment snapshot and pierce remain frozen")
		target.resistances = {"lightning" if skill == "bolt" else "cold": 0.5, "fire": 0.5}
		arena._update_projectiles(650.0 / float(center.speed) - 0.2)
		_expect(center.state == "returning" and center.snapshot == frozen, "Old return effect survives removal of its equipment source")
		arena._update_projectiles(0.25)
		var expected: float = 22.0 * _coefficient(skill) * 1.9 * 1.25 * 0.85 * 0.5
		_expect(_hits(int(center.id)).size() == 2, "Old center projectile makes one outbound and one return impact")
		_near(100000.0 - float(target.health), expected * 2.0, "Frozen offense and live target resistance govern actual old impacts")
		target.pos = Vector2(center.pos) + Vector2(center.velocity) * (float(center.lifetime) - float(center.age))
		arena.damage_trace.clear()
		arena._update_projectiles(float(center.lifetime) - float(center.age) + 0.01)
		_expect(arena.projectiles.is_empty() and arena.event_counts.get("explosion", 0) == (3 if skill == "bolt" else 5), "Every old carrier retains exactly one natural-end explosion after equipment removal")
		var explosions: int = 0
		for record: Dictionary in arena.damage_trace:
			if record.tags.has("explosion"):
				explosions += 1
				_near(record.total, 22.0 * 0.9 * 1.5 * 0.5, "Actual secondary explosion excludes pierce/focus/projectile more factors")
		_expect(explosions > 0, "Expiry-position target receives old real secondary explosion")
		arena.state.slot_skill(0, skill)
		arena.cooldowns[skill] = 0.0
		arena.mana = 100.0
		_expect(_cast() and arena.projectiles.size() == (5 if skill == "bolt" else 7), "Next cast uses new volley after skill swap")
		for shot: Dictionary in arena.projectiles:
			_expect(shot.pierce == (1 if skill == "bolt" else 2) and shot.snapshot.effects.is_empty(), "Only future carriers use removed pierce/equipment configuration")
			_near(shot.damage, 18.0 * _coefficient(skill) * 0.8, "Future actual carrier uses new bare volley damage")
	completed = true


func _literal_migration() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(V9)
	var legacy: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	_expect(legacy.version == 9 and legacy.size() == 16 and Equipment.CURRENT_VOCABULARY == 9, "Independent literal fixture is historical v9, including local weapon vocabulary")
	var path: String = "user://pierce_literal_v9.json"
	var backup: String = path + ".v9-backup.json"
	_write(path, bytes)
	var state = Model.new()
	state.changed.connect(_changed)
	changes = 0
	_expect(state.load_build(path) and state.migrated_from_v9 and changes == 1, "Literal v9 load migrates in memory with one committed change")
	var expected: Dictionary = _expected_literal_v10(legacy)
	_expect(Model.SAVE_VERSION == 13 and state._snapshot() == expected, "Empty crafting state is added; historical identities, gaps, rolls, nodes, special jewel, positions and legacy links persist")
	_expect(state.get_combat_snapshot().has("weapon_profile") and state.get_skill_supports("bolt") == ["focus", "volley"], "Schema10 explicitly accepts equipped schema9 local weapon and legacy supports")
	_expect(state.migration_message.contains("贯穿") and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(backup), "Load preserves original literal bytes and defers backup until overwrite")
	_expect(state.save_build("user://pierce_save_as.json") == OK and FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(backup), "Save-as does not consume pending source-byte protection")
	_expect(state.save_build(ProjectSettings.globalize_path(path)) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Absolute path alias makes byte-exact literal v9 backup before v10 overwrite")
	_expect(state.add_skill_support("frost", "pierce") and state.save_build(path) == OK, "Migrated model accepts and saves new pierce with existing frost volley")
	var reloaded = Model.new()
	_expect(reloaded.load_build(path) and not reloaded.migrated_from_v9 and reloaded._snapshot() == state._snapshot(), "Current v10 roundtrip preserves new support plus old equipment vocabulary")
	_expect(reloaded.save_build(path) == OK and FileAccess.get_file_as_bytes(backup) == bytes, "Later writes preserve the original historical backup")
	var conflict_path: String = "user://pierce_backup_conflict.json"
	_write(conflict_path, bytes)
	_write(conflict_path + ".v9-backup.json", JSON.stringify(legacy).to_utf8_buffer())
	var conflict = Model.new()
	_expect(conflict.load_build(conflict_path) and conflict.save_build(conflict_path) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(conflict_path) == bytes, "Differently encoded backup conflict fails closed without overwriting source")
	var stale_path: String = "user://pierce_stale_v9.json"
	_write(stale_path, bytes)
	var stale = Model.new()
	_expect(stale.load_build(stale_path), "Literal stale-source fixture loads")
	var rewritten: PackedByteArray = JSON.stringify(legacy).to_utf8_buffer()
	_write(stale_path, rewritten)
	_expect(stale.save_build(stale_path) == ERR_FILE_ALREADY_IN_USE and FileAccess.get_file_as_bytes(stale_path) == rewritten and not FileAccess.file_exists(stale_path + ".v9-backup.json"), "Externally rewritten legacy bytes refuse migration overwrite")
	completed = true


func _expected_literal_v10(legacy: Dictionary) -> Dictionary:
	# JSON parses numbers as floats; schema integer fields are canonically ints.
	# Preserve every authored value/field/order, independent of model validation.
	var expected: Dictionary = legacy.duplicate(true)
	expected.version = Model.SAVE_VERSION
	expected.crafting = {"materials":{"calibration_shard":0},"revision":0}
	for key: String in ["next_equipment_id", "level", "xp", "talent_points", "next_jewel_id"]:
		expected[key] = int(expected[key])
	for item: Dictionary in expected.equipment_instances.values():
		item.item_level = int(item.item_level)
		for affix: Dictionary in item.affixes:
			affix.tier = int(affix.tier)
			affix.value = int(affix.value)
	for key: String in expected.backpack_positions:
		var position: Array = expected.backpack_positions[key]
		expected.backpack_positions[key] = [int(position[0]), int(position[1])]
	return expected


func _historical_control(version: int) -> Dictionary:
	# Authored historical record, never a current Model._snapshot() relabelled old.
	var result: Dictionary = {"version": version, "inventory": ["ember_wand", "guardian_robe", "azure_charm"],
		"equipped": {"weapon": "ember_wand", "armor": "guardian_robe", "charm": "azure_charm"},
		"equipment_instances": {}, "next_equipment_id": 1, "skill_slots": ["bolt", "frost", "nova", "dash", "ward"],
		"skill_supports": {"bolt": ["focus"]}, "level": 1, "xp": 0, "talent_points": 5,
		"allocated_nodes": ["origin"], "jewels": {}, "jewel_inventory": [], "socketed_jewels": {},
		"next_jewel_id": 1, "backpack_positions": {}}
	if version < 5:
		result.erase("skill_supports")
	if version < 4:
		result.erase("equipment_instances")
		result.erase("next_equipment_id")
	if version == 1:
		for key: String in ["allocated_nodes", "jewels", "jewel_inventory", "socketed_jewels", "next_jewel_id", "backpack_positions"]:
			result.erase(key)
		result.talents = {}
	return result


func _version_fences() -> void:
	for version: int in range(1, 10):
		var control: Dictionary = _historical_control(version)
		var control_path: String = "user://pierce_control_v%d.json" % version
		_write(control_path, JSON.stringify(control).to_utf8_buffer())
		var state = Model.new()
		_expect(state.load_build(control_path), "Independent unmodified historical control is valid: v%d" % version)
		var before: Dictionary = state._snapshot()
		var invalid: Dictionary = control.duplicate(true)
		invalid.skill_supports = {"bolt": ["pierce"]}
		var bytes: PackedByteArray = JSON.stringify(invalid).to_utf8_buffer()
		var path: String = "user://pierce_injected_v%d.json" % version
		_write(path, bytes)
		_expect(not state.load_build(path) and state._snapshot() == before, "Old-version pierce injection rejects atomically, v%d" % version)
		_expect(not Registry.saved_links_reason("bolt", ["pierce"], version).is_empty(), "Unified version fence rejects extension identity for old schema")
		_expect(not state.save_block_reason(path).is_empty() and state.save_build(ProjectSettings.globalize_path(path)) == ERR_INVALID_DATA, "Rejected source blocks subsequent writes through absolute path alias")
		_expect(FileAccess.get_file_as_bytes(path) == bytes and not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".v%d-backup.json" % version), "Rejected old save keeps exact bytes and creates no temporary replacement or migration backup")
	var future: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(V9))
	future.version = Model.SAVE_VERSION + 1
	var future_path: String = "user://pierce_future_v11.json"
	var future_bytes: PackedByteArray = JSON.stringify(future).to_utf8_buffer()
	_write(future_path, future_bytes)
	var fresh = Model.new()
	var before: Dictionary = fresh._snapshot()
	_expect(not fresh.load_build(future_path) and fresh._snapshot() == before and fresh.save_build(future_path) == ERR_INVALID_DATA and FileAccess.get_file_as_bytes(future_path) == future_bytes, "Schema10 equipment mapping never permits unknown future save version")
	completed = true


func _scene_migration() -> void:
	arena.queue_free()
	await process_frame
	var literal: String = FileAccess.get_file_as_string(V9)
	var original: PackedByteArray = PackedByteArray([239, 187, 191])
	original.append_array(("\r\n  " + literal.replace("\n", "\r\n") + "\r\n\r\n").to_utf8_buffer())
	_write("user://build_save.json", original)
	_start_scene()
	var expected: Dictionary = _expected_literal_v10(JSON.parse_string(literal))
	_expect(arena.state.migrated_from_v9 and arena.state._snapshot() == expected, "Actual scene startup reads BOM/CRLF literal v9 and retains complete build")
	_expect(arena.hud.is_blocking() and arena.hud.find_child("SkillSupportPanel", true, false) != null, "V9 startup opens the real K support editor")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json") == original and not FileAccess.file_exists("user://build_save.json.v9-backup.json"), "Startup alone leaves original BOM/CRLF bytes untouched")
	_expect(arena.state.add_skill_support("frost", "pierce"), "Actual migrated scene transaction adds eligible new support")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json.v9-backup.json") == original, "First actual scene autosave preserves byte-exact original encoding")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://build_save.json"))
	_expect(saved.version == Model.SAVE_VERSION and FileAccess.get_file_as_bytes("user://build_save.json") == JSON.stringify(arena.state._snapshot(), "\t", true, true).to_utf8_buffer(), "Actual scene autosave writes byte-exact complete current schema including equipment vocabulary9")
	var reload = Model.new()
	_expect(reload.load_build() and not reload.migrated_from_v9 and reload.get_skill_supports("frost") == ["pierce", "volley"] and reload._snapshot() == arena.state._snapshot(), "Actual scene save reloads v10 without remigration or loss")
	completed = true
