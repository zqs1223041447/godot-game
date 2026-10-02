extends SceneTree
## v0.11 real scene contracts. Run only with disposable XDG data/config/cache.
## Formula overrides are explicit; encounter gear and contact tests use real rolls.
const Model = preload("res://scripts/build_state.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const BatchFixture = preload("res://tests/fixtures/progress_batch_fixture.gd")
const FRESH_PATH: String = "user://fire_integration_fresh.json"
const GEAR_PATH: String = "user://fire_integration_equipped.json"

class FixtureState extends "res://scripts/build_state.gd":
	var stat_overrides: Dictionary = {}
	func get_stats() -> Dictionary:
		var result: Dictionary = super.get_stats()
		result.merge(stat_overrides, true)
		return result

var arena: Node
var checks: int = 0
var failures: int = 0
var finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fresh = Model.new()
	_expect(fresh.save_build() == OK and fresh.save_build(FRESH_PATH) == OK, "Fresh fixtures use isolated user storage")
	_create_arena()
	_case(_test_incoming_order_and_atomicity, "typed order, strict rejection and bounded traces")
	_case(_test_player_lifecycle, "invulnerability, pause, recharge and death persistence")
	_case(_test_natural_cadence, "natural admission policy and full-cap RNG")
	_case(_test_queue_priority, "pending offspring retain admission priority")
	_case(_test_real_gear_and_contacts, "natural reward equipment, contacts, unequip and reload")
	_case(_test_outgoing_casts, "actual mixed casts settle the same preview packets")
	_case(_test_reward_once_and_batching, "one defense reward and v0.10 public cast batching")
	_case(_test_reward_exclusions_and_capacity, "descendants, demos and full inventory")
	_case(_test_v7_scene_migration, "scene migration and byte-exact first autosave backup")
	if is_instance_valid(arena):
		arena.free()
	print("Fire defense integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _create_arena() -> void:
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = FixtureState.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)


func _case(test: Callable, label: String) -> void:
	finished = false
	test.call()
	_expect(finished, "Case completes without a script exception: " + label)


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) < 0.0001,
		"%s (actual %.8f, expected %.8f)" % [label, actual, expected])


func _points(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for type: String in Damage.TYPES:
		_near(float(actual.get(type, 0.0)), float(expected.get(type, 0.0)), label + "/" + type)


func _reset() -> void:
	arena.state.stat_overrides.clear()
	arena.use_progress_batching = true
	_expect(arena.state.load_build(FRESH_PATH), "Fresh model loads through existing scene connection")
	arena.restart_run()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 1100311
	arena._autosave_timer = 0.0


func _stats(overrides: Dictionary) -> void:
	arena.state.stat_overrides = overrides.duplicate(true)
	arena.state.changed.emit()


func _player_ready(health: float = 100.0, shield: float = 0.0) -> void:
	arena.health = health
	arena.shield = shield
	arena.invulnerable = 0.0


func _incoming_observation() -> Dictionary:
	return {"health": arena.health, "shield": arena.shield, "mana": arena.mana, "alive": arena.alive,
		"invulnerable": arena.invulnerable, "damage_delay": arena.damage_delay, "hurt_flash": arena.hurt_flash,
		"screen_shake": arena.screen_shake, "rng": arena.rng.state,
		"incoming": arena.incoming_damage_trace.duplicate(true), "outgoing": arena.damage_trace.duplicate(true),
		"text": arena.floating_text.duplicate(true), "particles": arena.particles.duplicate(true),
		"save_attempts": arena.progress_save_attempt_count}


func _enemy(template: String = "crawler", position: Vector2 = Vector2(600, 300)) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster(template, position)
	if not enemy.is_empty():
		enemy.spawn = 0.0
	return enemy


func _natural_guard() -> Dictionary:
	arena.wave = 3
	var guard: Dictionary = {}
	for index: int in range(8):
		var enemy: Dictionary = arena._spawn_enemy()
		if enemy.get("template_id", "") == "ember_guard":
			guard = enemy
			break
	_expect(not guard.is_empty(), "Natural successful admissions reach an ember guard within eight spawns")
	if not guard.is_empty():
		guard.spawn = 0.0
		guard.pos = Vector2(600, 300)
		arena.enemies.clear()
		arena.enemies.append(guard)
	return guard


func _kill(enemy: Dictionary) -> void:
	arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 1.0, Color.WHITE)


func _loot() -> Dictionary:
	return {"instances": arena.state.equipment_instances.duplicate(true), "next_id": arena.state.next_equipment_id,
		"inventory": arena.state.inventory.duplicate(), "jewels": arena.state.jewels.duplicate(true),
		"next_jewel_id": arena.state.next_jewel_id, "positions": arena.state.backpack_positions.duplicate(true)}


func _saved_matches() -> bool:
	return FileAccess.get_file_as_bytes("user://build_save.json") == JSON.stringify(arena.state._snapshot(), "\t", true, true).to_utf8_buffer()


func _test_incoming_order_and_atomicity() -> void:
	_reset()
	_stats({"fire_resistance": 0.25})
	_player_ready(100.0, 10.0)
	var hit: Dictionary = {"physical": 20.0, "fire": 20.0}
	_expect(arena.hit_player_components(hit, 731), "Typed mixed hit enters live settlement")
	_near(arena.shield, 0.0, "Resistance applies before spending ten shield")
	_near(arena.health, 75.0, "20 physical plus 20 fire at 25 percent loses exactly 25 life after shield")
	var record: Dictionary = arena.incoming_damage_trace.back()
	_points(record.raw_components, hit, "Trace stores original mixed hit")
	_points(record.components, {"physical": 20.0, "fire": 15.0}, "Trace stores independently mitigated types")
	_points(record.mitigated_components, {"fire": 5.0}, "Only fire mitigation is attributed")
	_near(record.damage_total, 35.0, "Post-mitigation total is 35")
	_near(record.shield_spent, 10.0, "Trace agrees with shield mutation")
	_near(record.health_lost, 25.0, "Trace agrees with health mutation")
	_expect(record.source_id == 731 and hit == {"physical": 20.0, "fire": 20.0}, "Source identity retained and caller hit unchanged")
	for raw: float in [0.95, -0.25]:
		_stats({"fire_resistance": raw})
		_player_ready()
		var effective: float = 0.75 if raw > 0.0 else 0.0
		var profile: Dictionary = arena.player_defense_profile()
		_near(profile.raw_resistances.fire, raw, "Live profile preserves uncapped source")
		_near(profile.effective_resistances.fire, effective, "Live profile clamps only effective resistance")
		_expect(arena.hit_player_components({"fire": 40.0}), "Finite cap-boundary hit accepted")
		_near(arena.health, 100.0 - 40.0 * (1.0 - effective), "Effective cap governs actual resource loss")
	_stats({"fire_resistance": 0.25})
	_player_ready(100.0, 10.0)
	var before: Dictionary = _incoming_observation()
	var invalid: Array = [null, true, 40.0, [], {"poison": 10.0}, {7: 10.0}, {"fire": true},
		{"fire": "20"}, {"fire": -1.0}, {"physical": 20.0, "fire": NAN}, {"fire": INF},
		{"fire": -INF}, {"fire": 1.0e308, "physical": 1.0e308}, {}, {"fire": 0.0}]
	for input: Variant in invalid:
		_expect(not arena.hit_player_components(input, 991), "Malformed or zero typed hit rejects: " + str(input))
		_expect(_incoming_observation() == before, "Rejected typed hit is atomic, including timers, traces and RNG")
	for input: float in [-1.0, NAN, INF, 0.0]:
		arena.hit_player(input)
		_expect(_incoming_observation() == before, "Legacy invalid scalar remains an atomic no-op")
	arena.hit_player(20.0)
	_near(arena.health, 90.0, "Legacy scalar remains physical despite fire resistance")
	_points(arena.incoming_damage_trace.back().components, {"physical": 20.0}, "Legacy wrapper records physical provenance")
	for index: int in range(40):
		_player_ready()
		_expect(arena.hit_player_components({"fire": 1.0}, index + 1000), "Bounded-trace hit accepted")
	_expect(arena.incoming_damage_trace.size() == 32 and arena.incoming_damage_trace.front().source_id == 1008
		and arena.incoming_damage_trace.back().source_id == 1039, "Incoming trace retains exactly the newest 32 records")
	finished = true


func _test_player_lifecycle() -> void:
	_reset()
	_stats({"fire_resistance": 0.25})
	_player_ready(100.0, 20.0)
	_expect(arena.hit_player_components({"fire": 20.0}), "Initial hit starts normal hurt lifecycle")
	_near(arena.invulnerable, 0.32, "Typed hit retains invulnerability duration")
	_near(arena.damage_delay, 4.0, "Typed hit retains recharge delay")
	var before: Dictionary = _incoming_observation()
	_expect(not arena.hit_player_components({"fire": 20.0}), "Immediate repeated hit is invulnerable")
	_expect(_incoming_observation() == before, "Invulnerable hit changes no state")
	arena.hud.open_panel("pause")
	var elapsed: float = arena.elapsed
	arena._process(0.25)
	_expect(_incoming_observation() == before and arena.elapsed == elapsed, "Paused process freezes hit and recharge timers")
	arena.hud.close_panel()
	arena.tick(3.9)
	_near(arena.shield, 5.0, "Recharge does not start before the four-second boundary")
	arena.tick(0.2)
	_near(arena.shield, 5.0 + float(arena.get_stats().shield_regen) * 0.1, "Boundary-crossing recharge receives only time after delay")
	var splitter: Dictionary = _enemy("splitter")
	_kill(splitter)
	_expect(arena.monster_runtime.queue.size() == 3, "Real lineage is pending before owner death")
	arena.state.slot_skill(0, "tornado")
	arena.mana = 100.0
	_expect(arena.cast_skill(0) and not arena.projectiles.is_empty(), "Real cast exists before owner death")
	_player_ready(1.0, 0.0)
	var saves: int = arena.progress_save_attempt_count
	_expect(arena.hit_player_components({"fire": 100.0}), "Lethal typed hit settles")
	_expect(not arena.alive and arena.health == 0.0 and arena.monster_runtime.queue.is_empty()
		and arena.projectiles.is_empty(), "Typed death cancels projectiles and pending offspring")
	_expect(arena.progress_save_attempt_count == saves + 1 and _saved_matches(), "Typed death forces current build to disk once")
	before = _incoming_observation()
	_expect(not arena.hit_player_components({"physical": 1.0}) and _incoming_observation() == before, "Dead owner cannot receive another hit or save")
	arena.restart_run()
	_expect(arena.alive and arena.incoming_damage_trace.is_empty() and arena.ordinary_admissions == 3,
		"Restart clears hit history and resets natural count to three initial admissions")
	for enemy: Dictionary in arena.enemies:
		_expect(enemy.template_id != "ember_guard", "Restart starts with the original low-wave encounter pool")
	finished = true


func _test_natural_cadence() -> void:
	_reset()
	_expect(arena.ordinary_admissions == 3, "Initial ordinary admissions count even when scene fixtures clear enemies")
	arena.wave = 2
	for index: int in range(5):
		_expect(arena._spawn_enemy().template_id != "ember_guard", "No natural fire guard below wave three")
	_expect(arena.ordinary_admissions == 8, "Low-wave successful admissions advance the same counter")
	arena.wave = 3
	for admission: int in range(9, 25):
		var enemy: Dictionary = arena._spawn_enemy()
		_expect((enemy.template_id == "ember_guard") == (admission % 8 == 0), "Exact wave-three admission cadence: %d" % admission)
		_expect(arena.ordinary_admissions == admission, "Exactly one count for successful natural admission")
	var count: int = arena.ordinary_admissions
	for kind: int in range(3):
		var forced: Dictionary = arena._spawn_enemy(Vector2(650, 400), kind)
		_expect(forced.kind == kind and forced.rarity == "normal" and forced.template_id != "ember_guard",
			"Forced-kind fixture retains its original species")
	_expect(arena._spawn_enemy(Vector2(650, 400)).template_id != "ember_guard", "Forced position uses historical random pool")
	_expect(arena.ordinary_admissions == count, "Forced fixture admissions do not advance cadence")
	arena.demo_mode = true
	var demo: Dictionary = arena._spawn_enemy()
	_expect(not demo.reward_eligible and demo.template_id != "ember_guard" and arena.ordinary_admissions == count,
		"Demo admission does not enter reward eligibility or natural cadence")
	arena.demo_mode = false
	while arena.enemies.size() < arena.MAX_ENEMIES:
		arena._spawn_enemy(Vector2(700, 450), 0)
	var random_state: int = arena.rng.state
	var identity: int = arena.monster_runtime.next_id
	_expect(arena._spawn_enemy().is_empty(), "Natural admission fails at live enemy cap")
	_expect(arena.rng.state == random_state and arena.ordinary_admissions == count and arena.monster_runtime.next_id == identity,
		"Rejected full-cap spawn rolls no RNG and consumes neither admission nor monster identity")
	finished = true


func _test_queue_priority() -> void:
	_reset()
	arena.wave = 3
	while arena.ordinary_admissions < 7:
		arena._spawn_enemy()
	var splitter: Dictionary = _enemy("splitter")
	while arena.enemies.size() < arena.MAX_ENEMIES:
		arena._spawn_enemy(Vector2(750, 400), 0)
	_kill(splitter)
	var random_state: int = arena.rng.state
	arena.spawn_timer = 0.0
	arena._update_spawning(0.0)
	_expect(arena.enemies.size() == arena.MAX_ENEMIES and arena.monster_runtime.queue.size() == 2,
		"One freed slot admits the first queued child before natural spawning")
	_expect(arena.ordinary_admissions == 7 and arena.rng.state == random_state,
		"Pending descendants leave the eighth natural guard and RNG untouched")
	_expect(arena.enemies.back().generation == 1 and not arena.enemies.back().reward_eligible,
		"Priority admission remains a real rewardless descendant")
	finished = true


func _contact(enemy: Dictionary, expected_resistance: float) -> void:
	enemy.pos = arena.player_pos
	enemy.spawn = 0.0
	enemy.attack_timer = 0.0
	_player_ready(100.0, 10.0)
	var traces: int = arena.incoming_damage_trace.size()
	arena._update_enemies(0.0)
	_expect(arena.incoming_damage_trace.size() == traces + 1, "Actual overlapping catalog monster delivers one contact hit")
	var hit: Dictionary = arena.incoming_damage_trace.back()
	var raw: float = float(enemy.damage)
	_points(hit.raw_components, {"physical": raw * 0.5, "fire": raw * 0.5}, "Actual guard contact retains native damage split")
	_near(hit.damage_total, raw * (1.0 - expected_resistance * 0.5), "Actual contact mitigates only the fire half")
	_near(arena.health, 110.0 - float(hit.damage_total), "Contact applies resistance before shield and health")
	_expect(hit.source_id == enemy.id, "Real collision retains monster source identity")
	_near(enemy.attack_timer, 1.0 / float(enemy.attack_speed), "Fire contact retains original attack cadence")


func _test_real_gear_and_contacts() -> void:
	_reset()
	var guard: Dictionary = _natural_guard()
	_expect(guard.kind == 2 and guard.rarity == "rare" and guard.defense_stats == {"fire_resistance": 0.25}
		and guard.resistances == {"fire": 0.25}, "Natural guard carries authored rare brute identity and derived fire defense")
	_near(guard.max_health, 95.0 * 1.32 * 2.5, "Guard retains native wave-three rare brute life")
	_near(guard.speed, 43.0 + 3.0 * 1.4, "Guard retains native brute speed")
	_near(guard.radius, 22.0, "Guard retains native brute contact radius")
	_kill(guard)
	_expect(arena.state.equipment_instances.size() == 1, "Natural off-cadence guard death gives exactly one equipment item")
	var id: String = "gear_%06d" % (arena.state.next_equipment_id - 1)
	var item: Dictionary = arena.state.equipment_instances[id].duplicate(true)
	_expect(item.base_id == "emberhide_vest" and item.rarity == "rare" and item.item_level == 5
		and Equipment.validate_instance(item), "Natural reward is a valid rare level-five defense roll")
	_expect(arena.state.equip(id), "Natural reward equips through actual inventory/model path")
	var resistance: float = float(Equipment.get_stats(item).fire_resistance)
	_near(arena.player_defense_profile().raw_resistances.fire, resistance, "Real equipped base and suffix reach cached player defense")
	_expect(arena.state.save_build(GEAR_PATH) == OK and _saved_matches(), "Equipped defense roll persists through scene autosave")
	arena.enemies.clear()
	var contact_guard: Dictionary = _enemy("ember_guard")
	_contact(contact_guard, resistance)
	_expect(arena.state.unequip("armor"), "Real armor unequips")
	_near(arena.player_defense_profile().effective_resistances.fire, 0.0, "Unequipping immediately removes defense")
	_contact(contact_guard, 0.0)
	_expect(arena.state.load_build(GEAR_PATH), "Saved defense roll reloads through existing live state connection")
	_expect(arena.state.equipment_instances[id] == item and arena.state.equipped.armor == id,
		"Reload retains exact item roll, identity and equipped slot")
	_near(arena.player_defense_profile().effective_resistances.fire, resistance, "Reload restores effective defense immediately")
	_contact(contact_guard, resistance)
	arena.enemies.clear()
	var physical: Dictionary = _enemy("crawler", arena.player_pos)
	physical.attack_timer = 0.0
	_player_ready()
	arena._update_enemies(0.0)
	_points(arena.incoming_damage_trace.back().components, {"physical": physical.damage}, "Original crawler contact stays pure physical with new armor")
	_near(arena.health, 100.0 - float(physical.damage), "Fire armor does not reduce old physical monsters")
	finished = true


func _test_outgoing_casts() -> void:
	_reset()
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	_stats({"damage": 40.0, "spell_added_cold": 10.0, "fire_increased": 0.2, "cold_increased": 0.6})
	arena.wave = 3
	var guard: Dictionary = _enemy("ember_guard")
	guard.shield = 10.0 # Isolate shield settlement; HP, resistance and cast stay real.
	var initial_health: float = guard.health
	arena.state.slot_skill(0, "meteor")
	arena.mana = 100.0
	var compiled: Dictionary = arena.state.get_skill_cast("meteor")
	var packet: Dictionary = compiled.packets.direct
	var preview: Dictionary = Damage.resolve(Preview.entries(compiled)[0].packet, compiled.snapshot.modifiers)
	_points(preview.components, {"fire": 206.4, "cold": 68.8}, "Preview preserves distinct fire and cold increases")
	_expect(Preview.entries(compiled)[0].packet == packet, "Preview reads the exact compiled cast packet")
	_expect(arena.cast_skill(0), "Real mixed meteor cast succeeds")
	_expect(arena.damage_trace.size() == 1, "Real meteor produces one isolated guard hit")
	var record: Dictionary = arena.damage_trace.back()
	_points(record.before_defense_components, preview.components, "Actual trace starts from displayed pre-defense components")
	_points(record.components, {"fire": 154.8, "cold": 68.8}, "Guard mitigates only fire by its actual 25 percent")
	_points(record.prevented_components, {"fire": 51.6}, "Outgoing trace attributes prevented fire once")
	_near(record.total, 223.6, "Mixed components sum after a single resistance pass")
	_near(record.shield_spent, 10.0, "Outgoing shared settlement consumes shield first")
	_near(record.health_lost, 213.6, "Outgoing trace reports actual life loss after shield")
	_near(initial_health - float(guard.health), 213.6, "Live health agrees with outgoing trace")
	_expect(record.assembly == packet.assembly and record.skill_id == "meteor", "Actual damage retains preview assembly provenance")
	_near(arena.mana, 100.0 - float(compiled.mana), "Defense changes no compiled payment")
	guard.shield = 0.0
	var before: float = guard.health
	arena._damage_enemy(guard, 10.0, Color.WHITE)
	_near(before - float(guard.health), 10.0, "Legacy already-resolved helper does not apply enemy resistance again")
	finished = true


func _test_reward_once_and_batching() -> void:
	var reference: Dictionary = {}
	for batching: bool in [false, true]:
		_reset()
		arena.use_progress_batching = batching
		_stats({"damage": 1000.0})
		var guard: Dictionary = _natural_guard()
		var stale: Dictionary = guard.duplicate(true)
		arena.enemies.append(guard)
		arena.reward_kills = 7
		arena.state.slot_skill(0, "meteor")
		arena.mana = 100.0
		arena.progress_save_attempt_count = 0
		arena.progress_hud_refresh_count = 0
		arena.progress_save_success_count = 0
		_expect(arena.cast_skill(0), "Public cast kills actual naturally admitted guard")
		_expect(arena.kills == 1 and arena.reward_kills == 8 and arena.state.equipment_instances.size() == 1,
			"Rare fire guard on eighth-kill overlap grants one item despite duplicate world entry")
		_expect(arena.state.equipment_instances.gear_000001.base_id == "emberhide_vest"
			and arena.state.equipment_instances.gear_000001.rarity == "rare", "Overlap selects the explicit defense pool once")
		_expect(_saved_matches() and not arena._progress_save_dirty and arena._progress_transaction_depth == 0,
			"Public reward cast returns with exact latest bytes and balanced transaction")
		var snapshot: Dictionary = {"model": arena.state._snapshot(), "rng": arena.rng.state,
			"saved": FileAccess.get_file_as_bytes("user://build_save.json"), "pickups": arena.pickups.duplicate(true)}
		if batching:
			_expect(snapshot == reference, "Fire reward preserves complete model, RNG, pickups and saved-byte equivalence across batching modes")
			_expect(arena.progress_save_attempt_count == 1 and arena.progress_save_success_count == 1
				and arena.progress_hud_refresh_count == 1, "XP and defense loot coalesce into one successful save and HUD refresh")
		else:
			reference = snapshot
			_expect(arena.progress_save_attempt_count == 2 and arena.progress_hud_refresh_count == 2,
				"Historical mode still observes separate XP and equipment signals")
		var loot: Dictionary = _loot()
		var xp: int = arena.state.xp
		_kill(guard)
		_kill(stale)
		_expect(_loot() == loot and arena.state.xp == xp and arena.kills == 1 and arena.reward_kills == 8,
			"Repeated corpse and detached copied identity cannot replay fire rewards")
	finished = true


func _test_reward_exclusions_and_capacity() -> void:
	_reset()
	var templates: Dictionary = Monsters.TEMPLATES.duplicate(true)
	templates.splitter.death_spawns = [{"template": "ember_guard", "count": 1}]
	arena.monster_runtime = Runtime.new(templates)
	_kill(_enemy("splitter"))
	arena._flush_monster_spawns()
	_expect(arena.enemies.size() == 1 and arena.enemies[0].template_id == "ember_guard"
		and not arena.enemies[0].reward_eligible, "Valid test lineage creates an actual rare defense-pool descendant")
	var before: Dictionary = _loot()
	var rewards: int = arena.reward_kills
	_kill(arena.enemies[0])
	_expect(_loot() == before and arena.reward_kills == rewards, "Even a rare defense-pool descendant cannot award equipment")
	arena.monster_runtime = Runtime.new()
	arena.start_monster_demo()
	var count: int = arena.ordinary_admissions
	var demo_guard: Dictionary = arena._spawn_monster("ember_guard", Vector2(600, 300), "demo")
	before = _loot()
	_kill(demo_guard)
	_expect(_loot() == before and arena.reward_kills == 0 and arena.ordinary_admissions == count,
		"Actual demo guard death grants no loot and changes no ordinary admission progress")
	_reset()
	var full: Dictionary = BatchFixture.full_backpack()
	_expect(not arena.state._validate_snapshot(full).is_empty(), "Full inventory fixture is valid current save data")
	_expect(BatchFixture.write_bytes("user://fire_full.json", JSON.stringify(full).to_utf8_buffer())
		and arena.state.load_build("user://fire_full.json"), "Full inventory loads using normal guarded model path")
	var guard: Dictionary = _natural_guard()
	var stale: Dictionary = guard.duplicate(true)
	arena.reward_kills = 7
	before = _loot()
	_kill(guard)
	_expect(arena.reward_kills == 8 and _loot() == before, "Full inventory keeps every item, position and serial when rare/eighth defense reward fails")
	_expect(arena.state.discard_equipment("gear_000002"), "Existing recoverable generated item can free space in test fixture")
	before = _loot()
	_kill(stale)
	_expect(_loot() == before and arena.reward_kills == 8, "Freeing space cannot revive a rejected corpse reward")
	finished = true


func _test_v7_scene_migration() -> void:
	arena.free()
	arena = null
	var old: Dictionary = Model.new()._snapshot()
	old.version = 7
	old.erase("crafting")
	var original: PackedByteArray = ("\n  " + JSON.stringify(old, "  ", false, true) + "\n\n").to_utf8_buffer()
	_expect(BatchFixture.write_bytes("user://build_save.json", original), "Version-seven source writes only in isolated user storage")
	_create_arena()
	_expect(arena.state.migrated_from_v7 and arena.state.save_block_reason().is_empty(), "Actual startup accepts valid version-seven source")
	_expect(arena.hud.is_blocking() and arena.hud._active_panel == "inventory", "Migration opens inventory explanation before gameplay")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json") == original
		and not FileAccess.file_exists("user://build_save.json.v7-backup.json"), "Startup has not overwritten or prematurely backed up legacy bytes")
	var canonical: Dictionary = arena.state._snapshot()
	canonical.version = 7
	canonical.erase("crafting")
	_expect(canonical == old, "Scene load preserves every legacy owned item, roll, placement and build field")
	_expect(arena.state.equip("swift_blade"), "First real inventory edit triggers migrated autosave")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json.v7-backup.json") == original,
		"First scene autosave retains byte-exact whitespace and ordering in v7 backup")
	_expect(_saved_matches() and JSON.parse_string(FileAccess.get_file_as_string("user://build_save.json")).version == Model.SAVE_VERSION,
		"First scene autosave commits the current version-eight build")
	var reloaded = Model.new()
	_expect(reloaded.load_build() and reloaded._snapshot() == arena.state._snapshot(), "Version-eight autosave reloads exactly through normal validation")
	_expect(FileAccess.get_file_as_bytes("user://build_save.json.v7-backup.json") == original, "Normal reload preserves the original backup")
	finished = true
