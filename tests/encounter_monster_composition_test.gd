extends SceneTree
## Real factory/runtime/compiler composition; no production hook or replacement executor.
## Run after headless import, with disposable XDG directories. Not in validate.sh.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Compiler = preload("res://scripts/encounters/encounter_compiler.gd")
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const BOTH: Array[String] = ["enemy_max_health_120", "enemy_move_speed_110"]
const SEEDS: Array[int] = [261002, 261103, 261207]
var checks: int = 0
var failures: int = 0
var finished: bool = false
var live_cap: int = 0
var bounds: Rect2


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Read the admission owner's actual constants without instantiating a scene/UI.
	var constants: Dictionary = load("res://scripts/main.gd").get_script_constant_map()
	live_cap = int(constants.MAX_ENEMIES)
	bounds = constants.ARENA
	_expect(live_cap > 0 and bounds.has_area(), "Live admission parameters come from main.gd")
	print("Composition limits: live=%d generation=%d descendants=%d queue=%d per_death=%d" %
		[live_cap, Runtime.MAX_GENERATION, Runtime.MAX_DESCENDANTS, Runtime.MAX_QUEUE, Runtime.MAX_CHILDREN_PER_DEATH])
	_case(_test_shared_and_rarity, "shared talent identity and real rarity gates")
	_case(_test_native_and_ordinary_split, "native special A/B and configured finite ordinary A")
	_case(_test_valid_budget_graphs, "validated content reaches generation and lineage limits")
	_case(_test_queue_and_cancellation, "actual death-filled queue, FIFO, cancellation and reset")
	_case(_test_typed_defense, "typed damage, resistance and shield settlement parity")
	_case(_test_hundred, "100-root seeded lifecycle differential")
	_case(_test_global_rng, "independent global RNG sequence")
	print("Encounter monster composition: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	finished = false
	test.call()
	_expect(finished, "Case completes without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) <= maxf(0.000001, absf(expected) * 1e-10),
		"%s (actual %.8f expected %.8f)" % [label, actual, expected])


func _child_count(enemy: Dictionary) -> int:
	var count: int = 0
	for child: Dictionary in enemy.death_spawns:
		count += int(child.count)
	return count


func _reason(runtime: RefCounted) -> String:
	return str(runtime.trace.back().get("reason", "")) if not runtime.trace.is_empty() else ""


func _apply(enemy: Dictionary, profile: Dictionary, runtime: RefCounted, label: String) -> Dictionary:
	var before: Dictionary = enemy.duplicate(true)
	var profile_before: Dictionary = profile.duplicate(true)
	var roots_before: Dictionary = runtime.roots.duplicate(true)
	var queue_before: Array[Dictionary] = runtime.queue.duplicate(true)
	var result: Dictionary = Compiler.apply_to_enemy(enemy, profile)
	_expect(result.ok, label + ": actual canonical actor accepts profile")
	_expect(enemy == before and profile == profile_before, label + ": inputs are unchanged")
	_expect(runtime.roots == roots_before and runtime.queue == queue_before, label + ": application cannot spend lineage/queue budget")
	if not result.ok:
		return {}
	var changed: Dictionary = result.enemy
	_near(changed.max_health, float(before.max_health) * float(profile.multipliers.max_health), label + ": life applied once")
	_near(changed.health, float(before.health) * float(profile.multipliers.max_health), label + ": current life ratio preserved")
	_near(changed.speed, float(before.speed) * float(profile.multipliers.speed), label + ": speed applied once")
	var restored: Dictionary = changed.duplicate(true)
	restored.erase(Compiler.SOURCE_FIELD)
	for field: String in ["health", "max_health", "speed"]:
		restored[field] = before[field]
	_expect(restored == before, label + ": rarity, shared IDs, defense, rewards and all other fields stay equal")
	_expect(changed[Compiler.SOURCE_FIELD].before == {"health": before.health, "max_health": before.max_health,
		"shield": before.shield, "max_shield": before.max_shield, "speed": before.speed}, label + ": provenance records this actor's canonical values")
	var changed_before: Dictionary = changed.duplicate(true)
	for retry_profile: Dictionary in [profile, Compiler.compile([]).profile]:
		var rejected: Dictionary = Compiler.apply_to_enemy(changed, retry_profile)
		_expect(not rejected.ok and not rejected.has("enemy") and not rejected.error.is_empty(), label + ": repeated application fails atomically")
	_expect(changed == changed_before, label + ": rejection leaves challenged actor unchanged")
	return changed


func _die(runtime: RefCounted, enemy: Dictionary, label: String) -> Dictionary:
	# Exercise existing resistance -> shield -> health settlement before the death API.
	var stale: Dictionary = enemy.duplicate(true)
	stale.health = 0.0
	var hit: Dictionary = Defense.incoming_hit({"physical": float(enemy.health) + float(enemy.shield) + 1.0,
		"fire": 7.0}, enemy.defense_stats, enemy.shield, enemy.health, "monster")
	_expect(hit.ok and hit.remaining_health == 0.0, label + ": real hit kills actor")
	enemy.health = hit.remaining_health
	enemy.shield = hit.remaining_shield
	var death: Dictionary = runtime.process_death(enemy)
	_expect(death.processed, label + ": first death is processed")
	var queued: Array[Dictionary] = runtime.queue.duplicate(true)
	var roots: Dictionary = runtime.roots.duplicate(true)
	for corpse: Dictionary in [enemy, enemy.duplicate(true), stale]:
		_expect(runtime.process_death(corpse) == {"processed": false, "reward": false, "queued": 0},
			label + ": same/copy/pre-ledger corpse cannot award or spawn again")
	_expect(runtime.queue == queued and runtime.roots == roots, label + ": repeated death spends no budget")
	return death


func _drain(runtime: RefCounted, available: int, profile: Dictionary, label: String) -> Array[Dictionary]:
	var requests: Array[Dictionary] = runtime.queue.duplicate(true)
	var canonical: Array[Dictionary] = runtime.drain(available, bounds)
	_expect(canonical.size() == mini(maxi(available, 0), requests.size()), label + ": available slots bound actual admission")
	var changed: Array[Dictionary] = []
	for index: int in range(canonical.size()):
		var child: Dictionary = canonical[index]
		var request: Dictionary = requests[index]
		_expect(child.template_id == request.template and child.parent_id == request.parent_id
			and child.root_id == request.root_id and child.generation == request.generation, label + ": real drain retains exact FIFO identity")
		_expect(not child.has(Compiler.SOURCE_FIELD) and not child.reward_eligible and child.xp_reward == 0
			and child.spawn > 0.0, label + ": runtime emits fresh protected rewardless child before application")
		var target: Dictionary = Monsters.make_enemy(child.id, child.template_id, child.wave, child.pos,
			"death_child", "", [], runtime.templates)
		_expect(child.max_health == target.max_health and child.speed == target.speed
			and child.rarity == target.rarity and child.mechanism_ids == target.mechanism_ids
			and child.death_spawns == target.death_spawns, label + ": child uses target template instead of challenged parent")
		changed.append(_apply(child, profile, runtime, label + " child %d" % child.id))
	return changed


func _walk(runtime: RefCounted, actor: Dictionary, profile: Dictionary, expected_total: int, reward: bool, label: String) -> void:
	var actors: Array[Dictionary] = [_apply(actor, profile, runtime, label + " root")]
	var total: int = 0
	var rewards: int = 0
	for stage: int in range(Runtime.MAX_GENERATION + 2):
		if actors.is_empty() and runtime.queue.is_empty():
			break
		for enemy: Dictionary in actors:
			_expect(enemy.generation <= Runtime.MAX_GENERATION and enemy.root_id == actor.id, label + ": bounded original lineage")
			var death: Dictionary = _die(runtime, enemy, label)
			total += 1
			rewards += int(death.reward)
		actors.clear()
		runtime.collect_lineages(actors)
		actors = _drain(runtime, live_cap, profile, label)
	_expect(total == expected_total and rewards == int(reward), label + ": exact finite total and root-only reward")
	_expect(actors.is_empty() and runtime.queue.is_empty(), label + ": terminates within generation bound")
	runtime.collect_lineages(actors)
	_expect(runtime.roots.is_empty(), label + ": finished lineage is reclaimed")


func _test_shared_and_rarity() -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	_near(profile.multipliers.max_health, 1.2, "Requested life factor comes from compiled catalog")
	_near(profile.multipliers.speed, 1.1, "Requested speed factor comes from compiled catalog")
	var linked: Dictionary = {}
	for node_id: String in Passives.get_nodes():
		for id: String in Passives.get_node_mechanisms(node_id):
			linked[id] = node_id
	for id: String in Registry.get_ids("monster"):
		var player: Dictionary = Registry.resolve(id, "player")
		var monster: Dictionary = Registry.resolve(id, "monster")
		_expect(player.ok and monster.ok and player.stats == monster.stats and linked.has(id), "Shared talent/monster definition and tree ID: " + id)
		if linked.has(id):
			_expect(Passives.get_node_stats(linked[id]) == monster.stats, "Actual talent node resolves the same bundle: " + id)
		var runtime = Runtime.new()
		var enemy: Dictionary = runtime.create_root("brute", 8, bounds.get_center(), "ordinary", "magic", [id])
		_expect(enemy.mechanism_ids == monster.mechanism_ids and enemy.mechanism_stats == monster.stats, "Factory preserves authoritative shared IDs/stats: " + id)
		_apply(enemy, profile, runtime, "shared " + id)
	for template: String in Monsters.TEMPLATES:
		for wave: int in [1, 8, 23]:
			var runtime = Runtime.new()
			var context: String = "map_boss" if Monsters.TEMPLATES[template].rarity == "boss" else "ordinary"
			var enemy: Dictionary = runtime.create_root(template, wave, bounds.get_center(), context)
			_apply(enemy, profile, runtime, "%s wave %d" % [template, wave])
	for rarity: String in Monsters.ORDINARY_RARITIES:
		var grants: Array = [] if rarity == "normal" else ["talent.ember.power"] if rarity == "magic" else ["gale_stride", "aegis_capacity"]
		for ids: Array in [[], [BOTH[0]], [BOTH[1]], BOTH]:
			var runtime = Runtime.new()
			var enemy: Dictionary = runtime.create_root("crawler", 7, bounds.get_center(), "ordinary", rarity, grants)
			_apply(enemy, Compiler.compile(ids).profile, runtime, "rarity " + rarity)
	var gated = Runtime.new()
	_expect(gated.create_root("rift_warden", 8, bounds.get_center()).is_empty(), "Orange boss cannot enter ordinary context")
	_expect(gated.create_root("crawler", 8, bounds.get_center(), "level_boss", "boss").is_empty(), "Ordinary template cannot be upgraded to boss")
	_expect(gated.create_root("crawler", 8, bounds.get_center(), "ordinary", "reserved").is_empty(), "Black rarity remains reserved")
	for context: String in ["level_boss", "map_boss"]:
		_apply(gated.create_root("rift_warden", 8, bounds.get_center(), context), profile, gated, context)
	for id: String in Registry.get_ids():
		if not Registry.is_supported(id, "monster"):
			_expect(gated.create_root("crawler", 8, bounds.get_center(), "ordinary", "magic", [id]).is_empty(), "Player-only bundle is rejected in full: " + id)
	_expect(not Compiler.compile([BOTH[0], BOTH[0]]).ok, "Duplicate challenge IDs have no compiled profile")
	finished = true


func _test_native_and_ordinary_split() -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	for template: String in ["crawler", "splitter", "brood_host", "rift_warden"]:
		var runtime = Runtime.new()
		var context: String = "level_boss" if template == "rift_warden" else "ordinary"
		var total: int = {"crawler": 1, "splitter": 4, "brood_host": 9, "rift_warden": 5}[template]
		var actor: Dictionary = runtime.create_root(template, 9, bounds.position + Vector2.ONE, context)
		_walk(runtime, actor, profile, total, true, template)
	var original: Dictionary = Monsters.TEMPLATES.duplicate(true)
	var configured: Dictionary = Monsters.TEMPLATES.duplicate(true)
	configured.crawler.death_spawns = [{"template": "skitter", "count": 2}]
	_expect(Monsters.validate_templates(configured).is_empty(), "Ordinary A finite split is valid explicit content")
	var ordinary = Runtime.new(configured)
	var root_actor: Dictionary = ordinary.create_root("crawler", 4, bounds.get_center())
	_expect(root_actor.rarity == "normal" and root_actor.mechanism_ids.is_empty(), "Configured ordinary A remains white and has no artificial talent")
	_walk(ordinary, root_actor, profile, 3, true, "ordinary A -> terminal B x2")
	var demo = Runtime.new()
	_walk(demo, demo.create_root("brood_host", 5, bounds.get_center(), "demo", "", [], false), profile, 9, false, "rewardless demo")
	for indirect: bool in [false, true]:
		var cyclic: Dictionary = original.duplicate(true)
		cyclic.crawler.death_spawns = [{"template": "splitter" if indirect else "crawler", "count": 1}]
		var rejected = Runtime.new(cyclic)
		_expect(not rejected.validation_errors.is_empty() and rejected.create_root("crawler", 1, bounds.get_center()).is_empty()
			and rejected.queue.is_empty() and rejected.roots.is_empty(), "Real direct/indirect cycle counterexample fails before spawning")
	_expect(Monsters.TEMPLATES == original, "Configured and rejected graphs leave shipped content unchanged")
	finished = true


func _test_valid_budget_graphs() -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	# Use existing identities/kinds so both actual modules accept the same custom graph.
	var ids: Array[String] = ["crawler", "skitter", "brute", "splitter", "brood_host", "ember_guard"]
	var chain: Dictionary = Monsters.TEMPLATES.duplicate(true)
	_expect(ids.size() >= Runtime.MAX_GENERATION + 2, "Current shipped identities suffice for a real over-generation graph")
	for id: String in chain:
		chain[id].death_spawns = []
	for index: int in range(Runtime.MAX_GENERATION + 1):
		chain[ids[index]].death_spawns = [{"template": ids[index + 1], "count": 1}]
	_expect(Monsters.validate_templates(chain).is_empty(), "Over-generation chain is acyclic valid factory content")
	var runtime = Runtime.new(chain)
	var enemy: Dictionary = _apply(runtime.create_root(ids[0], 6, bounds.get_center()), profile, runtime, "chain root")
	var root_id: int = enemy.id
	for generation: int in range(Runtime.MAX_GENERATION + 1):
		_expect(enemy.generation == generation, "Generation is assigned by real drain")
		var death: Dictionary = _die(runtime, enemy, "generation %d" % generation)
		_expect(death.reward == (generation == 0), "Only root retains reward at generation boundary")
		if generation < Runtime.MAX_GENERATION:
			_expect(death.queued == 1, "Valid next generation is admitted")
			enemy = _drain(runtime, live_cap, profile, "chain")[0]
		else:
			_expect(death.queued == 0 and _reason(runtime) == "generation_budget", "Real next child is rejected at generation limit")
	_expect(runtime.roots[root_id].reserved == Runtime.MAX_GENERATION and runtime.queue.is_empty(), "Rejected generation spends no descendant budget")
	var branched: Dictionary = Monsters.TEMPLATES.duplicate(true)
	branched.brood_host.death_spawns = [{"template": "splitter", "count": Runtime.MAX_CHILDREN_PER_DEATH}]
	_expect(Monsters.validate_templates(branched).is_empty(), "Boundary branch graph validates before runtime admission")
	runtime = Runtime.new(branched)
	enemy = _apply(runtime.create_root("brood_host", 6, bounds.get_center()), profile, runtime, "branch root")
	var reserved: int = Runtime.MAX_CHILDREN_PER_DEATH
	_expect(_die(runtime, enemy, "branch root").queued == reserved, "Maximum valid death group is reserved")
	var branches: Array[Dictionary] = _drain(runtime, live_cap, profile, "branches")
	var rejected_groups: int = 0
	for branch: Dictionary in branches:
		var count: int = _child_count(branch)
		var admitted: bool = reserved + count <= Runtime.MAX_DESCENDANTS
		var death: Dictionary = _die(runtime, branch, "branch %d" % branch.id)
		_expect(death.queued == (count if admitted else 0) and not death.reward, "Actual sibling group obeys cumulative budget atomically")
		if admitted:
			reserved += count
		else:
			rejected_groups += 1
			_expect(_reason(runtime) == "lineage_budget", "Real sibling rejection records lineage budget")
	_expect(reserved == Runtime.MAX_DESCENDANTS and rejected_groups > 0
		and runtime.roots[enemy.id].reserved == reserved, "Current graph reaches exact descendant cap and rejects later groups")
	for leaf: Dictionary in _drain(runtime, live_cap, profile, "branch leaves"):
		_expect(not _die(runtime, leaf, "terminal leaf").reward, "Budget-bound terminal descendant cannot award")
	var empty: Array[Dictionary] = []
	runtime.collect_lineages(empty)
	_expect(runtime.queue.is_empty() and runtime.roots.is_empty(), "Budget-bound graph ends and is reclaimed")
	finished = true


func _test_queue_and_cancellation() -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	var configured: Dictionary = Monsters.TEMPLATES.duplicate(true)
	configured.crawler.death_spawns = [{"template": "skitter", "count": 1}]
	var runtime = Runtime.new(configured)
	var blocker: Dictionary = _apply(runtime.create_root("splitter", 3, bounds.get_center()), profile, runtime, "queue blocker")
	var group_size: int = _child_count(blocker)
	for index: int in range(Runtime.MAX_QUEUE - group_size):
		var actor: Dictionary = _apply(runtime.create_root("crawler", 3, bounds.get_center()), profile, runtime, "queue filler")
		_expect(_die(runtime, actor, "queue filler").queued == 1, "Queue is filled through real root deaths, never hand-written requests")
	_expect(_die(runtime, blocker, "exact queue boundary").queued == group_size and runtime.queue.size() == Runtime.MAX_QUEUE, "Whole group reaches exact real queue capacity")
	var actor: Dictionary = _apply(runtime.create_root("brood_host", 3, bounds.get_center()), profile, runtime, "queue overflow")
	var requests: Array[Dictionary] = runtime.queue.duplicate(true)
	var death: Dictionary = _die(runtime, actor, "queue overflow")
	_expect(death.reward and death.queued == 0 and _reason(runtime) == "queue_capacity"
		and runtime.queue == requests and runtime.roots[actor.id].reserved == 0, "Full queue rejects all children while retaining root's one reward")
	_expect(_drain(runtime, 0, profile, "full arena").is_empty() and runtime.queue == requests, "Zero live vacancy delays all requests")
	_expect(_drain(runtime, -1, profile, "negative vacancy").is_empty() and runtime.queue == requests, "Negative vacancy cannot over-admit")
	var occupants: Array[Dictionary] = []
	while not runtime.queue.is_empty():
		var children: Array[Dictionary] = _drain(runtime, mini(7, live_cap - occupants.size()), profile, "delayed FIFO")
		occupants.append_array(children)
		_expect(occupants.size() <= live_cap, "Delayed admission respects actual live cap")
		if children.is_empty():
			break
	_expect(runtime.queue.is_empty(), "Current queue capacity can drain within actual scene cap")
	var cancellation = Runtime.new()
	actor = _apply(cancellation.create_root("splitter", 3, bounds.get_center()), profile, cancellation, "cancelled root")
	_die(cancellation, actor, "cancelled root")
	var reserved: int = cancellation.roots[actor.id].reserved
	cancellation.cancel_pending("composition_test")
	_expect(cancellation.queue.is_empty() and cancellation.roots[actor.id].reserved == reserved, "Cancellation cannot refund lineage budget")
	var empty: Array[Dictionary] = []
	cancellation.collect_lineages(empty)
	_expect(cancellation.roots.is_empty() and not cancellation.process_death(actor.duplicate(true)).processed, "Collected stale corpse cannot award again")
	cancellation.reset()
	var fresh: Dictionary = cancellation.create_root("crawler", 3, bounds.get_center())
	_expect(fresh.id > actor.id and fresh.root_id == fresh.id and cancellation.queue.is_empty(), "Reset clears work without reusing actor identities")
	finished = true


func _test_typed_defense() -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	var runtime = Runtime.new()
	# Actual guarded template, with actual shared shield/recovery grants.
	var canonical: Dictionary = runtime.create_root("ember_guard", 8, bounds.get_center(), "ordinary", "rare", ["aegis_capacity", "aegis_recovery"])
	canonical.health *= 0.37
	canonical.shield *= 0.4
	var changed: Dictionary = _apply(canonical, profile, runtime, "injured fire guard")
	_expect(canonical.max_shield > 0.0 and canonical.shield_regen > 0.0 and canonical.resistances.fire > 0.0, "Defense fixture contains real resistance, shield and recovery")
	for raw: Dictionary in [{"physical": 5.0, "fire": 12.0, "cold": 3.0, "lightning": 4.0, "chaos": 2.0},
		{"physical": 800.0, "fire": 600.0}]:
		var baseline: Dictionary = Defense.incoming_hit(raw, canonical.defense_stats, canonical.shield, canonical.health, "monster")
		var challenged: Dictionary = Defense.incoming_hit(raw, changed.defense_stats, changed.shield, changed.health, "monster")
		_expect(baseline.ok and challenged.ok, "Both actual defense settlements accept typed packet")
		for field: String in ["raw_components", "components", "mitigated_components", "damage_total", "shield_spent", "remaining_shield", "details", "effective_resistances"]:
			_expect(baseline[field] == challenged[field], "Challenge preserves exact existing hit semantics: " + field)
		_near(challenged.components.fire, float(raw.fire) * (1.0 - float(canonical.resistances.fire)), "Fire mitigation applies once before shield")
		_near(challenged.health_lost, minf(float(changed.health), maxf(0.0, float(challenged.damage_total) - float(changed.shield))), "Only extra life changes bounded health settlement")
	_expect(Monsters.contact_components(canonical) == Monsters.contact_components(changed), "Native physical/fire contact damage remains equal")
	# Failure paths remain non-mutating even when the marker's value is empty.
	for marker: Variant in [null, {}]:
		var poisoned: Dictionary = canonical.duplicate(true)
		poisoned[Compiler.SOURCE_FIELD] = marker
		var before: Dictionary = poisoned.duplicate(true)
		var rejected: Dictionary = Compiler.apply_to_enemy(poisoned, profile)
		_expect(not rejected.ok and not rejected.has("enemy") and poisoned == before, "Any existing source marker rejects without modifying input")
	finished = true


func _test_hundred() -> void:
	_expect(live_cap == 100, "Current scene really admits 100 roots")
	for seed_value: int in SEEDS:
		_hundred(seed_value)
	finished = true


func _hundred(seed_value: int) -> void:
	var profile: Dictionary = Compiler.compile(BOTH).profile
	var original = Runtime.new()
	var challenged = Runtime.new()
	var spawn_reference := RandomNumberGenerator.new()
	var spawn_exercised := RandomNumberGenerator.new()
	var loot_reference := RandomNumberGenerator.new()
	var loot_exercised := RandomNumberGenerator.new()
	spawn_reference.seed = seed_value
	spawn_exercised.seed = seed_value
	loot_reference.seed = seed_value + 900000
	loot_exercised.seed = seed_value + 900000
	var left: Array[Dictionary] = []
	var right: Array[Dictionary] = []
	var total_deaths: int = 0
	var rewards: int = 0
	var xp: int = 0
	var expected_xp: int = 0
	var rejected_groups: int = 0
	# Admit a real multistage brood first, then force overflow with native splitters.
	# Remaining roots use seeded real rolls; all RNG draws still have a reference peer.
	var special_count: int = mini(live_cap - 4, Runtime.MAX_QUEUE / _child_count(Monsters.make_enemy(1, "splitter", 1, bounds.get_center())) + 2)
	for index: int in range(live_cap):
		var wave: int = 3 + index % 20
		var roll: Dictionary = Monsters.ordinary_roll(spawn_reference, wave)
		_expect(roll == Monsters.ordinary_roll(spawn_exercised, wave), "Independent seed preserves ordinary spawn sequence")
		if index == 0:
			roll = {"template": "brood_host", "rarity": "rare", "mechanisms": Monsters.TEMPLATES.brood_host.mechanisms}
		elif index <= special_count:
			roll = {"template": "splitter", "rarity": "magic", "mechanisms": Monsters.TEMPLATES.splitter.mechanisms}
		var position: Vector2 = bounds.position + Vector2(50 + index * 5, 100)
		var first: Dictionary = original.create_root(roll.template, wave, position, "ordinary", roll.rarity, roll.mechanisms)
		var second: Dictionary = challenged.create_root(roll.template, wave, position, "ordinary", roll.rarity, roll.mechanisms)
		_expect(first == second, "Both runtimes create identical canonical roots")
		var spawn_state: int = spawn_exercised.state
		var loot_state: int = loot_exercised.state
		left.append(first)
		right.append(_apply(second, profile, challenged, "seed %d root %d" % [seed_value, index]))
		_expect(spawn_exercised.state == spawn_state and loot_exercised.state == loot_state, "Application leaves independent spawn and loot RNG untouched")
		expected_xp += int(first.xp_reward)
	_expect(left.size() == live_cap and right.size() == live_cap, "Actual factories created exactly the live-cap population")
	for stage: int in range(Runtime.MAX_GENERATION + 2):
		if left.is_empty() and original.queue.is_empty():
			break
		var batch_size: int = left.size()
		for index: int in range(batch_size):
			var first: Dictionary = left[index]
			var second: Dictionary = right[index]
			var a: Dictionary = _die(original, first, "reference death")
			var b: Dictionary = _die(challenged, second, "challenged death")
			_expect(a == b and original.queue == challenged.queue and original.roots == challenged.roots
				and original.trace == challenged.trace, "Real once-only death, queue, ledger and bounded trace match reference")
			if _child_count(first) > 0 and a.queued == 0:
				rejected_groups += 1
			if b.reward:
				rewards += 1
				xp += int(second.xp_reward)
				var item_id: String = "gear_%06d" % rewards
				var expected_item: Dictionary = Equipment.generate_current_loot(loot_reference, item_id, mini(first.wave * 2 - 1, 30))
				var actual_item: Dictionary = Equipment.generate_current_loot(loot_exercised, item_id, mini(second.wave * 2 - 1, 30))
				_expect(Equipment.validate_instance(actual_item) and actual_item == expected_item
					and loot_reference.state == loot_exercised.state, "One eligible-death loot probe preserves exact valid item and RNG outcome")
			else:
				_expect(second.xp_reward == 0 and not second.reward_eligible, "All actual descendants suppress rewards and XP")
			total_deaths += 1
			_expect(original.queue.size() <= Runtime.MAX_QUEUE and left.size() == batch_size and right.size() == batch_size, "Death callbacks never synchronously insert actors or overflow queue")
		var waiting: Array[Dictionary] = challenged.queue.duplicate(true)
		_expect(_drain(challenged, 0, profile, "deferred batch").is_empty() and challenged.queue == waiting, "Pending requests wait while current batch still occupies slots")
		left.clear()
		right.clear()
		original.collect_lineages(left)
		challenged.collect_lineages(right)
		var frame: int = 0
		while not original.queue.is_empty() and left.size() < live_cap and frame <= Runtime.MAX_QUEUE:
			var vacancies: int = mini([1, 7, live_cap][frame % 3], live_cap - left.size())
			left.append_array(original.drain(vacancies, bounds))
			right.append_array(_drain(challenged, vacancies, profile, "seeded delayed children"))
			_expect(left.size() == right.size() and right.size() <= live_cap and original.queue == challenged.queue, "Uneven delayed drains preserve reference FIFO and live cap")
			frame += 1
	_expect(left.is_empty() and right.is_empty() and original.queue.is_empty() and challenged.queue.is_empty(), "100-root workload terminates without unbounded spawning")
	_expect(rewards == live_cap and xp == expected_xp and rejected_groups > 0, "Every root rewards once, descendants never reward, real overflow was exercised")
	_expect(total_deaths <= live_cap * (1 + Runtime.MAX_DESCENDANTS), "Total real deaths stay within summed lineage budgets")
	original.collect_lineages(left)
	challenged.collect_lineages(right)
	_expect(original.roots.is_empty() and challenged.roots.is_empty(), "All 100 completed lineages are reclaimed")
	for index: int in range(32):
		_expect(spawn_reference.randi() == spawn_exercised.randi() and loot_reference.randi() == loot_exercised.randi(), "Subsequent spawn/loot sequences remain identical after full lifecycle")
	print("Composition seed=%d roots=%d deaths=%d rewards=%d rejected_groups=%d" % [seed_value, live_cap, total_deaths, rewards, rejected_groups])


func _test_global_rng() -> void:
	seed(261309)
	var expected: Array[int] = []
	for index: int in range(16):
		expected.append(randi())
	seed(261309)
	var runtime = Runtime.new()
	var profile: Dictionary = Compiler.compile(BOTH).profile
	var enemy: Dictionary = _apply(runtime.create_root("splitter", 8, bounds.get_center()), profile, runtime, "global RNG")
	_expect(not Compiler.compile(["unknown"]).ok, "Global RNG probe includes compilation rejection")
	_die(runtime, enemy, "global RNG death")
	_drain(runtime, live_cap, profile, "global RNG children")
	for value: int in expected:
		_expect(randi() == value, "Independent global sequence survives compile/apply/reject/death/drain")
	finished = true
