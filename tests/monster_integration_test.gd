extends SceneTree
## Real arena/HUD contracts for monster deaths, combat defenses, and safe demos.
## Always run under disposable XDG data/config/cache roots (tools/validate.sh).
const Model = preload("res://scripts/build_state.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
var checks: int = 0
var failures: int = 0
var arena: Node
var _suite_finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fresh = Model.new()
	_expect(fresh.save_build() == OK, "Fresh build saves inside disposable integration fixture")
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	_case(_test_root_rewards, "once-only root and rewardless child kills")
	_case(_test_aoe_deferred, "AoE queue deferral and birth protection")
	_case(_test_explosion_deferred, "projectile explosion keeps deferred children outside target iteration")
	_case(_test_live_defenses, "live shield absorb, regeneration and attack speed")
	_case(_test_capacity, "55-live cap, queue priority and FIFO")
	_case(_test_player_death_reset, "death cancellation and clean restart")
	_case(_test_panel_demo, "F7 pause, no-reward demo and standard restoration")
	print("Monster integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_suite_finished = false
	test.call()
	_expect(_suite_finished, "Scene suite reaches final assertion without a script exception: " + label)


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
	arena.monster_runtime.reset()
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(500, 420)
	arena.player_facing = Vector2.RIGHT


func _enemy(template: String, position: Vector2 = Vector2(700, 300), rarity: String = "", mechanisms: Array = []) -> Dictionary:
	var enemy: Dictionary = arena._spawn_monster(template, position, "ordinary", rarity, mechanisms)
	enemy.spawn = 0.0
	return enemy


func _kill(enemy: Dictionary) -> void:
	arena._damage_enemy(enemy, float(enemy.health) + float(enemy.shield) + 1.0, Color.WHITE)


func _progress() -> Dictionary:
	return {"xp": arena.state.xp, "level": arena.state.level, "talent_points": arena.state.talent_points,
		"jewels": arena.state.jewels.duplicate(true), "next_jewel_id": arena.state.next_jewel_id}


func _test_root_rewards() -> void:
	_reset()
	var root_enemy: Dictionary = _enemy("splitter")
	arena.enemies.append(root_enemy) # Same corpse appears in two world slots.
	var stale_copy: Dictionary = root_enemy.duplicate(true)
	var xp_before: int = arena.state.xp
	var jewels_before: int = arena.state.jewels.size()
	arena.reward_kills = 19
	_kill(root_enemy)
	_expect(arena.kills == 1 and arena.reward_kills == 20, "Root death advances each counter exactly once despite duplicate reference")
	_expect(arena.state.xp == xp_before + root_enemy.xp_reward, "Root awards its configured rarity XP once")
	_expect(arena.state.jewels.size() == jewels_before + 1 and arena.pickups.size() == 1, "Twentieth eligible kill grants one jewel and one four-kill supply")
	_expect(arena.monster_runtime.queue.size() == 3 and arena.enemies.size() == 2, "Damage callback queues descendants without inserting into active array")
	var after_root: Dictionary = _progress()
	_kill(root_enemy)
	_kill(stale_copy)
	_expect(arena.kills == 1 and arena.reward_kills == 20 and _progress() == after_root and arena.pickups.size() == 1, "Repeated and copied corpse identities cannot replay XP, kill or drop rewards")
	_expect(arena.monster_runtime.queue.size() == 3, "Repeated corpse cannot duplicate child requests")
	arena._flush_monster_spawns()
	_expect(arena.enemies.size() == 3 and arena.monster_runtime.queue.is_empty(), "Flush removes both corpse references and admits exact child group")
	for child: Dictionary in arena.enemies.duplicate():
		_expect(not child.reward_eligible and child.xp_reward == 0 and child.death_spawns.is_empty(), "Real scene child is rewardless and terminal")
		_kill(child)
	arena._flush_monster_spawns()
	_expect(arena.kills == 4 and arena.reward_kills == 20, "Children count as defeated but never advance reward-kill progress")
	_expect(_progress() == after_root and arena.pickups.size() == 1, "Descendant deaths add no XP, jewel or supply reward")
	_expect(arena.enemies.is_empty() and arena.monster_runtime.roots.is_empty(), "Terminal scene lineage is fully reclaimed")
	var legacy: Dictionary = arena._spawn_enemy(Vector2(600, 300), 2)
	_expect(legacy.kind == 2 and legacy.rarity == "normal" and legacy.mechanism_ids.is_empty(), "Legacy forced species fixture remains a plain original-species enemy")
	_suite_finished = true


func _test_aoe_deferred() -> void:
	_reset()
	var brood: Dictionary = _enemy("brood_host")
	var original_id: int = brood.id
	arena._area_damage(brood.pos, 120.0, Damage.packet({"lightning": 100000.0}, ["hit", "spell", "area"], "nova"), Color.WHITE, 0.0)
	_expect(brood.death_processed and arena.kills == 1 and arena.monster_runtime.queue.size() == 2, "One AoE kills brood and queues exactly two splitters")
	_expect(arena.enemies.size() == 1 and arena.damage_trace.size() == 1, "One AoE cannot synchronously recurse through a multistage death chain")
	arena._flush_monster_spawns()
	_expect(arena.enemies.size() == 2 and arena.monster_runtime.queue.is_empty(), "Post-AoE flush creates only the first descendant generation")
	var protected: Dictionary = {}
	for child: Dictionary in arena.enemies:
		protected[child.id] = {"health": child.health, "shield": child.shield}
		_expect(child.root_id == original_id and child.generation == 1 and child.spawn > 0.0, "Flushed splitter starts with birth protection and lineage")
	arena._area_damage(brood.pos, 120.0, Damage.packet({"lightning": 100000.0}, ["hit", "spell", "area"], "nova"), Color.WHITE, 0.0)
	var untouched: bool = true
	for child: Dictionary in arena.enemies:
		untouched = untouched and child.health == protected[child.id].health and child.shield == protected[child.id].shield
	_expect(untouched and arena.monster_runtime.queue.is_empty(), "An immediate later AoE respects new descendant birth protection")
	arena._update_enemies(0.59)
	_expect(arena.enemies[0].spawn > 0.0 and arena.enemies[1].spawn > 0.0, "Birth protection survives until the configured grace interval")
	arena._update_enemies(0.02)
	_expect(arena.enemies[0].spawn == 0.0 and arena.enemies[1].spawn == 0.0, "Actual monster update expires birth protection after grace interval")
	arena._area_damage(brood.pos, 120.0, Damage.packet({"lightning": 100000.0}, ["hit", "spell", "area"], "nova"), Color.WHITE, 0.0)
	_expect(arena.monster_runtime.queue.size() == 6 and arena.kills == 3 and arena.reward_kills == 1, "After protection two splitters die and queue six rewardless terminal grandchildren")
	arena._flush_monster_spawns()
	_expect(arena.enemies.size() == 6, "Multistage scene chain drains into six terminal grandchildren")
	_suite_finished = true


func _test_explosion_deferred() -> void:
	_reset()
	var target: Dictionary = _enemy("splitter", Vector2(600, 300))
	target.radius = 0.0 # Keep contact exactly on the exclusive lifetime endpoint.
	arena.enemies.append(target)
	var snapshot: Dictionary = Recipes.snapshot({"damage": 10000.0}, ["explode_on_flight_end"])
	var shot: Dictionary = arena.projectile_runtime.make_projectile(Vector2(500, 300), Vector2.RIGHT,
		{"speed": 100.0, "range": 1000.0, "lifetime": 1.0, "radius": 0.0, "pierce": -1, "role": "child"},
		Damage.packet({"fire": 10000.0}, ["hit", "projectile"], "tornado"), snapshot,
		arena.projectile_runtime.new_cast(), Color.WHITE)
	arena.projectiles.append(shot)
	arena._update_projectiles(1.0)
	_expect(arena.event_counts.get("explosion", 0) == 1 and arena.event_counts.get("hit", 0) == 0, "Lifetime endpoint explosion enters real v0.3 damage path without a direct hit")
	_expect(arena.kills == 1 and arena.reward_kills == 1 and arena.damage_trace.size() == 1, "Explosion deduplicates corpse references and settles one root death")
	_expect(arena.enemies.size() == 3 and arena.monster_runtime.queue.is_empty(), "Explosion flushes descendants only after all existing-target damage events")
	var untouched: bool = true
	for child: Dictionary in arena.enemies:
		untouched = untouched and child.health == child.max_health and child.spawn > 0.0
	_expect(untouched, "New children are full health and were never part of parent-killing explosion")
	arena._update_projectiles(10.0)
	_expect(arena.kills == 1 and arena.damage_trace.size() == 1, "Expired projectile cannot repeat a monster death or explosion")
	_suite_finished = true


func _test_live_defenses() -> void:
	_reset()
	var defended: Dictionary = _enemy("brute", Vector2(900, 250), "rare", ["aegis_capacity", "aegis_recovery"])
	var starting_health: float = defended.health
	var capacity: float = defended.max_shield
	var regen: float = defended.shield_regen
	_expect(capacity > 0.0 and regen > 0.0, "Shared shield mechanisms produce real monster defenses")
	arena._damage_enemy(defended, capacity * 0.5, Color.WHITE)
	_near(defended.health, starting_health, "Shield absorbs damage before health")
	_near(defended.shield, capacity * 0.5, "Shield consumes only incoming damage")
	arena._damage_enemy(defended, capacity * 0.5 + 5.0, Color.WHITE)
	_near(defended.shield, 0.0, "Overflow fully depletes shield")
	_near(defended.health, starting_health - 5.0, "Only unabsorbed remainder reaches health")
	_near(defended.damage_delay, 4.0, "Every hit restarts four-second recharge delay")
	arena._update_enemies(3.0)
	_near(defended.shield, 0.0, "Shield cannot regenerate during first three seconds")
	arena._update_enemies(1.5)
	_near(defended.shield, minf(capacity, regen * 0.5), "Large step regenerates only time beyond the four-second boundary")
	arena._update_enemies(100.0)
	_near(defended.shield, capacity, "Long recharge saturates safely at shield capacity")
	var health_before: float = defended.health
	var shield_before: float = defended.shield
	for amount: float in [0.0, -1.0, NAN, INF]:
		arena._damage_enemy(defended, amount, Color.WHITE)
	_near(defended.health, health_before, "Invalid damage cannot corrupt monster health")
	_near(defended.shield, shield_before, "Invalid damage cannot corrupt shield")
	_reset()
	var ordinary: Dictionary = _enemy("crawler", arena.player_pos)
	ordinary.attack_timer = 0.0
	ordinary.speed = 0.0
	arena._update_enemies(0.0)
	var base_interval: float = ordinary.attack_timer
	_near(base_interval, 1.0 / ordinary.attack_speed, "Original monster cadence uses reciprocal attacks per second")
	arena.enemies.clear()
	var fast: Dictionary = _enemy("crawler", arena.player_pos, "magic", ["gale_alacrity"])
	fast.attack_timer = 0.0
	fast.speed = 0.0
	arena._update_enemies(0.0)
	var bonus: Dictionary = Registry.resolve_grants(["gale_alacrity"], "monster")
	_near(fast.attack_speed, ordinary.attack_speed + bonus.stats.attack_speed, "Shared attack-speed bonus reaches monster runtime")
	_near(fast.attack_timer, 1.0 / fast.attack_speed, "Attack executor consumes modified speed")
	_expect(fast.attack_timer < base_interval, "Positive attack-speed mechanism shortens contact attack cooldown")
	_suite_finished = true


func _test_capacity() -> void:
	_reset()
	for index: int in range(arena.MAX_ENEMIES - 1):
		_enemy("crawler", Vector2(150 + index, 250))
	var splitter: Dictionary = _enemy("splitter")
	_expect(arena.enemies.size() == 55 and arena._spawn_monster("crawler").is_empty(), "Scene enforces hard 55-live admission cap")
	_kill(splitter)
	_expect(arena.monster_runtime.queue.size() == 3, "Full arena still reserves whole death group")
	arena.spawn_timer = 0.0
	arena._update_spawning(1.0)
	_expect(arena.enemies.size() == 55 and arena.monster_runtime.queue.size() == 2, "First vacancy admits one queued child and keeps remainder")
	var first_child: Dictionary = arena.enemies.back()
	_expect(first_child.parent_id == splitter.id and first_child.template_id == "crawler", "Pending child takes priority over ordinary spawn")
	for expected: String in ["crawler", "skitter"]:
		_kill(arena.enemies[0])
		arena._update_spawning(1.0)
		_expect(arena.enemies.size() == 55 and arena.enemies.back().template_id == expected and arena.enemies.back().parent_id == splitter.id, "Later live vacancy respects exact death FIFO order: " + expected)
	_expect(arena.monster_runtime.queue.is_empty(), "Pending group finishes as slots free without overshooting cap")
	for index: int in range(120):
		arena._update_spawning(100.0)
	_expect(arena.enemies.size() == 55, "Repeated large spawning deltas cannot exceed scene cap")
	_suite_finished = true


func _test_player_death_reset() -> void:
	_reset()
	var splitter: Dictionary = _enemy("splitter")
	_kill(splitter)
	_expect(arena.monster_runtime.queue.size() == 3, "Death-cancellation fixture has queued descendants")
	var old_id: int = splitter.id
	var kills_before: int = arena.kills
	var progress_before: Dictionary = _progress()
	arena.invulnerable = 0.0
	arena.shield = 0.0
	arena.health = 1.0
	arena.hit_player(2.0)
	_expect(not arena.alive and arena.monster_runtime.queue.is_empty(), "Player death clears every queued monster descendant")
	_expect(arena.monster_runtime.trace.back().reason == "player_death", "Player death cancellation records its specific cause")
	arena._flush_monster_spawns()
	_expect(arena.enemies.is_empty() and arena.kills == kills_before and _progress() == progress_before, "Dead-player flush cannot spawn children or award synthetic kills")
	arena.restart_run()
	_expect(arena.alive and not arena.demo_mode and arena.kills == 0 and arena.reward_kills == 0, "Restart restores regular living run and both kill counters")
	_expect(arena.monster_runtime.queue.is_empty() and arena.monster_runtime.trace.is_empty() and arena.damage_trace.is_empty(), "Restart clears pending work and monster/combat damage traces")
	_expect(arena.monster_runtime.roots.size() == arena.enemies.size() and not arena.monster_runtime.roots.has(old_id), "Restart keeps only fresh starting lineages and discards old root budget")
	var fresh: bool = true
	for enemy: Dictionary in arena.enemies:
		fresh = fresh and enemy.id > old_id and enemy.generation == 0 and enemy.reward_eligible
	_expect(fresh and arena.enemies.size() == 3, "Fresh initial enemies have newer identities and normal root rewards")
	_expect(not arena.hud.is_blocking(), "Restart dismisses blocking death panel")
	_suite_finished = true


func _press(name: String) -> void:
	var button: Button = arena.hud.find_child(name, true, false) as Button
	_expect(button != null, "Monster panel control exists: " + name)
	if button != null:
		button.pressed.emit()


func _test_panel_demo() -> void:
	_reset()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F7
	key.pressed = true
	arena._unhandled_key_input(key)
	_expect(arena.hud.is_blocking() and arena.hud._active_panel == "monsters", "F7 opens blocking monster inspector")
	var elapsed_before: float = arena.elapsed
	arena._process(10.0)
	_near(arena.elapsed, elapsed_before, "Monster inspector pauses simulation even with large frame delta")
	_expect(not arena.cast_skill(0), "Monster inspector prevents combat skill casts")
	var before: Dictionary = _progress()
	_press("StartMonsterDemo")
	_expect(arena.demo_mode and arena.enemies.size() == 6 and arena.hud._active_panel == "monsters", "Demo panel starts six controlled examples and stays inspectable")
	var rarities: Dictionary = {}
	var templates: Dictionary = {}
	var rewardless: bool = true
	for enemy: Dictionary in arena.enemies:
		rarities[enemy.rarity] = true
		templates[enemy.template_id] = true
		rewardless = rewardless and not enemy.reward_eligible
	_expect(rarities.size() == 4 and not rarities.has("reserved") and templates.has("splitter") and templates.has("brood_host") and templates.has("rift_warden"), "Demo includes ordinary trio, both death templates and explicit gated boss; no black monster")
	_expect(rewardless, "Every demonstration root is reward-ineligible")
	_press("TriggerMonsterSplit")
	_expect(arena.enemies.size() == 8 and arena.kills == 1 and arena.reward_kills == 0, "Demo button visibly produces exactly two A plus one B")
	_expect(_progress() == before and arena.pickups.is_empty(), "Demo split cannot change saved growth or drop supplies")
	_press("TriggerMonsterSplit")
	_expect(arena.enemies.size() == 11 and arena.kills == 2 and arena.reward_kills == 0, "Split demo can repeat after original splitter has disappeared")
	# Complete every remaining stage, including boss children, using explicit fixture kills.
	var generations: int = 0
	while not arena.enemies.is_empty() and generations < 5:
		for enemy: Dictionary in arena.enemies.duplicate():
			_kill(enemy)
		arena._flush_monster_spawns()
		generations += 1
	_expect(arena.enemies.is_empty() and arena.monster_runtime.queue.is_empty(), "Entire demo reaches terminal descendants in bounded stages")
	_expect(_progress() == before and arena.reward_kills == 0 and arena.pickups.is_empty(), "Killing all demo roots and descendants grants no growth, jewels or supplies")
	arena._update_spawning(100000.0)
	_expect(arena.enemies.is_empty(), "Demo suppresses ordinary timer-based spawning")
	_press("RestoreStandardRun")
	_expect(not arena.demo_mode and arena.alive and arena.auto_fire and arena.enemies.size() == 3 and not arena.hud.is_blocking(), "Restore button returns to a clean playable standard challenge")
	var initial_reward: int = arena.reward_kills
	var ordinary: Dictionary = arena.enemies[0]
	_kill(ordinary)
	_expect(arena.reward_kills == initial_reward + 1, "Restored standard enemies once again advance real rewards")
	_suite_finished = true
