extends SceneTree
## Deterministic adversarial contracts for catalog, template graph and deferred life cycles.
## Run with an isolated XDG_DATA_HOME; production state and saves are never fixtures.
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const ARENA := Rect2(42, 104, 1196, 462)
var checks: int = 0
var failures: int = 0
var _suite_finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_case(_test_catalog, "catalog and 10,000 seeded ordinary rolls")
	_case(_test_gates, "explicit rarity/context gates")
	_case(_test_template_validation, "template graph and malformed content")
	_case(_test_factory_validation, "malformed factory fixtures")
	_case(_test_splitter, "special A to terminal A and B")
	_case(_test_brood, "multistage brood termination")
	_case(_test_budgets, "atomic lineage and generation budgets")
	_case(_test_real_graph_budgets, "valid content reaches generation and lineage boundaries")
	_case(_test_queue, "queue capacity, FIFO and deferred admission")
	_case(_test_mutation_guards, "runtime mutation guards")
	_case(_test_collection, "lineage collection, cancellation and reset")
	print("Monster system: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_suite_finished = false
	test.call()
	_expect(_suite_finished, "Test reaches its final assertion without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(absf(value - expected) < 0.0001, "%s (actual %.6f, expected %.6f)" % [label, value, expected])


func _dead(runtime: RefCounted, template: String = "splitter") -> Dictionary:
	var enemy: Dictionary = runtime.create_root(template, 1, ARENA.get_center())
	enemy.health = 0.0
	return enemy


func _last_reason(runtime: RefCounted) -> String:
	return str(runtime.trace.back().get("reason", "")) if not runtime.trace.is_empty() else ""


func _test_catalog() -> void:
	_expect(Catalog.RARITIES.size() == 5, "Five rarity classes have catalog definitions")
	_expect(Catalog.ORDINARY_RARITIES == ["normal", "magic", "rare"], "Ordinary pool explicitly excludes boss and reserved")
	_expect(Catalog.validate_templates(Catalog.TEMPLATES).is_empty(), "Shipped template graph validates")
	var rng := RandomNumberGenerator.new()
	rng.seed = 410240
	var counts: Dictionary = {}
	var species: Dictionary = {}
	var valid: bool = true
	var exact_affixes: bool = true
	for index: int in range(10000):
		var wave: int = 1 + index % 40
		var roll: Dictionary = Catalog.ordinary_roll(rng, wave)
		counts[roll.rarity] = int(counts.get(roll.rarity, 0)) + 1
		valid = valid and str(roll.rarity) in Catalog.ORDINARY_RARITIES
		var enemy: Dictionary = Catalog.make_enemy(index + 1, roll.template, wave, Vector2(300, 300), "ordinary", roll.rarity, roll.mechanisms)
		valid = valid and not enemy.is_empty()
		if enemy.is_empty():
			continue
		species[enemy.kind] = true
		exact_affixes = exact_affixes and enemy.mechanism_ids.size() == int(Catalog.RARITIES[enemy.rarity].affixes)
		var unique: Dictionary = {}
		for id: String in enemy.mechanism_ids:
			unique[id] = true
		exact_affixes = exact_affixes and unique.size() == enemy.mechanism_ids.size()
	_expect(valid and not counts.has("boss") and not counts.has("reserved"), "10,000 rolls all create white/blue/gold enemies, never orange/black")
	_expect(counts.size() == 3 and species.size() == 3, "Seeded roll coverage includes every ordinary rarity and original species")
	_expect(exact_affixes, "Every random rarity has its exact distinct implemented-affix count")
	_suite_finished = true


func _test_gates() -> void:
	for context: String in ["ordinary", "death_child", "demo", "", "level_bos"]:
		_expect(Catalog.make_enemy(1, "rift_warden", 1, Vector2.ZERO, context).is_empty(), "Boss refused in non-boss context: " + context)
	for context: String in ["level_boss", "map_boss"]:
		var boss: Dictionary = Catalog.make_enemy(1, "rift_warden", 1, Vector2.ZERO, context)
		_expect(not boss.is_empty() and boss.rarity == "boss", "Explicit boss accepted in " + context)
		_expect(Catalog.make_enemy(2, "crawler", 1, Vector2.ZERO, context, "boss", []).is_empty(), "Ordinary template cannot become boss through override")
		_expect(Catalog.make_enemy(3, "rift_warden", 1, Vector2.ZERO, context, "normal", []).is_empty(), "Boss template cannot be downgraded to evade its gate")
		_expect(Catalog.make_enemy(4, "crawler", 1, Vector2.ZERO, context).is_empty(), "Boss-only context cannot launder ordinary template")
	for context: String in ["ordinary", "death_child", "demo", "level_boss", "map_boss"]:
		_expect(Catalog.make_enemy(1, "crawler", 1, Vector2.ZERO, context, "reserved", []).is_empty(), "Reserved rarity refused in every context: " + context)
	_expect(Catalog.make_enemy(0, "crawler", 1, Vector2.ZERO).is_empty(), "Zero enemy identity refused")
	_expect(Catalog.make_enemy(-1, "crawler", 1, Vector2.ZERO).is_empty(), "Negative enemy identity refused")
	_expect(Catalog.make_enemy(1, "crawler", 0, Vector2.ZERO).is_empty(), "Invalid wave refused")
	_expect(Catalog.make_enemy(1, "missing", 1, Vector2.ZERO).is_empty(), "Missing template refused")
	_expect(Catalog.make_enemy(1, "crawler", 1, Vector2(INF, 0)).is_empty(), "Infinite position refused")
	_expect(Catalog.make_enemy(1, "crawler", 1, Vector2(NAN, 0)).is_empty(), "NaN position refused")
	_expect(Catalog.make_enemy(1, "crawler", 1, Vector2.ZERO, "ordinary", "magic", ["missing_mechanism"]).is_empty(), "Unknown mechanism rejects entire monster")
	_expect(Catalog.make_enemy(1, "crawler", 1, Vector2.ZERO, "ordinary", "normal", ["ember_power"]).is_empty(), "White cannot silently retain a bonus mechanism")
	_expect(Catalog.make_enemy(1, "crawler", 1, Vector2.ZERO, "ordinary", "magic", ["ember_power", "gale_stride"]).is_empty(), "Magic rejects excess grants")
	_suite_finished = true


func _bad_template(field: String, value: Variant, label: String) -> void:
	var templates: Dictionary = Catalog.TEMPLATES.duplicate(true)
	templates.crawler[field] = value
	var errors: Array[String] = Catalog.validate_templates(templates)
	_expect(not errors.is_empty(), "Malformed content rejected: " + label)
	var runtime = Runtime.new(templates)
	_expect(not runtime.validation_errors.is_empty() and runtime.templates.is_empty(), "Invalid graph cannot partially initialize: " + label)
	_expect(runtime.create_root("crawler", 1, Vector2.ZERO).is_empty(), "Invalid graph cannot produce roots: " + label)


func _test_template_validation() -> void:
	_expect(not Catalog.validate_templates({}).is_empty(), "Empty graph refused")
	_expect(not Catalog.validate_templates({1: {}}).is_empty(), "Non-string template key refused")
	_expect(not Catalog.validate_templates({"bad": null}).is_empty(), "Null template body refused")
	var too_many: Dictionary = {}
	for index: int in range(257):
		too_many[str(index)] = Catalog.TEMPLATES.crawler.duplicate(true)
	_expect(not Catalog.validate_templates(too_many).is_empty(), "Graph size limit is enforced")
	_bad_template("kind", -1, "negative species")
	_bad_template("kind", 3, "unknown species")
	_bad_template("kind", "0", "string species")
	_bad_template("kind", 0.5, "fractional species")
	_bad_template("rarity", "reserved", "reserved rarity")
	_bad_template("rarity", "legendary", "unknown rarity")
	_bad_template("mechanisms", {}, "non-array mechanisms")
	_bad_template("mechanisms", ["missing_mechanism"], "unknown mechanism")
	_bad_template("mechanisms", ["ember_power"], "white mechanism excess")
	_bad_template("death_spawns", {}, "non-array death list")
	_bad_template("death_spawns", [null], "null child rule")
	_bad_template("death_spawns", ["crawler"], "string child rule")
	for count: Variant in [0, -1, 7, 1.5, "2", null]:
		_bad_template("death_spawns", [{"template": "skitter", "count": count}], "invalid count " + str(count))
	_bad_template("death_spawns", [{"template": "missing", "count": 1}], "missing child")
	_bad_template("death_spawns", [{"template": "rift_warden", "count": 1}], "boss child")
	_bad_template("death_spawns", [{"template": "skitter", "count": 4}, {"template": "brute", "count": 3}], "aggregate children exceed six")
	_bad_template("death_spawns", [{"template": "crawler", "count": 1}], "direct state self-cycle")
	var cycle: Dictionary = Catalog.TEMPLATES.duplicate(true)
	cycle.crawler.death_spawns = [{"template": "skitter", "count": 1}]
	cycle.skitter.death_spawns = [{"template": "brute", "count": 1}]
	cycle.brute.death_spawns = [{"template": "crawler", "count": 1}]
	_expect(not Catalog.validate_templates(cycle).is_empty(), "Three-state indirect cycle refused")
	var valid: Dictionary = Catalog.TEMPLATES.duplicate(true)
	valid.crawler.death_spawns = [{"template": "skitter", "count": 6}]
	_expect(Catalog.validate_templates(valid).is_empty(), "Six terminal children is a valid boundary")
	_suite_finished = true


func _test_factory_validation() -> void:
	# Public factory must not throw, coerce bad fields, or rely on a prior caller validation.
	var fixtures: Array[Dictionary] = [
		{"field": "kind", "value": "0"}, {"field": "kind", "value": 0.5},
		{"field": "kind", "value": null}, {"field": "mechanisms", "value": {}},
		{"field": "death_spawns", "value": {}},
		{"field": "death_spawns", "value": [{"template": "missing", "count": 2}]},
	]
	for fixture: Dictionary in fixtures:
		var templates: Dictionary = Catalog.TEMPLATES.duplicate(true)
		templates.crawler[fixture.field] = fixture.value
		var result: Variant = Catalog.make_enemy(1, "crawler", 1, Vector2.ZERO, "ordinary", "", [], templates)
		_expect(result is Dictionary and result.is_empty(), "Factory rejects malformed " + str(fixture.field) + ": " + str(fixture.value))
	var wrong_body: Dictionary = {"crawler": "not a template"}
	var rejected: Variant = Catalog.make_enemy(1, "crawler", 1, Vector2.ZERO, "ordinary", "", [], wrong_body)
	_expect(rejected is Dictionary and rejected.is_empty(), "Factory rejects non-dictionary template body without exception")
	_suite_finished = true


func _test_splitter() -> void:
	var runtime = Runtime.new()
	var parent: Dictionary = runtime.create_root("splitter", 4, ARENA.get_center())
	_expect(not runtime.process_death(parent).processed and runtime.queue.is_empty(), "Living monster cannot emit a death transaction")
	parent.health = 0.0
	var copied_corpse: Dictionary = parent.duplicate(true)
	var result: Dictionary = runtime.process_death(parent)
	_expect(result.processed and result.reward and result.queued == 3 and parent.death_processed, "Special A death reserves two ordinary A and one B once")
	_expect(runtime.queue.size() == 3 and runtime.roots[parent.id].reserved == 3, "Death admission reserves whole descendant group")
	var again: Dictionary = runtime.process_death(parent)
	_expect(not again.processed and not again.reward and again.queued == 0 and runtime.queue.size() == 3, "Repeated corpse event cannot duplicate reward or descendants")
	var copied_result: Dictionary = runtime.process_death(copied_corpse)
	_expect(not copied_result.processed and not copied_result.reward and copied_result.queued == 0 and runtime.queue.size() == 3, "A copied corpse with stale flag cannot replay the same identity")
	var children: Array[Dictionary] = runtime.drain(55, ARENA)
	var names: Array[String] = []
	var positions: Dictionary = {}
	var identities: Dictionary = {parent.id: true}
	var clean: bool = true
	for child: Dictionary in children:
		names.append(child.template_id)
		positions[child.pos] = true
		identities[child.id] = true
		clean = clean and child.rarity == "normal" and child.mechanism_ids.is_empty() and child.death_spawns.is_empty()
		clean = clean and not child.reward_eligible and child.xp_reward == 0 and child.root_id == parent.id and child.parent_id == parent.id and child.generation == 1 and child.wave == 4
		clean = clean and float(child.spawn) > 0.0 and float(child.health) > 0.0
		child.health = 0.0
		var terminal: Dictionary = runtime.process_death(child)
		clean = clean and terminal.processed and not terminal.reward and terminal.queued == 0
	_expect(names == ["crawler", "crawler", "skitter"], "Child ordering and explicit target templates are exact")
	_expect(clean, "Children use target-only stats, birth protection, no rewards and terminal death behavior")
	_expect(positions.size() == 3 and identities.size() == 4, "Children get separated positions and unique identities")
	_expect(runtime.queue.is_empty(), "Terminal children cannot regenerate the special A state")
	_suite_finished = true


func _test_brood() -> void:
	var runtime = Runtime.new()
	var parent: Dictionary = _dead(runtime, "brood_host")
	_expect(runtime.process_death(parent).queued == 2, "Brood produces exactly two explicit splitters")
	var splitters: Array[Dictionary] = runtime.drain(55, ARENA)
	_expect(splitters.size() == 2, "Brood first generation contains two children")
	for child: Dictionary in splitters:
		_expect(child.template_id == "splitter" and child.rarity == "magic" and child.generation == 1, "Brood descendants adopt target splitter state")
		_expect(not child.reward_eligible and child.xp_reward == 0 and child.death_spawns.size() == 2, "Splitter child keeps its own death behavior but loses reward")
		child.health = -100.0
		var death: Dictionary = runtime.process_death(child)
		_expect(death.processed and not death.reward and death.queued == 3, "Each child splitter admits three rewardless grandchildren")
	var grandchildren: Array[Dictionary] = runtime.drain(55, ARENA)
	var count_a: int = 0
	var count_b: int = 0
	for child: Dictionary in grandchildren:
		count_a += int(child.template_id == "crawler")
		count_b += int(child.template_id == "skitter")
		_expect(child.generation == 2 and child.root_id == parent.id and not child.reward_eligible and child.death_spawns.is_empty(), "Grandchild stays terminal in original lineage")
		child.health = 0.0
		_expect(runtime.process_death(child).queued == 0, "Grandchild death terminates chain")
	_expect(grandchildren.size() == 6 and count_a == 4 and count_b == 2, "Brood chain ends with four ordinary A and two B")
	_expect(runtime.queue.is_empty() and runtime.roots[parent.id].reserved == 8, "Two-stage chain reserves exactly eight descendants")
	_suite_finished = true


func _test_budgets() -> void:
	for reserved: int in [9, 10, 12]:
		var runtime = Runtime.new()
		var parent: Dictionary = _dead(runtime)
		runtime.roots[parent.id].reserved = reserved
		var result: Dictionary = runtime.process_death(parent)
		var admitted: bool = reserved == 9
		_expect(result.queued == (3 if admitted else 0) and runtime.queue.size() == (3 if admitted else 0), "Lineage limit admits all or none at reserved=%d" % reserved)
		_expect(runtime.roots[parent.id].reserved == (12 if admitted else reserved), "Rejected lineage group does not partly spend budget")
		if not admitted:
			_expect(_last_reason(runtime) == "lineage_budget", "Lineage rejection records explicit reason")
	for generation: int in [2, 3, 100]:
		var runtime = Runtime.new()
		var parent: Dictionary = _dead(runtime)
		parent.generation = generation
		var result: Dictionary = runtime.process_death(parent)
		_expect(result.queued == (3 if generation == 2 else 0), "Generation three is admitted and generation four is refused")
		if generation == 2:
			_expect(runtime.queue[0].generation == 3, "Boundary generation stored accurately")
		else:
			_expect(_last_reason(runtime) == "generation_budget" and runtime.roots[parent.id].reserved == 0, "Generation rejection has no partial reservation")
	var runtime = Runtime.new()
	var missing: Dictionary = _dead(runtime)
	runtime.roots.erase(missing.id)
	var orphan: Dictionary = runtime.process_death(missing)
	_expect(not orphan.processed and not orphan.reward and orphan.queued == 0 and runtime.queue.is_empty(), "Orphan death cannot invent a fresh descendant budget or reward")
	_suite_finished = true


func _test_real_graph_budgets() -> void:
	var chain: Dictionary = {}
	for index: int in range(5):
		var template: Dictionary = Catalog.TEMPLATES.crawler.duplicate(true)
		if index < 4:
			template.death_spawns = [{"template": "state_%d" % (index + 1), "count": 1}]
		chain["state_%d" % index] = template
	_expect(Catalog.validate_templates(chain).is_empty(), "Acyclic five-state chain is valid content before runtime budgets")
	var runtime = Runtime.new(chain)
	var current: Dictionary = runtime.create_root("state_0", 1, ARENA.get_center())
	var root_id: int = current.id
	for generation: int in range(4):
		_expect(current.generation == generation, "Real chain retains expected generation %d" % generation)
		current.health = 0.0
		var result: Dictionary = runtime.process_death(current)
		_expect(result.reward == (generation == 0), "Only real chain root can award a reward")
		if generation < 3:
			_expect(result.queued == 1, "Real chain admits child through generation three")
			current = runtime.drain(55, ARENA)[0]
		else:
			_expect(result.queued == 0 and _last_reason(runtime) == "generation_budget", "Validated acyclic content still cannot reach fourth generation")
	_expect(runtime.roots[root_id].reserved == 3 and runtime.queue.is_empty(), "Generation cap leaves exactly three reserved descendants")
	var branched: Dictionary = Catalog.TEMPLATES.duplicate(true)
	branched.brood_host.death_spawns = [{"template": "splitter", "count": 6}]
	_expect(Catalog.validate_templates(branched).is_empty(), "Six-way split is valid at per-death content boundary")
	runtime = Runtime.new(branched)
	var parent: Dictionary = _dead(runtime, "brood_host")
	_expect(runtime.process_death(parent).queued == 6, "Boundary six-child death group admitted atomically")
	var branches: Array[Dictionary] = runtime.drain(55, ARENA)
	for index: int in range(branches.size()):
		var child: Dictionary = branches[index]
		child.health = 0.0
		var result: Dictionary = runtime.process_death(child)
		_expect(result.queued == (3 if index < 2 else 0), "Real sibling branch respects cumulative 12-descendant budget at branch %d" % index)
		_expect(not result.reward, "Rejected or admitted descendant branch never awards root rewards")
	_expect(runtime.queue.size() == 6 and runtime.roots[parent.id].reserved == 12, "Lineage boundary admits two whole sibling groups and refuses four without partial groups")
	_suite_finished = true


func _test_queue() -> void:
	for count: int in [61, 62, 64]:
		var runtime = Runtime.new()
		var first: Dictionary = _dead(runtime, "brood_host")
		var parent: Dictionary = _dead(runtime)
		for index: int in range(count):
			runtime.queue.append({"template": "crawler", "root_id": first.id, "generation": 1, "wave": 1, "pos": ARENA.position, "parent_id": first.id})
		var before: Array[Dictionary] = runtime.queue.duplicate(true)
		var result: Dictionary = runtime.process_death(parent)
		_expect(result.queued == (3 if count == 61 else 0), "Queue group admission is atomic with %d occupied slots" % count)
		_expect(runtime.queue.size() == (64 if count == 61 else count), "Queue cap never exceeds 64")
		if count != 61:
			_expect(runtime.queue == before and runtime.roots[parent.id].reserved == 0 and _last_reason(runtime) == "queue_capacity", "Full queue preserves older work, budget and explicit rejection reason")
	var runtime = Runtime.new()
	var first: Dictionary = _dead(runtime)
	var second: Dictionary = _dead(runtime, "brood_host")
	runtime.process_death(first)
	runtime.process_death(second)
	var waiting: Array[Dictionary] = runtime.queue.duplicate(true)
	_expect(runtime.drain(0, ARENA).is_empty() and runtime.queue == waiting, "No live slots keeps complete queue unchanged")
	_expect(runtime.drain(-10, ARENA).is_empty() and runtime.queue == waiting, "Negative available slots cannot drop pending descendants")
	var spawned: Array[Dictionary] = runtime.drain(2, ARENA)
	_expect(spawned.size() == 2 and runtime.queue.size() == 3, "Two live slots admit exactly two children and retain remainder")
	_expect(spawned[0].parent_id == first.id and spawned[1].parent_id == first.id, "FIFO does not interleave later brood into earlier split")
	spawned = runtime.drain(1000, ARENA)
	_expect(spawned.size() == 3 and spawned[0].template_id == "skitter" and spawned[1].template_id == "splitter" and spawned[2].template_id == "splitter", "Subsequent drain preserves child and root FIFO order")
	_expect(runtime.queue.is_empty(), "Oversized availability drains only actual queued requests")
	var edge: Dictionary = _dead(runtime)
	edge.pos = Vector2(-99999, 99999)
	runtime.process_death(edge)
	for child: Dictionary in runtime.drain(55, ARENA):
		_expect(child.pos.x >= ARENA.position.x + child.radius and child.pos.x <= ARENA.end.x - child.radius and child.pos.y >= ARENA.position.y + child.radius and child.pos.y <= ARENA.end.y - child.radius, "Every child is clamped by its own radius at arena edges")
	_suite_finished = true


func _mutated_death(children: Variant, expected_reason: String) -> void:
	var runtime = Runtime.new()
	var parent: Dictionary = _dead(runtime)
	parent.death_spawns = children
	var result: Variant = runtime.process_death(parent)
	_expect(result is Dictionary and result.get("processed", false) and not result.get("queued", 0), "Corrupt death rule completes a controlled once-only rejection: " + str(children))
	_expect(runtime.queue.is_empty() and runtime.roots[parent.id].reserved == 0, "Corrupt death rule has no partial queue/budget side effects")
	_expect(_last_reason(runtime) == expected_reason, "Corrupt death rule records reason " + expected_reason)
	var again: Dictionary = runtime.process_death(parent)
	_expect(not again.processed and not again.reward, "Rejected malformed death is still once-only")


func _test_mutation_guards() -> void:
	_mutated_death([{"template": "crawler", "count": 7}], "per_death_budget")
	_mutated_death([{"template": "crawler", "count": 0}], "invalid_child_template")
	_mutated_death([{"template": "missing", "count": 2}], "invalid_child_template")
	_mutated_death([{"template": "rift_warden", "count": 2}], "invalid_child_template")
	_mutated_death([{"template": "crawler", "count": 2}, {"template": "missing", "count": 1}], "invalid_child_template")
	# Mutation fixtures intentionally include wrong types. Script exceptions must fail this suite.
	_mutated_death([{"template": "crawler", "count": 1.5}], "invalid_child_template")
	_mutated_death([{"template": "crawler", "count": "2"}], "invalid_child_template")
	_mutated_death([null], "invalid_child_template")
	_mutated_death({"template": "crawler", "count": 2}, "invalid_child_list")
	var source: Dictionary = Catalog.TEMPLATES.duplicate(true)
	var runtime = Runtime.new(source)
	source.splitter.death_spawns[0].count = 999
	var original: Dictionary = _dead(runtime)
	_expect(runtime.process_death(original).queued == 3, "Runtime snapshots validated templates against caller mutation")
	var parent: Dictionary = _dead(runtime)
	runtime.process_death(parent)
	runtime.templates.erase("crawler")
	var drained: Array[Dictionary] = runtime.drain(55, ARENA)
	_expect(drained.is_empty() and runtime.queue.is_empty() and _last_reason(runtime) == "template_changed", "Template removal invalidates graph and safely rejects queued requests without looping or crashing")
	_expect(runtime.roots[parent.id].reserved == 3, "Canceled descendants never refund reserved lineage budget")
	_suite_finished = true


func _test_collection() -> void:
	var runtime = Runtime.new()
	var parent: Dictionary = _dead(runtime)
	runtime.process_death(parent)
	var empty: Array[Dictionary] = []
	runtime.collect_lineages(empty)
	_expect(runtime.roots.has(parent.id), "Pending children keep dead root lineage alive")
	var children: Array[Dictionary] = runtime.drain(55, ARENA)
	runtime.collect_lineages(children)
	_expect(runtime.roots.has(parent.id), "Live descendants retain original root ledger")
	for child: Dictionary in children:
		child.health = 0.0
	runtime.collect_lineages(children)
	_expect(runtime.roots.is_empty(), "Dead descendants with no pending work reclaim lineage ledger")
	var cancelled: Dictionary = _dead(runtime)
	runtime.process_death(cancelled)
	runtime.cancel_pending("owner_death")
	_expect(runtime.queue.is_empty() and _last_reason(runtime) == "owner_death", "Owner death cancellation empties queue with cause")
	_expect(runtime.roots[cancelled.id].reserved == 3, "Cancellation does not refund already reserved budget")
	var trace_count: int = runtime.trace.size()
	runtime.cancel_pending("owner_death")
	_expect(runtime.trace.size() == trace_count, "Repeated cancellation of empty queue adds no duplicate work")
	runtime.collect_lineages(empty)
	_expect(runtime.roots.is_empty(), "Canceled, dead lineage can be collected")
	var pending: Dictionary = _dead(runtime)
	runtime.process_death(pending)
	var old_id: int = runtime.next_id
	runtime.reset()
	_expect(runtime.queue.is_empty() and runtime.roots.is_empty() and runtime.trace.is_empty(), "Reset clears pending children, budgets and trace")
	_expect(not runtime.process_death(pending).processed, "Reset cannot reanimate a previously processed corpse")
	var fresh: Dictionary = runtime.create_root("crawler", 1, Vector2.ZERO)
	_expect(fresh.id > old_id, "Reset never reuses an old enemy identity")
	for index: int in range(60):
		var parent_trace: Dictionary = _dead(runtime)
		parent_trace.generation = 3
		runtime.process_death(parent_trace)
	_expect(runtime.trace.size() == 48, "Diagnostic trace is bounded at 48 events")
	runtime.collect_lineages([fresh])
	_expect(runtime.roots.size() == 1 and runtime.roots.has(fresh.id), "Repeated roots do not accumulate once dead lineages are collected")
	_suite_finished = true
