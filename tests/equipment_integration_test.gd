extends SceneTree
## Actual scene transactions and damage delivery. Use disposable XDG roots only.
const Model = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const FRESH_PATH: String = "user://equipment_integration_fresh.json"
var arena: Node
var checks: int = 0
var failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fresh = Model.new()
	_expect(fresh.save_build() == OK and fresh.save_build(FRESH_PATH) == OK, "Scene fixtures save in disposable user directory")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_case(_test_root_loot, "real root rarity and eighth-kill drops")
	_case(_test_no_child_demo_cancel_loot, "descendant/demo/cancellation exclusion")
	_case(_test_full_loot_and_flight_snapshot, "full inventory and generated cast snapshot")
	_case(_test_damage_scopes, "actual skill and secondary event scopes")
	_case(_test_rates_and_caps, "live percentage rates and resource caps")
	_case(_test_projectile_volley_capacity, "whole skill volley admission")
	print("Equipment integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Scene case completes without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.0001, "%s (actual %.6f, expected %.6f)" % [label, value, expected])


func _reset() -> void:
	_expect(arena.state.load_build(FRESH_PATH), "Fresh known state restores without replacing live signal connections")
	arena.restart_run()
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 300)
	arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 950501


func _enemy(template: String = "crawler", rarity: String = "normal", context: String = "ordinary") -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster(template, Vector2(600, 300), context, rarity, [])
	if not enemy.is_empty():
		enemy.spawn = 0.0
	return enemy


func _kill(enemy: Dictionary) -> void:
	arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 1.0, Color.WHITE)


func _loot() -> Dictionary:
	return {"instances": arena.state.equipment_instances.duplicate(true), "counter": arena.state.next_equipment_id,
		"inventory": arena.state.inventory.duplicate()}


func _latest() -> Dictionary:
	return arena.state.equipment_instances["gear_%06d" % (arena.state.next_equipment_id - 1)]


func _install(affixes: Array, base_id: String = "wayglass_token") -> String:
	var id: String = "gear_%06d" % arena.state.next_equipment_id
	var instance: Dictionary = {"id": id, "base_id": base_id, "rarity": "normal" if affixes.is_empty() else "magic", "item_level": 1, "affixes": affixes.duplicate(true)}
	_expect(Catalog.validate_instance(instance), "Equipped scene fixture obeys the real catalog")
	arena.state.equipment_instances[id] = instance
	arena.state.inventory.append(id)
	arena.state.next_equipment_id += 1
	arena.state._sync_backpack()
	_expect(arena.state.equip(id), "Generated instance reaches real build-change and autosave path")
	return id


func _test_root_loot() -> void:
	_reset()
	for index: int in range(7):
		_kill(_enemy())
		arena._flush_monster_spawns()
	_expect(arena.reward_kills == 7 and arena.state.equipment_instances.is_empty(), "Seven eligible normal roots do not grant an early equipment drop")
	var eighth: Dictionary = _enemy()
	var stale: Dictionary = eighth.duplicate(true)
	arena.enemies.append(eighth)
	_kill(eighth)
	_expect(arena.reward_kills == 8 and arena.kills == 8 and arena.state.equipment_instances.size() == 1, "Eighth root grants exactly one item despite duplicate world reference")
	_expect(_latest().item_level == 1 and Catalog.validate_instance(_latest()), "Wave-one drop is a valid level-one rolled record")
	var before: Dictionary = _loot()
	_kill(eighth)
	_kill(stale)
	_expect(_loot() == before and arena.reward_kills == 8, "Same corpse and detached stale corpse cannot replay equipment rewards")
	arena._flush_monster_spawns()
	arena.reward_kills = 15
	arena.wave = 5
	_kill(_enemy("brute", "rare"))
	_expect(arena.state.equipment_instances.size() == 2 and arena.reward_kills == 16, "Rare root on an eighth-kill boundary grants one item, not two")
	_expect(_latest().rarity == "rare" and _latest().item_level == 9, "Rare root forces rare gear at wave times two minus one")
	arena._flush_monster_spawns()
	arena.wave = 30
	var boss: Dictionary = _enemy("rift_warden", "", "level_boss")
	_expect(not boss.is_empty() and boss.rarity == "boss", "Loot test uses actual gated orange boss identity, not a synthetic rarity")
	_kill(boss)
	_expect(arena.state.equipment_instances.size() == 3 and _latest().rarity == "rare" and _latest().item_level == 30, "Real boss guarantees one rare drop off cadence and clamps level to thirty")
	arena._flush_monster_spawns()
	arena.wave = 1
	var low_wave_root: Dictionary = _enemy("brute", "rare")
	arena.wave = 0
	_kill(low_wave_root)
	_expect(arena.state.equipment_instances.size() == 4 and _latest().item_level == 1, "Low wave input clamps equipment level to one")
	var persisted = Model.new()
	_expect(persisted.load_build() and persisted.equipment_instances == arena.state.equipment_instances and persisted.next_equipment_id == arena.state.next_equipment_id, "Real loot auto-save preserves every roll and serial on disk")
	_finished = true


func _test_no_child_demo_cancel_loot() -> void:
	_reset()
	arena.reward_kills = 7
	var root_enemy: Dictionary = _enemy("splitter", "rare")
	_kill(root_enemy)
	_expect(arena.state.equipment_instances.size() == 1 and arena.monster_runtime.queue.size() == 3, "Rare root death grants one item and queues real descendants")
	arena._flush_monster_spawns()
	arena.reward_kills = 15
	var before: Dictionary = _loot()
	for child: Dictionary in arena.enemies.duplicate():
		_expect(child.generation == 1 and not child.reward_eligible, "Flushed descendant carries actual reward-ineligible lineage")
		child.rarity = "rare" # Eligibility must win even if a child has valuable rarity.
		_kill(child)
	arena._flush_monster_spawns()
	_expect(_loot() == before and arena.reward_kills == 15 and arena.enemies.is_empty(), "Rare-looking descendants never advance cadence or award equipment")
	arena.start_monster_demo()
	before = _loot()
	var depth: int = 0
	while not arena.enemies.is_empty() and depth < 5:
		for enemy: Dictionary in arena.enemies.duplicate():
			_kill(enemy)
		arena._flush_monster_spawns()
		depth += 1
	_expect(arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(), "Actual demonstration roots and multistage children all finish")
	_expect(_loot() == before and arena.reward_kills == 0, "Demonstration rare roots, boss and all descendants award no equipment")
	_reset()
	var split: Dictionary = _enemy("splitter", "normal")
	var stale: Dictionary = split.duplicate(true)
	_kill(split)
	before = _loot()
	arena.invulnerable = 0.0
	arena.shield = 0.0
	arena.health = 1.0
	arena.hit_player(2.0)
	arena._flush_monster_spawns()
	_expect(not arena.alive and arena.monster_runtime.queue.is_empty() and _loot() == before, "Player-death cancellation of pending descendants synthesizes no drops")
	arena.restart_run()
	_kill(stale)
	_expect(arena.reward_kills == 0 and _loot() == before, "Stale root from cancelled run cannot enter fresh reward accounting")
	_finished = true


func _target() -> Dictionary:
	arena.projectiles.clear()
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.damage_trace.clear()
	arena.event_counts.clear()
	arena.total_damage = 0.0
	var target: Dictionary = _enemy()
	target.radius = 0.0
	target.health = 100000.0
	target.max_health = 100000.0
	target.shield = 0.0
	target.resistances = {}
	target.speed = 0.0
	return target


func _skill_damage(skill: String) -> Dictionary:
	var target: Dictionary = _target()
	arena.state.slot_skill(0, skill)
	arena.cooldowns[skill] = 0.0
	arena.mana = arena.get_stats().max_mana
	_expect(arena.cast_skill(0), "Real skill cast succeeds: " + skill)
	if skill in ["bolt", "frost", "tornado"]:
		arena._update_projectiles(0.25)
	_expect(arena.damage_trace.size() == 1, "Isolated target receives exactly one center event: " + skill)
	return {"amount": 100000.0 - float(target.health), "record": arena.damage_trace[0] if not arena.damage_trace.is_empty() else {}}


func _explosion_damage() -> Dictionary:
	var target: Dictionary = _target()
	var snapshot: Dictionary = arena.state.get_combat_snapshot()
	snapshot.effects.append("explode_on_flight_end")
	arena.projectiles.append(arena.projectile_runtime.make_projectile(Vector2(500, 300), Vector2.RIGHT,
		{"speed": 100.0, "range": 1000.0, "lifetime": 1.0, "radius": 0.0, "pierce": -1, "role": "child"},
		Combat.tornado_packet(snapshot, "child"), snapshot, arena.projectile_runtime.new_cast(), Color.WHITE))
	arena._update_projectiles(1.0)
	_expect(arena.damage_trace.size() == 1 and arena.event_counts.get("explosion", 0) == 1 and arena.event_counts.get("hit", 0) == 0, "Endpoint creates one actual secondary explosion and no projectile hit")
	return {"amount": 100000.0 - float(target.health), "record": arena.damage_trace[0] if not arena.damage_trace.is_empty() else {}}


func _test_full_loot_and_flight_snapshot() -> void:
	_reset()
	# Reserve all 96 cells: original equipment 30, jewels 64, new charms 2.
	var jewel_template: Dictionary = arena.state.jewels["jewel_000001"].duplicate(true)
	for serial: int in range(4, 65):
		var id: String = "jewel_%06d" % serial
		var jewel: Dictionary = jewel_template.duplicate(true)
		jewel.id = id
		arena.state.jewels[id] = jewel
		arena.state.jewel_inventory.append(id)
	arena.state.next_jewel_id = 65
	_install([])
	_install([])
	_expect(not arena.state._validate_snapshot(arena.state._snapshot()).is_empty(), "Loot-full fixture reserves every owned item even while equipment is worn")
	arena.reward_kills = 7
	var root_enemy: Dictionary = _enemy("brute", "rare")
	var stale: Dictionary = root_enemy.duplicate(true)
	var before: Dictionary = _loot()
	_kill(root_enemy)
	_expect(arena.reward_kills == 8 and _loot() == before, "Full grid rejects actual rare/eighth-root loot without replacing records or consuming serial")
	arena.state.unequip("charm")
	arena.state.discard_equipment("gear_000002")
	before = _loot()
	_kill(stale)
	_expect(arena.reward_kills == 8 and _loot() == before, "Freeing space does not let a stale death replay its failed reward")
	_reset()
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	var id: String = _install([{"id": "runesong", "tier": 1, "value": 7}])
	var target: Dictionary = _target()
	arena.state.slot_skill(0, "bolt")
	arena.mana = 100.0
	_expect(arena.cast_skill(0), "Generated affix snapshot starts a real in-flight spell")
	var original: Dictionary = arena.projectiles[1].snapshot.duplicate(true)
	arena.state.unequip("charm")
	_expect(arena.state.discard_equipment(id), "In-flight source gear can be discarded after unequipping")
	_expect(arena.state.get_combat_snapshot().modifiers.is_empty(), "Live build no longer contains the discarded spell modifier")
	arena._update_projectiles(0.25)
	_near(100000.0 - float(target.health), 18.0 * 1.6 * 1.07, "Existing spell retains snapshotted generated affix after source item is discarded")
	_expect(arena.projectiles[0].snapshot == original, "Remaining carriers retain detached generated-item snapshot")
	_near(_skill_damage("bolt").amount, 18.0 * 1.6, "Later spell uses current build and cannot inherit discarded gear")
	_finished = true


func _test_damage_scopes() -> void:
	# Independent expected multipliers: spell lightning, spell cold, spell fire,
	# mixed physical/fire attack projectile, then secondary fire-only explosion.
	var cases: Dictionary = {
		"runesong": {"ticks": 7, "bolt": 1.07, "frost": 1.07, "meteor": 1.07, "tornado": 1.0, "explosion": 1.0},
		"prismedge": {"ticks": 7, "bolt": 1.0, "frost": 1.0, "meteor": 1.0, "tornado": 1.028, "explosion": 1.0},
		"farweave": {"ticks": 7, "bolt": 1.07, "frost": 1.07, "meteor": 1.0, "tornado": 1.07, "explosion": 1.0},
		"coalglow": {"ticks": 8, "bolt": 1.0, "frost": 1.0, "meteor": 1.08, "tornado": 1.032, "explosion": 1.08},
		"rimeecho": {"ticks": 8, "bolt": 1.0, "frost": 1.08, "meteor": 1.0, "tornado": 1.0, "explosion": 1.0},
		"sparkthread": {"ticks": 8, "bolt": 1.08, "frost": 1.0, "meteor": 1.0, "tornado": 1.0, "explosion": 1.0},
	}
	var coefficients: Dictionary = {"bolt": 1.6, "frost": 0.85, "meteor": 4.3, "tornado": 1.0}
	for family: String in cases:
		_reset()
		for slot: String in Model.EQUIPMENT_SLOTS:
			arena.state.unequip(slot)
		_install([{"id": family, "tier": 1, "value": int(cases[family].ticks)}])
		for skill: String in coefficients:
			var hit: Dictionary = _skill_damage(skill)
			_near(hit.amount, 18.0 * float(coefficients[skill]) * float(cases[family][skill]), "Affix only scales matching live damage components: " + family + "/" + skill)
			if not hit.record.is_empty():
				_expect(hit.record.tags.has("attack" if skill == "tornado" else "spell"), "Real emitted event carries correct attack/spell scope: " + skill)
		var explosion: Dictionary = _explosion_damage()
		_near(explosion.amount, 18.0 * 0.9 * float(cases[family].explosion), "Independent explosion applies only matching fire scope: " + family)
		if not explosion.record.is_empty():
			_expect(explosion.record.tags.has("secondary") and not explosion.record.tags.has("projectile") and not explosion.record.tags.has("spell") and not explosion.record.tags.has("attack"), "Secondary explosion never inherits the carrier's source tags")
	# Chain and nova travel through separate direct application paths.
	_reset()
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	_install([{"id": "runesong", "tier": 1, "value": 7}, {"id": "sparkthread", "tier": 1, "value": 8}])
	_near(_skill_damage("chain").amount, 18.0 * 2.2 * 1.15, "Direct lightning chain adds spell and lightning increases once")
	_near(_skill_damage("nova").amount, 18.0 * 2.7 * 1.15, "Area nova adds spell and lightning increases once")
	_finished = true


func _test_rates_and_caps() -> void:
	_reset()
	_install([{"id": "wellturn", "tier": 1, "value": 5}])
	var expected_regen: float = (9.0 + 1.0 + 0.3) * 1.05
	arena.mana = 0.0
	arena.tick(0.5)
	_near(arena.mana, expected_regen * 0.5, "Real tick consumes percent mana regeneration after all flat values")
	arena.mana = float(arena.get_stats().max_mana) - 0.1
	arena.tick(0.5)
	_near(arena.mana, arena.get_stats().max_mana, "Percent mana regeneration saturates at the actual equipped mana cap")
	_reset()
	arena.state.equip("swift_blade")
	_install([{"id": "beatlink", "tier": 1, "value": 3}])
	var target: Dictionary = _target()
	arena.auto_fire = true
	arena.attack_timer = 0.0
	arena._update_auto_attack()
	var interval: float = 1.0 / ((1.7 + 0.5) * 1.03)
	_near(arena.attack_timer, interval, "Actual auto-fire cadence uses base plus fixed flat attacks multiplied by gear percent")
	_expect(arena.projectiles.size() == 1, "Zero autoattack timer emits one basic attack")
	arena.tick(interval - 0.0001)
	_expect(arena.total_shots == 1, "No extra autoattack fires before modified interval")
	arena.tick(0.0002)
	_expect(arena.total_shots == 2 and float(target.health) < 100000.0, "Next attack fires after the modified frequency boundary and real first shot hit")
	arena.auto_fire = false
	arena.state.slot_skill(0, "bolt")
	arena.mana = 100.0
	arena.cooldowns.bolt = 0.0
	_expect(arena.cast_skill(0), "Attack-speed gear does not block manual spell")
	_near(arena.cooldowns.bolt, Data.SKILLS.bolt.cooldown, "Attack speed never shortens the spell's initial cooldown")
	arena.tick(0.1)
	_near(arena.cooldowns.bolt, float(Data.SKILLS.bolt.cooldown) - 0.1, "Attack speed does not accelerate spell cooldown recovery")
	_reset()
	arena.state.equip("swift_blade")
	_install([{"id": "trailstep", "tier": 1, "value": 2}], "pulse_seed")
	var origin: Vector2 = arena.player_pos
	Input.action_press("move_right")
	arena._move_player(0.25)
	Input.action_release("move_right")
	_near(arena.player_pos.x - origin.x, (240.0 + 20.0 + 3.0) * 1.02 * 0.25, "Movement executor uses percentage after all equipped flat movement")
	_reset()
	for slot: String in Model.EQUIPMENT_SLOTS:
		arena.state.unequip(slot)
	_install([{"id": "rootwell", "tier": 1, "value": 14}], "woven_bastion")
	_install([{"id": "deepwell", "tier": 1, "value": 9}])
	arena.restart_run()
	_near(arena.health, 120.0 + 12.0 + 14.0, "Spawn health consumes generated base and life affix")
	_near(arena.mana, 100.0 + 6.0 + 9.0, "Spawn mana consumes generated base and mana affix")
	_install([{"id": "lanternveil", "tier": 1, "value": 9}], "woven_bastion")
	arena.restart_run()
	_near(arena.shield, 60.0 + 5.0 + 9.0, "Spawn shield consumes generated base and global shield affix")
	arena.state.unequip("armor")
	_near(arena.shield, 60.0, "Unequipping generated shield gear clamps current live shield immediately")
	_finished = true


func _test_projectile_volley_capacity() -> void:
	for skill: String in ["bolt", "frost"]:
		var count: int = 3 if skill == "bolt" else 5
		for free_slots: int in [0, count - 1, count]:
			_reset()
			arena.state.slot_skill(0, skill)
			var snapshot: Dictionary = arena.state.get_combat_snapshot()
			for index: int in range(arena.MAX_PROJECTILES - free_slots):
				arena.projectiles.append(arena.projectile_runtime.make_projectile(Vector2(500, 300), Vector2.RIGHT,
					{"speed": 1.0, "range": 1000.0, "lifetime": 10.0, "radius": 0.0},
					Damage.packet({"physical": 1.0}, ["hit", "attack", "projectile"], "basic"), snapshot,
					arena.projectile_runtime.new_cast(), Color.WHITE))
			var before: Array = arena.projectiles.duplicate(true)
			arena.mana = 100.0
			arena.cooldowns[skill] = 0.0
			var accepted: bool = arena.cast_skill(0)
			if free_slots < count:
				_expect(not accepted and arena.projectiles == before and arena.total_shots == 0, "%s rejects whole volley with only %d free slots, preserving all existing carriers" % [skill, free_slots])
				_near(arena.mana, 100.0, "Rejected partial volley does not spend mana: " + skill)
				_near(arena.cooldowns[skill], 0.0, "Rejected partial volley does not start cooldown: " + skill)
			else:
				_expect(accepted and arena.projectiles.size() == arena.MAX_PROJECTILES and arena.total_shots == count, "Exact capacity accepts complete volley: " + skill)
				_near(arena.mana, 100.0 - float(Data.SKILLS[skill].mana), "Exact-fit volley charges mana exactly once: " + skill)
				_near(arena.cooldowns[skill], Data.SKILLS[skill].cooldown, "Exact-fit volley starts one normal cooldown: " + skill)
	_finished = true
